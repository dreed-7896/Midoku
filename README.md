# extensions

Midoku/Aidoku source list.

Add this URL in Midoku → Settings → Source Lists:

```
https://raw.githubusercontent.com/dreed-7896/extensions/main/index.min.json
```

## Sources

- **nhentai** (`multi.nhentai`, v100): based on the Aidoku-Community source (MIT/Apache-2.0).
  - The Artist filter matches the artist tag only (it used to search titles). Separate several artists with `|`; names with no artist tag are retried as a group/circle.
  - Language filter (Default / Any / English / Japanese / Chinese).
  - "Hide artist & tags in titles" filter and setting: `[Circle (Artist)] Title [English]` shows as `Title`.
  - Rate limited to 2 requests/second, retries on HTTP 429/503, caches search pages for 5 minutes, loads Home shelves one at a time.

## Building

```
rustup target add wasm32-unknown-unknown
python3 scripts/build.py
```
