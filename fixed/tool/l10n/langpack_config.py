#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Single source of truth for which languages this repo ships as
downloadable packs. Imported by tool/l10n/build_release.py and by
tests/validate_language_pack_contract.py so the two can never drift."""

LANGUAGES = [
    "ar", "cs", "da", "de", "el", "en", "es", "fa", "fi", "fr",
    "he", "hi", "hu", "id", "it", "ja", "ko", "nl", "no", "pl",
    "pt", "ro", "ru", "sv", "th", "tr", "uk", "ur", "vi", "zh",
]

NATIVE_NAMES = {
    "ar": "العربية", "cs": "Čeština", "da": "Dansk", "de": "Deutsch",
    "el": "Ελληνικά", "en": "English", "es": "Español", "fa": "فارسی",
    "fi": "Suomi", "fr": "Français", "he": "עברית", "hi": "हिन्दी",
    "hu": "Magyar", "id": "Bahasa Indonesia", "it": "Italiano",
    "ja": "日本語", "ko": "한국어", "nl": "Nederlands", "no": "Norsk",
    "pl": "Polski", "pt": "Português", "ro": "Română", "ru": "Русский",
    "sv": "Svenska", "th": "ไทย", "tr": "Türkçe", "uk": "Українська",
    "ur": "اردو", "vi": "Tiếng Việt", "zh": "中文",
}

RTL = {"fa", "ar", "he", "ur"}
