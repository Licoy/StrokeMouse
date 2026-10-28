#!/usr/bin/env python3
"""Render the StrokeMouse website into static files.

    python3 build.py                 # build into ./dist
    python3 build.py --serve         # build, serve on :9243 and rebuild on change
    python3 build.py --offline       # skip the GitHub Releases API

Every page is rendered server-side from Jinja templates, per-locale TOML
strings and Markdown guides. The output is plain HTML/CSS/JS that GitHub
Pages serves as-is.
"""

from __future__ import annotations

import argparse
import functools
import hashlib
import http.server
import json
import os
import re
import shutil
import sys
import threading
import time
import tomllib
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape

from jinja2 import Environment, FileSystemLoader, StrictUndefined
from markupsafe import Markup, escape

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sitegen import config as C  # noqa: E402
from sitegen import seo  # noqa: E402
from sitegen.docs import Doc, load_doc, render_markdown, strip_tags  # noqa: E402

PROMO_VIDEO = "/video/strokemouse-promo.mp4?v=d269ecf1"
SCREENSHOTS = [
    {"n": 1, "w": 2032, "h": 1342},
    {"n": 2, "w": 1720, "h": 1160},
    {"n": 3, "w": 1800, "h": 1144},
    {"n": 4, "w": 1800, "h": 1144},
    {"n": 5, "w": 1120, "h": 1120},
    {"n": 6, "w": 1120, "h": 1120},
]
# The seven built-in mouse strokes (`DefaultGestures.make`), drawn in a 100×100
# box with y pointing down. `seq` is the direction sequence the pad recognizes.
DEFAULT_GESTURES = [
    {"key": "up", "seq": "U", "d": "M50 88V12", "start": [50, 88]},
    {"key": "down", "seq": "D", "d": "M50 12V88", "start": [50, 12]},
    {"key": "downLeft", "seq": "DL", "d": "M64 12V66H14", "start": [64, 12]},
    {"key": "downRight", "seq": "DR", "d": "M36 12V66H86", "start": [36, 12]},
    {"key": "upRight", "seq": "UR", "d": "M30 88V34H84", "start": [30, 88]},
    {"key": "rightLeft", "seq": "RL", "d": "M12 42H82Q90 50 82 58H12", "start": [12, 42]},
    {"key": "upLeft", "seq": "UL", "d": "M70 88V34H16", "start": [70, 88]},
]
SIGNING_NOTE_RE = re.compile(
    r"\n*These builds use a stable self-signed.*?(?=\n#|\Z)", re.S
)


# --------------------------------------------------------------------------- data


def deep_merge(base: dict, override: dict) -> dict:
    out = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = value
    return out


def load_strings() -> dict[str, dict]:
    """Per-locale strings; anything missing falls back to English."""
    english = tomllib.loads((C.CONTENT_DIR / "en" / "site.toml").read_text(encoding="utf-8"))
    strings = {}
    for loc in C.LOCALES:
        own = tomllib.loads((C.CONTENT_DIR / loc.code / "site.toml").read_text(encoding="utf-8"))
        strings[loc.code] = deep_merge(english, own)
    return strings


def fetch_releases(offline: bool) -> list[dict]:
    """Published releases from GitHub, newest first ([] when unavailable)."""
    if offline:
        return []
    request = urllib.request.Request(
        f"https://api.github.com/repos/{C.GITHUB_REPO}/releases?per_page=30",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "strokemouse-site"},
    )
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            data = json.load(response)
    except Exception as error:  # noqa: BLE001 — the site must build without network
        print(f"warning: GitHub releases unavailable ({error}); changelog left empty", file=sys.stderr)
        return []
    releases = []
    for item in data:
        if item.get("draft") or item.get("prerelease"):
            continue
        body = SIGNING_NOTE_RE.sub("", (item.get("body") or "").replace("\r\n", "\n")).strip()
        releases.append({
            "tag": item["tag_name"],
            "version": item["tag_name"].lstrip("v"),
            "date": (item.get("published_at") or "")[:10],
            "published": item.get("published_at") or "",
            "url": item["html_url"],
            "markdown": body,
            "html": render_markdown(body, {}, {}) if body else "",
        })
    return releases


