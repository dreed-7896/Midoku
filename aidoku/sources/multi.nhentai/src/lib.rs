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
	/// Names that turned out to be groups/circles rather than artists.
	known_groups: RefCell<Vec<String>>,
}

/// Languages nhentai tags galleries with. A multi-language choice is expressed by excluding
/// the others, since nhentai search has no OR operator.
const LANGUAGES: [&str; 3] = ["english", "japanese", "chinese"];
/// Upper bound on searches for one page when several artists or `|` terms are combined.
const MAX_SEARCHES: usize = 24;

/// One search to run: the query, plus a group query to try if an artist query finds nothing.
struct PlannedSearch {
	query: String,
	fallback: Option<String>,
	/// Lowercase name whose namespace (artist or group) is remembered after the search.
	name: Option<String>,
	/// Artist name this search is for, saved to Saved Artists when it finds something.
	artist: Option<String>,
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

		let mut plan: Vec<PlannedSearch> = Vec::new();
		for term in &query_terms {
			let mut parts = query_parts.clone();
			if let Some(term) = term {
				parts.insert(0, term.clone());
			}
			if names.is_empty() {
				plan.push(PlannedSearch {
					query: parts.join(" "),
					fallback: None,
					name: None,
					artist: None,
				});
				continue;
			}
			for (name, namespace) in &names {
				let with = |namespace: &str| {
					let mut parts = parts.clone();
					parts.push(format!("{namespace}:\"{name}\""));
					parts.join(" ")
				};
				// Skip the artist attempt for names already known to be groups.
				let known_group = *namespace == "group" || self.known_groups.borrow().contains(name);
				let artist = (*namespace == "artist").then(|| name.clone());
				plan.push(if known_group {
					PlannedSearch {
						query: with("group"),
						fallback: None,
						name: None,
						artist,
					}
				} else {
					PlannedSearch {
						query: with("artist"),
						fallback: Some(with("group")),
						name: Some(name.clone()),
						artist,
					}
				});
			}
		}
		plan.truncate(MAX_SEARCHES);

		let responses = self.run_searches(&plan, page, sort)?;
		let has_next_page = responses.iter().any(|response| page < response.num_pages);
		let lists = responses
			.into_iter()
			.map(|response| response.result)
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

	/// Run planned searches in parallel (the runner's rate limiter still spaces them out),
	/// then retry artist searches that found nothing as group searches.
	/// A search that fails is skipped unless every search fails.
	fn run_searches(
		&self,
		plan: &[PlannedSearch],
		page: i32,
		sort: &str,
	) -> Result<Vec<NHentaiSearchResponse>> {
		let queries: Vec<&str> = plan.iter().map(|p| p.query.as_str()).collect();
		let mut results = self.search_batch(&queries, page, sort);

		let retry: Vec<usize> = (0..plan.len())
			.filter(|&i| {
				plan[i].fallback.is_some()
					&& matches!(&results[i], Ok(response) if response.num_pages == 0)
			})
			.collect();
		if !retry.is_empty() {
			let fallbacks: Vec<&str> = retry
				.iter()
				.filter_map(|&i| plan[i].fallback.as_deref())
				.collect();
			let fallback_results = self.search_batch(&fallbacks, page, sort);
			for (&i, result) in retry.iter().zip(fallback_results) {
				if let (Ok(response), Some(name)) = (&result, &plan[i].name)
					&& response.num_pages > 0
				{
					let mut groups = self.known_groups.borrow_mut();
					if !groups.contains(name) {
						groups.push(name.clone());
					}
				}
				results[i] = result;
			}
		}

		let found: Vec<String> = plan
			.iter()
			.zip(&results)
			.filter_map(|(p, r)| match (r, &p.artist) {
				(Ok(response), Some(artist)) if response.num_pages > 0 => Some(artist.clone()),
				_ => None,
			})
			.collect();
		settings::remember_artists(&found);

		let mut responses = Vec::new();
		let mut first_error = None;
		for result in results {
			match result {
				Ok(response) => responses.push(response),
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
			known_groups: RefCell::new(Vec::new()),
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

