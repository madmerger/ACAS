#!/usr/bin/env python3
"""CALC ケース（計算ロジック）を実アプリの REST API へ再生し、レガシー実測値と比較する。

使い方: python3 tools/calc_replay.py <証跡展開dir> [--url http://localhost:8080] [--out 結果.json]
レガシー未実施のケース（比較対象なし）は「対象外」とする。
"""
import argparse, json, urllib.parse
from collections import Counter
from decimal import Decimal
from pathlib import Path

from replay import Api, load_catalog

API = {"drv09": "check-digit", "drv04": "date", "drvvat": "vat", "drvage": "age", "drvavg": "average-cost"}
DRIVER_BY_KEY = {"code": "drv09", "date": "drv04", "net": "drvvat", "days": "drvage", "value": "drvavg"}


def same(want, got):
    for k, w in want.items():
        g = got.get(k)
        if k in ("vat", "cost"):
            if g is None or Decimal(str(w)) != Decimal(str(g)): return False
        elif w != g: return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("evidence", type=Path)
    ap.add_argument("--url", default="http://localhost:18080")
    ap.add_argument("--out", type=Path)
    a = ap.parse_args()
    cases = [c for c in load_catalog(a.evidence) if c["subsystem"] == "CALC"]
    api = Api(a.url)
    results = []
    for c in cases:
        lr, inp = c["legacy_result"], c["input_data"]
        r = {"id": c["id"], "title": c["title"], "legacy_verdict": lr["verdict"], "input": inp}
        driver = next((d for k, d in DRIVER_BY_KEY.items() if k in inp), None)
        if lr["verdict"] == "未実施" or lr.get("actual") is None or driver is None:
            r.update(verdict="対象外", reason="レガシー未実施のため比較対象なし: " + str(lr.get("reason") or ""))
        else:
            path = f"/api/calc/{API[driver]}?" + urllib.parse.urlencode(inp)
            try:
                got = api.call("GET", path)
                ok = same(lr["actual"], got)
                r.update(java_actual=got, legacy_actual=lr["actual"], verdict="一致" if ok else "不一致",
                         reason=("REST API の計算結果がレガシー実測と一致: " if ok else "計算結果相違: legacy=%s java=" % json.dumps(lr["actual"], ensure_ascii=False))
                                + json.dumps(got, ensure_ascii=False))
            except Exception as e:  # noqa
                r.update(verdict="不一致", reason=f"実行エラー: {e}")
        results.append(r)
        if r["verdict"] != "一致": print(r["id"], r["verdict"], r["reason"][:120])
    if a.out:
        a.out.parent.mkdir(parents=True, exist_ok=True)
        a.out.write_text(json.dumps(results, ensure_ascii=False, indent=1))
    print(dict(Counter(r["verdict"] for r in results)))


if __name__ == "__main__":
    main()
