"""請求書の登録・印刷に使う実測証跡を実 UI 用の形式に変換する。"""
import argparse
import json

from generate_customer_fixtures import BASE, IPAD, customer_seed
from pathlib import Path


WORKFLOWS = {
    "SL-100": ("sales-invoice-save", "掛売請求書の登録"),
    "SL-101": ("sales-invoice-save", "貸方票の登録"),
    "SL-103": ("sales-invoice-print", "請求書の一括印刷"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    evidence = parser.parse_args().evidence.resolve()
    cases = BASE.read_json(BASE.evidence_path(evidence, "scenarios/catalog.json"))["cases"]
    fixtures = IPAD / ".generated/fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    for case in cases:
        case_id = case["id"]
        if case_id not in WORKFLOWS:
            continue
        workflow, title = WORKFLOWS[case_id]
        legacy = case["legacy_result"]
        run = BASE.evidence_path(evidence, legacy["evidence"][0])
        targets = legacy["comparison_targets"]
        with BASE.evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
            date = json.loads(recording.readline())["timestamp"]
        reports = {}
        for path in targets["report_files"]:
            if "/files/ledgers/" in path:
                file = BASE.evidence_path(evidence, path)
                reports[str(file.relative_to(run / "files"))] = file.read_bytes().hex()
        values = case["input_data"]["record_values"]
        inputs = {
            "customer": values[0]["customer"],
            "reference": case["input_data"]["text_inputs"][3].split("\r")[2],
            "order": case["input_data"]["text_inputs"][3].split("\r")[3],
            "product": values[1]["product"],
            "analysis": values[1]["analysis"],
            "description": case["input_data"]["text_inputs"][6 if case_id == "SL-100" else 7].strip(),
            "unit": values[1]["net"],
        } if workflow == "sales-invoice-save" else {}
        BASE.save(fixtures / f"{case_id}.json", {
            "id": case_id, "title": title, "workflow": workflow, "dateSeconds": date,
            "seed": customer_seed(evidence, run),
            "changes": BASE.expected_changes(evidence, targets["keyed_record_diff"]),
            "reports": reports, "input": inputs,
        })
    print(f"請求書の実 UI 用データ {len(WORKFLOWS)} 件")


if __name__ == "__main__":
    main()