# --------------------------------------------------------------------------- helpers


def kbd_filter(text: str) -> Markup:
    """`{Key}` → <kbd>Key</kbd>, everything else escaped."""
    parts = re.split(r"\{([^{}]+)\}", str(text))
    out = []
    for i, part in enumerate(parts):
        out.append(f"<kbd>{escape(part)}</kbd>" if i % 2 else str(escape(part)))
    return Markup("".join(out))


def unkbd_filter(text: str) -> str:
    """`{⌃}{↑}` → `⌃↑`, for attributes where markup cannot go."""
    return re.sub(r"\{([^{}]+)\}", r"\1", str(text))


def inline_links_filter(text: str, loc: C.Locale) -> Markup:
    """`[label](page-id)` → link to that page in the current locale."""
    out, last = [], 0
    for match in re.finditer(r"\[([^\]]+)\]\(([^)]+)\)", str(text)):
        out.append(str(escape(text[last:match.start()])))
        target = match.group(2)
        href = target if target.startswith(("http", "/", "#")) else loc.path(target)
        out.append(f'<a href="{escape(href)}">{escape(match.group(1))}</a>')
        last = match.end()
    out.append(str(escape(text[last:])))
    return Markup("".join(out))


def plain_links(text: str) -> str:
    return re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)


def page_file(out: Path, path: str) -> Path:
    """Clean URLs: /guide/faq → guide/faq.html, /en/ → en/index.html."""
    rel = path.strip("/")
    if path.endswith("/"):
        return out / rel / "index.html" if rel else out / "index.html"
    return out / f"{rel}.html"


def head_script(redirect: str) -> str:
    theme = (
        "(function(){try{var p=localStorage.getItem('sm-theme')||'auto';"
        "var d=p==='dark'||(p==='auto'&&matchMedia('(prefers-color-scheme: dark)').matches);"
        "document.documentElement.dataset.theme=d?'dark':'light';"
        "document.documentElement.dataset.themePref=p}catch(e){"
        "if(matchMedia('(prefers-color-scheme: dark)').matches)document.documentElement.dataset.theme='dark'}})();"
    )
    return theme + redirect


def locale_redirect_script() -> str:
    """First-visit language detection, ported from the previous site.

    Unprefixed (Simplified Chinese) URLs follow the remembered choice or the
    browser languages; prefixed URLs only remember the choice. Crawlers never
    redirect.
    """
    prefixes = {loc.store: loc.prefix for loc in C.LOCALES if loc.prefix}
    return (
        "(function(){try{"
        f"var K='sm-locale',F={json.dumps(C.FALLBACK_LOCALE.store)},P={json.dumps(prefixes)},"
        f"G={json.dumps([p for p in C.PAGE_IDS])};"
        "function save(v){try{localStorage.setItem(K,v)}catch(e){}}"
        "function match(id){var s=String(id||'').replace(/_/g,'-').toLowerCase().split('-');"
        "var l=s[0];if(!l)return null;if(l==='en'||l==='ko'||l==='ja'||l==='ru'||l==='fr')return l;"
        "if(l!=='zh')return null;for(var i=1;i<s.length;i++){if(s[i]==='hant'||s[i]==='tw'||s[i]==='hk'||s[i]==='mo')return 'zh-hant'}"
        "return 'root'}"
        "var path=location.pathname.replace(/\\/index\\.html$/,'/').replace(/\\.html$/,'');"
        "var clean=path.replace(/\\/$/,'')||'/';"
        "for(var k in P){if(clean===P[k]||clean.indexOf(P[k]+'/')===0){save(k);return}}"
        "if(/bot|crawl|spider|slurp|bingpreview|facebookexternalhit|linkedinbot|embedly|quora|pinterest|redditbot|whatsapp|telegram|skypeuri|vkshare|w3c_validator|lighthouse|gptbot|claude|perplexity/i.test(navigator.userAgent||''))return;"
        "var t=null;try{t=localStorage.getItem(K)}catch(e){}"
        "if(t&&t!=='root'&&!P[t])t=null;"
        "if(!t){var L=(navigator.languages&&navigator.languages.length)?navigator.languages:[navigator.language];"
        "for(var j=0;j<L.length;j++){t=match(L[j]);if(t)break}if(!t)t=F;save(t)}"
        "if(t==='root')return;var id=clean==='/'?'':clean.slice(1);"
        "if(G.indexOf(id)<0)return;"
        "location.replace(P[t]+'/'+id+location.search+location.hash)"
        "}catch(e){}})();"
    )


