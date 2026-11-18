use aidoku::{
	alloc::{string::String, vec::Vec},
	imports::defaults::{DefaultValue, defaults_get, defaults_set},
};
const TITLE_PREFERENCE_KEY: &str = "titlePreference";
const LANGUAGE_KEY: &str = "language";
const BLOCKLIST_KEY: &str = "blocklist";
const LIST_VIEWER_KEY: &str = "isListView";
const CLEAN_TITLES_KEY: &str = "cleanTitles";
const SAVED_ARTISTS_KEY: &str = "savedArtists";
const AUTO_SAVE_ARTISTS_KEY: &str = "autoSaveArtists";
const MAX_SAVED_ARTISTS: usize = 100;

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum TitlePreference {
	#[default]
	English,
	Japanese,
}

impl From<String> for TitlePreference {
	fn from(value: String) -> Self {
		match value.as_str() {
			"japanese" => Self::Japanese,
			"english" => Self::English,
			_ => Self::English,
		}
	}
}

pub fn get_title_preference() -> TitlePreference {
	defaults_get::<String>(TITLE_PREFERENCE_KEY)
		.map(TitlePreference::from)
		.unwrap_or_default()
}

pub fn get_language() -> Option<String> {
	defaults_get::<String>(LANGUAGE_KEY).and_then(|lang| match lang.as_str() {
		"en" => Some("english".into()),
		"ja" => Some("japanese".into()),
		"zh" => Some("chinese".into()),
		_ => None,
	})
}

pub fn get_blocklist() -> Vec<String> {
	defaults_get::<Vec<String>>(BLOCKLIST_KEY)
		.unwrap_or_default()
		.into_iter()
		.map(|s| s.trim().to_lowercase())
		.filter(|s| !s.is_empty())
		.collect()
}

pub fn get_list_viewer() -> bool {
	defaults_get(LIST_VIEWER_KEY).unwrap_or(false)
}

/// Whether titles should drop their bracketed circle/artist, language and translator parts.
pub fn get_clean_titles() -> bool {
	defaults_get(CLEAN_TITLES_KEY).unwrap_or(false)
}

/// Artists saved in the source settings, offered as a pick list in the search filters.
pub fn get_saved_artists() -> Vec<String> {
	let mut artists: Vec<String> = Vec::new();
	for artist in defaults_get::<Vec<String>>(SAVED_ARTISTS_KEY).unwrap_or_default() {
		let artist = artist.trim().to_lowercase();
		if !artist.is_empty() && !artists.contains(&artist) {
			artists.push(artist);
		}
	}
	artists
}

/// Add artists that a search found to Saved Artists (if enabled), so they show up as chips.
pub fn remember_artists(found: &[String]) {
	if found.is_empty() || !defaults_get::<bool>(AUTO_SAVE_ARTISTS_KEY).unwrap_or(true) {
		return;
	}
	let mut saved: Vec<String> = defaults_get::<Vec<String>>(SAVED_ARTISTS_KEY).unwrap_or_default();
	let mut changed = false;
	for name in found {
		let name = name.trim().to_lowercase();
		if !name.is_empty()
			&& saved.len() < MAX_SAVED_ARTISTS
			&& !saved.iter().any(|s| s.trim().to_lowercase() == name)
		{
			saved.push(name);
			changed = true;
		}
	}
	if changed {
		defaults_set(SAVED_ARTISTS_KEY, DefaultValue::StringArray(saved));
	}
}
