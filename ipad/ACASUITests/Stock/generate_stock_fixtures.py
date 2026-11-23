"""在庫監査帳票と入出庫のレガシー実測から実画面用の入力を生成する。"""
import argparse
import base64
import json
import sys
from pathlib import Path

IPAD = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(IPAD / "scripts"))
from generate_cases import evidence_path, expected_changes, read_json, save, snapshot_seed


def movement_fixture(evidence, case):
    legacy = case["legacy_result"]
    run = evidence_path(evidence, legacy["evidence"][0])
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    ship = case["id"] in {"ST-402", "ST-403"}
    path = "ledgers/acas/prt-1"
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    seed["files"][path] = {"type": "raw", "hex": evidence_path(evidence, run / "before-files" / path).read_bytes().hex()}
    inputs = case["input_data"]["text_inputs"]
    return {
        "id": case["id"],
        "title": {"ST-400": "在庫入庫1件", "ST-401": "入庫の不存在品目",
                  "ST-402": "在庫出庫1件", "ST-403": "出庫の不存在品目"}[case["id"]],
        "workflow": "stock.issue" if ship else "stock.receive",
        "dateSeconds": timestamp,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": expected_changes(evidence, legacy["comparison_targets"]["keyed_record_diff"]),
        "reports": {path: evidence_path(evidence, run / "files" / path).read_bytes().hex()},
        "input": {"code": inputs[4].strip(), "quantity": str(int(inputs[5].strip())) if len(inputs) > 5 else "1",
                  "price": None if ship else inputs[6].strip() if len(inputs) > 6 else "0"},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path, default=IPAD / ".generated" / "fixtures")
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    cases = {c["id"]: c for c in read_json(evidence_path(evidence, Path("scenarios/catalog.json")))["cases"]}
    case = cases["ST-214"]
    result = case["legacy_result"]
    run = evidence_path(evidence, Path(result["evidence"][0]))
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    outputs = {}
    for path in result["comparison_targets"]["report_files"]:
        data = evidence_path(evidence, path).read_bytes()
        name = "audit-additions.prt" if b"Additions Stock Audit Report" in data[:132] else "audit-deductions.prt"
        outputs["ledgers/acas/" + name] = data.hex()
    if len(outputs) != 2:
        parser.error("入庫・出庫の監査帳票が必要です。")
    args.output.mkdir(parents=True, exist_ok=True)
    save(args.output / "ST-214.json", {
        "id": case["id"], "title": "在庫監査帳票を発行する", "workflow": "stock.audit",
        "dateSeconds": timestamp, "seed": snapshot_seed(evidence, run),
        "changes": [], "recordFiles": [], "reports": outputs,
    })
    for case_id in ("ST-400", "ST-401", "ST-402", "ST-403"):
        save(args.output / (case_id + ".json"), movement_fixture(evidence, cases[case_id]))
    print("在庫の実画面用データ 5 件")


if __name__ == "__main__":
    main()
