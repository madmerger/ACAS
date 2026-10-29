#!/usr/bin/env python3
"""Generate docs/migration/01-program-inventory.md and 02-file-layouts.md from the COBOL sources.

Usage: python3 docs/migration/tools/gen_docs.py
"""
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / "docs" / "migration"
sys.path.insert(0, str(HERE))
import cobol_layout as cl  # noqa: E402
import extract_calls as ec  # noqa: E402
import extract_menus as em  # noqa: E402

MODULES = [("(root)", "ACAS メインメニュー"), ("common", "共通サブルーチン"), ("sales", "売掛 SL"),
           ("purchase", "買掛 PL"), ("stock", "在庫"), ("general", "総勘定元帳 GL"),
           ("incomplete_records_system", "IRS")]
EXTERNAL = {"SYSTEM", "CBL_CHECK_FILE_EXIST", "C$JUSTIFY"}

# (logical file, select copybook, fd/record copybooks, physical name, organization, keys, notes)
FILES = [
    ("system", "copybooks/selsys.cob", ["copybooks/wssystem.cob", "copybooks/wsdflt.cob", "copybooks/wsfinal.cob", "copybooks/wssys4.cob"],
     "system.dat (file-0)", "RELATIVE", "RRN 1=System-Record, 2=Default-Record, 3=Final-Record, 4=System-Record-4 (sys002.cbl:776-792)", "4 種のレコードを RRN で多重化"),
    ("ledger", "general/seledger.cob", ["general/fdledger.cob"], "ledger.dat (file-5)", "INDEXED", "ledger-key (ledger-nos 9(6) + ledger-pc 9(2))", "GL 勘定科目"),
    ("posting", "copybooks/selpost.cob", ["copybooks/fdpost.cob"], "posting.dat (file-6)", "RELATIVE", "RRN（post-key = batch + post-number を内包）", "GL 仕訳"),
    ("batch", "copybooks/selbatch.cob", ["copybooks/fdbatch.cob"], "batch.dat (file-7)", "INDEXED", "batch-key (ledger 9 + batch-nos 9(5))", "GL/SL/PL バッチ"),
    ("irs-post (SL/PL→IRS)", "copybooks/selpost-irs.cob", ["copybooks/fdpost-irs.cob"], "postings2irs.dat (file-8)", "SEQUENTIAL (optional)", "なし", "SL/PL から IRS への転記インタフェース"),
    ("stock-audit", "copybooks/selaud.cob", ["copybooks/fdaudit.cob"], "staudit.dat (file-10)", "SEQUENTIAL (optional)", "なし", "在庫監査ログ"),
    ("stock", "copybooks/selstock.cob", ["copybooks/fdstock.cob"], "stockctl.dat (file-11)", "INDEXED",
     "Stock-Key x(13); ALT Stock-Abrev-Key x(7); ALT Stock-Desc x(32) WITH DUPLICATES", "在庫マスタ"),
    ("sales (customer)", "copybooks/selsl.cob", ["copybooks/fdsl.cob"], "salesled.dat (file-12)", "INDEXED", "sales-key x(7)（6 桁 + チェックデジット）", "顧客マスタ"),
    ("value (SL/PL analysis totals)", "copybooks/selval.cob", ["copybooks/fdval.cob"], "value.dat (file-13)", "INDEXED", "va-code x(3)", "分析コード別集計"),
    ("delivery", "copybooks/seldel.cob", ["copybooks/fddel.cob"], "delivery.dat (file-14)", "INDEXED", "deliv-key (type x + account x(7))", "配送先/メモ（顧客・仕入先共用）"),
    ("analysis", "copybooks/selanal.cob", ["copybooks/fdanal.cob"], "analysis.dat (file-15)", "INDEXED", "pa-code x(3)", "分析コードマスタ"),
    ("sales invoice", "sales/selinv.cob", ["sales/fdinv2.cob"], "invoice.dat (file-16)", "INDEXED", "invoice-key (invoice-nos 9(8) + invoice-let x + item-nos binary-char)",
     "ヘッダ(item-nos=0)と明細(1..40)を同一キー空間で多重化"),
    ("sales deleted invoice nos", "sales/seldnos.cob", ["sales/fddnos.cob"], "delinvno.dat (file-17)", "SEQUENTIAL", "なし", "削除済請求書番号"),
    ("sales open item (seq)", "sales/seloi2.cob", ["sales/fdoi2.cob", "sales/wsoi.cob"], "openitm2.dat (file-18)", "SEQUENTIAL", "なし", "転記前 OI（中身は wsoi oi-header）"),
    ("sales open item", "sales/seloi3.cob", ["sales/fdoi3.cob", "sales/wsoi.cob"], "openitm3.dat (file-19)", "INDEXED", "oi3-key (customer x(7) + invoice binary-long)", "売掛オープンアイテム（中身は wsoi oi-header）"),
    ("sales oi sort work", "sales/selois.cob", ["sales/fdois.cob"], "oisort.wrk (file-20)", "SEQUENTIAL", "なし", "作業ファイル（移行対象外）"),
    ("purchase (supplier)", "copybooks/selpl.cob", ["copybooks/fdpl.cob"], "purchled.dat (file-22)", "INDEXED", "purch-key x(7)", "仕入先マスタ"),
    ("purchase deleted folio nos", "purchase/selpdnos.cob", ["purchase/fdpdnos.cob"], "delfolio.dat (file-23)", "SEQUENTIAL", "なし", "削除済フォリオ番号"),
    ("purchase invoice", "purchase/selpinv.cob", ["purchase/fdpinv2.cob"], "pinvoice.dat (file-26)", "INDEXED", "invoice-key (invoice-nos 9(8) + item-nos binary-char)", "ヘッダ/明細多重化"),
    ("purchase oi sort work", "purchase/selois.cob", ["purchase/fdois.cob"], "poisort.wrk (file-27)", "SEQUENTIAL", "なし", "作業ファイル（移行対象外）"),
    ("purchase open item (seq)", "purchase/seloi4.cob", ["purchase/fdoi4.cob", "purchase/wsoi.cob"], "openitm4.dat (file-28)", "SEQUENTIAL", "なし", "転記前 OI"),
    ("purchase open item", "copybooks/seloi5.cob", ["purchase/fdoi5.cob", "purchase/wsoi.cob"], "openitm5.dat (file-29)", "INDEXED", "oi5-key (supplier x(7) + invoice binary-long)", "買掛オープンアイテム"),
    ("pay", "purchase/selpay.cob", ["purchase/fdpay.cob"], "pay.dat (file-32)", "INDEXED", "pay-key (supplier x(7) + pay-nos binary-char)", "支払（明細 9 件 OCCURS）"),
    ("IRS nominal ledger", "common/irsub1.cbl", ["incomplete_records_system/wsnl.cob"], "acnts.dat", "INDEXED", "key-1 (owning 9(5) + sub-nominal 9(5))", "IRS 勘定（owner/sub の REDEFINES）"),
    ("IRS system", "incomplete_records_system/irsub2.cbl", ["incomplete_records_system/wssystem.cob"], "system.dat (IRS)", "LINE SEQUENTIAL", "なし（1 レコード）", "ACAS の system.dat とは別形式"),
    ("IRS defaults", "common/irsub3.cbl", ["incomplete_records_system/wsdflt.cob"], "dflt.dat", "LINE SEQUENTIAL", "なし（1 レコード）", ""),
    ("IRS posting", "common/irsub4.cbl", ["incomplete_records_system/wspost.cob"], "post.dat", "INDEXED", "post-key 9(5)", ""),
    ("IRS final accounts", "common/irsub5.cbl", ["incomplete_records_system/wsfinal.cob"], "final.dat", "LINE SEQUENTIAL", "なし（1 レコード）", ""),
]


