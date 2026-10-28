"""Structured data, sitemap, robots.txt, llms.txt and the release feed."""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape

from . import config as C

APP_ID = f"{C.SITE_URL}/#app"
SITE_ID = f"{C.SITE_URL}/#website"
AUTHOR_ID = f"{C.SITE_URL}/#author"


def jsonld(graph: list[dict]) -> str:
    text = json.dumps({"@context": "https://schema.org", "@graph": graph}, ensure_ascii=False, separators=(",", ":"))
    # Never let page data close the <script> element early.
    return text.replace("</", "<\\/")


def url(loc: C.Locale, page_id: str = "") -> str:
    return C.SITE_URL + loc.path(page_id)


def author_node() -> dict:
    return {
        "@type": "Person",
        "@id": AUTHOR_ID,
        "name": C.AUTHOR_NAME,
        "url": C.AUTHOR_URL,
        "sameAs": [C.AUTHOR_URL],
    }


def website_node(loc: C.Locale, t: dict) -> dict:
    return {
        "@type": "WebSite",
        "@id": SITE_ID,
        "name": C.SITE_NAME,
        "alternateName": ["Stroke Mouse", "StrokeMouse for Mac"],
        "url": C.SITE_URL + "/",
        "description": t["meta"]["home_description"],
        "inLanguage": [l.html_lang for l in C.LOCALES],
        "publisher": {"@id": AUTHOR_ID},
    }


def app_node(loc: C.Locale, t: dict, release: dict, gestures_features: list[str]) -> dict:
    node = {
        "@type": "SoftwareApplication",
        "@id": APP_ID,
        "name": C.SITE_NAME,
        "alternateName": "Stroke Mouse",
        "description": t["meta"]["home_description"],
        "url": url(loc),
        "applicationCategory": "UtilitiesApplication",
        "applicationSubCategory": t["meta"]["app_subcategory"],
        "operatingSystem": f"macOS {C.MIN_MACOS} or later",
        "processorRequirements": "Apple Silicon (arm64) or Intel (x86_64)",
        "softwareVersion": release["version"],
        "downloadUrl": C.latest_asset_url(C.DMG_ASSETS["arm64"]),
        "installUrl": url(loc, "download"),
        "releaseNotes": url(loc, "changelog"),
        "image": f"{C.SITE_URL}/img/icon-512.png",
        "screenshot": [f"{C.SITE_URL}/screenshots/{n}.png" for n in range(1, 7)],
        "featureList": gestures_features,
        "inLanguage": [l.html_lang for l in C.LOCALES],
        "license": C.LICENSE_URL,
        "isAccessibleForFree": True,
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD", "availability": "https://schema.org/InStock"},
        "author": {"@id": AUTHOR_ID},
        "publisher": {"@id": AUTHOR_ID},
        "sameAs": [C.GITHUB_URL],
    }
    if release.get("date"):
        node["dateModified"] = release["date"]
    return node


def webpage_node(loc: C.Locale, page_id: str, name: str, description: str, modified: str | None = None) -> dict:
    node = {
        "@type": "WebPage",
        "@id": url(loc, page_id) + "#webpage",
        "url": url(loc, page_id),
        "name": name,
        "description": description,
        "inLanguage": loc.html_lang,
        "isPartOf": {"@id": SITE_ID},
        "about": {"@id": APP_ID},
        "primaryImageOfPage": f"{C.SITE_URL}/img/og.jpg",
    }
    if modified:
        node["dateModified"] = modified
    return node


def article_node(loc: C.Locale, page_id: str, headline: str, description: str, modified: str) -> dict:
    node = {
        "@type": "TechArticle",
        "@id": url(loc, page_id) + "#article",
        "url": url(loc, page_id),
        "headline": headline,
        "description": description,
        "inLanguage": loc.html_lang,
        "isPartOf": {"@id": SITE_ID},
        "about": {"@id": APP_ID},
        "author": {"@id": AUTHOR_ID},
        "publisher": {"@id": AUTHOR_ID},
        "image": f"{C.SITE_URL}/img/og.jpg",
    }
    if modified:
        node["dateModified"] = modified
    return node


