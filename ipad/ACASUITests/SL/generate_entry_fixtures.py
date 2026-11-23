"""売掛元帳の処理日画面に対応する実 UI 用の証跡を生成する。"""
import argparse
import json
from pathlib import Path

from generate_customer_fixtures import BASE, IPAD


CASES = {
    "SL-001": ("sales-date-view", "処理日入力の表示"),
    "SL-200": ("sales-start-date-view", "売掛元帳を開く"),
    "SL-201": ("sales-date-view", "処理日入力を開く"),
    "SL-243": ("sales-start-date-view", "売掛元帳の開始時の日付入力"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    evidence = parser.parse_args().evidence.resolve()
    catalog = BASE.read_json(BASE.evidence_path(evidence, "scenarios/catalog.json"))
    fixtures = IPAD / ".generated/fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    for case in catalog["cases"]:
        case_id = case["id"]
        if case_id not in CASES:
            continue
        workflow, title = CASES[case_id]
        legacy = case["legacy_result"]
        run = BASE.evidence_path(evidence, legacy["evidence"][0])
        with BASE.evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
            date = json.loads(recording.readline())["timestamp"]
        BASE.save(fixtures / (case_id + ".json"), {
            "id": case_id, "title": title, "workflow": workflow,
            "dateSeconds": date, "seed": BASE.snapshot_seed(evidence, run),
            "changes": BASE.expected_changes(evidence, legacy["comparison_targets"]["keyed_record_diff"]),
            "reports": {}, "input": {},
        })
    print(f"処理日の実 UI 用データ {len(CASES)} 件")


if __name__ == "__main__":
    main()
