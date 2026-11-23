"""売掛元帳の画面到達確認に使うレガシー実測証跡を変換する。"""
import argparse
import base64
import hashlib
import json
from pathlib import Path, PurePosixPath

from generate_customer_fixtures import BASE, IPAD, customer_seed


CASES = {
    "SL-002": ("sales-customers-menu-view", "得意先マスター管理を開く"),
    "SL-004": ("sales-invoice-entry-view", "売上取引入力を開く"),
    "SL-005": ("sales-invoice-edit-list-view", "売上取引修正を開く"),
    "SL-006": ("sales-proof", "売上の確認帳票・取引なし"),
    "SL-012": ("sales-analysis-menu-view", "売上分析コード管理を開く"),
    "SL-015": ("sales-statement", "得意先明細書・売掛明細なし"),
    "SL-016": ("sales-dunning", "督促状出力・売掛明細なし"),
    "SL-021": ("sales-period-view", "期間締めの確認画面"),
    "SL-022": ("sales-customer-report-view", "得意先ファイル帳票の抽出条件"),
    "SL-202": ("sales-customers-menu-view", "得意先マスター管理の到達確認"),
    "SL-203": ("sales-customer-screen-register", "得意先登録の到達確認"),
    "SL-204": ("sales-customer-screen-edit", "得意先変更の到達確認"),
    "SL-205": ("sales-customer-screen-remove", "得意先削除の到達確認"),
    "SL-207": ("sales-customer-screen-view", "得意先表示の到達確認"),
    "SL-209": ("sales-invoice-entry-view", "売上取引入力の到達確認"),
    "SL-210": ("sales-invoice-edit-list-view", "売上取引修正の到達確認"),
    "SL-211": ("sales-proof", "売上の確認帳票・取引なし"),
    "SL-217": ("sales-analysis-menu-view", "売上分析コード管理の到達確認"),
    "SL-218": ("sales-analysis-add-view", "売上分析コード登録の到達確認"),
    "SL-225": ("sales-statement", "得意先明細書・売掛明細なし"),
    "SL-226": ("sales-dunning", "督促状出力・売掛明細なし"),
    "SL-231": ("sales-invoice-menu-view", "請求書サブシステムの到達確認"),
    "SL-232": ("sales-invoice-entry-view", "一括印刷待ち請求書登録の到達確認"),
    "SL-233": ("sales-invoice-immediate-view", "請求書即時印刷の到達確認"),
    "SL-234": ("sales-invoice-edit-list-view", "請求書修正の到達確認"),
    "SL-235": ("sales-invoice-delete-list-view", "請求書削除の到達確認"),
    "SL-239": ("sales-period-view", "期間締めの確認画面"),
    "SL-240": ("sales-customer-report-view", "得意先ファイル帳票の抽出条件"),
}


def unchanged_reports(evidence, run):
    before = BASE.read_json(BASE.evidence_path(evidence, run / "before.json"))
    after = BASE.read_json(BASE.evidence_path(evidence, run / "result.json"))["after"]
    reports = {}
    for name, metadata in before.items():
        path = PurePosixPath(name)
        if path.parent != PurePosixPath("ledgers/acas") or not path.name.startswith("prt-"):
            continue
        if after.get(name) != metadata:
            raise ValueError(f"到達確認の帳票が変化しました: {run.name}: {name}")
        source = BASE.evidence_path(evidence, run / "before-files" / name)
        if not source.is_file():
            continue
        data = source.read_bytes()
        if hashlib.sha256(data).hexdigest() != metadata["sha256"]:
            raise ValueError(f"帳票の証跡バイトが一致しません: {run.name}: {name}")
        reports[name] = data.hex()
    return reports


def save_analysis_reports(evidence, cases, fixtures):
    header_size = 3 * 132 + 4
    for case_id, title in [("SL-220", "売上分析コード印刷"),
                           ("SL-221", "売上分析コード全件印刷・旧版の異常反復")]:
        legacy = cases[case_id]["legacy_result"]
        run = BASE.evidence_path(evidence, legacy["evidence"][0])
        targets = legacy["comparison_targets"]
        with BASE.evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
            date = json.loads(recording.readline())["timestamp"]
        path = "ledgers/acas/prt-1"
        source = BASE.evidence_path(evidence, run / "files" / path)
        if source not in [BASE.evidence_path(evidence, name) for name in targets["report_files"]]:
            raise ValueError(f"帳票が比較対象にありません: {case_id}")
        size = source.stat().st_size
        if case_id == "SL-220" and size != header_size or case_id == "SL-221" and size <= header_size:
            raise ValueError(f"分析コード帳票の証跡の長さが想定外です: {case_id}: {size}")
        with source.open("rb") as report:
            # 旧版異常時は見出し直後の1バイトも含め、全体が不一致であることを確かめる。
            original = report.read(header_size + 1)
        fixture = {
            "id": case_id, "title": title, "workflow": "sales-analysis-report", "dateSeconds": date,
            "seed": customer_seed(evidence, run),
            "changes": BASE.expected_changes(evidence, targets["keyed_record_diff"]),
        }
        BASE.save(fixtures / f"{case_id}.json", fixture | {"reports": {path: original.hex()}})
        if case_id == "SL-221":
            prefix_id = f"{case_id}-prefix"
            BASE.save(fixtures / f"{prefix_id}.json", fixture | {
                "id": prefix_id, "title": "売上分析コード全件印刷・原本先頭400バイトの照合",
                "reports": {path: original[:header_size].hex()},
            })


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
        reports = unchanged_reports(evidence, run)
        seed = json.loads(base64.b64decode(customer_seed(evidence, run)))
        seed["files"].update({name: {"type": "raw", "hex": data} for name, data in reports.items()})
        BASE.save(fixtures / f"{case_id}.json", {
            "id": case_id, "title": title, "workflow": workflow, "dateSeconds": date,
            "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
            "changes": BASE.expected_changes(evidence, targets["keyed_record_diff"]),
            "reports": reports,
        })
    print(f"売掛元帳の画面到達確認用データ {len(CASES)} 件")
    save_analysis_reports(evidence, cases, fixtures)
    print("売上分析コードの帳票比較用データ 3 件")


if __name__ == "__main__":
    main()
