#!/usr/bin/env python3
"""同一性確認ハーネス: 証跡のシナリオ台帳を Web 版（REST API）で再生し、レガシー実測と比較する。

  python3 tools/replay.py <証跡dir> [--url http://localhost:18080] [--out out] [-v] CASE_ID|PREFIX ...

サーバーは `--acas.test-api=true --acas.fixed-date=2026-11-23` で起動しておく。
比較対象: 画面テキスト（レガシー原文面, 時刻はマスク）、レコード差分（追加/更新/削除の 16 進）、帳票（prt-*）。
画面操作そのもの（ブラウザ UI）の確認・録画は tools/ui_replay.py を使う。
"""
import argparse, difflib, json, re, sys, urllib.request
from pathlib import Path

ESC = {"\x1b[H": "HOME", "\x1bOH": "HOME", "\x1b[A": "UP", "\x1b[B": "DOWN", "\x1b[C": "RIGHT", "\x1b[D": "LEFT",
       "\x1bOA": "UP", "\x1bOB": "DOWN", "\x1bOC": "RIGHT", "\x1bOD": "LEFT", "\x1b[F": "END", "\x1bOF": "END",
       "\x1bOP": "F1", "\x1bOQ": "F2", "\x1bOR": "F3", "\x1bOS": "F4", "\x1b[15~": "F5", "\x1b[17~": "F6",
       "\x1b[18~": "F7", "\x1b[19~": "F8", "\x1b[20~": "F9", "\x1b[21~": "F10", "\x1b[5~": "PGUP", "\x1b[6~": "PGDN",
       "\x1b[3~": "DELETE", "\x1b[Z": "BACKTAB"}


def to_keys(text):
    keys, i = [], 0
    while i < len(text):
        ch = text[i]
        if ch == "\x1b":
            for seq, name in sorted(ESC.items(), key=lambda x: -len(x[0])):
                if text.startswith(seq, i):
                    keys.append(name); i += len(seq); break
            else:
                keys.append("ESC"); i += 1
            continue
        keys.append({"\r": "ENTER", "\n": "ENTER", "\t": "TAB", "\x7f": "BACKSPACE", "\x08": "BACKSPACE"}.get(ch, ch))
        i += 1
    return keys


class Api:
    def __init__(self, url): self.url = url.rstrip("/")
    def call(self, method, path, body=None):
        req = urllib.request.Request(self.url + path, method=method,
                                     data=None if body is None else json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=120) as r:
            data = r.read()
        return json.loads(data) if data else None


def norm_screen(s):
    lines = [re.sub(r"\d\d:\d\d:\d\d", "HH:MM:SS", l.rstrip()) for l in s.split("\n")]
    while lines and not lines[-1]: lines.pop()
    return lines


def snap_diff(before, after):
    out = []
    for f in sorted(set(before) | set(after)):
        b, a = before.get(f, {}), after.get(f, {})
        for k in sorted(set(b) | set(a)):
            if k not in b: out.append((f, "追加", None, a[k]))
            elif k not in a: out.append((f, "削除", b[k], None))
            elif a[k] != b[k]: out.append((f, "更新", b[k], a[k]))
    return out


def is_report(f): return Path(f).name.startswith(("prt-", "final-")) or f.startswith("spool/")


