#![no_std]
use aidoku::{
	Chapter, DeepLinkHandler, DeepLinkResult, DynamicFilters, Filter, FilterValue, Listing,
	ListingProvider, Manga, MangaPageResult, MultiSelectFilter, Page, PageContent, Result, Source,
	alloc::{String, Vec, string::ToString, vec},
	helpers::uri::encode_uri_component,
	imports::{
		error::AidokuError,
		net::Request,
		std::current_date,
	},
	prelude::*,
};

mod api;
mod artist_feed;
mod home;
mod models;
mod multi_search;
mod settings;

use core::cell::RefCell;

use models::*;
use api::{gallery_id, request_json};

const BASE_URL: &str = "https://nhentai.net";
const API_URL: &str = "https://nhentai.net/api/v2";
const USER_AGENT: &str = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) \
						  AppleWebKit/605.1.15 (KHTML, like Gecko) GSA/300.0.598994205 \
						  Mobile/15E148 Safari/604";

/// Searches sent at once. The runner's rate limiter and `sleep` block a shared thread while
/// they wait, which can stall every source when several shelves load together, so requests
/// are throttled by batching instead.
const BATCH_SIZE: usize = 4;
/// How long, in seconds, a search page stays cached.
const SEARCH_CACHE_TTL: i64 = 300;
const SEARCH_CACHE_SIZE: usize = 30;

struct NHentai {
	cache: RefCell<Option<(String, NHentaiGallery)>>,
	search_cache: RefCell<Vec<(String, i64, NHentaiSearchResponse)>>,
}

/// Languages nhentai tags galleries with. A multi-language choice is expressed by excluding
/// the others, since nhentai search has no OR operator.
const LANGUAGES: [&str; 3] = ["english", "japanese", "chinese"];
/// Upper bound on searches for one page when several artists or `|` terms are combined.
const MAX_SEARCHES: usize = 24;
/// Newest artist feed entries given an upload time (for apps sorting several sources by date).
const DATED_ENTRIES: usize = 40;

/// One search to run, and the exact tag its results must carry. nhentai's `artist:"x"`
/// search also matches tags that merely contain the words (e.g. "jirou" finds
/// "tamakichi. jirou"), so results are checked against the tag's id.
struct PlannedSearch {
	query: String,
	tag_id: Option<i32>,
}

