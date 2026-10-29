#!/usr/bin/env python3
"""Extract CALL graph and COPY usage from ACAS COBOL sources (*.cbl).

Static calls: CALL "name".  Dynamic calls: MOVE "name" TO <var> followed by CALL <var>.
Outputs JSON to stdout: {program: {"path", "lines", "calls": [...], "copies": [...]}}
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EXCLUDE_DIRS = {"experimental-stuff"}

RE_CALL_LIT = re.compile(r"""\bcall\s+(["'])([^"']+)\1""", re.I)
RE_CALL_VAR = re.compile(r'\bcall\s+([a-z][a-z0-9-]*)', re.I)
RE_MOVE_LIT = re.compile(r"""\bmove\s+(["'])([^"']+)\1\s+to\s+([a-z][a-z0-9-]*(?:[ \t]+[a-z][a-z0-9-]*)*)""", re.I)
COBOL_WORDS = {"if", "else", "end-if", "move", "perform", "go", "to", "call", "display", "accept", "when", "not"}
RE_COPY = re.compile(r'\bcopy\s+"?([a-z0-9._-]+)"?', re.I)


def strip_comment(line: str) -> str:
    if len(line) > 6 and line[6] in "*/":
        return ""
    idx = line.find("*>")
    if idx >= 0:
        line = line[:idx]
    return line


def analyse(path: Path):
    text = path.read_text(errors="replace").splitlines()
    code = [strip_comment(l) for l in text]
    joined = "\n".join(code)
    call_vars = {m.group(1).lower() for m in RE_CALL_VAR.finditer(joined)
                 if m.group(1).lower() not in {"using"}}
    calls = set(m.group(2) for m in RE_CALL_LIT.finditer(joined))
    for m in RE_MOVE_LIT.finditer(joined):
        lit = m.group(2)
        targets = set()
        for t in m.group(3).split():
            if t.lower() in COBOL_WORDS:
                break
            targets.add(t.lower())
        if targets & call_vars and re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{1,15}", lit):
            calls.add(lit)
    copies = sorted({m.group(1) for m in RE_COPY.finditer(joined)})
    return {
        "path": str(path.relative_to(ROOT)),
        "lines": len(text),
        "calls": sorted(calls, key=str.lower),
        "copies": copies,
    }


def main():
    result = {}
    for p in sorted(ROOT.rglob("*.cbl")):
        if any(part in EXCLUDE_DIRS for part in p.parts):
            continue
        name = p.stem
        key = name if name not in result else f"{p.parent.name}/{name}"
        result[key] = analyse(p)
    json.dump(result, sys.stdout, indent=1)


if __name__ == "__main__":
    main()
