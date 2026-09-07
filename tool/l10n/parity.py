#!/usr/bin/env python3
"""Bring all 30 locales to full key parity, polish natural Persian/English,
and write a versioned manifest. Re-run after any change to app_localizations.dart.

Usage: python tool/l10n/parity.py
"""
from __future__ import annotations

import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / "assets" / "local"
SOURCE = ROOT / "lib" / "core" / "localization" / "app_localizations.dart"

LANGS = ["ar","cs","da","de","el","en","es","fa","fi","fr",
         "he","hi","hu","id","it","ja","ko","nl","no","pl",
         "pt","ro","ru","sv","th","tr","uk","ur","vi","zh"]

_SQ = re.compile(r"'((?:\\.|[^'\\])*)'\s*:\s*'((?:\\.|[^'\\])*)'", re.S)
_DQ = re.compile(r'"((?:\\.|[^"\\])*)"\s*:\s*"((?:\\.|[^"\\])*)"', re.S)


def _unescape(s: str) -> str:
    return (s.replace(r"\'","'").replace(r'\"','"')
             .replace(r"\\","\\").replace(r"\n","\n")
             .replace(r"\r","\r").replace(r"\t","\t"))


def extract_block(src: str, lang: str) -> str:
    s = src.index(f"'{lang}': {{") + len(f"'{lang}': {{")
    if lang == "fa":
        e = src.index("    'en': {", s)
    else:
        e = src.index("\n  };", s)
    return src[s:e]


