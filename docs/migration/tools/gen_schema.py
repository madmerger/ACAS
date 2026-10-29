#!/usr/bin/env python3
"""Generate the proposed RDB DDL (docs/migration/schema/acas-schema.sql) from the COBOL record layouts.

Rules (see 03-rdb-schema.md):
  * one table per business record; FILLER and REDEFINES alternatives are dropped
  * group names are flattened; columns are snake_case of the leaf names
  * OCCURS > 1 (elementary or group) becomes a child table keyed by parent PK + seq_no
  * PK = leaf columns under the COBOL record-key group; single-record files use id = 1
  * binary-long / PIC 9(8) COMP fields whose name contains "date" are COBOL integer dates -> DATE
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
import cobol_layout as cl  # noqa: E402

# table, copybook, 01 record name, key group (None => single row id), unique alt keys, non-unique indexes, source file
TABLES = [
    ("system_record", "copybooks/wssystem.cob", "System-Record", None, [], [], "system.dat RRN 1"),
    ("default_record", "copybooks/wsdflt.cob", "Default-Record", None, [], [], "system.dat RRN 2"),
    ("final_record", "copybooks/wsfinal.cob", "Final-Record", None, [], [], "system.dat RRN 3"),
    ("system_record_4", "copybooks/wssys4.cob", "System-Record-4", None, [], [], "system.dat RRN 4"),
    ("gl_ledger", "general/fdledger.cob", "ledger-record", "ledger-key", [], [], "ledger.dat"),
    ("gl_posting", "copybooks/fdpost.cob", "posting-record", "post-key", [], [], "posting.dat"),
    ("batch", "copybooks/fdbatch.cob", "batch-record", "batch-key", [], [], "batch.dat"),
    ("irs_interface_posting", "copybooks/fdpost-irs.cob", "irs-posting-record", None, [], [], "postings2irs.dat (sequential, surrogate id)"),
    ("stock_audit", "copybooks/fdaudit.cob", "Stock-Audit-Record", None, [], [], "staudit.dat (sequential, surrogate id)"),
    ("stock", "copybooks/fdstock.cob", "Stock-Record", "Stock-Key", ["Stock-Abrev-Key"], ["Stock-Desc"], "stockctl.dat"),
    ("sl_customer", "copybooks/fdsl.cob", "Sales-Record", "Sales-Key", [], [], "salesled.dat"),
    ("analysis_value", "copybooks/fdval.cob", "value-record", "va-code", [], [], "value.dat"),
    ("delivery", "copybooks/fddel.cob", "delivery-record", "deliv-key", [], [], "delivery.dat"),
    ("analysis_code", "copybooks/fdanal.cob", "analysis-record", "pa-code", [], [], "analysis.dat"),
    ("sl_invoice_header", "sales/fdinv2.cob", "invoice-header", ["ih-invoice", "ih-letter", "ih-test"], [], [], "invoice.dat (item-nos = 0)"),
    ("sl_invoice_line", "sales/fdinv2.cob", "invoice-line", ["il-invoice", "il-letter", "il-line"], [], [], "invoice.dat (item-nos 1..40)"),
    ("sl_open_item", "sales/wsoi.cob", "oi-header", "oi-key", [], [], "openitm3.dat (+ openitm2.dat before posting)"),
    ("sl_deleted_invoice_no", "sales/fddnos.cob", "del-inv-nos-record", None, [], [], "delinvno.dat (sequential, surrogate id)"),
    ("pl_supplier", "copybooks/fdpl.cob", "Purch-Record", "Purch-Key", [], [], "purchled.dat"),
    ("pl_invoice_header", "purchase/fdpinv2.cob", "invoice-header", ["ih-invoice", "ih-test"], [], [], "pinvoice.dat (item-nos = 0)"),
    ("pl_invoice_line", "purchase/fdpinv2.cob", "invoice-line", ["il-invoice", "il-line"], [], [], "pinvoice.dat (item-nos 1..)"),
    ("pl_open_item", "purchase/wsoi.cob", "oi-header", "oi-key", [], [], "openitm5.dat (+ openitm4.dat before posting)"),
    ("pl_deleted_folio_no", "purchase/fdpdnos.cob", "del-inv-nos-record", None, [], [], "delfolio.dat (sequential, surrogate id)"),
    ("pl_payment", "purchase/fdpay.cob", "pay-record", "pay-key", [], [], "pay.dat"),
    ("irs_nominal", "incomplete_records_system/wsnl.cob", "nl-record", "nl-key", [], [], "acnts.dat"),
    ("irs_system", "incomplete_records_system/wssystem.cob", "system-record", None, [], [], "IRS system.dat"),
    ("irs_default", "incomplete_records_system/wsdflt.cob", "default-record", None, [], [], "dflt.dat"),
    ("irs_posting", "incomplete_records_system/wspost.cob", "posting-record", "post-key", [], [], "post.dat"),
    ("irs_final", "incomplete_records_system/wsfinal.cob", "Final-Record", None, [], [], "final.dat"),
]


CHILD_NAMES = {("pl_payment", "filler"): "line"}


def col(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def sqltype(it):
    _, _, sql, _ = cl.type_map(it)
    usage = (it.usage or "").upper()
    if "date" in it.name.lower() and (usage == "BINARY-LONG" or (it.pic and usage.startswith("COMP") and "V" not in it.pic.upper() and usage != "COMP-3")):
        return "DATE", "COBOL integer date (FUNCTION DATE-OF-INTEGER)"
    return sql, ""


def leaves(it, out, ctx):
    """Collect (column, item) of non-filler leaves, stopping at OCCURS (returned separately)."""
    for c in it.children if it.children else []:
        if c.redefines or c.name.lower() == "filler" and not c.children:
            continue
        if c.occurs > 1:
            ctx["child"].append(c)
            continue
        if c.children:
            leaves(c, out, ctx)
        else:
            out.append(c)
    return out


def find(it, name):
    if it.name.lower() == name.lower():
        return it
    for c in it.children:
        r = find(c, name)
        if r:
            return r
    return None


def table_ddl(table, root, keygrp, uniq, idx, source, warn):
    ctx = {"child": []}
    cols = leaves(root, [], ctx)
    seen, colsdef = set(), []
    for c in cols:
        n = col(c.name)
        if n in seen:
            n = f"{n}_{c.offset}"
        seen.add(n)
        t, note = sqltype(c)
        colsdef.append((n, t, f"{c.name} @{c.offset}+{c.length} {cl.type_map(c)[0]}" + (f"; {note}" if note else "")))
    if isinstance(keygrp, list):
        pk = [col(x) for x in keygrp]
    elif keygrp:
        k = find(root, keygrp)
        if not k:
            warn.append(f"{table}: key {keygrp} not found")
            pk = ["id"]
        else:
            pk = [col(x.name) for x in (leaves(k, [], {"child": []}) if k.children else [k])]
    else:
        pk = ["id"]
        colsdef.insert(0, ("id", "BIGINT", "surrogate / single-record id"))
    defs = [f"    {n:<32} {t:<14}" for n, t, _ in colsdef] + [f"    PRIMARY KEY ({', '.join(pk)})"]
    cmts = [c for _, _, c in colsdef] + [""]
    body = []
    for i, (d, c) in enumerate(zip(defs, cmts)):
        sep = "," if i < len(defs) - 1 else ""
        body.append(f"{d.rstrip()}{sep}" + (f"  -- {c}" if c else ""))
    out = f"-- {table}: {source}; COBOL {root.name} ({root.length} bytes)\nCREATE TABLE {table} (\n" + "\n".join(body) + "\n);\n"
    for u in uniq:
        k = find(root, u)
        cs = [col(x.name) for x in (leaves(k, [], {"child": []}) if k.children else [k])]
        out += f"CREATE UNIQUE INDEX ux_{table}_{col(u)} ON {table} ({', '.join(cs)});\n"
    for u in idx:
        out += f"CREATE INDEX ix_{table}_{col(u)} ON {table} ({col(u)});  -- WITH DUPLICATES\n"
    pkcols = [(n, t) for n, t, _ in colsdef if n in pk]
    for ch in ctx["child"]:
        ct = f"{table}_{CHILD_NAMES.get((table, col(ch.name)), col(ch.name))}"
        sub = leaves(ch, [], {"child": []}) if ch.children else [ch]
        cd = [f"    {n:<32} {t}" for n, t in pkcols] + [f"    {'seq_no':<32} SMALLINT"]
        for s in sub:
            t, note = sqltype(s)
            cd.append(f"    {col(s.name):<32} {t}")
        cd.append(f"    PRIMARY KEY ({', '.join([n for n, _ in pkcols] + ['seq_no'])})")
        cd.append(f"    FOREIGN KEY ({', '.join(n for n, _ in pkcols)}) REFERENCES {table} ({', '.join(n for n, _ in pkcols)})")
        out += f"-- {ct}: OCCURS {ch.occurs} of {ch.name}\nCREATE TABLE {ct} (\n" + ",\n".join(cd) + "\n);\n"
    return out, len(colsdef), [f"{table}_{CHILD_NAMES.get((table, col(c.name)), col(c.name))}" for c in ctx["child"]], pk


def main():
    warn, summary = [], []
    parts = ["-- ACAS proposed RDB schema (PostgreSQL dialect). Generated by docs/migration/tools/gen_schema.py - do not edit.\n"]
    for table, path, rec, key, uniq, idx, source in TABLES:
        roots = {r.name.lower(): r for r in cl.parse((ROOT / path).read_text(errors="replace"))}
        root = roots.get(rec.lower())
        if not root:
            warn.append(f"{table}: record {rec} not in {path}")
            continue
        ddl, ncols, children, pk = table_ddl(table, root, key, uniq, idx, source, warn)
        parts.append(ddl)
        summary.append((table, source, f"{root.name} ({path})", ncols, pk, children))
    out = ROOT / "docs" / "migration" / "schema"
    out.mkdir(exist_ok=True)
    (out / "acas-schema.sql").write_text("\n".join(parts))
    for w in warn:
        print("WARN", w, file=sys.stderr)
    for s in summary:
        print("|", " | ".join([f"`{s[0]}`", s[1], f"`{s[2]}`", str(s[3]), ", ".join(s[4]), ", ".join(f"`{c}`" for c in s[5]) or "-"]), "|")


if __name__ == "__main__":
    main()