def module_of(path: str) -> str:
    parts = path.split("/")
    return parts[0] if len(parts) > 1 else "(root)"


def gen_inventory(calls, menus):
    lines = ["# 01. プログラム一覧と呼び出し関係", "",
             "> 本書は `docs/migration/tools/gen_docs.py` により COBOL ソースから自動生成（手編集しない）。",
             "> 抽出ルール: 静的 `CALL \"x\"` と、動的呼び出し `MOVE \"x\" TO ws-called` → `CALL ws-called`。"
             " コメント（`*>`、固定形式 7 桁目 `*`）は除外。`experimental-stuff/` は対象外。", ""]
    progs = {k: v for k, v in calls.items()}
    known = {Path(v["path"]).stem for v in progs.values()}
    # module summary
    lines += ["## 1. モジュール別サマリ", "", "| モジュール | 役割 | プログラム数 | 行数 |", "|---|---|---:|---:|"]
    for mod, desc in MODULES:
        ps = [v for v in progs.values() if module_of(v["path"]) == mod]
        lines.append(f"| `{mod}` | {desc} | {len(ps)} | {sum(p['lines'] for p in ps):,} |")
    sub = [v for v in progs.values() if module_of(v["path"]) not in dict(MODULES)]
    rw = [v for v in progs.values() if "RW-" in v["path"]]
    lines += ["", f"合計 {len(progs)} プログラム / {sum(p['lines'] for p in progs.values()):,} 行"
              f"（うち `RW-Programs`/`RW-programs` の Report Writer 版・`.original` 等の派生 {len(rw)} 本を含む）。", ""]
    # module-level dependency diagram
    lines += ["## 2. モジュール依存図（モジュール間 CALL）", "", "```mermaid", "flowchart LR"]
    edges = defaultdict(int)
    for v in progs.values():
        src = module_of(v["path"])
        for c in v["calls"]:
            if c in EXTERNAL:
                continue
            tgt = next((module_of(w["path"]) for w in progs.values() if Path(w["path"]).stem == c), None)
            if tgt and tgt != src:
                edges[(src, tgt)] += 1
    ids = {m: re.sub(r"\W", "_", m.strip("()")) for m, _ in MODULES}
    for m, d in MODULES:
        lines.append(f'    {ids[m]}["{m}<br/>{d}"]')
    for (a, b), n in sorted(edges.items()):
        lines.append(f"    {ids[a]} -->|{n}| {ids[b]}")
    lines += ["```", "", "矢印のラベルは呼び出し元プログラム→呼び出し先プログラムの組の数。", ""]
    # menus
    lines += ["## 3. メニュー → プログラム対応（エントリポイント）", "",
              "`ACAS.cbl` と各サブシステムのメニューは選択文字 A–Z を `GO TO ... DEPENDING ON z` で段落に振り分け、"
              "段落内で `ws-called` に設定したプログラムを順に CALL する（`extract_menus.py`）。"
              " IRS は画面セクションで 1–9/A を受け付け直接 CALL する（irs.cbl:405-455、手動抽出）。", ""]
    for menu, data in menus.items():
        rows = [r for r in data["dispatch"] if r["label"] or r["programs"]]
        if not rows:
            continue
        lines += [f"### `{menu}`", "", "| キー | メニュー表示 | 段落 | 呼び出しプログラム（順） |", "|---|---|---|---|"]
        for r in rows:
            progs_s = " → ".join(f"`{p}`" for p in r["programs"]) or "（内部処理/未実装）"
            lines.append(f"| {r['key']} | {r['label']} | `{r['paragraph']}` | {progs_s} |")
        lines.append("")
    lines += ["### `incomplete_records_system/irs.cbl`（手動抽出）", "",
              "| キー | メニュー表示 | 呼び出しプログラム（順） |", "|---|---|---|",
              "| 1 | System Set-Up & Maintenance | 内部段落 `set-up` |",
              "| 2 | Accounts Set-Up & Maintenance | `irs010` |",
              "| 3 | Default A/Cs Set-Up & Maintenance | `irs020` |",
              "| 4 | Posting | `irs030` |", "| 5 | Trial Balance | `irs040` |", "| 6 | Audit Trail | `irs050` |",
              "| 7 | Accounts Production | `irs065` → `irs060` |", "| 8 | Posting Amendments | `irs070` |",
              "| 9 | Analysis Report | `irs085` → `irs090` |", "| A | Nominal File Fix up | `irs080` |",
              "| \\| | （テスト用：任意プログラム名を入力して CALL） | `call-prog` 動的 — **移植しない**（任意モジュール実行） |", ""]
    # sub-menus
    lines += ["### サブメニュー", "",
              "| 親 | 呼び出し先 | 備考 |", "|---|---|---|",
              "| `sales/sl900.cbl` (Invoice Sub-System) | " + ", ".join(f"`{c}`" for c in progs["sl900"]["calls"]) + " | 請求書サブシステム |",
              "| `purchase/pl900.cbl` (Cheque Sub-System) | " + ", ".join(f"`{c}`" for c in progs["pl900"]["calls"]) + " | 小切手/支払サブシステム |",
              "| `purchase/pl180.cbl` (Invoice Parameter Amend) | " + ", ".join(f"`{c}`" for c in progs["pl180"]["calls"]) + " | |",
              "| `general/gl090.cbl` (Trial Balance) | " + ", ".join(f"`{c}`" for c in progs["gl090"]["calls"]) + " | |", ""]
    # full table
    lines += ["## 4. 全プログラム一覧", "",
              "凡例: **S**=SCREEN SECTION 使用、**P**=印刷（`selprint`/print-spool）使用。ファイル列は COPY している `sel*.cob`"
              "（IRS は irsub* 経由でファイルアクセスするため空欄が多い）。", ""]
    for mod, desc in MODULES:
        ps = sorted([(k, v) for k, v in progs.items() if module_of(v["path"]) == mod], key=lambda x: x[1]["path"])
        lines += [f"### {mod} — {desc}", "", "| プログラム | 行数 | 段落数 | S/P | 使用ファイル (sel) | CALL 先 |", "|---|---:|---:|---|---|---|"]
        for k, v in ps:
            src = (ROOT / v["path"]).read_text(errors="replace")
            paras = len(re.findall(r"^ {1,4}[A-Za-z0-9][A-Za-z0-9-]*\.\s*$", src, re.M))
            s = "S" if re.search(r"screen\s+section", src, re.I) else "-"
            p = "P" if any(c.lower().startswith(("selprint", "print-spool")) for c in v["copies"]) else "-"
            sels = ", ".join(c.replace(".cob", "") for c in v["copies"] if c.lower().startswith("sel"))
            cs = []
            for c in v["calls"]:
                if c in EXTERNAL:
                    cs.append(f"*{c}*")
                elif c in known:
                    cs.append(f"`{c}`")
                else:
                    cs.append(f"`{c}`⚠")
            lines.append(f"| `{v['path']}` | {v['lines']} | {paras} | {s}{p} | {sels} | {', '.join(cs)} |")
        lines.append("")
    lines += ["⚠ = 呼び出し先がリポジトリに存在しない（`OE`/`payroll`/`epos` はオープンソース版で除外、`gl210` は未提供、"
              "`stockMT` 内の `HandleDB` 等は RDB DAL（未収録）。*斜体* = ランタイム/ライブラリ呼び出し。", ""]
    return "\n".join(lines)


