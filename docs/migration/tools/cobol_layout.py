#!/usr/bin/env python3
"""Parse COBOL record descriptions (copybooks) into byte layouts.

Storage rules follow GnuCOBOL 3.1.2 defaults (verified with cobc on this repo):
  * DISPLAY numeric: 1 byte/digit (SIGN LEADING without SEPARATE adds no byte)
  * COMP-3: digits//2 + 1 bytes
  * COMP / BINARY with PIC: binary-size 1-2-4-8 (1-2 digits:1, 3-4:2, 5-9:4, 10-18:8), big-endian
  * BINARY-CHAR/SHORT/LONG/DOUBLE: 1/2/4/8 bytes, native (little-endian on x86-64)
  * USAGE on a group item applies to all elementary items below it
"""
import json
import re
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import List, Optional

USAGE_WORDS = {
    "comp": "COMP", "computational": "COMP", "binary": "COMP", "comp-4": "COMP",
    "comp-3": "COMP-3", "packed-decimal": "COMP-3", "computational-3": "COMP-3",
    "comp-5": "COMP-5", "display": "DISPLAY",
    "binary-char": "BINARY-CHAR", "binary-short": "BINARY-SHORT",
    "binary-long": "BINARY-LONG", "binary-double": "BINARY-DOUBLE",
}
FIXED_BIN = {"BINARY-CHAR": 1, "BINARY-SHORT": 2, "BINARY-LONG": 4, "BINARY-DOUBLE": 8}


@dataclass
class Item:
    level: int
    name: str
    pic: Optional[str] = None
    usage: Optional[str] = None
    unsigned: bool = False
    occurs: int = 1
    redefines: Optional[str] = None
    sign_leading: bool = False
    sign_separate: bool = False
    children: List["Item"] = field(default_factory=list)
    offset: int = 0
    length: int = 0  # length of ONE occurrence
    line: int = 0


def clean_lines(text: str):
    free = False
    out = []
    for no, raw in enumerate(text.splitlines(), 1):
        if re.match(r"\s*>>\s*source\s+free", raw, re.I):
            free = True
            continue
        line = raw
        if not free and len(line) > 6 and line[6] in "*/":
            continue
        idx = line.find("*>")
        if idx >= 0:
            line = line[:idx]
        line = line.replace("\t", " ")
        if not free and len(line) > 72:
            line = line[:72]
        out.append((no, line))
    return out


def statements(text: str):
    """Yield (line_no, statement) split on periods that end a clause."""
    buf, start = "", None
    for no, line in clean_lines(text):
        s = line.strip()
        if not s:
            continue
        if start is None:
            start = no
        buf += " " + s
        # split on '.' followed by whitespace/end, but not inside quotes or picture strings like 99v99
        while True:
            m = _find_terminator(buf)
            if m is None:
                break
            stmt, buf = buf[:m].strip(), buf[m + 1:]
            if stmt:
                yield start, stmt
            start = no if buf.strip() else None
    if buf.strip():
        yield start, buf.strip()


def _find_terminator(buf: str):
    inq = None
    for i, ch in enumerate(buf):
        if inq:
            if ch == inq:
                inq = None
            continue
        if ch in "\"'":
            inq = ch
        elif ch == "." and (i + 1 == len(buf) or buf[i + 1] == " "):
            return i
    return None


def pic_info(pic: str):
    p = pic.upper()
    expanded = re.sub(r"(.)\((\d+)\)", lambda m: m.group(1) * int(m.group(2)), p)
    signed = expanded.startswith("S")
    body = expanded.lstrip("S")
    if any(c in body for c in "XA"):
        return {"kind": "alnum", "chars": len(body), "digits": 0, "scale": 0, "signed": False}
    int_part, _, frac = body.partition("V")
    digits = sum(c in "9P" for c in int_part + frac)
    edited = any(c in body for c in "Z,.-+*B0/$CRDB")
    return {"kind": "edited" if edited else "numeric", "chars": len(body.replace("V", "")),
            "digits": digits, "scale": sum(c == "9" for c in frac), "signed": signed}


def binsize(digits: int) -> int:
    if digits <= 2:
        return 1
    if digits <= 4:
        return 2
    if digits <= 9:
        return 4
    return 8


def parse(text: str) -> List[Item]:
    roots: List[Item] = []
    stack: List[Item] = []
    for no, stmt in statements(text):
        toks = stmt.split()
        if not toks or not toks[0].isdigit():
            continue
        level = int(toks[0])
        if level in (66, 77, 78, 88):
            if level == 77:
                pass
            continue
        rest = toks[1:]
        name = "FILLER"
        if rest and rest[0].lower() not in ("pic", "picture", "redefines", "occurs", "value", "values") \
                and rest[0].lower() not in USAGE_WORDS:
            name = rest[0]
            rest = rest[1:]
        it = Item(level=level, name=name, line=no)
        i = 0
        while i < len(rest):
            w = rest[i].lower()
            if w in ("pic", "picture"):
                i += 1
                if i < len(rest) and rest[i].lower() == "is":
                    i += 1
                it.pic = rest[i]
            elif w == "redefines":
                i += 1
                it.redefines = rest[i]
            elif w == "occurs":
                i += 1
                it.occurs = int(rest[i])
            elif w in USAGE_WORDS:
                it.usage = USAGE_WORDS[w]
            elif w == "usage":
                pass
            elif w == "unsigned":
                it.unsigned = True
            elif w == "leading":
                it.sign_leading = True
            elif w == "separate":
                it.sign_separate = True
            elif w in ("value", "values"):
                break
            i += 1
        if level == 1 or not stack:
            roots.append(it)
            stack = [it]
            continue
        while stack and stack[-1].level >= level:
            stack.pop()
        if not stack:
            roots.append(it)
            stack = [it]
        else:
            stack[-1].children.append(it)
            stack.append(it)
    for r in roots:
        layout(r, 0, None)
    return roots


