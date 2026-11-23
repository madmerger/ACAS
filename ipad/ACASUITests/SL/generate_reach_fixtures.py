"""得意先・売上取引・請求の到達確認に使うレガシー実測証跡を変換する。"""
import argparse
import json
from pathlib import Path

from generate_customer_fixtures import BASE, IPAD, customer_seed


CASES = {
    "SL-002": ("sales-customers-menu-view", "得意先マスター管理を開く"),
    "SL-004": ("sales-invoice-entry-view", "売上取引入力を開く"),
    "SL-005": ("sales-invoice-edit-list-view", "売上取引修正を開く"),
    "SL-202": ("sales-customers-menu-view", "得意先マスター管理の到達確認"),
    "SL-203": ("sales-customer-screen-register", "得意先登録の到達確認"),
    "SL-204": ("sales-customer-screen-edit", "得意先変更の到達確認"),
    "SL-205": ("sales-customer-screen-remove", "得意先削除の到達確認"),
    "SL-207": ("sales-customer-screen-view", "得意先表示の到達確認"),
    "SL-209": ("sales-invoice-entry-view", "売上取引入力の到達確認"),
    "SL-210": ("sales-invoice-edit-list-view", "売上取引修正の到達確認"),
    "SL-231": ("sales-invoice-menu-view", "請求書サブシステムの到達確認"),
    "SL-232": ("sales-invoice-entry-view", "一括印刷待ち請求書登録の到達確認"),
    "SL-233": ("sales-invoice-immediate-view", "請求書即時印刷の到達確認"),
    "SL-234": ("sales-invoice-edit-list-view", "請求書修正の到達確認"),
    "SL-235": ("sales-invoice-delete-list-view", "請求書削除の到達確認"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    evidence = parser.parse_args().evidence.resolve()
    catalog = BASE.read_json(BASE.evidence_path(evidence, "scenarios/catalog.json"))
    cases = {case["id"]: case for case in catalog["cases"]}
    fixtures = IPAD / ".generated/fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    for case_id, (workflow, title) in CASES.items():
        legacy = cases[case_id]["legacy_result"]
        run = BASE.evidence_path(evidence, legacy["evidence"][0])
        targets = legacy["comparison_targets"]
        if targets["report_files"]:
            raise ValueError(f"到達確認に帳票差分があります: {case_id}")
        with BASE.evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
            date = json.loads(recording.readline())["timestamp"]
        BASE.save(fixtures / f"{case_id}.json", {
            "id": case_id, "title": title, "workflow": workflow, "dateSeconds": date,
            "seed": customer_seed(evidence, run),
            "changes": BASE.expected_changes(evidence, targets["keyed_record_diff"]),
            "reports": {},
        })
    print(f"得意先・売上取引・請求の到達確認用データ {len(CASES)} 件")


if __name__ == "__main__":
    main()