def run_case(api, evid, case, verbose=False):
    cid, runner, legacy = case["id"], case["runner"], case["legacy_result"]
    res = {"id": cid, "title": case["title"], "legacy_verdict": legacy.get("verdict")}
    if legacy.get("verdict") == "未実施":
        return dict(res, verdict="対象外", reason="レガシー未実施のため比較対象なし: " + str(legacy.get("reason")))
    if not runner.get("steps"):
        return dict(res, verdict="未確認", reason="UI 手順なし（CALC は tools/calc_replay.py を使用）")
    targets = legacy.get("comparison_targets") or {}
    screens = targets.get("screen_text") or []
    api.call("POST", "/api/test/reset?baseline=" + case["baseline"])
    before = api.call("GET", "/api/test/snapshot")
    sid = api.call("POST", "/api/sessions?app=" + runner["app"] + ("&irsPath=" + runner["irs_path"] if runner.get("irs_path") else ""))["id"]
    mism, detail, missing_expect = [], [], []
    for i, step in enumerate(runner["steps"]):
        keys = to_keys(step.get("text", "")) + ([step["key"]] if "key" in step else [])
        api.call("POST", f"/api/sessions/{sid}/keys", {"keys": keys})
        scr = api.call("GET", f"/api/test/sessions/{sid}/screen?lang=en")
        got = norm_screen(scr["text"])
        if step.get("expect") and step["expect"] not in "\n".join(scr["text"].split("\n")):
            missing_expect.append({"step": i, "expect": step["expect"]})
        if i < len(screens):
            p = evid / screens[i]
            want = norm_screen(p.read_text(errors="replace")) if p.exists() else None
            if want is not None and want != got:
                mism.append(i)
                if len(detail) < 3:
                    detail.append({"step": i, "input": step.get("text", step.get("key", "")),
                                   "diff": [l for l in difflib.unified_diff(want, got, "legacy", "java", lineterm="", n=0)][:24]})
    ja = api.call("GET", f"/api/test/sessions/{sid}/screen?lang=ja")
    after = api.call("GET", "/api/test/snapshot")
    api.call("DELETE", f"/api/sessions/{sid}")
    res["screens"] = {"total": len(runner["steps"]), "legacy": len(screens), "mismatch_steps": mism, "missing_expect": missing_expect}
    res["final_screen_ja"] = ja["text"]
    # レコード差分
    rec = {"compared": False}
    dpath = targets.get("keyed_record_diff")
    jdiff = [d for d in snap_diff(before, after) if not is_report(d[0])]
    if dpath and (evid / dpath).exists():
        ld = json.loads((evid / dpath).read_text())
        unsupported = {Path(f).name for f in ld.get("unsupported_files", [])}
        lset = sorted((c["file"].replace("ledgers/", "", 1), c["operation"], (c.get("before") or {}).get("hex"), (c.get("after") or {}).get("hex")) for c in ld["changes"])
        jset = sorted(d for d in jdiff if Path(d[0]).name not in unsupported)
        rec = {"compared": True, "legacy_changes": len(lset), "java_changes": len(jset), "match": lset == jset,
               "java_changes_in_files_without_legacy_decoder": sorted({d[0] for d in jdiff if Path(d[0]).name in unsupported})}
        if lset != jset:
            ls, js = set(map(tuple, lset)), set(map(tuple, jset))
            rec["only_legacy"] = [list(x) for x in sorted(ls - js, key=str)][:6]
            rec["only_java"] = [list(x) for x in sorted(js - ls, key=str)][:6]
    res["records"] = rec
    # 帳票
    reps = []
    for rp in targets.get("report_files") or []:
        m = re.search(r"files/ledgers/(.+)$", rp) or re.search(r"files/(spool/.+)$", rp)
        p = evid / rp
        if not m or not p.exists() or p.name == "command.json": continue
        want = norm_screen(p.read_text(errors="replace").replace("\f", ""))
        name = m.group(1)
        if name.startswith("spool/"):
            cands = [f for f in after if f.startswith("spool/") and Path(f).name == Path(name).name and f not in before]
            got = [norm_screen("\n".join(bytes.fromhex(v).decode("latin1") for v in after[f].values()).replace("\f", "")) for f in cands]
            ok = want in got
        else:
            got = norm_screen("\n".join(bytes.fromhex(v).decode("latin1") for v in after.get(name, {}).values()).replace("\f", ""))
            ok = want == got
            if not ok and len(detail) < 4:
                detail.append({"report": name, "diff": [l for l in difflib.unified_diff(want, got, "legacy", "java", lineterm="", n=0)][:24]})
        reps.append({"file": name, "match": ok})
    res["reports"] = reps
    problems = []
    if mism: problems.append(f"画面相違 {len(mism)}/{len(screens)} 画面 (step {mism[:8]})")
    if missing_expect: problems.append(f"期待文言なし {missing_expect[:3]}")
    if rec.get("compared") and not rec["match"]: problems.append(f"レコード差分相違 (legacy {rec['legacy_changes']} / java {rec['java_changes']})")
    if any(not r["match"] for r in reps): problems.append("帳票相違 " + ",".join(r["file"] for r in reps if not r["match"]))
    res["verdict"] = "不一致" if problems else "一致"
    res["reason"] = "; ".join(problems) if problems else f"画面 {len(screens)}・レコード差分 {rec.get('legacy_changes', 0)} 件・帳票 {len(reps)} 件がレガシー実測と一致"
    if problems: res["detail"] = detail
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("evidence", type=Path)
    ap.add_argument("cases", nargs="+")
    ap.add_argument("--url", default="http://localhost:18080")
    ap.add_argument("--out", type=Path)
    ap.add_argument("-v", action="store_true")
    a = ap.parse_args()
    catalog = json.loads((a.evidence / "scenarios/catalog.json").read_text())["cases"]
    sel = [c for c in catalog if any(c["id"] == x or (x.endswith("-") and c["id"].startswith(x)) for x in a.cases)]
    api, results = Api(a.url), []
    for c in sel:
        try:
            r = run_case(api, a.evidence, c, a.v)
        except Exception as e:  # noqa
            r = {"id": c["id"], "title": c["title"], "verdict": "不一致", "reason": f"実行エラー: {e}"}
        results.append(r)
        print(r["id"], r["verdict"], r["reason"][:150], flush=True)
        if a.v and r.get("detail"):
            for d in r["detail"]:
                print("  ", {k: v for k, v in d.items() if k != "diff"}); print("\n".join("     " + l for l in d["diff"]))
    if a.out:
        a.out.parent.mkdir(parents=True, exist_ok=True)
        a.out.write_text(json.dumps(results, ensure_ascii=False, indent=1))
    from collections import Counter
    print(dict(Counter(r["verdict"] for r in results)))


if __name__ == "__main__":
    main()
