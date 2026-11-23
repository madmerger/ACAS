"""売掛元帳の得意先操作に対応する基盤ハーネス用データを生成する。"""
import argparse
import importlib.util
import json
from pathlib import Path

IPAD = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("generate_cases", IPAD / "scripts/generate_cases.py")
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)

CASES = {
    "SL-400": ("edit", "得意先名称の変更"),
    "SL-401": ("remove", "残高がない得意先の削除"),
    "SL-402": ("view", "存在しない得意先の照会"),
    "SL-403": ("register", "新規得意先の登録"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    cases = {c["id"]: c for c in BASE.read_json(args.evidence / "scenarios/catalog.json")["cases"]}
    fixtures = IPAD / ".generated/fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    for case_id, (operation, title) in CASES.items():
        case = cases[case_id]
        legacy = case["legacy_result"]
        run = args.evidence / legacy["evidence"][0]
        with (run / "terminal.cast").open(encoding="utf-8") as recording:
            date = json.loads(recording.readline())["timestamp"]
        inputs = case["input_data"]["text_inputs"]
        values = {"code": inputs[4].strip()}
        if operation == "edit":
            values["name"] = inputs[5].strip()
        if operation == "register":
            values["name"], values["address"] = inputs[5].strip().split("\t", maxsplit=1)
        BASE.save(fixtures / (case_id + ".json"), {
            "id": case_id, "title": title, "workflow": "sales-customer-" + operation,
            "dateSeconds": date, "seed": BASE.snapshot_seed(run),
            "changes": BASE.expected_changes(args.evidence, legacy["comparison_targets"]["keyed_record_diff"]),
            "reports": {}, "input": values,
        })
    print(f"得意先の実 UI 用データ {len(CASES)} 件")


if __name__ == "__main__":
    main()
