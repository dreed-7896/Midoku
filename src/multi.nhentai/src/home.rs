use crate::{NHentai, settings};
use aidoku::{
	Home, HomeComponent, HomeLayout, HomePartialResult, Listing, ListingKind, Manga, Result,
	alloc::{Vec, vec},
	imports::std::send_partial_result,
	prelude::*,
};

fn send_component(component: HomeComponent) {
	send_partial_result(&HomePartialResult::Component(component));
}

impl Home for NHentai {
	fn get_home(&self) -> Result<HomeLayout> {
		// send basic home layout
		send_partial_result(&HomePartialResult::Layout(HomeLayout {
			components: vec![
				HomeComponent {
					title: Some("Popular Today".into()),
					subtitle: None,
					value: aidoku::HomeComponentValue::empty_big_scroller(),
				},
				HomeComponent {
					title: Some("Popular This Week".into()),
					subtitle: None,
					value: aidoku::HomeComponentValue::empty_manga_list(),
				},
				HomeComponent {
					title: Some("Popular All Time".into()),
					subtitle: None,
					value: aidoku::HomeComponentValue::empty_manga_list(),
				},
				HomeComponent {
					title: Some("Latest".into()),
					subtitle: None,
					value: aidoku::HomeComponentValue::empty_scroller(),
				},
			],
		}));

		let blocklist = settings::get_blocklist();
		let mut query_parts = Vec::new();

		if let Some(language) = settings::get_language() {
			query_parts.push(format!("language:{language}"));
		}
		for blocked in blocklist.iter() {
			if !blocked.is_empty() {
				query_parts.push(format!("-tag:\"{blocked}\""));
			}
		}
		let query = query_parts.join(" ");

		// Fetched one at a time (through the rate limiter, retry and cache) instead of four
		// parallel requests, and each shelf is sent as soon as it arrives.
		let fetch = |sort: &str| -> Result<Vec<Manga>> {
			Ok(self
				.search(&query, 1, sort)?
				.result
				.into_iter()
				.map(|gallery| gallery.into())
				.collect::<Vec<Manga>>())
		};
		let listing_kind = || {
			if settings::get_list_viewer() {
				ListingKind::List
			} else {
				ListingKind::Default
			}
		};
		let mut first_error = None;

		match fetch("popular-today") {
			Ok(entries) if !entries.is_empty() => send_component(HomeComponent {
				title: Some("Popular Today".into()),
				subtitle: None,
				value: aidoku::HomeComponentValue::BigScroller {
					entries,
					auto_scroll_interval: Some(8.0),
				},
			}),
			Ok(_) => {}
			Err(error) => first_error = first_error.or(Some(error)),
		}

		match fetch("popular-week") {
			Ok(entries) if !entries.is_empty() => send_component(HomeComponent {
				title: Some("Popular This Week".into()),
				subtitle: None,
				value: aidoku::HomeComponentValue::MangaList {
					ranking: true,
					page_size: Some(3),
					entries: entries.into_iter().map(|item| item.into()).collect(),
					listing: Some(Listing {
						id: "popular-week".into(),
						name: "Popular This Week".into(),
						kind: listing_kind(),
					}),
				},
			}),
			Ok(_) => {}
			Err(error) => first_error = first_error.or(Some(error)),
		}

		match fetch("popular") {
			Ok(entries) if !entries.is_empty() => send_component(HomeComponent {
				title: Some("Popular All Time".into()),
				subtitle: None,
				value: aidoku::HomeComponentValue::MangaList {
					ranking: true,
					page_size: Some(3),
					entries: entries.into_iter().map(|item| item.into()).collect(),
					listing: Some(Listing {
						id: "popular".into(),
						name: "Popular All Time".into(),
						kind: listing_kind(),
					}),
				},
			}),
			Ok(_) => {}
			Err(error) => first_error = first_error.or(Some(error)),
		}

		match fetch("date") {
			Ok(entries) if !entries.is_empty() => send_component(HomeComponent {
				title: Some("Latest".into()),
				subtitle: None,
				value: aidoku::HomeComponentValue::Scroller {
					entries: entries.into_iter().map(|item| item.into()).collect(),
					listing: Some(Listing {
						id: "latest".into(),
						name: "Latest".into(),
						kind: listing_kind(),
					}),
				},
			}),
			Ok(_) => {}
			Err(error) => first_error = first_error.or(Some(error)),
		}

		if let Some(error) = first_error {
			return Err(error);
		}

		Ok(HomeLayout::default())
	}
}
