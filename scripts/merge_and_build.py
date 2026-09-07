#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Merge the 116 new translated keys into every locale, update base_strings,
then rebuild the .abl language packs and manifest (547 keys per language)."""
import json, re, sys, gzip, hashlib
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path("/home/user/projects/lang/Make-langueg-fixed")
NEWTRANS = ROOT / "scripts" / "newtrans"
LOCALES = ROOT / "locales"
OUT = ROOT / "out"

# ---- 1. Load canonical new keys (fa + en from the app) ----
ref = json.load(open(NEWTRANS / "keys_fa_en.json", encoding="utf-8"))
canon = list(ref.keys())
print("canonical new keys:", len(canon))

# ---- 2. Load translation files, fixing stray `" "key` syntax ----
def load_translations():
    T = {}
    for mod in ["tr_a", "tr_b", "tr_c"]:
        text = (NEWTRANS / f"{mod}.py").read_text(encoding="utf-8")
        # fix `" "key"` -> `"key"` (stray space inside quote)
        text = re.sub(r'" "([a-z_][a-z0-9_]*)":', r'"\1":', text)
        ns = {}
        exec(compile(text, mod, "exec"), ns)
        T.update(ns["T"])
    return T

T = load_translations()
print("loaded languages:", len(T))

# ---- 3. Corrections for wrong keys / placeholder typos ----
FIX = {
 ("tr","dash_camera_traffic_sign_recognition"): "dashcam_traffic_sign_recognition",
 ("uk","hhud_info_speed_limit"): "hud_info_speed_limit",
 ("uk","hud_no_active_navigtion"): "hud_no_active_navigation",
 ("uk","hud_hud_arrived"): "hud_arrived",
 ("uk","ddashcam_level_low"): "dashcam_level_low",
 ("uk","route_maneueuver_uturn"): "route_maneuver_uturn",
 ("uk","route_error_offlineine_unavailable"): "route_error_offline_unavailable",
 ("uk","alert_trafik_light"): "alert_traffic_light",
 ("zh","hud_info_mananeuver"): "hud_info_maneuver",
 ("zh","route_maneueuver_continue"): "route_maneuver_continue",
 ("zh","route_maneuver__off_ramp"): "route_maneuver_off_ramp",
 ("ur","hhud_preview"): "hud_preview",
}
for (lang, wrong), right in FIX.items():
    if wrong in T[lang]:
        T[lang][right] = T[lang].pop(wrong)

# fix double-brace placeholders like {{road}} / {{code}} / {{name}}
def fix_braces(v):
    return v.replace("{{", "{").replace("}}", "}")
for lang, d in T.items():
    for k, v in d.items():
        if "{{" in v or "}}" in v:
            d[k] = fix_braces(v)

# ---- 4. Validate every language ----
def ph(s):
    return set(re.findall(r"\{[a-zA-Z_][a-zA-Z0-9_]*\}", s))

problems = []
for lang in sorted(T):
    d = T[lang]
    missing = set(canon) - set(d)
    extra = set(d) - set(canon)
    bad = []
    for k in canon:
        if k not in d:
            continue
        if ph(ref[k]["fa"]) != ph(d[k]):
            bad.append((k, sorted(ph(ref[k]["fa"])), sorted(ph(d[k]))))
    if missing or extra or bad:
        problems.append((lang, sorted(missing), sorted(extra), bad))
if problems:
    for lang, miss, extra, bad in problems:
        print(f"PROBLEM {lang}: missing={miss} extra={extra} badph={bad}")
    sys.exit(1)
print("ALL TRANSLATIONS VALID for", len(T), "languages")

# ---- 5. Build base_strings.json (fa source + new keys) ----
base = json.load(open(ROOT / "examples" / "base_strings.json", encoding="utf-8"))
for k in canon:
    base[k] = ref[k]["fa"]
json.dump(base, open(ROOT / "examples" / "base_strings.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=2, sort_keys=True)
print("base_strings updated to", len(base), "keys")

# ---- 6. Merge into every locale ----
locale_codes = sorted(p.stem for p in LOCALES.glob("*.json"))
print("locales:", locale_codes)
for code in locale_codes:
    path = LOCALES / f"{code}.json"
    d = json.load(open(path, encoding="utf-8"))
    if code == "fa":
        for k in canon:
            d[k] = ref[k]["fa"]
    elif code == "en":
        for k in canon:
            d[k] = ref[k]["en"]
    else:
        if code not in T:
            print("MISSING TRANSLATION for", code)
            sys.exit(1)
        for k in canon:
            d[k] = T[code][k]
    json.dump(d, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2, sort_keys=True)
    print(f"  {code}: {len(d)} keys")

# ---- 7. Rebuild .abl packs + manifest (all 30 locales incl fa/en) ----
sys.path.insert(0, str(ROOT / "scripts"))
from language_catalog import LANGUAGES

expected = set(base)
out_dir = OUT
out_dir.mkdir(parents=True, exist_ok=True)
languages = []
for code, (english_name, native_name, flag, direction) in LANGUAGES.items():
    path = LOCALES / f"{code}.json"
    values = json.load(open(path, encoding="utf-8"))
    if set(values) != expected:
        print(f"INCOMPLETE {code}: missing={len(expected-set(values))} extra={len(set(values)-expected)}")
        sys.exit(1)
    raw = json.dumps(values, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    packed = gzip.compress(raw, compresslevel=9, mtime=0)
    (out_dir / f"lang_{code}.abl").write_bytes(packed)
    languages.append({
        "language_code": code, "language": native_name, "english_name": english_name,
        "flag": flag, "direction": direction,
        "version": hashlib.sha256(raw).hexdigest()[:16],
        "string_count": len(values), "size": len(packed),
        "sha256": hashlib.sha256(packed).hexdigest(),
        "download_url": f"https://github.com/abtin123/Make-langueg/releases/download/langpacks-latest/lang_{code}.abl",
    })
manifest = {
    "schema_version": 2,
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "app_strings": "non-map-ui",
    "base_language": "fa",
    "string_count": len(base),
    "languages": sorted(languages, key=lambda i: i["language_code"]),
}
(out_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("BUILT", len(languages), "packs with", len(base), "strings each ->", out_dir)