def gen_layouts():
    lines = ["# 02. ファイル（ISAM）構造とレコードレイアウト", "",
             "> `docs/migration/tools/gen_docs.py` により自動生成。オフセット/長さは `cobol_layout.py` で算出し、"
             "全レコード長を `verify_layout.sh`（GnuCOBOL `FUNCTION LENGTH`）で照合済み。", "",
             "## 1. ファイル一覧", "", "| 論理ファイル | 物理ファイル | 編成 | キー | 備考 | 定義 |", "|---|---|---|---|---|---|"]
    for name, sel, recs, phys, org, keys, note in FILES:
        lines.append(f"| {name} | `{phys}` | {org} | {keys} | {note} | `{sel}` / " + ", ".join(f"`{r}`" for r in recs) + " |")
    lines += ["", "上記以外に `copybooks/wsnames.cob` には `archive.dat`(file-2)、`final.dat`(file-3)、`tmp-stock.dat`(file-9)、"
              "`work.tmp`(file-21)、`cheque.dat`(file-33) 等の作業/出力ファイルが定義されている（業務データとしての移行対象外）。", ""]
    lines += ["## 2. レコードレイアウト", "",
              "列: Off=0 始まりのバイトオフセット、Len=1 出現分の長さ、Occ=OCCURS 回数。codec はデータ移行ツールでのデコード方法。", ""]
    seen = set()
    for name, sel, recs, phys, org, keys, note in FILES:
        for r in recs:
            if r in seen:
                continue
            seen.add(r)
            roots = cl.parse((ROOT / r).read_text(errors="replace"))
            for root in roots:
                rows = cl.flatten(root)
                lines += [f"### `{root.name}` — `{r}`（{root.length * root.occurs} バイト）", "",
                          "| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |", "|---:|---:|---:|---|---|---|---|---|"]
                for row in rows[1:]:
                    nm = ("&nbsp;" * 2 * (row["depth"] - 1)) + row["name"]
                    if row["redefines"]:
                        nm += f" *(REDEFINES {row['redefines']})*"
                    if row["group"]:
                        lines.append(f"| {row['offset']} | {row['length']} | {row['occurs'] if row['occurs'] > 1 else ''} | **{nm}** | group | | | |")
                    else:
                        lines.append(f"| {row['offset']} | {row['length']} | {row['occurs'] if row['occurs'] > 1 else ''} | {nm} | `{row['cobol']}` | {row['java']} | {row['sql']} | {row['codec']} |")
                lines.append("")
    return "\n".join(lines)


def main():
    calls = {}
    for p in sorted(ROOT.rglob("*.cbl")):
        if "experimental-stuff" in p.parts:
            continue
        key = p.stem if p.stem not in calls else str(p.relative_to(ROOT))
        calls[key] = ec.analyse(p)
    menus = {m: em.menu(ROOT / m) for m in em.MENUS}
    (OUT / "01-program-inventory.md").write_text(gen_inventory(calls, menus) + "\n")
    (OUT / "02-file-layouts.md").write_text(gen_layouts() + "\n")
    (OUT / "data").mkdir(exist_ok=True)
    (OUT / "data" / "calls.json").write_text(json.dumps(calls, indent=1) + "\n")
    (OUT / "data" / "menus.json").write_text(json.dumps(menus, indent=1, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