def elem_len(it: Item, usage: Optional[str]) -> int:
    u = it.usage or usage or "DISPLAY"
    if u in FIXED_BIN and not it.pic:
        return FIXED_BIN[u]
    info = pic_info(it.pic)
    if u == "COMP-3":
        return info["digits"] // 2 + 1
    if u in ("COMP", "COMP-5"):
        return binsize(info["digits"])
    n = info["chars"]
    if info["signed"] and it.sign_separate:
        n += 1
    return n


def layout(it: Item, offset: int, usage: Optional[str]) -> int:
    it.offset = offset
    eff_usage = it.usage or usage
    it.usage = eff_usage if (it.pic or eff_usage in FIXED_BIN) else it.usage
    if it.children:
        pos = offset
        last_end = offset
        for c in it.children:
            if c.redefines:
                target = next((x for x in it.children if x.name.lower() == c.redefines.lower()), None)
                start = target.offset if target else pos
                layout(c, start, eff_usage)
                last_end = max(last_end, start + c.length * c.occurs)
                continue
            end = layout(c, pos, eff_usage)
            pos = end
            last_end = max(last_end, pos)
        it.length = last_end - offset
    else:
        it.length = elem_len(it, eff_usage)
    return offset + it.length * it.occurs


def type_map(it: Item):
    """Return (cobol_type, java_type, sql_type, codec)."""
    u = it.usage or "DISPLAY"
    if u in FIXED_BIN and not it.pic:
        signed = not it.unsigned
        java = {1: "short" if not signed else "byte", 2: "short", 4: "int" if signed else "long", 8: "long"}[FIXED_BIN[u]]
        if FIXED_BIN[u] == 1:
            java = "int"
        sql = {1: "SMALLINT", 2: "SMALLINT", 4: "INTEGER" if signed else "BIGINT", 8: "BIGINT"}[FIXED_BIN[u]]
        return (u.lower() + (" unsigned" if it.unsigned else ""), java, sql,
                f"native LE int{FIXED_BIN[u]*8}{'' if signed else ' unsigned'}")
    info = pic_info(it.pic)
    if info["kind"] == "alnum":
        return (f"PIC {it.pic}", "String", f"VARCHAR({info['chars']})" if info["chars"] > 1 else "CHAR(1)",
                "text (trailing spaces trimmed)")
    d, s, sg = info["digits"], info["scale"], info["signed"]
    if s > 0 or d > 9:
        java = "BigDecimal"
        sql = f"NUMERIC({d},{s})"
    else:
        java = "int" if d <= 9 else "long"
        sql = "SMALLINT" if d <= 4 else "INTEGER"
    if s == 0 and d >= 10:
        java, sql = "long", "BIGINT"
    if u == "COMP-3":
        codec = f"packed decimal {d} digits, scale {s}" + (", signed" if sg else "")
    elif u in ("COMP", "COMP-5"):
        codec = f"{'big-endian' if u == 'COMP' else 'native LE'} binary {binsize(d)} bytes, scale {s}" + \
                (", signed" if sg else ", unsigned")
    else:
        codec = f"zoned decimal {d} digits, scale {s}" + (
            (", sign leading" + (" separate" if it.sign_separate else " overpunch") if it.sign_leading
             else ", trailing overpunch sign") if sg else "")
    cob = f"PIC {it.pic}" + (f" {u}" if u != "DISPLAY" else "")
    return cob, java, sql, codec


def flatten(it: Item, depth=0, out=None, prefix_occ=""):
    if out is None:
        out = []
    row = {"depth": depth, "level": it.level, "name": it.name, "offset": it.offset,
           "length": it.length, "occurs": it.occurs, "redefines": it.redefines,
           "group": bool(it.children), "line": it.line}
    if not it.children:
        cob, java, sql, codec = type_map(it)
        row.update(cobol=cob, java=java, sql=sql, codec=codec)
    out.append(row)
    for c in it.children:
        flatten(c, depth + 1, out)
    return out


def main():
    res = {}
    for path in sys.argv[1:]:
        roots = parse(Path(path).read_text(errors="replace"))
        res[path] = [{"name": r.name, "length": r.length * r.occurs, "fields": flatten(r)} for r in roots]
    json.dump(res, sys.stdout, indent=1)


if __name__ == "__main__":
    main()
