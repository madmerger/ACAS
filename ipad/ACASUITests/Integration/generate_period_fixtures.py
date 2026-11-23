"""台帳連携の既存実測から、実画面検証用の入力を生成する。"""
import argparse
import base64
import json
import sys
from pathlib import Path

IPAD = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(IPAD / "scripts"))
from generate_cases import evidence_path, read_json, save, snapshot_seed


def purchase_transfer(evidence, run, date):
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    invoices = read_json(evidence_path(evidence, run / "before-records/records.json"))
    invoice_path = "ledgers/acas/pinvoice.dat"
    seed["files"][invoice_path] = {
        "type": "indexed",
        "records": [[row["hex"][:18], row["hex"]] for row in invoices["files"][invoice_path]["records"].values()],
    }
    changes = []
    reports = {}
    for entry in read_json(evidence_path(evidence, run / "record-diff.json"))["changes"]:
        path = entry["file"]
        before, after = (entry[k]["hex"] if entry[k] else None for k in ("before", "after"))
        if path.endswith("/posting.dat"):
            raw_file = evidence_path(evidence, run / "files" / path)
            reports[path] = raw_file.read_bytes().hex()
            continue
        code = (after or before)[:18] if path == invoice_path else entry["key"].encode("ascii").hex()
        changes.append(dict(file=path, key=code, before=before, after=after))
    report = "ledgers/acas/prt-1"
    reports[report] = evidence_path(evidence, run / "files" / report).read_bytes().hex()
    return {
        "id": "INT-405", "title": "仕入請求書を転記し、総勘定元帳の仕訳を生成する",
        "workflow": "integration.purchasePosting", "dateSeconds": date,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": changes, "recordFiles": sorted({entry["file"] for entry in changes}), "reports": reports,
    }

def confirmed_period(evidence, run, case_id, workflow, title):
    result = read_json(evidence_path(evidence, run / "result.json"))
    if result["exitstatus"] != 0 or result["error"] or result["lifecycle"] != "normal-exit":
        raise ValueError(f"{case_id}: 期末確定後の正常終了証跡が必要です")
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        date = json.loads(recording.readline())["timestamp"]
    system = "ledgers/acas/system.dat"
    ledger = "ledgers/acas/" + ("salesled.dat" if workflow == "salesPeriod" else "purchled.dat")
    invoice = "ledgers/acas/" + ("invoice.dat" if workflow == "salesPeriod" else "pinvoice.dat")
    keys = {ledger: 14, invoice: 20 if workflow == "salesPeriod" else 18}
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    before = read_json(evidence_path(evidence, run / "before-records/records.json"))
    for file, width in keys.items():
        seed["files"][file] = {
            "type": "indexed",
            "records": [[record["hex"][:width], record["hex"]]
                        for record in before["files"][file]["records"].values()],
        }
    changes = []
    for change in read_json(evidence_path(evidence, run / "record-diff.json"))["changes"]:
        if (file := change["file"]) not in keys:
            continue
        old, new = (change[k]["hex"] if change[k] else None for k in ("before", "after"))
        changes.append({"file": file, "key": (new or old)[:keys[file]], "before": old, "after": new})
    before_extra = read_json(evidence_path(evidence, run / "before-extra.json"))
    after_extra = read_json(evidence_path(evidence, run / "after-extra.json"))
    open_items = "ledgers/acas/" + ("openitm3.dat" if workflow == "salesPeriod" else "openitm5.dat")
    value = "ledgers/acas/value.dat"
    extra_files = {open_items, value}
    for file in sorted(extra_files):
        old = before_extra[file]
        if file == value and file not in after_extra and file not in result["changed"] and file not in result["deleted"]:
            new = old
        else:
            new = after_extra[file]
        seed["files"][file] = {"type": "indexed", "records": sorted(old.items())}
        changes.extend({"file": file, "key": key, "before": old.get(key), "after": new.get(key)}
                       for key in sorted(old.keys() | new.keys()) if old.get(key) != new.get(key))
    return {
        "id": case_id, "title": title, "workflow": "integration." + workflow + ".close", "dateSeconds": date,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": changes, "recordFiles": sorted(keys.keys() | extra_files),
        "reports": {system: evidence_path(evidence, run / "files" / system).read_bytes().hex()},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path, default=IPAD / ".generated" / "fixtures")
    parser.add_argument("--confirmed-root", type=Path, help="INT-402 と INT-403 の期末確定実測の親ディレクトリ")
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    cases = {
        "INT-400": "irs.settings", "INT-401": "irs.settings",
        "INT-402": "salesPeriod", "INT-403": "purchasePeriod", "INT-405": "purchasePosting",
    }
    for case in read_json(evidence_path(evidence, Path("scenarios/catalog.json")))["cases"]:
        if case["id"] not in cases:
            continue
        run = evidence_path(evidence, Path(case["legacy_result"]["evidence"][0]))
        with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
            date = json.loads(recording.readline())["timestamp"]
        if cases[case["id"]] == "irs.settings":
            relative_path = "ledgers/irs/system.dat"
            before = evidence_path(evidence, run / "before-files" / relative_path).read_bytes()
            after = evidence_path(evidence, run / "files" / relative_path).read_bytes()
            typed = case["input_data"]["text_inputs"][-1].split("\t")[2].encode("shift_jis")
            client = (typed + before[32 + len(typed):56]).decode("shift_jis").rstrip(" ")
            env = read_json(evidence_path(evidence, run / "environment.json"))
            save(args.output / (case["id"] + ".json"), {
                "id": case["id"],
                "title": "簡易記帳の事業者設定（" + ("通常指定" if case["id"] == "INT-400" else "主台帳指定") + "）",
                "workflow": "irs.settings",
                "dateSeconds": date,
                "seed": snapshot_seed(evidence, run),
                "changes": [],
                "reports": {relative_path: after.hex()},
                "input": {"client": client, "irsDirectory": "/".join(Path(env["ACAS_IRS"]).parts[-2:])},
            })
            continue
        if case["id"] == "INT-405":
            save(args.output / "INT-405.json", purchase_transfer(evidence, run, date))
            continue
        if read_json(evidence_path(evidence, run / "record-diff.json"))["changes"]:
            parser.error(f"{case['id']} は確認画面で終わる証跡ではありません")
        save(args.output / (case["id"] + ".json"), {
            "id": case["id"],
            "title": "売掛元帳の期末処理確認" if case["id"] == "INT-402" else "買掛元帳の期末処理確認",
            "workflow": "integration." + cases[case["id"]],
            "dateSeconds": date,
            "seed": snapshot_seed(evidence, run),
            "changes": [],
            "reports": {},
        })
    if args.confirmed_root:
        root = args.confirmed_root.resolve()
        for case_id, title in (("INT-402", "売掛元帳の期末処理確定"), ("INT-403", "買掛元帳の期末処理確定")):
            save(args.output / (case_id + "-close.json"), confirmed_period(root, Path(case_id), case_id, cases[case_id], title))
    print(f"連携の実画面用データ {7 if args.confirmed_root else 5} 件")


if __name__ == "__main__":
    main()