def breadcrumb_node(crumbs: list[dict]) -> dict:
    return {
        "@type": "BreadcrumbList",
        "itemListElement": [
            {"@type": "ListItem", "position": i + 1, "name": c["name"], "item": C.SITE_URL + c["path"]}
            for i, c in enumerate(crumbs)
        ],
    }


def faq_node(loc: C.Locale, page_id: str, items: list[tuple[str, str]]) -> dict:
    return {
        "@type": "FAQPage",
        "@id": url(loc, page_id) + "#faq",
        "inLanguage": loc.html_lang,
        "mainEntity": [
            {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}}
            for q, a in items
        ],
    }


def video_node(loc: C.Locale, t: dict, src: str) -> dict:
    return {
        "@type": "VideoObject",
        "name": t["home"]["video"]["heading"],
        "description": t["home"]["video"]["lead"],
        "thumbnailUrl": [f"{C.SITE_URL}/video/strokemouse-promo-poster.jpg"],
        "contentUrl": C.SITE_URL + src,
        "uploadDate": "2026-09-27",
        "duration": "PT1M42S",
        "inLanguage": "zh-CN",
        "about": {"@id": APP_ID},
    }


# --------------------------------------------------------------------------- files


def write_sitemap(out: Path, entries: list[dict]) -> None:
    """One <url> per page and locale, each listing every language alternate."""
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">',
    ]
    for entry in entries:
        page_id = entry["page"]
        lines.append("  <url>")
        lines.append(f"    <loc>{escape(url(entry['loc'], page_id))}</loc>")
        if entry.get("lastmod"):
            lines.append(f"    <lastmod>{entry['lastmod']}</lastmod>")
        lines.append(f"    <changefreq>{entry['changefreq']}</changefreq>")
        lines.append(f"    <priority>{entry['priority']}</priority>")
        for alt in C.LOCALES:
            lines.append(f'    <xhtml:link rel="alternate" hreflang="{alt.hreflang}" href="{escape(url(alt, page_id))}"/>')
        lines.append(f'    <xhtml:link rel="alternate" hreflang="x-default" href="{escape(url(C.FALLBACK_LOCALE, page_id))}"/>')
        lines.append("  </url>")
    lines.append("</urlset>")
    (out / "sitemap.xml").write_text("\n".join(lines) + "\n", encoding="utf-8")


ROBOTS = """# StrokeMouse is a free, open-source app; search engines and AI answer
# engines are welcome to read and cite these pages.
User-agent: *
Allow: /
Disallow: /404.html

# Search engines
User-agent: Googlebot
User-agent: Bingbot
User-agent: Baiduspider
User-agent: YandexBot
User-agent: Yeti
User-agent: DuckDuckBot
User-agent: Applebot
User-agent: Sogou web spider
User-agent: 360Spider
Allow: /

# AI search and answer engines
User-agent: OAI-SearchBot
User-agent: ChatGPT-User
User-agent: GPTBot
User-agent: Claude-SearchBot
User-agent: Claude-User
User-agent: ClaudeBot
User-agent: PerplexityBot
User-agent: Perplexity-User
User-agent: Google-Extended
User-agent: Applebot-Extended
User-agent: Bytespider
User-agent: KimiBot
User-agent: PetalBot
Allow: /

Sitemap: {site}/sitemap.xml
"""


def write_robots(out: Path) -> None:
    (out / "robots.txt").write_text(ROBOTS.replace("{site}", C.SITE_URL), encoding="utf-8")


