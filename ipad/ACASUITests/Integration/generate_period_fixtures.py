"""期末確認の既存実測から、実画面検証用の入力を生成する。"""
import argparse
import json
import sys
from pathlib import Path

IPAD = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(IPAD / "scripts"))
from generate_cases import read_json, save, snapshot_seed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path, default=IPAD / ".generated" / "fixtures")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    cases = {"INT-402": "salesPeriod", "INT-403": "purchasePeriod"}
    for case in read_json(args.evidence / "scenarios/catalog.json")["cases"]:
        if case["id"] not in cases:
            continue
        run = args.evidence / case["legacy_result"]["evidence"][0]
        if read_json(run / "record-diff.json")["changes"]:
            parser.error(f"{case['id']} は確認画面で終わる証跡ではありません")
        with (run / "terminal.cast").open(encoding="utf-8") as recording:
            date = json.loads(recording.readline())["timestamp"]
        save(args.output / (case["id"] + ".json"), {
            "id": case["id"],
            "title": "売掛元帳の期末処理確認" if case["id"] == "INT-402" else "買掛元帳の期末処理確認",
            "workflow": "integration." + cases[case["id"]],
            "dateSeconds": date,
            "seed": snapshot_seed(run),
            "changes": [],
            "reports": {},
        })
    print("期末確認の実画面用データ 2 件")


if __name__ == "__main__":
    main()
