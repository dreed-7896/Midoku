use aidoku::{
	alloc::{string::String, vec::Vec},
	imports::defaults::defaults_get,
};
const TITLE_PREFERENCE_KEY: &str = "titlePreference";
const LANGUAGE_KEY: &str = "language";
const BLOCKLIST_KEY: &str = "blocklist";
const LIST_VIEWER_KEY: &str = "isListView";
const CLEAN_TITLES_KEY: &str = "cleanTitles";
const SAVED_ARTISTS_KEY: &str = "savedArtists";

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
