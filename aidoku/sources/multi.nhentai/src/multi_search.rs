//! `a | b` searches in the query box: each alternative is searched on its own and the
//! results are merged (see `NHentai::search_all`).
use aidoku::alloc::{String, Vec};

/// The separate terms of a query written as `term one | term two`, or `None` for a plain query.
pub fn terms(query: Option<&str>) -> Option<Vec<String>> {
	let query = query?;
	if !query.contains('|') {
		return None;
	}
	let terms: Vec<String> = query
		.split('|')
		.map(str::trim)
		.filter(|term| !term.is_empty())
		.map(String::from)
		.collect();
	if terms.is_empty() { None } else { Some(terms) }
}