# --------------------------------------------------------------------------- build


class Site:
    def __init__(self, out: Path, releases: list[dict]):
        self.out = out
        self.strings = load_strings()
        self.releases = releases
        project_version = C.read_app_version()
        latest = self.releases[0] if self.releases else None
        self.release = {
            "version": latest["version"] if latest else project_version,
            "date": latest["date"] if latest else "",
        }
        self.asset_versions: dict[str, str] = {}
        self.sitemap: list[dict] = []
        self.env = Environment(
            loader=FileSystemLoader(C.TEMPLATE_DIR),
            autoescape=True,
            undefined=StrictUndefined,
            trim_blocks=False,
            lstrip_blocks=False,
        )
        self.env.filters["kbd"] = kbd_filter
        self.env.filters["unkbd"] = unkbd_filter
        self.env.filters["inline_links"] = inline_links_filter
        self.env.globals.update(
            locales=C.LOCALES,
            site_url=C.SITE_URL,
            github_url=C.GITHUB_URL,
            releases_url=C.GITHUB_RELEASES,
            homebrew_tap_url=C.HOMEBREW_TAP_URL,
            author_url=C.AUTHOR_URL,
            min_macos=C.MIN_MACOS,
            guide_slugs=C.GUIDE_SLUGS,
            release=self.release,
            year=date.today().year,
            promo_video=PROMO_VIDEO,
            screenshots=SCREENSHOTS,
            brew={"install": C.BREW_INSTALL},
            head_script=head_script(locale_redirect_script()),
            asset=self.asset_url,
        )

    # -- assets

    def asset_url(self, rel: str) -> str:
        return f"/{rel}?v={self.asset_versions.get(rel, 'dev')}"

    def copy_static(self) -> None:
        if self.out.exists():
            shutil.rmtree(self.out)
        shutil.copytree(C.STATIC_DIR, self.out)
        for path in self.out.rglob("*"):
            if path.is_file() and path.suffix in {".css", ".js"}:
                rel = path.relative_to(self.out).as_posix()
                self.asset_versions[rel] = hashlib.sha256(path.read_bytes()).hexdigest()[:10]

    # -- pages

    def alternates(self, page_id: str) -> list[dict]:
        alts = [{"hreflang": loc.hreflang, "href": C.SITE_URL + loc.path(page_id)} for loc in C.LOCALES]
        alts.append({"hreflang": "x-default", "href": C.SITE_URL + C.FALLBACK_LOCALE.path(page_id)})
        return alts

    def write(self, path: str, template: str, context: dict, sitemap: dict | None = None) -> None:
        html = self.env.get_template(template).render(**context)
        html = re.sub(r"\n\s*\n+", "\n", html)
        target = page_file(self.out, path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(html, encoding="utf-8")
        if sitemap is not None:
            self.sitemap.append({**sitemap, "loc": context["loc"]})

    def page_meta(self, loc: C.Locale, t: dict, page_id: str, kind: str, section: str,
                  title: str, description: str, keywords: str, graph: list[dict],
                  crumbs: list[dict] | None = None, og_type: str = "website",
                  markdown_url: str = "") -> dict:
        canonical = C.SITE_URL + loc.path(page_id)
        crumbs = crumbs or []
        return {
            "kind": kind,
            "section": section,
            "title": title,
            "description": description,
            "keywords": keywords,
            "canonical": canonical,
            "alternates": self.alternates(page_id),
            "locale_links": [{"locale": other, "path": other.path(page_id)} for other in C.LOCALES],
            "breadcrumbs": crumbs,
            "og_type": og_type,
            "robots": "",
            "markdown_url": markdown_url,
            "jsonld": seo.jsonld(graph),
        }

    def facts(self, loc: C.Locale, t: dict) -> list[dict]:
        f = t["facts"]
        version = f"v{self.release['version']}" + (f" · {self.release['date']}" if self.release["date"] else "")
        values = {
            "type": f["type_value"],
            "price": f["price_value"],
            "license": f["license_value"],
            "system": f["system_value"],
            "chips": f["chips_value"],
            "version": version,
            "languages": " · ".join(l.label for l in C.LOCALES),
            "install": f["install_value"],
            "privacy": f["privacy_value"],
        }
        return [{"label": f[f"{key}_label"], "value": value} for key, value in values.items()]

    def build_locale(self, loc: C.Locale) -> dict:
        t = self.strings[loc.code]
        base = {"loc": loc, "t": t}
        callouts = {k: t["ui"][f"callout_{k}"] for k in ("tip", "info", "warning", "danger")}
        gestures = [
            {**g, "name": t["gestures"][g["key"]]["name"], "action": t["gestures"][g["key"]]["action"]}
            for g in DEFAULT_GESTURES
        ]
        components = {"DefaultGestures": self.env.get_template("partials/gesture-table.html").render(
            **base, gestures=gestures)}
        docs: dict[str, Doc] = {}
        for slug in C.GUIDE_SLUGS:
            docs[slug] = load_doc(C.CONTENT_DIR / loc.code / "guide" / f"{slug}.md", slug, callouts, components)
        doc_titles = {slug: doc.title for slug, doc in docs.items()}
        base["doc_titles"] = doc_titles
        home_crumb = {"name": t["ui"]["home"], "path": loc.path()}
        app = seo.app_node(loc, t, self.release, gestures_features=t["home"]["features"])
        common = [seo.website_node(loc, t), seo.author_node(), app]
        facts = self.facts(loc, t)
        lastmod_site = max([d.updated for d in docs.values() if d.updated] + [self.release["date"] or ""]) or None

        # Home
        home_title = f"StrokeMouse — {t['meta']['home_title']}"
        graph = common + [
            seo.webpage_node(loc, "", home_title, t["meta"]["home_description"]),
            seo.faq_node(loc, "", [(i["q"], plain_links(i["a"])) for i in t["home"]["faq"]["items"]]),
            seo.video_node(loc, t, PROMO_VIDEO),
        ]
        self.write(loc.path(), "home.html", {
            **base,
            "page": self.page_meta(loc, t, "", "home", "home", home_title,
                                   t["meta"]["home_description"], t["meta"]["home_keywords"], graph),
            "pad_gestures": gestures,
            "facts": facts,
        }, {"page": "", "priority": "1.0", "changefreq": "weekly", "lastmod": lastmod_site})

        # Download
        d_title = f"{t['meta']['download_title']} | StrokeMouse"
        crumbs = [home_crumb, {"name": t["ui"]["nav_download"], "path": loc.path("download")}]
        graph = common + [
            seo.webpage_node(loc, "download", d_title, t["meta"]["download_description"]),
            seo.breadcrumb_node(crumbs),
        ]
        self.write(loc.path("download"), "download.html", {
            **base,
            "page": self.page_meta(loc, t, "download", "download", "download", d_title,
                                   t["meta"]["download_description"], t["meta"]["download_keywords"],
                                   graph, crumbs),
            "dmg_cards": [
                {"key": "arm", "arch": "arm64", "file": C.DMG_ASSETS["arm64"], "url": C.latest_asset_url(C.DMG_ASSETS["arm64"])},
                {"key": "intel", "arch": "x86_64", "file": C.DMG_ASSETS["x86_64"], "url": C.latest_asset_url(C.DMG_ASSETS["x86_64"])},
            ],
            "brew_rows": [
                {"key": "install", "cmd": C.BREW_INSTALL},
                {"key": "upgrade", "cmd": C.BREW_UPGRADE},
                {"key": "uninstall", "cmd": C.BREW_UNINSTALL},
                {"key": "zap", "cmd": C.BREW_ZAP},
            ],
            "facts": [row for row in facts if row["label"] in {
                t["facts"]["system_label"], t["facts"]["chips_label"], t["facts"]["version_label"],
                t["facts"]["price_label"], t["facts"]["license_label"]}],
        }, {"page": "download", "priority": "0.9", "changefreq": "weekly", "lastmod": self.release["date"] or None})

        # Changelog
        ch_title = f"{t['meta']['changelog_title']} | StrokeMouse"
        crumbs = [home_crumb, {"name": t["ui"]["nav_changelog"], "path": loc.path("changelog")}]
        graph = common + [
            seo.webpage_node(loc, "changelog", ch_title, t["meta"]["changelog_description"],
                             modified=self.release["date"] or None),
            seo.breadcrumb_node(crumbs),
        ]
        self.write(loc.path("changelog"), "changelog.html", {
            **base,
            "page": self.page_meta(loc, t, "changelog", "changelog", "changelog", ch_title,
                                   t["meta"]["changelog_description"], t["meta"]["changelog_keywords"],
                                   graph, crumbs),
            "releases": self.releases,
        }, {"page": "changelog", "priority": "0.6", "changefreq": "weekly", "lastmod": self.release["date"] or None})

        # Guides
        sidebar = [
            {"title": t["ui"]["sidebar"][group],
             "items": [{"slug": s, "title": doc_titles[s], "path": loc.path(f"guide/{s}")} for s in slugs]}
            for group, slugs in C.GUIDE_GROUPS
        ]
        for index, slug in enumerate(C.GUIDE_SLUGS):
            doc = docs[slug]
            page_id = f"guide/{slug}"
            title = f"{doc.title} | StrokeMouse"
            crumbs = [home_crumb, {"name": t["ui"]["nav_docs"], "path": loc.path("guide/getting-started")},
                      {"name": doc.title, "path": loc.path(page_id)}]
            graph = common + [
                seo.article_node(loc, page_id, doc.title, doc.description, doc.updated),
                seo.breadcrumb_node(crumbs),
            ]
            if doc.faq:
                graph.append(seo.faq_node(loc, page_id, doc.faq))
            neighbours = [docs[s] for s in C.GUIDE_SLUGS]
            prev_doc = neighbours[index - 1] if index > 0 else None
            next_doc = neighbours[index + 1] if index + 1 < len(neighbours) else None
            md_url = f"{loc.prefix}/guide/{slug}.md"
            self.write(loc.path(page_id), "doc.html", {
                **base,
                "page": self.page_meta(loc, t, page_id, "doc", "docs", title, doc.description,
                                       doc.keywords, graph, crumbs, og_type="article", markdown_url=md_url),
                "doc": doc,
                "sidebar": sidebar,
                "prev": {"title": prev_doc.title, "path": loc.path(f"guide/{prev_doc.slug}")} if prev_doc else None,
                "next": {"title": next_doc.title, "path": loc.path(f"guide/{next_doc.slug}")} if next_doc else None,
                "edit_url": f"{C.GITHUB_URL}/edit/main/website/content/{loc.code}/guide/{slug}.md",
            }, {"page": page_id, "priority": "0.85" if slug == "getting-started" else "0.7",
                "changefreq": "monthly", "lastmod": doc.updated or None})
            # Plain Markdown twin for LLM readers (linked from llms.txt).
            md_target = self.out / md_url.lstrip("/")
            md_target.parent.mkdir(parents=True, exist_ok=True)
            md_target.write_text(f"# {doc.title}\n\n> {doc.description}\n\n"
                                 f"Source: {C.SITE_URL}{loc.path(page_id)}\n\n{seo.clean_markdown(doc.markdown)}\n",
                                 encoding="utf-8")

        self.write_search_index(loc, t, docs)
        return {"t": t, "docs": docs}

    def write_search_index(self, loc: C.Locale, t: dict, docs: dict[str, Doc]) -> None:
        entries = []
        for slug, doc in docs.items():
            for section in doc.sections:
                entries.append({
                    "p": doc.title,
                    "h": section.heading,
                    "u": loc.path(f"guide/{slug}") + (f"#{section.anchor}" if section.anchor else ""),
                    "x": section.text[:600],
                })
        entries.append({"p": t["ui"]["nav_download"], "h": t["download"]["title"], "u": loc.path("download"),
                        "x": t["download"]["lead"]})
        target = self.out / "search" / f"{loc.code}.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        payload = json.dumps(entries, ensure_ascii=False, separators=(",", ":"))
        target.write_text(payload, encoding="utf-8")
        self.asset_versions[f"search/{loc.code}.json"] = hashlib.sha256(payload.encode()).hexdigest()[:10]

    def build(self) -> None:
        started = time.time()
        self.copy_static()
        built = {loc.code: self.build_locale(loc) for loc in C.LOCALES}
        en = built["en"]
        # 404 (GitHub Pages serves /404.html for every missing path).
        loc, t = C.FALLBACK_LOCALE, en["t"]
        self.write("/404", "404.html", {
            "loc": loc, "t": t, "doc_titles": {s: d.title for s, d in en["docs"].items()},
            "page": {**self.page_meta(loc, t, "", "notfound", "", f"{t['ui']['notfound_title']} | StrokeMouse",
                                      t["meta"]["home_description"], "", []), "robots": "noindex"},
        })
        seo.write_sitemap(self.out, self.sitemap)
        seo.write_robots(self.out)
        seo.write_llms(self.out, self.strings, built, self.release)
        seo.write_feed(self.out, self.releases)
        (self.out / ".nojekyll").write_text("", encoding="utf-8")
        pages = sum(1 for _ in self.out.rglob("*.html"))
        print(f"built {pages} pages into {self.out} in {time.time() - started:.2f}s (v{self.release['version']})")


# --------------------------------------------------------------------------- serve


class CleanURLHandler(http.server.SimpleHTTPRequestHandler):
    """Mimic GitHub Pages: /guide/faq serves guide/faq.html."""

    def translate_path(self, path: str) -> str:
        local = Path(super().translate_path(path))
        if not local.exists() and local.with_suffix(".html").exists():
            return str(local.with_suffix(".html"))
        return str(local)

    def send_error(self, code, message=None, explain=None):  # noqa: ANN001
        if code == 404 and (Path(self.directory) / "404.html").exists():
            body = (Path(self.directory) / "404.html").read_bytes()
            self.send_response(404)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().send_error(code, message, explain)

    def log_message(self, fmt, *args):  # noqa: ANN001
        pass


def snapshot() -> dict[str, float]:
    roots = [C.CONTENT_DIR, C.TEMPLATE_DIR, C.STATIC_DIR, C.WEBSITE_DIR / "sitegen"]
    files = {str(p): p.stat().st_mtime for root in roots for p in root.rglob("*") if p.is_file()}
    files[__file__] = Path(__file__).stat().st_mtime
    return files


def serve(out: Path, port: int, releases: list[dict]) -> None:
    def watch() -> None:
        last = snapshot()
        while True:
            time.sleep(0.8)
            current = snapshot()
            if current != last:
                # Imported code cannot be reloaded in place; restart the whole server.
                if any(k.endswith(".py") and current.get(k) != last.get(k) for k in current.keys() | last.keys()):
                    print("python source changed, restarting", file=sys.stderr)
                    os.execv(sys.executable, [sys.executable, *sys.argv])
                last = current
                try:
                    Site(out, releases).build()
                except Exception as error:  # noqa: BLE001
                    print(f"build failed: {error}", file=sys.stderr)

    threading.Thread(target=watch, daemon=True).start()
    handler = functools.partial(CleanURLHandler, directory=str(out))
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as httpd:
        print(f"serving http://localhost:{port}")
        httpd.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, default=C.DEFAULT_OUT_DIR)
    parser.add_argument("--offline", action="store_true", help="skip the GitHub Releases API")
    parser.add_argument("--serve", action="store_true", help="serve and rebuild on change")
    parser.add_argument("--port", type=int, default=9243)
    args = parser.parse_args()
    out = args.out.resolve()
    releases = fetch_releases(args.offline)
    Site(out, releases).build()
    if args.serve:
        serve(out, args.port, releases)


if __name__ == "__main__":
    main()
