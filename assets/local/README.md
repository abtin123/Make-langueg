# Localized UI assets

Only `fa.json` (Persian) and `en.json` (English) are bundled into the APK.
The other locales live under `tool/l10n/source/` and are compressed into
`.abl` packs for the GitHub `langpacks-latest` release.

Run from the project root:

```bash
python tool/l10n/build_release.py
```

The generated `out/` folder contains the 28 downloadable language packs and
`manifest.json`. Upload those files to the `langpacks-latest` GitHub Release.
