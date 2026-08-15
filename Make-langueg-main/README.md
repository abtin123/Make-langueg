# lang-sync — GitHub-hosted language packs for a nav app

Human-editable JSON per language in `locales/` → gzip-compressed into one
small `.lpk` file per language → published as GitHub Release assets → app
fetches `manifest.json` first, shows a language picker, downloads only the
`.lpk` file the user picks. Same shape as this repo's sibling `Make-voice`
(manifest-first, download-only, no server).

## Build locally

```
python scripts/build.py --locales-dir locales --out out
```

Produces:

```
out/en.lpk
out/fa.lpk
out/ar.lpk
out/manifest.json
```

Add a language: drop a new `locales/<code>.json` with the same keys as
`locales/en.json`, commit, done — the build warns (not fails) on missing
keys so partial translations still ship.

## Publish to GitHub (the "hosted, download-only" part)

Push the repo, then run the `build-and-publish-langpacks` workflow (Actions
tab → Run workflow, or just push a change under `locales/`). It builds all
`.lpk` files + `manifest.json` and publishes them as assets on a GitHub
Release (`langpacks-latest` by default). No server needed — the app
downloads straight from the release's asset URLs, same as `Make-voice`.

## `.lpk` format

Plain gzip of the locale's JSON. Read it with:

```
python scripts/extract_lpk.py out/fa.lpk
```

## App flow

1. Fetch **only** `manifest.json` from the release — a few KB, instant.
2. Render a language picker from `manifest["languages"]` keys.
3. When the user picks e.g. `fa`, download `manifest["languages"]["fa"]["file"]`,
   gunzip it, and load it as the app's active string table.
4. Compare `manifest["languages"][code]["version"]` against the locally
   installed version to skip re-downloading unchanged packs.

`manifest.json`:

```
{
  "version": 1,
  "languages": {
    "fa": {"file": "fa.lpk", "version": "a1b2c3d4e5f6", "size_bytes": 812, "sha256": "..."},
    "en": {"file": "en.lpk", "version": "9f8e7d6c5b4a", "size_bytes": 790, "sha256": "..."}
  }
}
```
