"""Site-wide constants: locales, URLs, paths and the app version.

The app version is read from the repository's `project.yml`, so `bump.sh`
no longer needs to touch the website.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

WEBSITE_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = WEBSITE_DIR.parent
CONTENT_DIR = WEBSITE_DIR / "content"
TEMPLATE_DIR = WEBSITE_DIR / "templates"
STATIC_DIR = WEBSITE_DIR / "static"
DEFAULT_OUT_DIR = WEBSITE_DIR / "dist"

SITE_NAME = "StrokeMouse"
SITE_URL = "https://strokemouse.com"
GITHUB_REPO = "Licoy/StrokeMouse"
GITHUB_URL = f"https://github.com/{GITHUB_REPO}"
GITHUB_RELEASES = f"{GITHUB_URL}/releases"
HOMEBREW_TAP_URL = "https://github.com/Licoy/homebrew-tap"
AUTHOR_NAME = "Licoy"
AUTHOR_URL = "https://github.com/Licoy"
LICENSE_NAME = "AGPL-3.0"
LICENSE_URL = "https://www.gnu.org/licenses/agpl-3.0.html"
MIN_MACOS = "14"

BREW_INSTALL = "brew install --cask licoy/tap/strokemouse"
BREW_UPGRADE = "brew upgrade --cask --greedy strokemouse"
BREW_UNINSTALL = "brew uninstall --cask strokemouse"
BREW_ZAP = "brew uninstall --cask --zap strokemouse"

# `releases/latest/download/<asset>` always points at the newest release, so
# links stay valid between a version bump commit and the published release.
DMG_ASSETS = {
    "arm64": "StrokeMouse-macos-arm64.dmg",
    "x86_64": "StrokeMouse-macos-x86_64.dmg",
}


def latest_asset_url(filename: str) -> str:
    return f"{GITHUB_RELEASES}/latest/download/{filename}"


@dataclass(frozen=True)
class Locale:
    code: str  # content directory and template key
    store: str  # value kept in localStorage (matches the previous site)
    prefix: str  # URL prefix, "" for the root locale
    label: str  # native name shown in the language menu
    html_lang: str
    hreflang: str
    og_locale: str

    def path(self, page: str = "") -> str:
        """URL path for a page id such as "", "download" or "guide/faq"."""
        base = f"{self.prefix}/"
        return base + page if page else base


LOCALES: list[Locale] = [
    Locale("zh-hans", "root", "", "简体中文", "zh-CN", "zh-Hans", "zh_CN"),
    Locale("en", "en", "/en", "English", "en", "en", "en_US"),
    Locale("zh-hant", "zh-hant", "/zh-hant", "繁體中文", "zh-Hant", "zh-Hant", "zh_TW"),
    Locale("ko", "ko", "/ko", "한국어", "ko", "ko", "ko_KR"),
    Locale("ja", "ja", "/ja", "日本語", "ja", "ja", "ja_JP"),
    Locale("ru", "ru", "/ru", "Русский", "ru", "ru", "ru_RU"),
    Locale("fr", "fr", "/fr", "Français", "fr", "fr", "fr_FR"),
]
LOCALE_BY_CODE = {loc.code: loc for loc in LOCALES}
DEFAULT_LOCALE = LOCALE_BY_CODE["zh-hans"]
# Unmatched browser languages and x-default hreflang go to English.
FALLBACK_LOCALE = LOCALE_BY_CODE["en"]

# Docs sidebar: (group key in `ui.sidebar`, [page slugs]).
GUIDE_GROUPS: list[tuple[str, list[str]]] = [
    ("start", ["getting-started", "installation", "permissions"]),
    ("manual", ["gestures", "actions", "settings", "config-file"]),
    ("help", ["faq"]),
]
GUIDE_SLUGS = [slug for _, slugs in GUIDE_GROUPS for slug in slugs]

# Pages that exist in every locale; the first-visit redirect only targets these.
PAGE_IDS = ["", "download", "changelog", *[f"guide/{s}" for s in GUIDE_SLUGS]]


def read_app_version() -> str:
    text = (REPO_DIR / "project.yml").read_text(encoding="utf-8")
    match = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text)
    if not match:
        raise SystemExit("MARKETING_VERSION not found in project.yml")
    return match.group(1)
