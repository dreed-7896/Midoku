#![no_std]
use aidoku::{
	Chapter, DeepLinkHandler, DeepLinkResult, FilterValue, Listing, ListingProvider, Manga,
	MangaPageResult, Page, PageContent, Result, Source,
	alloc::{String, Vec, string::ToString, vec},
	helpers::uri::encode_uri_component,
	imports::{
		error::AidokuError,
		net::{TimeUnit, set_rate_limit},
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

/// Requests allowed per period, and the period length in seconds.
const RATE_LIMIT_PERMITS: i32 = 2;
const RATE_LIMIT_PERIOD: i32 = 1;
/// How long, in seconds, a search page stays cached.
const SEARCH_CACHE_TTL: i64 = 300;
const SEARCH_CACHE_SIZE: usize = 30;

struct NHentai {
	cache: RefCell<Option<(String, NHentaiGallery)>>,
	search_cache: RefCell<Vec<(String, i64, NHentaiSearchResponse)>>,
}

impl NHentai {
	fn search_single(
		&self,
		query: Option<String>,
		page: i32,
		filters: Vec<FilterValue>,
	) -> Result<MangaPageResult> {
		// If the query is a numeric ID, return the manga directly
		if let Some(q) = &query
			&& let Ok(id) = q.parse::<i32>()
		{
			let gallery: NHentaiGallery = self.fetch_gallery(&id.to_string(), None)?;
			return Ok(MangaPageResult {
				entries: vec![gallery.into()],
				has_next_page: false,
			});
		}

		let mut query_parts: Vec<String> = Vec::new();
		// multi_search has already split `a | b` artist fields, so this is a single name.
		let mut artist: Option<String> = None;
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
					// "author" is the id of the Artist field in filters.json. It used to be sent as
					// plain text, which nhentai matches against titles; match the artist tag instead.
					"author" | "artist" => {
						let name = value.trim().trim_matches('"').trim().to_lowercase();
						if !name.is_empty() {
							artist = Some(name);
						}
					}
					"groups" => {
						let name = value.trim().trim_matches('"').trim();
						if !name.is_empty() {
							query_parts.push(format!("group:\"{name}\""));
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

		let response = match &artist {
			Some(name) => {
				let with = |namespace: &str| {
					let mut parts = query_parts.clone();
					parts.push(format!("{namespace}:\"{name}\""));
					parts.join(" ")
				};
				let response = self.search(&with("artist"), page, sort)?;
				// Names that are circles rather than artists (e.g. "ringoya") have no artist tag;
				// retry those as a group before giving up.
				if response.num_pages == 0 {
					self.search(&with("group"), page, sort)?
				} else {
					response
				}
			}
			None => self.search(&query_parts.join(" "), page, sort)?,
		};

		let has_next_page = page < response.num_pages;
		let entries = response
			.result
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
		let response: NHentaiSearchResponse = request_json(&url)?;
		let mut cache = self.search_cache.borrow_mut();
		if cache.len() >= SEARCH_CACHE_SIZE {
			cache.remove(0);
		}
		cache.push((url, now, response.clone()));
		Ok(response)
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
		if let Some(variants) = multi_search::variants(query.as_deref(), &filters) {
			return multi_search::search(variants, |(query, filters)| {
				self.search_single(query, page, filters)
			});
		}
		self.search_single(query, page, filters)
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

register_source!(NHentai, Home, ListingProvider, DeepLinkHandler);