impl NHentai {
	fn search_all(
		&self,
		query: Option<String>,
		page: i32,
		filters: Vec<FilterValue>,
	) -> Result<MangaPageResult> {
		// If the query is a numeric ID, return the manga directly
		if let Some(q) = &query
			&& let Ok(id) = q.trim().parse::<i32>()
		{
			let gallery: NHentaiGallery = self.fetch_gallery(&id.to_string(), None)?;
			return Ok(MangaPageResult {
				entries: vec![gallery.into()],
				has_next_page: false,
			});
		}

		let mut query_parts: Vec<String> = Vec::new();
		// (name, namespace): artists fall back to group when they have no artist tag.
		let mut names: Vec<(String, &str)> = Vec::new();
		let mut languages: Option<(Vec<String>, Vec<String>)> = None;
		let mut clean_titles = settings::get_clean_titles();
		let mut sort = "date";

		let push_name = |names: &mut Vec<(String, &'static str)>, name: &str, namespace: &'static str| {
			let name = name.trim().trim_matches('"').trim().to_lowercase();
			if !name.is_empty() && !names.iter().any(|(n, _)| n == &name) {
				names.push((name, namespace));
			}
		};

		for filter in filters {
			match filter {
				FilterValue::Text { id, value } => match id.as_str() {
					// "author" is the id of the Artist field in filters.json. It used to be sent as
					// plain text, which nhentai matches against titles; match the artist tag instead.
					"author" | "artist" => {
						for name in value.split('|') {
							push_name(&mut names, name, "artist");
						}
					}
					"groups" => {
						for name in value.split('|') {
							push_name(&mut names, name, "group");
						}
					}
					_ => continue,
				},
				FilterValue::Sort { index, .. } => {
					sort = match index {
						0 => "date",          // Latest
						1 => "popular-today", // Popular Today
						2 => "popular-week",  // Popular Week
						3 => "popular",       // Popular All
						_ => "date",
					};
				}
				FilterValue::MultiSelect {
					id,
					included,
					excluded,
					..
				} => match id.as_str() {
					"tags" => {
						for tag in included {
							query_parts.push(format!("tag:\"{tag}\""));
						}
						for tag in excluded {
							query_parts.push(format!("-tag:\"{tag}\""));
						}
					}
					"saved_artists" => {
						for name in included {
							push_name(&mut names, &name, "artist");
						}
						for name in excluded {
							let name = name.trim().to_lowercase();
							if !name.is_empty() {
								query_parts.push(format!("-artist:\"{name}\""));
							}
						}
					}
					"languages" => {
						if !included.is_empty() || !excluded.is_empty() {
							languages = Some((included, excluded));
						}
					}
					_ => continue,
				},
				FilterValue::Select { id, value } => {
					if id == "genre" {
						query_parts.push(format!("tag:\"{value}\""));
					}
				}
				FilterValue::Check { id, value } => {
					if id == "clean_titles" && value > 0 {
						clean_titles = true;
					}
				}
				_ => continue,
			}
		}

		match languages {
			Some((included, excluded)) => {
				for language in LANGUAGES {
					let chosen = included.iter().any(|l| l == language);
					let dropped = excluded.iter().any(|l| l == language);
					if dropped || (!included.is_empty() && !chosen) {
						query_parts.push(format!("-language:{language}"));
					}
				}
			}
			None => {
				if let Some(language) = settings::get_language() {
					query_parts.push(format!("language:{language}"));
				}
			}
		}

		for blocked in settings::get_blocklist() {
			if !blocked.is_empty() {
				query_parts.push(format!("-tag:\"{blocked}\""));
			}
		}

		// `a | b` in the search box runs one search per term.
		let query_terms: Vec<Option<String>> = match multi_search::terms(query.as_deref()) {
			Some(terms) => terms.into_iter().map(Some).collect(),
			None => vec![query.map(|q| q.trim().into()).filter(|q: &String| !q.is_empty())],
		};

		// Exact tags for the names: artist first, then group (circles such as "ringoya").
		// Names nhentai has no tag for are skipped instead of falling back to a loose search.
		let resolved: Vec<(String, &str, i32)> = {
			let lookups: Vec<(&str, &str)> =
				names.iter().map(|(n, ns)| (n.as_str(), *ns)).collect();
			names
				.iter()
				.zip(self.resolve_tags(&lookups))
				.filter_map(|((name, _), tag)| tag.map(|(ns, id)| (name.clone(), ns, id)))
				.collect()
		};
		settings::remember_artists(
			&resolved
				.iter()
				.filter(|(_, ns, _)| *ns == "artist")
				.map(|(name, _, _)| name.clone())
				.collect::<Vec<_>>(),
		);
		if !names.is_empty() && resolved.is_empty() {
			return Ok(MangaPageResult {
				entries: Vec::new(),
				has_next_page: false,
			});
		}

		// Newest galleries of the artists (e.g. a Home shelf): served from the artist feed, which
		// reads only uploads since the last refresh instead of searching every artist.
		if page == 1 && sort == "date" && matches!(query_terms.as_slice(), [None]) && !resolved.is_empty() {
			let items = self.artist_latest(&query_parts.join(" "), &resolved)?;
			let has_next_page = items.len() >= 25;
			let entries = items
				.into_iter()
				.map(|item| {
					let mut manga: Manga = item.into();
					if clean_titles {
						manga.title = clean_title(&manga.title);
					}
					manga
				})
				.collect();
			return Ok(MangaPageResult {
				entries,
				has_next_page,
			});
		}

		let mut plan: Vec<PlannedSearch> = Vec::new();
		for term in &query_terms {
			let mut parts = query_parts.clone();
			if let Some(term) = term {
				parts.insert(0, term.clone());
			}
			if resolved.is_empty() {
				plan.push(PlannedSearch {
					query: parts.join(" "),
					tag_id: None,
				});
				continue;
			}
			for (name, namespace, id) in &resolved {
				let mut parts = parts.clone();
				parts.push(format!("{namespace}:\"{name}\""));
				plan.push(PlannedSearch {
					query: parts.join(" "),
					tag_id: Some(*id),
				});
			}
		}
		plan.truncate(MAX_SEARCHES);

		let responses = self.run_searches(&plan, page, sort)?;
		let has_next_page = responses.iter().any(|(_, response)| page < response.num_pages);
		let lists = responses
			.into_iter()
			.map(|(tag_id, response)| match tag_id {
				Some(id) => response
					.result
					.into_iter()
					.filter(|item| item.tag_ids.contains(&id))
					.collect(),
				None => response.result,
			})
			.collect::<Vec<_>>();
		let entries = merge_results(lists, sort == "date")
			.into_iter()
			.map(|item| {
				let mut manga: Manga = item.into();
				if clean_titles {
					manga.title = clean_title(&manga.title);
				}
				manga
			})
			.collect::<Vec<Manga>>();

		Ok(MangaPageResult {
			entries,
			has_next_page,
		})
	}

	/// Newest galleries by any of the artist tags, newest first (see `artist_feed`).
	fn artist_latest(
		&self,
		base: &str,
		resolved: &[(String, &str, i32)],
	) -> Result<Vec<NHentaiGalleryListItem>> {
		let mut state = artist_feed::FeedState::load(base);
		let requested: Vec<i32> = resolved.iter().map(|(_, _, id)| *id).collect();

		// 1. Read latest uploads back to the watermark and keep the followed artists' galleries.
		let latest_query = if base.trim().is_empty() { " " } else { base };
		let mut followed = state.covered.clone();
		followed.extend(requested.iter().filter(|id| !state.covered.contains(id)));
		let mut newest = state.watermark;
		let mut reached = state.watermark == 0;
		let mut page = 1;
		loop {
			let response = self.search(latest_query, page, "date")?;
			if let Some(top) = response.result.first() {
				newest = newest.max(top.id);
			}
			if state.watermark > 0 {
				let fresh: Vec<NHentaiGalleryListItem> = response
					.result
					.iter()
					.filter(|item| item.id > state.watermark)
					.cloned()
					.collect();
				reached = fresh.len() < response.result.len() || response.result.is_empty();
				state.merge(fresh, &followed);
			}
			if reached || page >= response.num_pages || page >= artist_feed::MAX_SCAN_PAGES {
				break;
			}
			page += 1;
		}
		if !reached {
			// Too long since the last refresh to read through: search the artists again.
			state.reset();
		}
		state.watermark = newest;

		// 2. Search artists not covered yet on their own, a bounded number per refresh.
		let plan: Vec<PlannedSearch> = resolved
			.iter()
			.filter(|(_, _, id)| !state.is_covered(*id))
			.take(MAX_SEARCHES)
			.map(|(name, namespace, id)| {
				let mut parts: Vec<String> = Vec::new();
				if !base.trim().is_empty() {
					parts.push(base.into());
				}
				parts.push(format!("{namespace}:\"{name}\""));
				PlannedSearch {
					query: parts.join(" "),
					tag_id: Some(*id),
				}
			})
			.collect();
		if !plan.is_empty() {
			let responses = match self.run_searches(&plan, 1, "date") {
				Ok(responses) => responses,
				// Nothing stored to show either: report the error.
				Err(error) if state.entries_for(&requested).is_empty() => return Err(error),
				Err(_) => Vec::new(),
			};
			for (tag_id, response) in responses {
				let Some(id) = tag_id else { continue };
				let items: Vec<NHentaiGalleryListItem> = response
					.result
					.into_iter()
					.filter(|item| item.tag_ids.contains(&id))
					.collect();
				state.mark_covered(id);
				let mut tags = state.covered.clone();
				tags.extend(requested.iter().copied());
				state.merge(items, &tags);
			}
		}

		state.prune(&requested);
		self.fill_upload_dates(&mut state, &requested);
		state.save();
		Ok(state.entries_for(&requested))
	}

	/// Look up the upload time of the newest entries that lack one. Each gallery is looked up
	/// once, since the time is stored with the entry.
	fn fill_upload_dates(&self, state: &mut artist_feed::FeedState, requested: &[i32]) {
		let missing: Vec<i32> = state
			.entries_for(requested)
			.iter()
			.take(DATED_ENTRIES)
			.filter(|item| item.upload_date.is_none())
			.map(|item| item.id)
			.collect();
		for chunk in missing.chunks(BATCH_SIZE) {
			let requests: Vec<Request> = chunk
				.iter()
				.filter_map(|id| api::json_request(&format!("{API_URL}/galleries/{id}")).ok())
				.collect();
			if requests.len() != chunk.len() {
				continue;
			}
			for (id, response) in chunk.iter().zip(Request::send_all(requests)) {
				let Ok(response) = response else { continue };
				let Ok(gallery) = api::decode_response::<NHentaiGallery>(response) else { continue };
				if let Some(item) = state.items.iter_mut().find(|item| item.id == *id) {
					item.upload_date = Some(gallery.upload_date);
				}
			}
		}
	}

	/// Run planned searches in parallel batches, keeping each result with its tag id.
	/// A search that fails is skipped unless every search fails.
	fn run_searches(
		&self,
		plan: &[PlannedSearch],
		page: i32,
		sort: &str,
	) -> Result<Vec<(Option<i32>, NHentaiSearchResponse)>> {
		let queries: Vec<&str> = plan.iter().map(|p| p.query.as_str()).collect();
		let results = self.search_batch(&queries, page, sort);
		let mut responses = Vec::new();
		let mut first_error = None;
		for (planned, result) in plan.iter().zip(results) {
			match result {
				Ok(response) => responses.push((planned.tag_id, response)),
				Err(error) => {
					if first_error.is_none() {
						first_error = Some(error);
					}
				}
			}
		}
		if responses.is_empty()
			&& let Some(error) = first_error
		{
			return Err(error);
		}
		Ok(responses)
	}

	/// The exact tag (namespace, id) for each (name, preferred namespace). Artist names that
	/// have no artist tag are tried as groups. Lookups are remembered across launches.
	fn resolve_tags(&self, names: &[(&str, &str)]) -> Vec<Option<(&'static str, i32)>> {
		let mut results: Vec<Option<Option<(&'static str, i32)>>> = names
			.iter()
			.map(|(name, _)| settings::cached_tag(name))
			.collect();
		for namespace in ["artist", "group"] {
			let pending: Vec<usize> = (0..names.len())
				.filter(|&i| {
					results[i].is_none() && (namespace == "group" || names[i].1 == "artist")
				})
				.collect();
			for chunk in pending.chunks(BATCH_SIZE) {
				let urls: Vec<String> = chunk
					.iter()
					.map(|&i| {
						let slug = names[i].0.trim().to_lowercase().replace(' ', "-");
						format!("{API_URL}/tags/{namespace}/{}", encode_uri_component(slug))
					})
					.collect();
				let requests: Vec<Request> =
					urls.iter().filter_map(|url| api::json_request(url).ok()).collect();
				if requests.len() != chunk.len() {
					continue;
				}
				for (&i, response) in chunk.iter().zip(Request::send_all(requests)) {
					let Ok(response) = response else { continue };
					let status = response.status_code();
					if status == 404 {
						if namespace == "group" {
							// Neither an artist nor a group: remember that too.
							results[i] = Some(None);
							settings::cache_tag(names[i].0, None);
						}
						continue;
					}
					if let Ok(tag) = api::decode_response::<NHentaiTagInfo>(response) {
						let ns: &'static str = if namespace == "artist" { "artist" } else { "group" };
						results[i] = Some(Some((ns, tag.id)));
						settings::cache_tag(names[i].0, Some((ns, tag.id)));
					}
				}
			}
		}
		results.into_iter().map(Option::flatten).collect()
	}

	fn search_url(query: &str, page: i32, sort: &str) -> String {
		let query = if query.trim().is_empty() { " " } else { query };
		format!(
			"{API_URL}/search?query={}&page={page}&sort={sort}",
			encode_uri_component(query),
		)
	}

	fn cached_search(&self, url: &str) -> Option<NHentaiSearchResponse> {
		let now = current_date();
		let mut cache = self.search_cache.borrow_mut();
		cache.retain(|(_, time, _)| now - *time < SEARCH_CACHE_TTL);
		cache
			.iter()
			.find(|(key, _, _)| key == url)
			.map(|(_, _, response)| response.clone())
	}

	fn store_search(&self, url: String, response: &NHentaiSearchResponse) {
		let mut cache = self.search_cache.borrow_mut();
		if cache.len() >= SEARCH_CACHE_SIZE {
			cache.remove(0);
		}
		cache.push((url, current_date(), response.clone()));
	}

	/// Run several searches at once, serving cached pages without a request. A request that is
	/// rate limited is retried on its own with backoff.
	fn search_batch(
		&self,
		queries: &[&str],
		page: i32,
		sort: &str,
	) -> Vec<Result<NHentaiSearchResponse>> {
		let urls: Vec<String> = queries
			.iter()
			.map(|q| Self::search_url(q, page, sort))
			.collect();
		let mut results: Vec<Option<Result<NHentaiSearchResponse>>> =
			urls.iter().map(|url| self.cached_search(url).map(Ok)).collect();

		let missing: Vec<usize> = (0..urls.len()).filter(|&i| results[i].is_none()).collect();
		for chunk in missing.chunks(BATCH_SIZE) {
			if chunk.len() == 1 {
				results[chunk[0]] = Some(request_json(&urls[chunk[0]]));
				continue;
			}
			let requests: Vec<Request> = chunk
				.iter()
				.filter_map(|&i| api::json_request(&urls[i]).ok())
				.collect();
			if requests.len() != chunk.len() {
				for &i in chunk {
					results[i] = Some(request_json(&urls[i]));
				}
				continue;
			}
			for (&i, response) in chunk.iter().zip(Request::send_all(requests)) {
				results[i] = Some(match response {
					Ok(response) => api::decode_response(response),
					Err(error) => Err(error.into()),
				});
			}
		}

		results
			.into_iter()
			.zip(urls)
			.map(|(result, url)| {
				let result = result.unwrap_or_else(|| Err(AidokuError::message("search was not run")));
				if let Ok(response) = &result
					&& self.cached_search(&url).is_none()
				{
					self.store_search(url, response);
				}
				result
			})
			.collect()
	}

	/// Run one search request, served from the short-lived cache when possible.
	pub(crate) fn search(&self, query: &str, page: i32, sort: &str) -> Result<NHentaiSearchResponse> {
		self.search_batch(&[query], page, sort)
			.pop()
			.unwrap_or_else(|| Err(AidokuError::message("search was not run")))
	}

	fn fetch_gallery(&self, key: &str, url: Option<&str>) -> Result<NHentaiGallery> {
		let id = gallery_id(key, url)?;
		let gallery: NHentaiGallery = request_json(&format!("{API_URL}/galleries/{id}"))?;
		if gallery.id.to_string() != id || gallery.pages.is_empty() {
			bail!("nhentai returned incomplete or mismatched gallery data. Try opening the gallery on the source website.");
		}
		Ok(gallery)
	}
}

/// Combine result pages from several searches, dropping duplicates. Latest sort orders by
/// gallery id (newest first); popularity sorts interleave the lists.
fn merge_results(
	lists: Vec<Vec<NHentaiGalleryListItem>>,
	newest_first: bool,
) -> Vec<NHentaiGalleryListItem> {
	if lists.len() == 1 {
		return lists.into_iter().next().unwrap_or_default();
	}
	let mut seen: Vec<i32> = Vec::new();
	let mut merged = Vec::new();
	let longest = lists.iter().map(|list| list.len()).max().unwrap_or(0);
	for index in 0..longest {
		for list in &lists {
			if let Some(item) = list.get(index)
				&& !seen.contains(&item.id)
			{
				seen.push(item.id);
				merged.push(item.clone());
			}
		}
	}
	if newest_first {
		merged.sort_by_key(|item| core::cmp::Reverse(item.id));
	}
	merged
}

impl Source for NHentai {
	fn new() -> Self {
		Self {
			cache: RefCell::new(None),
			search_cache: RefCell::new(Vec::new()),
		}
	}

	fn get_search_manga_list(
		&self,
		query: Option<String>,
		page: i32,
		filters: Vec<FilterValue>,
	) -> Result<MangaPageResult> {
		self.search_all(query, page, filters)
	}

	fn get_manga_update(
		&self,
		mut manga: Manga,
		needs_details: bool,
		needs_chapters: bool,
	) -> Result<Manga> {
		if needs_details || needs_chapters {
			let id = gallery_id(&manga.key, manga.url.as_deref())?;
			let gallery = self.fetch_gallery(&id, None)?;

			if needs_details {
				// Keep imported physical keys stable for saved progress and bookmarks.
				let stored_key = manga.key.clone();
				manga.copy_from(gallery.clone().into());
				manga.key = stored_key;
			}

			if needs_chapters {
				let mut languages = Vec::new();
				for tag in &gallery.tags {
					if tag.r#type == "language" && tag.name != "translated" && tag.name != "rewrite"
					{
						languages.push(tag.name.clone());
					}
				}

				let chapter = Chapter {
					key: manga.key.clone(),
					chapter_number: Some(1.0),
					date_uploaded: Some(gallery.upload_date),
					url: Some(format!("{BASE_URL}/g/{id}/")),
					scanlators: if !languages.is_empty() {
						Some(vec![languages.join(", ")])
					} else {
						None
					},
					..Default::default()
				};
				manga.chapters = Some(vec![chapter]);
			}

			// Cache the fetched gallery for potential reuse in get_page_list
			self.cache
				.borrow_mut()
				.replace((manga.key.clone(), gallery));
		}

		manga.update_strategy = aidoku::UpdateStrategy::Never;
		Ok(manga)
	}

	fn get_page_list(&self, manga: Manga, chapter: Chapter) -> Result<Vec<Page>> {
		// Try to reuse cached gallery fetched by get_manga_update
		let maybe_cached = self.cache.borrow();
		let gallery: NHentaiGallery = match &*maybe_cached {
			Some((cached_key, cached_gallery)) if cached_key == &chapter.key => {
				cached_gallery.clone()
			}
			_ => {
				let id = gallery_id(&chapter.key, chapter.url.as_deref())
					.or_else(|_| gallery_id(&manga.key, manga.url.as_deref()))?;
				self.fetch_gallery(&id, None)?
			}
		};

		let pages = gallery
			.pages
			.iter()
			.map(|page| {
				let path = make_image_url(&page.path, false);

				Page {
					content: PageContent::url(path),
					..Default::default()
				}
			})
			.collect::<Vec<Page>>();

		Ok(pages)
	}
}

impl ListingProvider for NHentai {
	fn get_manga_list(&self, listing: Listing, page: i32) -> Result<MangaPageResult> {
		match listing.id.as_str() {
			"popular-today" => self.get_search_manga_list(
				None,
				page,
				vec![FilterValue::Sort {
					id: "sort".to_string(),
					index: 1,
					ascending: false,
				}],
			),
			"popular-week" => self.get_search_manga_list(
				None,
				page,
				vec![FilterValue::Sort {
					id: "sort".to_string(),
					index: 2,
					ascending: false,
				}],
			),
			"popular" => self.get_search_manga_list(
				None,
				page,
				vec![FilterValue::Sort {
					id: "sort".to_string(),
					index: 3,
					ascending: false,
				}],
			),
			"latest" => self.get_search_manga_list(
				None,
				page,
				vec![FilterValue::Sort {
					id: "sort".to_string(),
					index: 0,
					ascending: false,
				}],
			),
			_ => Err(AidokuError::Unimplemented),
		}
	}
}

impl DeepLinkHandler for NHentai {
	fn handle_deep_link(&self, url: String) -> Result<Option<DeepLinkResult>> {
		if !url.starts_with(BASE_URL) {
			return Ok(None);
		}

		const GALLERY_PATH: &str = "/g/";

		if let Some(id_start) = url.find(GALLERY_PATH) {
			let id_part = &url[id_start + GALLERY_PATH.len()..];
			let end = id_part.find('/').unwrap_or(id_part.len());
			let manga_id = &id_part[..end];

			Ok(Some(DeepLinkResult::Manga {
				key: manga_id.into(),
			}))
		} else {
			Ok(None)
		}
	}
}

impl DynamicFilters for NHentai {
	/// Saved artists (from the source settings) as a pick list next to the typed Artist field.
	fn get_dynamic_filters(&self) -> Result<Vec<Filter>> {
		let artists = settings::get_saved_artists();
		if artists.is_empty() {
			let mut note = Filter::note(
				"Saved Artists: no artists yet. Artists you search by name are saved here as chips, or add them in the source settings.",
			);
			note.id = "saved_artists_note".into();
			return Ok(vec![note]);
		}
		Ok(vec![
			MultiSelectFilter {
				id: "saved_artists".into(),
				title: Some("Saved Artists".into()),
				can_exclude: true,
				uses_tag_style: true,
				options: artists.into_iter().map(Into::into).collect(),
				..Default::default()
			}
			.into(),
		])
	}
}

register_source!(NHentai, Home, ListingProvider, DeepLinkHandler, DynamicFilters);