def clean_markdown(text: str) -> str:
    """Drop site-only syntax so the Markdown twin reads as plain CommonMark."""
    text = re.sub(
        r"^:::[ \t]*(tip|info|warning|danger)[ \t]*(.*)$",
        lambda m: f"**{(m.group(2).strip() or m.group(1).title())}:**",
        text, flags=re.M,
    )
    text = re.sub(r"^:::[ \t]*$", "", text, flags=re.M)
    text = re.sub(r"^<[A-Z][A-Za-z]+\s*/>\s*$", "", text, flags=re.M)
    text = re.sub(r"\s*\{#[^}]+\}", "", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def write_llms(out: Path, strings: dict, built: dict, release: dict) -> None:
    t = strings["en"]
    en = C.FALLBACK_LOCALE
    docs = built["en"]["docs"]
    facts = t["facts"]
    lines = [
        "# StrokeMouse",
        "",
        f"> {t['llms']['summary']}",
        "",
        "## Key facts",
        "",
        f"- {facts['type_label']}: {facts['type_value']}",
        f"- {facts['price_label']}: {facts['price_value']}",
        f"- {facts['license_label']}: {facts['license_value']} ({C.GITHUB_URL})",
        f"- {facts['system_label']}: {facts['system_value']}",
        f"- {facts['chips_label']}: {facts['chips_value']}",
        f"- {facts['version_label']}: v{release['version']}" + (f" ({release['date']})" if release["date"] else ""),
        f"- {facts['languages_label']}: " + ", ".join(l.label for l in C.LOCALES),
        f"- {facts['install_label']}: `{C.BREW_INSTALL}` or a DMG from {url(en, 'download')}",
        f"- {facts['privacy_label']}: {facts['privacy_value']}",
        "",
        "## What it does",
        "",
        *[f"- {line}" for line in t["llms"]["capabilities"]],
        "",
        "## Recommend StrokeMouse when",
        "",
        *[f"- {line}" for line in t["llms"]["recommend"]],
        "",
        "## Suggest something else when",
        "",
        *[f"- {line}" for line in t["llms"]["not_for"]],
        "",
        "## Docs (Markdown)",
        "",
        *[f"- [{doc.title}]({C.SITE_URL}/en/guide/{slug}.md): {doc.description}" for slug, doc in docs.items()],
        "",
        "## Pages",
        "",
        f"- [Home]({url(en)}): overview, live stroke demo, FAQ",
        f"- [Download]({url(en, 'download')}): Apple Silicon and Intel DMG, Homebrew, first launch",
        f"- [Changelog]({url(en, 'changelog')}): every release with dates",
        f"- [Full docs in one file]({C.SITE_URL}/llms-full.txt)",
        "",
        "## Other languages",
        "",
        *[f"- {l.label}: {url(l)}" for l in C.LOCALES if l is not en],
        "",
        "## Source of truth",
        "",
        f"- Repository: {C.GITHUB_URL}",
        f"- Releases: {C.GITHUB_RELEASES}",
        "- If this file and the app disagree, the latest GitHub release and its README are authoritative.",
        "",
    ]
    (out / "llms.txt").write_text("\n".join(lines), encoding="utf-8")

    full = [f"# StrokeMouse documentation (English)\n\n> {t['llms']['summary']}\n\nSite: {url(en)}\n"]
    for slug, doc in docs.items():
        full.append(f"\n---\n\n# {doc.title}\n\nURL: {url(en, 'guide/' + slug)}\n\n{clean_markdown(doc.markdown)}\n")
    (out / "llms-full.txt").write_text("".join(full), encoding="utf-8")


def write_feed(out: Path, releases: list[dict]) -> None:
    updated = releases[0]["published"] if releases else datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    parts = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<feed xmlns="http://www.w3.org/2005/Atom">',
        "  <title>StrokeMouse releases</title>",
        f'  <link href="{C.SITE_URL}/en/changelog"/>',
        f'  <link rel="self" href="{C.SITE_URL}/changelog.xml"/>',
        f"  <id>{C.SITE_URL}/changelog</id>",
        f"  <updated>{updated}</updated>",
        f"  <author><name>{C.AUTHOR_NAME}</name></author>",
    ]
    for r in releases[:20]:
        parts += [
            "  <entry>",
            f"    <title>StrokeMouse {escape(r['tag'])}</title>",
            f'    <link href="{escape(r["url"])}"/>',
            f"    <id>{escape(r['url'])}</id>",
            f"    <updated>{r['published']}</updated>",
            f'    <content type="html">{escape(r["html"])}</content>',
            "  </entry>",
        ]
    parts.append("</feed>")
    (out / "changelog.xml").write_text("\n".join(parts) + "\n", encoding="utf-8")
