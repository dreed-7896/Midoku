use aidoku::{
	alloc::{String, Vec},
	imports::defaults::{DefaultValue, defaults_get, defaults_set},
};

const LANGUAGE_KEY: &str = "language";
const TITLE_PREFERENCE_KEY: &str = "titlePreference";
const SAVED_ARTISTS_KEY: &str = "savedArtists";
const AUTO_SAVE_ARTISTS_KEY: &str = "autoSaveArtists";
const MAX_SAVED_ARTISTS: usize = 100;

pub fn get_nozomi_language() -> String {
	defaults_get::<String>(LANGUAGE_KEY)
		.map(|lang| match lang.as_str() {
			"en" => "english".into(),
			"id" => "indonesian".into(),
			"jv" => "javanese".into(),
			"ca" => "catalan".into(),
			"ceb" => "cebuano".into(),
			"cs" => "czech".into(),
			"da" => "danish".into(),
			"de" => "german".into(),
			"et" => "estonian".into(),
			"es" => "spanish".into(),
			"eo" => "esperanto".into(),
			"fr" => "french".into(),
			"it" => "italian".into(),
			"hi" => "hindi".into(),
			"hu" => "hungarian".into(),
			"pl" => "polish".into(),
			"pt" => "portuguese".into(),
			"vi" => "vietnamese".into(),
			"tr" => "turkish".into(),
			"ru" => "russian".into(),
			"uk" => "ukrainian".into(),
			"ar" => "arabic".into(),
			"ko" => "korean".into(),
			"zh" => "chinese".into(),
			"ja" => "japanese".into(),
			_ => "all".into(),
		})
		.unwrap_or_else(|| "all".into())
}

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
			_ => Self::English,
		}
	}
}

pub fn get_title_preference() -> TitlePreference {
	defaults_get::<String>(TITLE_PREFERENCE_KEY)
		.map(TitlePreference::from)
		.unwrap_or_default()
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
