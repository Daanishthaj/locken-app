#!/usr/bin/env python3
"""Turns the published legal documents in docs/legal into static pages on locken-app.vercel.app.

    python3 scripts/build-legal-pages.py

Writes web/public/terms.html, privacy.html, acceptable-use.html and credits.html (served as /terms, /privacy,
/acceptable-use and /credits thanks to cleanUrls in web/vercel.json). Run it again whenever a legal document changes,
then deploy. The Security & Data Protection Policy is internal and is not published; links to it point to
the Privacy Policy's Security section.
"""
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs" / "legal"
OUT = ROOT / "web" / "public"

PAGES = {
    "TERMS_OF_SERVICE.md": ("terms", "Terms of Service"),
    "PRIVACY_POLICY.md": ("privacy", "Privacy Policy"),
    "ACCEPTABLE_USE_POLICY.md": ("acceptable-use", "Acceptable Use Policy"),
    "ACKNOWLEDGEMENTS.md": ("credits", "Credits & Licenses"),
}
LINKS = {
    "TERMS_OF_SERVICE.md": "/terms",
    "PRIVACY_POLICY.md": "/privacy",
    "ACCEPTABLE_USE_POLICY.md": "/acceptable-use",
    "ACKNOWLEDGEMENTS.md": "/credits",
    "SECURITY_AND_DATA_PROTECTION_POLICY.md": "/privacy#11-security",
}


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def inline(text: str) -> str:
    text = html.escape(text, quote=False)

    def link(match: re.Match) -> str:
        label, target = match.group(1), match.group(2)
        for name, url in LINKS.items():
            if target.startswith(name):
                target = url + target[len(name):]
                break
        if target.startswith("mailto:") or target.startswith("/") or target.startswith("https://") or target.startswith("#"):
            return f'<a href="{html.escape(target)}">{label}</a>'
        return label  # anything else (relative files) stays plain text

    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)
    text = re.sub(r"(?<![\"=>])\b(https://[^\s<)]+[^\s<).,])", r'<a href="\1">\1</a>', text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![*\w])\*(?!\s)(.+?)(?<!\s)\*(?![*\w])", r"<em>\1</em>", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\b([\w.+-]+@[\w-]+\.[\w.]+)\b(?![^<]*</a>)", r'<a href="mailto:\1">\1</a>', text)
    return text


