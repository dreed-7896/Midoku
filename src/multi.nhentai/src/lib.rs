#![no_std]
use aidoku::{
	Chapter, DeepLinkHandler, DeepLinkResult, FilterValue, Listing, ListingProvider, Manga,
	MangaPageResult, Page, PageContent, Result, Source,
	alloc::{String, Vec, string::ToString, vec},
	helpers::uri::encode_uri_component,
	imports::{
		error::AidokuError,
		net::{Request, TimeUnit, set_rate_limit},
		std::{current_date, sleep},
	},
	prelude::*,
};
use serde::de::DeserializeOwned;

mod home;
mod models;
mod settings;

use core::cell::RefCell;

use models::*;

const BASE_URL: &str = "https://nhentai.net";
const API_URL: &str = "https://nhentai.net/api/v2";
const USER_AGENT: &str = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) \
						  AppleWebKit/605.1.15 (KHTML, like Gecko) GSA/300.0.598994205 \
						  Mobile/15E148 Safari/604";

/// Requests allowed per period, and the period length in seconds.
const RATE_LIMIT_PERMITS: i32 = 2;
const RATE_LIMIT_PERIOD: i32 = 1;
/// Retries after a 429/503 before giving up.
const MAX_RETRIES: i32 = 2;
/// How long, in seconds, a search page stays cached.
const SEARCH_CACHE_TTL: i64 = 300;
const SEARCH_CACHE_SIZE: usize = 30;

struct NHentai {
	cache: RefCell<Option<(String, NHentaiGallery)>>,
	search_cache: RefCell<Vec<(String, i64, NHentaiSearchResponse)>>,
}

