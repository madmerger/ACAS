#!/usr/bin/env python3
"""fragments/<sub>.{en,ja}.strings を結合して Localizable.strings を生成し、キー一致とセル幅を検査する。
使い方: python3 ipad/scripts/merge_strings.py [--check]"""
import re, sys, unicodedata
from pathlib import Path
LOC = Path(__file__).resolve().parent.parent / "ACAS/Resources/Localization"
PAIR = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
def width(s):
    s = s.replace('\\"', '"').replace('\\\\', '\\')
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s)
def load(lang):
    keys, text = {}, []
    for f in sorted((LOC / "fragments").glob(f"*.{lang}.strings")):
        text.append(f"/* ---- {f.name} ---- */")
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            m = PAIR.match(line)
            if m:
                if m.group(1) in keys: sys.exit(f"{f.name}:{n}: duplicate key {m.group(1)}")
                keys[m.group(1)] = m.group(2)
            elif line.strip() and not line.lstrip().startswith(("/*", "//")):
                sys.exit(f"{f.name}:{n}: unparsable line: {line}")
            text.append(line)
    return keys, "\n".join(text) + "\n"
en, en_text = load("en"); ja, ja_text = load("ja")
errors = [f"missing in ja: {k}" for k in en if k not in ja] + [f"missing in en: {k}" for k in ja if k not in en]
# 画面文言 (ui. / report. 以外) は日本語のセル幅が英語原文以下であること
errors += [f"ja wider than en ({width(ja[k])}>{width(en[k])}): {k}" for k in en
           if k in ja and not k.startswith(("ui.", "report.")) and width(ja[k]) > width(en[k])]
if errors:
    print("\n".join(errors)); sys.exit(1)
if "--check" not in sys.argv:
    (LOC / "en.lproj/Localizable.strings").write_text(en_text, encoding="utf-8")
    (LOC / "ja.lproj/Localizable.strings").write_text(ja_text, encoding="utf-8")
print(f"OK: {len(en)} keys")