def convert(markdown: str):
    lines = markdown.splitlines()
    out = []
    title = ""
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if not stripped:
            i += 1
            continue
        heading = re.match(r"^(#{1,4})\s+(.*)", stripped)
        if heading:
            level = len(heading.group(1))
            text = heading.group(2).strip()
            if level == 1 and not title:
                title = text
                out.append(f"<h1>{inline(text)}</h1>")
            else:
                out.append(f'<h{level} id="{slug(text)}">{inline(text)}</h{level}>')
            i += 1
            continue
        if re.match(r"^(-{3,}|\*{3,})$", stripped):
            i += 1  # section headings already draw a dividing line
            continue
        if stripped.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(lines[i].strip())
                i += 1
            cells = [[c.strip() for c in row.strip("|").split("|")] for row in rows]
            body = [r for r in cells[1:] if not all(re.match(r"^:?-{2,}:?$", c) for c in r)]
            table = ["<div class=\"table\"><table><thead><tr>"]
            table += [f"<th>{inline(c)}</th>" for c in cells[0]]
            table.append("</tr></thead><tbody>")
            for row in body:
                table.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>")
            table.append("</tbody></table></div>")
            out.append("".join(table))
            continue
        if stripped.startswith(">"):
            quote = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                quote.append(lines[i].strip().lstrip(">").strip())
                i += 1
            out.append(f"<blockquote><p>{inline(' '.join(quote))}</p></blockquote>")
            continue
        bullet = re.match(r"^[-*]\s+(.*)", stripped)
        number = re.match(r"^\d+\.\s+(.*)", stripped)
        if bullet or number:
            tag = "ul" if bullet else "ol"
            pattern = r"^[-*]\s+(.*)" if bullet else r"^\d+\.\s+(.*)"
            items = []
            while i < len(lines):
                current = lines[i].strip()
                match = re.match(pattern, current)
                if match:
                    items.append(match.group(1))
                elif current and items and lines[i].startswith((" ", "\t")):
                    items[-1] += " " + current
                else:
                    break
                i += 1
            out.append(f"<{tag}>" + "".join(f"<li>{inline(item)}</li>" for item in items) + f"</{tag}>")
            continue
        paragraph = [stripped]
        i += 1
        while i < len(lines) and lines[i].strip() and not re.match(r"^(#|\||>|[-*]\s|\d+\.\s|-{3,})", lines[i].strip()):
            paragraph.append(lines[i].strip())
            i += 1
        # Lines like "**Effective date:** ..." / "**Last updated:** ..." stay on their own lines.
        joiner = "<br>" if len(paragraph) > 1 and all(p.startswith("**") for p in paragraph) else " "
        out.append(f"<p>{joiner.join(inline(p) for p in paragraph)}</p>")
    return title, "\n".join(out)


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · Locken</title>
<link rel="icon" href="/favicon.png" type="image/png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<meta name="description" content="{page_name} for Locken, the focus app for Mac.">
<style>
@font-face {{ font-family: "Doto"; src: url("/fonts/Doto.ttf") format("truetype"); font-weight: 100 900; font-style: normal; font-display: swap; }}
:root {{ color-scheme: dark; --bg: #0b0b0f; --panel: #14131b; --text: #fff; --muted: #fff; --line: rgba(255,255,255,.12); --accent: #b48cff; }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--text); font: 800 16px/1.65 "Doto", -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif; font-variation-settings: "ROND" 100; }}
h1, h2, h3, strong, th, header a.brand {{ font-weight: 900; }}
header {{ border-bottom: 1px solid var(--line); }}
header .wrap {{ display: flex; align-items: center; justify-content: space-between; gap: 16px; padding-top: 18px; padding-bottom: 18px; }}
header a.brand {{ color: #fff; text-decoration: none; letter-spacing: .2px; display: inline-flex; align-items: center; gap: 10px; }}
nav {{ display: flex; gap: 18px; flex-wrap: wrap; font-size: 14px; }}
nav a {{ color: var(--muted); text-decoration: none; }}
nav a[aria-current="page"] {{ color: #fff; }}
.wrap {{ max-width: 820px; margin: 0 auto; padding: 0 16px; }}
main {{ padding: 40px 0 72px; }}
h1 {{ font-size: 34px; line-height: 1.2; margin: 0 0 12px; color: #fff; }}
h2 {{ font-size: 21px; margin: 40px 0 10px; color: #fff; padding-top: 22px; border-top: 1px solid var(--line); }}
h3 {{ font-size: 17px; margin: 26px 0 8px; color: #fff; }}
p, li {{ color: var(--text); }}
a {{ color: var(--accent); }}
strong {{ color: #fff; }}
code {{ font: 14px ui-monospace, SFMono-Regular, Menlo, monospace; background: var(--panel); padding: 1px 5px; border-radius: 4px; }}
blockquote {{ margin: 18px 0; padding: 12px 16px; border-left: 3px solid var(--accent); background: var(--panel); border-radius: 0 8px 8px 0; }}
.table {{ overflow-x: auto; margin: 16px 0; border: 1px solid var(--line); border-radius: 10px; }}
table {{ border-collapse: collapse; width: 100%; font-size: 14px; }}
th, td {{ text-align: left; vertical-align: top; padding: 10px 12px; border-bottom: 1px solid var(--line); }}
th {{ color: #fff; background: var(--panel); }}
tr:last-child td {{ border-bottom: 0; }}
hr {{ border: 0; border-top: 1px solid var(--line); margin: 32px 0; }}
footer {{ border-top: 1px solid var(--line); color: var(--muted); font-size: 14px; padding: 24px 0 40px; }}
</style>
</head>
<body>
<header><div class="wrap">
<a class="brand" href="/"><img src="/locken-logo.png" alt="" width="26" height="26">Locken</a>
<nav>{nav}</nav>
</div></header>
<main><div class="wrap">
{body}
</div></main>
<footer><div class="wrap">Questions: <a href="mailto:daanu.focus@gmail.com">daanu.focus@gmail.com</a></div></footer>
</body>
</html>
"""


def main() -> None:
    for source, (name, page_name) in PAGES.items():
        title, body = convert((SOURCE / source).read_text(encoding="utf-8"))
        current = ' aria-current="page"'
        nav = " ".join(
            f'<a href="/{n}"{current if n == name else ""}>{label}</a>'
            for n, label in PAGES.values()
        )
        page = TEMPLATE.format(title=html.escape(title or page_name), page_name=page_name, nav=nav, body=body)
        (OUT / f"{name}.html").write_text(page, encoding="utf-8")
        print(f"wrote web/public/{name}.html")


if __name__ == "__main__":
    main()