impl Source for NHentai {
	fn new() -> Self {
		// nhentai's API sits behind Cloudflare and answers bursts with HTTP 429.
		// Queue requests in the runner instead of firing them all at once.
		set_rate_limit(RATE_LIMIT_PERMITS, RATE_LIMIT_PERIOD, TimeUnit::Seconds);
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
		// If the query is a numeric ID, return the manga directly
		if let Some(q) = &query
			&& let Ok(id) = q.trim().parse::<i32>()
		{
			let gallery: NHentaiGallery = fetch_json(&format!("{API_URL}/galleries/{id}"))?;
			return Ok(MangaPageResult {
				entries: vec![gallery.into()],
				has_next_page: false,
			});
		}

		let mut query_parts: Vec<String> = Vec::new();
		let mut artists: Vec<String> = Vec::new();
		let mut language_override: Option<Option<String>> = None;
		let mut clean_titles = settings::get_clean_titles();

		if let Some(q) = query {
			let q = q.trim();
			if !q.is_empty() {
				query_parts.push(q.into());
			}
		}

		let mut sort = "date";

		// parse filters
		for filter in filters {
			match filter {
				FilterValue::Text { id, value } => match id.as_str() {
					// "author" is the id of the Artist field in filters.json; "artist" is kept
					// for app-driven artist searches. Both match the artist tag only, never titles.
					// Several artists can be separated with `|`.
					"author" | "artist" => {
						for name in split_names(&value) {
							if !artists.contains(&name) {
								artists.push(name);
							}
						}
					}
					"groups" => {
						let value = value.trim();
						if !value.is_empty() {
							query_parts.push(format!("group:\"{}\"", strip_quotes(value)));
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
				} => {
					if id == "tags" {
						for tag in included {
							query_parts.push(format!("tag:\"{tag}\""));
						}
						for tag in excluded {
							query_parts.push(format!("-tag:\"{tag}\""));
						}
					}
				}
				FilterValue::Select { id, value } => match id.as_str() {
					"genre" => query_parts.push(format!("tag:\"{value}\"")),
					"language" => {
						language_override = match value.as_str() {
							"" | "default" => None,
							"any" => Some(None),
							lang => Some(Some(lang.into())),
						};
					}
					_ => continue,
				},
				FilterValue::Check { id, value } => {
					if id == "clean_titles" && value > 0 {
						clean_titles = true;
					}
				}
				_ => continue,
			}
		}

		let language = language_override.unwrap_or_else(settings::get_language);
		if let Some(language) = language {
			query_parts.push(format!("language:{language}"));
		}

		for blocked in settings::get_blocklist() {
			if !blocked.is_empty() {
				query_parts.push(format!("-tag:\"{blocked}\""));
			}
		}

		// nhentai has no OR operator, so each artist needs its own query.
		// Each entry is (artist query, fallback group query).
		let queries: Vec<(String, Option<String>)> = if artists.is_empty() {
			vec![(query_parts.join(" "), None)]
		} else {
			artists
				.iter()
				.map(|artist| {
					let with = |namespace: &str| {
						let mut parts = query_parts.clone();
						parts.push(format!("{namespace}:\"{artist}\""));
						parts.join(" ")
					};
					(with("artist"), Some(with("group")))
				})
				.collect()
		};

		let mut lists: Vec<Vec<NHentaiGalleryListItem>> = Vec::new();
		let mut has_next_page = false;
		let mut last_error = None;
		for (query, fallback) in &queries {
			// Names that are circles rather than artists (e.g. "ringoya") have no artist tag;
			// retry those as a group before giving up.
			let result = self.search(query, page, sort).and_then(|response| match fallback {
				Some(fallback) if response.num_pages == 0 => self.search(fallback, page, sort),
				_ => Ok(response),
			});
			match result {
				Ok(response) => {
					has_next_page |= page < response.num_pages;
					lists.push(response.result);
				}
				// One failing artist shouldn't hide the others' results.
				Err(error) if queries.len() > 1 => last_error = Some(error),
				Err(error) => return Err(error),
			}
		}
		if lists.is_empty()
			&& let Some(error) = last_error
		{
			return Err(error);
		}

		let items = merge_results(lists, sort == "date");
		let entries = items
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

	fn get_manga_update(
		&self,
		mut manga: Manga,
		needs_details: bool,
		needs_chapters: bool,
	) -> Result<Manga> {
		if needs_details || needs_chapters {
			let gallery = self.gallery(&manga.key)?;

			if needs_details {
				manga.copy_from(gallery.clone().into());
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
					url: Some(format!("{}/g/{}", BASE_URL, manga.key)),
					scanlators: if !languages.is_empty() {
						Some(vec![languages.join(", ")])
					} else {
						None
					},
					..Default::default()
				};
				manga.chapters = Some(vec![chapter]);
			}
		}

		Ok(manga)
	}

	fn get_page_list(&self, _manga: Manga, chapter: Chapter) -> Result<Vec<Page>> {
		// Reuses the gallery fetched by get_manga_update when it is cached.
		let gallery = self.gallery(&chapter.key)?;

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

impl NHentai {
	/// Fetch a gallery, reusing the last one fetched when the key matches.
	fn gallery(&self, key: &str) -> Result<NHentaiGallery> {
		if let Some((cached_key, cached)) = &*self.cache.borrow()
			&& cached_key == key
		{
			return Ok(cached.clone());
		}
		let gallery: NHentaiGallery = fetch_json(&format!("{API_URL}/galleries/{key}"))?;
		self.cache.replace(Some((key.into(), gallery.clone())));
		Ok(gallery)
	}

	/// Run one search request, served from a short-lived cache when possible so paging
	/// back, reopening Home and re-running a search don't hit the API again.
	pub(crate) fn search(&self, query: &str, page: i32, sort: &str) -> Result<NHentaiSearchResponse> {
		let query = if query.trim().is_empty() { " " } else { query };
		let url = format!(
			"{API_URL}/search?query={}&page={page}&sort={sort}",
			encode_uri_component(query),
		);
		let now = current_date();
		{
			let mut cache = self.search_cache.borrow_mut();
			cache.retain(|(_, time, _)| now - *time < SEARCH_CACHE_TTL);
			if let Some((_, _, response)) = cache.iter().find(|(key, _, _)| key == &url) {
				return Ok(response.clone());
			}
		}
		let response: NHentaiSearchResponse = fetch_json(&url)?;
		let mut cache = self.search_cache.borrow_mut();
		if cache.len() >= SEARCH_CACHE_SIZE {
			cache.remove(0);
		}
		cache.push((url, now, response.clone()));
		Ok(response)
	}
}

/// GET a JSON endpoint, waiting and retrying when nhentai rate limits the request.
pub(crate) fn fetch_json<T: DeserializeOwned>(url: &str) -> Result<T> {
	let mut attempt = 0;
	loop {
		let response = Request::get(url)?.header("User-Agent", USER_AGENT).send()?;
		let status = response.status_code();
		if status == 429 || status == 503 {
			if attempt >= MAX_RETRIES {
				return Err(AidokuError::message(
					"nhentai is rate limiting requests. Wait a moment and try again.",
				));
			}
			let wait = response
				.get_header("Retry-After")
				.and_then(|value| value.trim().parse::<i32>().ok())
				.unwrap_or(2 << attempt)
				.clamp(1, 10);
			drop(response);
			sleep(wait);
			attempt += 1;
			continue;
		}
		return response.get_json_owned();
	}
}

/// Split an artist field on `|` into lowercase names without surrounding quotes.
fn split_names(value: &str) -> Vec<String> {
	value
		.split('|')
		.map(|name| strip_quotes(name.trim()).trim().to_lowercase())
		.filter(|name| !name.is_empty())
		.collect()
}

fn strip_quotes(value: &str) -> &str {
	value.trim_matches('"')
}

/// Combine per-artist result pages, dropping duplicates. Latest sort orders by gallery id
/// (newest first); popularity sorts interleave the lists so every artist shows up near the top.
fn merge_results(
	lists: Vec<Vec<NHentaiGalleryListItem>>,
	newest_first: bool,
) -> Vec<NHentaiGalleryListItem> {
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
	if newest_first && lists.len() > 1 {
		merged.sort_by_key(|item| core::cmp::Reverse(item.id));
	}
	merged
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

register_source!(NHentai, Home, ListingProvider, DeepLinkHandler);