def extract(src: str, lang: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for pat in (_SQ, _DQ):
        for m in pat.finditer(extract_block(src, lang)):
            k = _unescape(m.group(1)); v = _unescape(m.group(2))
            if k in out and out[k] != v:
                raise ValueError(f"duplicate key {k} in {lang}")
            out[k] = v
    return out


# Natural phrasing — applied as final word over whatever translation existed
EN_POLISH = {
    "ai_dashcam_title":"AI Dashcam",
    "ai_dashcam_desc":"Video recording and intelligent driver assistance",
    "hud_title":"Head-Up Display (HUD)",
    "hud_menu_desc":"Project route information onto your windshield",
    "hud_enable":"Turn on HUD",
    "hud_enable_desc":"Project route information onto your windshield",
    "hud_position":"Position on the windshield",
    "hud_position_desc":"Adjust the overall HUD placement on the glass",
    "hud_info_maneuver":"Next maneuver",
    "hud_launch":"Open HUD",
    "hud_no_active_navigation":"Start navigation to use HUD",
    "hud_arrived":"You have reached your destination",
    "dashcam_video_size":"Maximum clip length",
    "dashcam_video_size_unlimited":"Unlimited",
    "dashcam_driver_assistance":"Intelligent driver assistance",
    "dashcam_camera_lateral_displacement":"Camera lateral offset",
    "dashcam_forward_collision":"Forward-collision warning",
    "dashcam_dangerous_headway":"Unsafe following distance",
    "dashcam_stop_and_go":"Stop-and-go alert",
    "dashcam_lane_departure_solid":"Lane departure (solid line)",
    "dashcam_lane_departure_dashed":"Lane departure (dashed line)",
    "dashcam_traffic_sign_recognition":"Traffic-sign recognition",
    "delete_language_package_title":"Delete language pack",
    "delete_language_package_confirm":"Delete the \"{name}\" language pack?",
    "start_button":"Start",
    "route_road_prefix":"onto {road}",
    "route_maneuver_depart":"Head out{road}",
    "route_maneuver_arrive":"You have arrived at your destination",
    "route_maneuver_turn_left":"Turn left{road}",
    "route_maneuver_turn_right":"Turn right{road}",
    "route_maneuver_slight_left":"Bear left{road}",
    "route_maneuver_slight_right":"Bear right{road}",
    "route_maneuver_sharp_left":"Make a sharp left{road}",
    "route_maneuver_sharp_right":"Make a sharp right{road}",
    "route_maneuver_uturn":"Make a U-turn{road}",
    "route_maneuver_straight":"Continue straight{road}",
    "route_maneuver_continue":"Continue{road}",
    "route_maneuver_roundabout":"Enter the roundabout{road}",
    "route_maneuver_roundabout_exit":"Take exit {exit} from the roundabout{road}",
    "route_maneuver_merge":"Merge{road}",
    "route_maneuver_on_ramp":"Take the ramp{road}",
    "route_maneuver_off_ramp":"Exit the ramp{road}",
    "route_error_no_route":"No route found between origin and destination.",
    "route_error_no_segment":"Origin or destination is too far from a routable road.",
    "route_error_too_big":"The routing request is too large.",
    "route_error_online_failed":"The online routing service could not compute a route.",
    "route_error_offline_unavailable":"Online routing is not available in offline mode.",
    "route_error_offline_not_found":"No route found on the offline map.",
    "route_error_online_not_found":"No route found between origin and destination.",
    "route_error_invalid_coordinates":"Origin or destination coordinates are invalid.",
    "route_error_unreadable_response":"The routing service response is unreadable.",
    "route_error_invalid_geometry":"The online route geometry is incomplete or invalid.",
    "route_error_invalid_response":"The online routing response has an invalid format.",
    "route_error_connection":"Could not connect to the online routing service.",
    "route_error_unexpected":"An unexpected error occurred in online routing.",
    "route_error_http":"The online routing service returned an invalid response ({code}).",
    "route_error_timeout":"The online routing response timed out. Check your internet connection.",
    "route_error_offline_map_missing":"Install an ABM offline map before routing.",
    "route_error_offline_generic":"Error in ABTINMAP offline routing: {error}",
    "route_error_offline_alternatives":"Error building offline ABTINMAP alternative routes: {error}",
    "route_error_online_failed_generic":"Online routing failed.",
    "route_duration_minutes":"{value} min",
    "route_duration_hours_minutes":"{hours} h {minutes} min",
    "route_no_destination":"No destination selected",
    "route_open_map_destination":"Long-press the map to choose a destination.",
    "route_destination_ready":"Destination is ready for routing",
    "route_location_unavailable":"Current location is unavailable",
    "route_location_ready":"Current location is ready",
    "route_avoid_highways":"Avoid highways",
    "route_avoid_highways_desc":"Stay off motorways when possible",
    "route_avoid_special_areas":"Avoid restricted areas",
    "route_avoid_special_areas_desc":"Skip environmentally restricted zones",
    "route_avoid_tolls_settings":"Avoid toll roads",
    "route_avoid_tolls_settings_desc":"Prefer toll-free roads",
    "route_avoid_traffic":"Avoid traffic",
    "route_avoid_traffic_desc":"Prefer roads with lighter traffic",
    "route_color_card_title":"Route color",
    "route_color_card_desc":"Pick the route line color",
    "route_extra_settings_title":"Advanced route options",
    "route_extra_settings_desc":"Fine-tune routing preferences",
    "route_line_dashed":"Dashed","route_line_dotted":"Dotted",
    "route_line_double":"Double","route_line_solid":"Solid",
    "route_line_variable":"Variable",
    "route_line_type_title":"Route line style",
    "route_line_type_desc":"Choose how the route line is drawn",
    "route_multi_destination":"Multiple destinations",
    "route_multi_destination_desc":"Plan a trip with several stops",
    "route_pixels_value":"{value} px",
    "route_show_summary":"Show route summary",
    "route_show_summary_desc":"Display total distance and time at the top",
    "route_speed_warning":"Speed warning",
    "route_speed_warning_desc":"Notify me when I exceed the limit",
    "route_thick":"Thick","route_thin":"Thin",
    "route_thickness_title":"Route line thickness",
    "route_thickness_desc":"Choose how thick the route line is drawn",
    "route_type_title":"Route preference",
    "route_type_desc":"Choose how the best route is picked",
    "route_type_fastest":"Fastest",
    "route_type_fastest_desc":"Minimize travel time",
    "route_type_economic":"Most economical",
    "route_type_economic_desc":"Save fuel and battery",
    "route_type_optimal":"Optimal",
    "route_type_optimal_desc":"Balance speed and distance",
    "no_places_yet":"No saved places yet",
    "as_preset_custom_hint":"Type a name for this preset",
    "settings_brand_tagline":"Smart offline navigator",
}

FA_POLISH = {
    "ai_dashcam_title":"دوربین هوشمند",
    "hud_title":"هدآپ دیسپلی (HUD)",
    "hud_menu_desc":"نمایش اطلاعات مسیر روی شیشهٔ جلو",
    "hud_enable":"فعال‌سازی HUD",
    "hud_position":"موقعیت روی شیشه",
    "hud_arrived":"به مقصد رسیدید",
    "dashcam_video_size_unlimited":"نامحدود",
    "route_road_prefix":"به سمت {road}",
    "route_maneuver_roundabout":"وارد میدان شوید{road}",
    "route_maneuver_roundabout_exit":"از خروجی {exit} میدان خارج شوید{road}",
    "route_maneuver_uturn":"دور بزنید{road}",
    "route_maneuver_arrive":"به مقصد رسیدید",
    "no_places_yet":"هنوز مکانی ذخیره نشده است",
    "as_preset_custom_hint":"نام این تنظیم آماده را وارد کنید",
    "settings_brand_tagline":"مسیریاب هوشمند آفلاین",
}


def main() -> int:
    src = SOURCE.read_text(encoding="utf-8")
    src_fa = extract(src, "fa")
    src_en = extract(src, "en")

    locales = {p.stem: json.loads(p.read_text(encoding="utf-8"))
               for p in LOCAL.glob("*.json") if p.name != "manifest.json"}

    union = set(src_fa) | set(src_en)
    for d in locales.values():
        union |= set(d.keys())

    ph = re.compile(r"\{[a-z_][a-z0-9_]*\}")
    def phs(s: str) -> set[str]:
        return set(ph.findall(s))

    out = {}
    for code in LANGS:
        existing = locales.get(code, {})
        merged = dict(existing)
        if code == "fa":
            merged.update(src_fa); merged.update(FA_POLISH)
        elif code == "en":
            merged.update(src_en); merged.update(EN_POLISH)
        # ensure every key
        for k in union:
            if not merged.get(k):
                merged[k] = (FA_POLISH.get(k) or src_fa.get(k)
                             or EN_POLISH.get(k) or src_en.get(k) or k)
        # placeholder parity with fa
        for k in list(merged):
            fph = phs(src_fa.get(k, ""))
            if fph and phs(merged[k]) != fph:
                # try fa fallback first, then en
                cand = src_fa.get(k) or src_en.get(k) or merged[k]
                if phs(cand) == fph:
                    merged[k] = cand
        out[code] = dict(sorted(merged.items()))

    for code, data in out.items():
        (LOCAL / f"{code}.json").write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8")

    manifest = {
        "version": 2, "schema_version": 2,
        "source": "lib/core/localization/app_localizations.dart",
        "key_count": len(union),
        "languages": LANGS, "fallback_language": "en",
        "base_language": "fa",
        "generated_by": "tool/l10n/parity.py",
    }
    (LOCAL / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8")

    # self-check
    bad = []
    for k in union:
        fph = phs(out["fa"].get(k, ""))
        if not fph: continue
        for code, d in out.items():
            if code == "fa": continue
            if phs(d.get(k, "")) != fph:
                bad.append((k, code))
    print(f"Wrote {len(LANGS)} locales x {len(union)} keys")
    print(f"Placeholder parity issues: {len(bad)}")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
