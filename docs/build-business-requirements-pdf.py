#!/usr/bin/env python3
"""Generate docs/business-requirements-as-is.pdf from the Markdown source.

Requirements: pip install markdown ; npm i -g @mermaid-js/mermaid-cli ;
Google Chrome / Chromium on PATH (or CHROME env var) ; Noto Sans CJK JP font.
Usage: python3 docs/build-business-requirements-pdf.py
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile

import markdown

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE / 'business-requirements-as-is.md'
OUT = HERE / 'business-requirements-as-is.pdf'
CHROME = os.environ.get('CHROME') or next(
    (c for c in (shutil.which(n) for n in ('google-chrome', 'chromium', 'chromium-browser')) if c), None)
if not CHROME:
    raise SystemExit('Chrome/Chromium not found; set CHROME=/path/to/chrome')

MERMAID_CFG = {"theme": "default",
               "themeVariables": {"fontSize": "20px", "fontFamily": "Noto Sans CJK JP, sans-serif"},
               "flowchart": {"nodeSpacing": 30, "rankSpacing": 35, "padding": 10}}
PUPPETEER_CFG = {"args": ["--no-sandbox"]}

CSS = """
@page { size: A4; margin: 12mm 12mm; }
body { font-family: 'Noto Sans CJK JP', sans-serif; font-size: 8.4pt; line-height: 1.3; color: #111; }
h1 { font-size: 16pt; margin: 0 0 6pt; } h2 { font-size: 12pt; margin: 10pt 0 4pt; border-bottom: 1.5px solid #333; }
h2.pb { break-before: page; } td.nw, th { white-space: nowrap; }
h3 { font-size: 10pt; margin: 8pt 0 3pt; }
table { border-collapse: collapse; width: 100%; margin: 4pt 0 6pt; font-size: 7.6pt; break-inside: auto; }
th, td { border: 1px solid #999; padding: 2pt 3pt; vertical-align: top; text-align: left; }
th { background: #eee; } tr { break-inside: avoid; }
p.fig { text-align: center; margin: 4pt 0; } p.fig img { max-width: 100%; max-height: 118mm; }
code { font-family: 'DejaVu Sans Mono', monospace; font-size: 7.5pt; }
ul { margin: 2pt 0 4pt 14pt; padding: 0; } li { margin: 1pt 0; }
"""
PAGE_BREAK_SECTIONS = ('2.', '4.', '5.', '6.', '8.', '10.')

with tempfile.TemporaryDirectory() as tmp:
    work = pathlib.Path(tmp)
    (work / 'mermaid.json').write_text(json.dumps(MERMAID_CFG))
    (work / 'puppeteer.json').write_text(json.dumps(PUPPETEER_CFG))
    text = SRC.read_text()
    for i, block in enumerate(re.findall(r'```mermaid\n(.*?)```', text, re.S)):
        mmd, png = work / f'd{i}.mmd', work / f'd{i}.png'
        mmd.write_text(block)
        subprocess.run(['mmdc', '-i', str(mmd), '-o', str(png), '-b', 'white', '-s', '3', '-w', '1400',
                        '-p', str(work / 'puppeteer.json'), '-c', str(work / 'mermaid.json')], check=True)
        text = text.replace('```mermaid\n' + block + '```', f'<p class="fig"><img src="{png}"></p>', 1)
    body = markdown.markdown(text, extensions=['tables', 'fenced_code'])
    for sec in PAGE_BREAK_SECTIONS:
        body = body.replace(f'<h2>{sec}', f'<h2 class="pb">{sec}')
    body = re.sub(r'<td>(A|B|C|D|⚠|―|SL-\d+|PL-\d+|ST-\d+|Q\d+|高|中|低)</td>', r'<td class="nw">\1</td>', body)
    html = work / 'doc.html'
    html.write_text(f'<!doctype html><html lang="ja"><head><meta charset="utf-8"><style>{CSS}</style></head>'
                    f'<body>{body}</body></html>')
    subprocess.run([CHROME, '--headless=new', '--no-sandbox', '--disable-gpu', '--no-pdf-header-footer',
                    f'--print-to-pdf={OUT}', f'file://{html}'], check=True)
print('ok', OUT)
