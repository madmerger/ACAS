"""在庫監査帳票のレガシー証跡を実画面で照合する入力を生成する。"""
import argparse
import json
import sys
from pathlib import Path

IPAD = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(IPAD / "scripts"))
from generate_cases import evidence_path, read_json, save, snapshot_seed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path, default=IPAD / ".generated" / "fixtures")
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    case = next(c for c in read_json(evidence_path(evidence, Path("scenarios/catalog.json")))["cases"]
                if c["id"] == "ST-214")
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
    print("在庫の実画面用データ 1 件")


if __name__ == "__main__":
    main()
