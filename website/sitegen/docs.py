"""Markdown guide pages → HTML fragments, outline, search sections and FAQ."""

from __future__ import annotations

import html
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

import markdown
from markdown.extensions.toc import slugify_unicode

from .config import REPO_DIR

CONTAINER_RE = re.compile(
    r"^:::[ \t]*(tip|info|warning|danger)[ \t]*(.*?)\n(.*?)^:::[ \t]*$", re.M | re.S
)
COMPONENT_RE = re.compile(r"^<([A-Z][A-Za-z]+)\s*/>\s*$", re.M)
FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n", re.S)
TAG_RE = re.compile(r"<[^>]+>")
HEADING_RE = re.compile(r'<h([23]) id="([^"]+)">(.*?)</h\1>', re.S)


@dataclass
class Heading:
    level: int
    id: str
    text: str


@dataclass
class Section:
    heading: str
    anchor: str
    text: str


@dataclass
class Doc:
    slug: str
    source: Path
    title: str
    description: str
    keywords: str
    markdown: str
    html: str
    headings: list[Heading] = field(default_factory=list)
    sections: list[Section] = field(default_factory=list)
    faq: list[tuple[str, str]] = field(default_factory=list)
    updated: str = ""


def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    match = FRONTMATTER_RE.match(text)
    if not match:
        return {}, text
    meta: dict[str, str] = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        meta[key.strip()] = value
    return meta, text[match.end():]


def strip_tags(fragment: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(TAG_RE.sub(" ", fragment))).strip()


def git_updated(path: Path) -> str:
    """ISO date of the last commit touching `path` ('' outside git)."""
    try:
        out = subprocess.run(
            ["git", "log", "-1", "--format=%cs", "--", str(path)],
            cwd=REPO_DIR, capture_output=True, text=True, check=False,
        ).stdout.strip()
    except OSError:
        return ""
    return out


def _md() -> markdown.Markdown:
    return markdown.Markdown(
        extensions=["tables", "fenced_code", "codehilite", "attr_list", "md_in_html", "toc", "sane_lists"],
        extension_configs={
            "codehilite": {"css_class": "hl", "guess_lang": False},
            "toc": {"slugify": slugify_unicode, "toc_depth": "2-3"},
        },
    )


def render_markdown(source: str, callout_titles: dict[str, str], components: dict[str, str]) -> str:
    def container(match: re.Match[str]) -> str:
        kind, title, body = match.group(1), match.group(2).strip(), match.group(3)
        title = title or callout_titles.get(kind, kind.title())
        return (
            f'<div class="callout callout-{kind}" markdown="1">\n'
            f'<p class="callout-title">{html.escape(title)}</p>\n\n{body}\n</div>'
        )

    source = CONTAINER_RE.sub(container, source)
    # Components become placeholders that survive Markdown untouched.
    source = COMPONENT_RE.sub(lambda m: f"\n<!--component:{m.group(1)}-->\n", source)
    out = _md().convert(source)
    out = re.sub(
        r"<!--component:([A-Za-z]+)-->", lambda m: components.get(m.group(1), ""), out
    )
    out = out.replace("<table>", '<div class="table-wrap"><table>').replace("</table>", "</table></div>")
    # Heading permalinks, appended so the visible text stays the anchor's label.
    out = HEADING_RE.sub(
        lambda m: (
            f'<h{m.group(1)} id="{m.group(2)}">{m.group(3)}'
            f'<a class="h-anchor" href="#{m.group(2)}" aria-hidden="true" tabindex="-1">#</a></h{m.group(1)}>'
        ),
        out,
    )
    # External links open in a new tab.
    out = re.sub(
        r'<a href="(https?://[^"]+)"',
        r'<a href="\1" target="_blank" rel="noopener"',
        out,
    )
    return out


def outline(fragment: str) -> list[Heading]:
    return [
        Heading(int(level), anchor, strip_tags(TAG_RE.sub("", re.sub(r'<a class="h-anchor".*?</a>', "", inner))))
        for level, anchor, inner in re.findall(r'<h([23]) id="([^"]+)">(.*?)</h\1>', fragment, re.S)
    ]


def split_sections(fragment: str, title: str) -> list[Section]:
    """Split by h2/h3 for the search index; text before the first heading is the intro."""
    parts = re.split(r'(<h[23] id="[^"]+">.*?</h[23]>)', fragment, flags=re.S)
    sections = [Section(title, "", strip_tags(re.sub(r"<h1.*?</h1>", "", parts[0], flags=re.S)))]
    for i in range(1, len(parts), 2):
        anchor = re.search(r'id="([^"]+)"', parts[i]).group(1)
        heading = strip_tags(re.sub(r'<a class="h-anchor".*?</a>', "", parts[i]))
        sections.append(Section(heading, anchor, strip_tags(parts[i + 1])))
    return [s for s in sections if s.text or s.anchor]


def extract_faq(fragment: str) -> list[tuple[str, str]]:
    """FAQ pages use one h2 per question; the answer is everything until the next h2."""
    items = []
    for match in re.finditer(r'<h2 id="[^"]+">(.*?)</h2>(.*?)(?=<h2 |\Z)', fragment, re.S):
        question = strip_tags(re.sub(r'<a class="h-anchor".*?</a>', "", match.group(1)))
        answer = strip_tags(match.group(2))
        if question and answer:
            items.append((question, answer))
    return items


def load_doc(path: Path, slug: str, callout_titles: dict[str, str], components: dict[str, str]) -> Doc:
    meta, body = parse_frontmatter(path.read_text(encoding="utf-8"))
    fragment = render_markdown(body, callout_titles, components)
    # The template renders the page title; drop the Markdown h1.
    fragment = re.sub(r"\A\s*<h1[^>]*>.*?</h1>\s*", "", fragment, flags=re.S)
    title = meta.get("title") or slug
    return Doc(
        slug=slug,
        source=path,
        title=title,
        description=meta.get("description", ""),
        keywords=meta.get("keywords", ""),
        markdown=body.strip(),
        html=fragment,
        headings=outline(fragment),
        sections=split_sections(fragment, title),
        faq=extract_faq(fragment) if slug == "faq" else [],
        updated=git_updated(path),
    )
