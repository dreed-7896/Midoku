//! Latest galleries from many artists without searching each one every time.
//!
//! The newest galleries of each followed artist tag are kept between launches together with a
//! watermark: the newest gallery id nhentai had at the last refresh. A refresh then only reads
//! nhentai's own latest uploads back to the watermark (usually one or two requests) and picks
//! out the followed artists' galleries by tag id. An artist is searched on its own once, when it
//! is first followed, or again when the gap since the last refresh is too long to read through.
use aidoku::{
	alloc::{String, Vec},
	imports::defaults::{DefaultValue, defaults_get, defaults_set},
};
use serde::{Deserialize, Serialize};

use crate::models::NHentaiGalleryListItem;

const STATE_KEY: &str = "artistFeedState";
/// Pages of latest uploads read before the gap counts as too long (25 galleries a page).
pub const MAX_SCAN_PAGES: i32 = 12;
/// Galleries kept per artist tag: one full search page, so page 2 continues where it ends.
const PER_TAG: usize = 25;
/// Upper bounds on what is stored, so the saved state stays small.
const MAX_ITEMS: usize = 3000;
const MAX_COVERED: usize = 600;

#[derive(Serialize, Deserialize, Default)]
pub struct FeedState {
	/// The language, tag and blocklist part of the query the state was built with.
	pub base: String,
	/// Newest gallery id seen in latest uploads at the last refresh.
	pub watermark: i32,
	/// Artist tags whose own search has been merged in, oldest first.
	pub covered: Vec<i32>,
	/// Stored galleries, newest first, with `tag_ids` trimmed to followed tags.
	pub items: Vec<NHentaiGalleryListItem>,
}

impl FeedState {
	pub fn load(base: &str) -> Self {
		defaults_get::<String>(STATE_KEY)
			.and_then(|json| serde_json::from_str::<FeedState>(&json).ok())
			.filter(|state| state.base == base)
			.unwrap_or_else(|| FeedState {
				base: base.into(),
				..Default::default()
			})
	}

	pub fn save(&self) {
		if let Ok(json) = serde_json::to_string(self) {
			defaults_set(STATE_KEY, DefaultValue::String(json));
		}
	}

	/// Forget everything but the base, e.g. after a gap too long to read through.
	pub fn reset(&mut self) {
		self.watermark = 0;
		self.covered.clear();
		self.items.clear();
	}

	pub fn is_covered(&self, tag: i32) -> bool {
		self.covered.contains(&tag)
	}

	pub fn mark_covered(&mut self, tag: i32) {
		if !self.covered.contains(&tag) {
			self.covered.push(tag);
		}
	}

	/// Add galleries, keeping only the tags in `followed` on each and skipping known ids.
	pub fn merge(&mut self, items: impl IntoIterator<Item = NHentaiGalleryListItem>, followed: &[i32]) {
		for mut item in items {
			item.tag_ids.retain(|id| followed.contains(id));
			if item.tag_ids.is_empty() {
				continue;
			}
			if let Some(existing) = self.items.iter_mut().find(|known| known.id == item.id) {
				for tag in item.tag_ids {
					if !existing.tag_ids.contains(&tag) {
						existing.tag_ids.push(tag);
					}
				}
			} else {
				self.items.push(item);
			}
		}
	}

	/// Sort newest first and drop what no longer needs keeping: galleries past the newest
	/// `PER_TAG` of every tag they carry, and tags no longer followed or covered.
	pub fn prune(&mut self, requested: &[i32]) {
		if self.covered.len() > MAX_COVERED {
			let extra = self.covered.len() - MAX_COVERED;
			self.covered.drain(0..extra);
		}
		let covered = self.covered.clone();
		self.items.sort_by_key(|item| core::cmp::Reverse(item.id));
		let mut counts: Vec<(i32, usize)> = Vec::new();
		self.items.retain_mut(|item| {
			item.tag_ids.retain(|tag| covered.contains(tag) || requested.contains(tag));
			let mut keep = false;
			for tag in &item.tag_ids {
				match counts.iter_mut().find(|(t, _)| t == tag) {
					Some((_, count)) => {
						if *count < PER_TAG {
							keep = true;
						}
						*count += 1;
					}
					None => {
						counts.push((*tag, 1));
						keep = true;
					}
				}
			}
			keep
		});
		self.items.truncate(MAX_ITEMS);
	}

	/// Stored galleries by any of `tags`, newest first.
	pub fn entries_for(&self, tags: &[i32]) -> Vec<NHentaiGalleryListItem> {
		self.items
			.iter()
			.filter(|item| item.tag_ids.iter().any(|tag| tags.contains(tag)))
			.cloned()
			.collect()
	}
}
