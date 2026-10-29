#!/usr/bin/env python3
"""Extract menu letter -> paragraph -> called program(s) for ACAS menu programs.

Menus display "(X)  label" lines and dispatch with
    GO TO para1 para2 ... DEPENDING ON z   (z = 1 for "A", 2 for "B", ...).
Each target paragraph sets ws-called with MOVE "prog" TO ws-called.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MENUS = ["ACAS.cbl", "sales/sales.cbl", "purchase/purchase.cbl", "stock/stock.cbl",
         "general/general.cbl", "incomplete_records_system/irs.cbl"]
sys.path.insert(0, str(Path(__file__).parent))
from extract_calls import strip_comment  # noqa: E402


def paragraphs(code_lines):
    paras, cur = {}, None
    for line in code_lines:
        m = re.match(r"^ {1,4}([A-Za-z0-9][A-Za-z0-9-]*)\.\s*$", line)
        if m:
            cur = m.group(1).lower()
            paras[cur] = []
            continue
        if cur:
            paras[cur].append(line)
    return paras


def menu(path: Path):
    code = [strip_comment(l) for l in path.read_text(errors="replace").splitlines()]
    joined = "\n".join(code)
    labels = {}
    for m in re.finditer(r'"\(([A-Z0-9])\)\s+([^"]*)"', joined):
        labels.setdefault(m.group(1), m.group(2).strip())
    paras = paragraphs(code)
    m = re.search(r"go\s+to\s+((?:[a-z0-9-]+\s+)+?)depending\s+on\s+([a-z0-9-]+)", joined, re.I | re.S)
    out = []
    if not m:
        return {"labels": labels, "dispatch": []}
    targets = m.group(1).split()
    for idx, t in enumerate(targets):
        letter = chr(ord("A") + idx)
        # include fall-through sub-paragraphs such as load21 -> load21a
        body = "\n".join(l for name, ls in paras.items()
                          if name == t.lower() or re.fullmatch(re.escape(t.lower()) + r"[a-z]", name)
                          for l in ls)
        progs = re.findall(r'move\s+"([a-z0-9]+)"\s+to\s+ws-called', body, re.I)
        out.append({"key": letter, "label": labels.get(letter, ""), "paragraph": t, "programs": progs})
    return {"labels": labels, "dispatch": out}


if __name__ == "__main__":
    json.dump({p: menu(ROOT / p) for p in MENUS}, sys.stdout, indent=1, ensure_ascii=False)
