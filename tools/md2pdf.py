#!/usr/bin/env python3
"""Markdown -> HTML -> PDF (A4) converter for docs/*.md.

Usage: python3 tools/md2pdf.py docs/ACAS_spec.md [docs/ACAS_spec.pdf]
Requires: pip install markdown playwright && python3 -m playwright install chromium
```mermaid fenced blocks are rendered to SVG with mermaid, loaded from $MERMAID_JS (a local
mermaid.min.js) or else from MERMAID_URL; if it cannot be loaded the block is left as a code block.
Relative image paths are resolved against the input file's directory.
"""
import html as htmlmod
import os
import re
import sys
from pathlib import Path

import markdown
from playwright.sync_api import sync_playwright

CSS = """
@page { size: A4; margin: 15mm 15mm 16mm 15mm; }
body { font-family: "Hiragino Sans", "Noto Sans CJK JP", "Noto Sans JP", "Yu Gothic", sans-serif;
       font-size: 9.5pt; line-height: 1.45; color: #111; }
h1 { font-size: 16pt; margin: 0 0 6pt; }
h2 { font-size: 12.5pt; margin: 12pt 0 5pt; border-bottom: 1px solid #888; padding-bottom: 2pt;
     page-break-after: avoid; }
h3 { font-size: 10.5pt; margin: 9pt 0 3pt; page-break-after: avoid; }
p, li { margin: 2pt 0; }
ul { padding-left: 16pt; margin: 2pt 0; }
table { border-collapse: collapse; width: 100%; font-size: 8.3pt; margin: 4pt 0 8pt;
        page-break-inside: auto; }
tr { page-break-inside: avoid; }
thead { display: table-header-group; }
th, td { border: 1px solid #999; padding: 2pt 4pt; vertical-align: top; text-align: left;
         word-break: break-word; }
th { background: #eee; }
code { font-family: "Menlo", "DejaVu Sans Mono", monospace; font-size: 8.3pt; }
pre { font-size: 7.8pt; line-height: 1.3; background: #f5f5f5; border: 1px solid #ccc;
      padding: 4pt; white-space: pre-wrap; page-break-inside: avoid; }
.front { font-size: 8.5pt; color: #444; margin-bottom: 8pt; }
.mermaid { text-align: center; margin: 4pt 0 8pt; page-break-inside: avoid; }
.mermaid svg { max-width: 100%; height: auto; max-height: 190mm; }
"""

MERMAID_URL = "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js"
MERMAID_RE = re.compile(r"^```mermaid\n(.*?)\n```$", re.S | re.M)


def extract_mermaid(text: str):
    blocks = []

    def repl(m):
        blocks.append(m.group(1))
        return f"<div class='mermaid'>{htmlmod.escape(m.group(1))}</div>"

    return MERMAID_RE.sub(repl, text), blocks


def split_front_matter(text: str):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return {}, text
    meta = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    return meta, text[m.end():]


def main() -> None:
    if len(sys.argv) not in (2, 3) or not Path(sys.argv[1]).is_file():
        sys.exit(f"usage: {sys.argv[0]} <input.md> [output.pdf]")
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".pdf")
    meta, body = split_front_matter(src.read_text(encoding="utf-8"))
    body, mermaid_blocks = extract_mermaid(body)
    html_body = markdown.markdown(body, extensions=["tables", "fenced_code", "toc"])
    front = " / ".join(f"{htmlmod.escape(k)}: {htmlmod.escape(v)}" for k, v in meta.items())
    html = (f"<html><head><meta charset='utf-8'><style>{CSS}</style></head><body>"
            f"<div class='front'>{front}</div>{html_body}</body></html>")
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        tmp = src.with_suffix(".md2pdf.html")
        tmp.write_text(html, encoding="utf-8")
        try:
            page.goto(tmp.resolve().as_uri(), wait_until="load")
        finally:
            tmp.unlink()
        if mermaid_blocks:
            try:
                local_js = os.environ.get("MERMAID_JS")
                if local_js:
                    page.add_script_tag(path=local_js)
                else:
                    page.add_script_tag(url=MERMAID_URL)
                page.evaluate(
                    "async () => { mermaid.initialize({startOnLoad: false, theme: 'neutral',"
                    " fontFamily: 'Noto Sans CJK JP, sans-serif', fontSize: 15,"
                    " sequence: {wrap: true, width: 120, messageFontSize: 16, actorFontSize: 15,"
                    " noteFontSize: 15, messageMargin: 24, actorMargin: 24, boxMargin: 6},"
                    " flowchart: {useMaxWidth: true, nodeSpacing: 18, rankSpacing: 28},"
                    " er: {useMaxWidth: true, fontSize: 16, minEntityWidth: 60, entityPadding: 10}});"
                    " await mermaid.run({querySelector: '.mermaid'}); }")
            except Exception as e:  # noqa: BLE001 - offline fallback keeps the text
                print(f"mermaid not rendered: {e}", file=sys.stderr)
            page.evaluate(
                "() => document.querySelectorAll('.mermaid').forEach(d => {"
                " if (d.querySelector('svg')) return;"
                " const pre = document.createElement('pre'); const code = document.createElement('code');"
                " code.className = 'language-mermaid'; code.textContent = d.textContent;"
                " pre.appendChild(code); d.replaceWith(pre); })")
            n = page.evaluate("document.querySelectorAll('.mermaid svg').length")
            print(f"mermaid diagrams rendered: {n}/{len(mermaid_blocks)}")
        page.pdf(path=str(dst), format="A4", print_background=True,
                 display_header_footer=True,
                 header_template="<span></span>",
                 footer_template="<div style='font-size:8pt;width:100%;text-align:center;'>"
                                 "<span class='pageNumber'></span> / <span class='totalPages'></span></div>",
                 margin={"top": "15mm", "bottom": "16mm", "left": "15mm", "right": "15mm"})
        browser.close()
    print(f"wrote {dst}")


if __name__ == "__main__":
    main()
