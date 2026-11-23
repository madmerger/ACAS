"""売掛元帳の画面到達確認に使うレガシー実測証跡を変換する。"""
import argparse
import base64
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess

from generate_customer_fixtures import BASE, IPAD, customer_seed


CASES = {
    "SL-002": ("sales-customers-menu-view", "得意先マスター管理を開く"),
    "SL-003": ("sales-enquiry-unavailable", "売掛残高・明細照会"),
    "SL-004": ("sales-invoice-entry-view", "売上取引入力を開く"),
    "SL-005": ("sales-invoice-edit-list-view", "売上取引修正を開く"),
    "SL-006": ("sales-proof", "売上の確認帳票・取引なし"),
    "SL-007": ("sales-posting-work-file-unavailable", "売上転記・作業ファイルなし"),
    "SL-008": ("sales-payment-unavailable", "入金登録・売掛明細なし"),
    "SL-009": ("sales-payment-unavailable", "入金修正・対象なし"),
    "SL-010": ("sales-payment-unavailable", "入金検証帳票・対象なし"),
    "SL-011": ("sales-payment-unavailable", "入金転記・検証帳票が未作成"),
    "SL-012": ("sales-analysis-menu-view", "売上分析コード管理を開く"),
    "SL-013": ("sales-analysis-totals-unavailable", "売上分析帳票・集計ファイルなし"),
    "SL-014": ("sales-day-book-unavailable", "売上日計簿・必要ファイルなし"),
    "SL-015": ("sales-statement", "得意先明細書・売掛明細なし"),
    "SL-016": ("sales-dunning", "督促状出力・売掛明細なし"),
    "SL-017": ("sales-ageing-unavailable", "売掛金年齢表"),
    "SL-020": ("sales-invoice-fixed-data-view", "請求書の初回固定項目設定"),
    "SL-021": ("sales-period-view", "期間締めの確認画面"),
    "SL-022": ("sales-customer-report-view", "得意先ファイル帳票の抽出条件"),
    "SL-091": ("sales-analysis-registration-refused", "分析ファイルのレコード長不一致で登録を中断"),
    "SL-202": ("sales-customers-menu-view", "得意先マスター管理の到達確認"),
    "SL-203": ("sales-customer-screen-register", "得意先登録の到達確認"),
    "SL-204": ("sales-customer-screen-edit", "得意先変更の到達確認"),
    "SL-205": ("sales-customer-screen-remove", "得意先削除の到達確認"),
    "SL-207": ("sales-customer-screen-view", "得意先表示の到達確認"),
    "SL-208": ("sales-enquiry-unavailable", "売掛残高・明細照会の到達確認"),
    "SL-209": ("sales-invoice-entry-view", "売上取引入力の到達確認"),
    "SL-210": ("sales-invoice-edit-list-view", "売上取引修正の到達確認"),
    "SL-211": ("sales-proof", "売上の確認帳票・取引なし"),
    "SL-212": ("sales-posting-work-file-unavailable", "売上転記・作業ファイルなし"),
    "SL-213": ("sales-payment-unavailable", "入金登録・売掛明細なし"),
    "SL-214": ("sales-payment-unavailable", "入金修正・対象なし"),
    "SL-215": ("sales-payment-unavailable", "入金検証帳票・対象なし"),
    "SL-216": ("sales-payment-unavailable", "入金転記・検証帳票が未作成"),
    "SL-217": ("sales-analysis-menu-view", "売上分析コード管理の到達確認"),
    "SL-218": ("sales-analysis-add-view", "売上分析コード登録の到達確認"),
    "SL-219": ("sales-analysis-code-list-view", "売上分析コード変更・削除の一覧"),
    "SL-222": ("sales-analysis-code-list-view", "売上分析コード表示の一覧"),
    "SL-223": ("sales-analysis-totals-unavailable", "売上分析帳票・集計ファイルなし"),
    "SL-224": ("sales-day-book-unavailable", "売上日計簿・必要ファイルなし"),
    "SL-225": ("sales-statement", "得意先明細書・売掛明細なし"),
    "SL-226": ("sales-dunning", "督促状出力・売掛明細なし"),
    "SL-227": ("sales-ageing-unavailable", "売掛金年齢表の到達確認"),
    "SL-230": ("sales-invoice-fixed-data-view", "請求書サブシステムの初回固定項目設定"),
    "SL-231": ("sales-invoice-fixed-data-view", "請求書固定項目設定・次の請求書番号"),
    "SL-232": ("sales-invoice-entry-view", "一括印刷待ち請求書登録の到達確認"),
    "SL-233": ("sales-invoice-immediate-view", "請求書即時印刷の到達確認"),
    "SL-234": ("sales-invoice-edit-list-view", "請求書修正の到達確認"),
    "SL-235": ("sales-invoice-delete-list-view", "請求書削除の到達確認"),
    "SL-236": ("sales-invoice-deletion-report", "請求書削除帳票・削除済み請求書なし"),
    "SL-237": ("sales-invoice-print-view", "請求書一括印刷・印刷種別の選択"),
    "SL-238": ("sales-invoice-delivery-print-view", "納品書・ピッキングリスト印刷の到達確認"),
    "SL-239": ("sales-period-view", "期間締めの確認画面"),
    "SL-240": ("sales-customer-report-view", "得意先ファイル帳票の抽出条件"),
    "SL-241": ("sales-exit", "売掛元帳からメインメニューへ戻る"),
    "SL-242": ("sales-common-settings-view", "共通設定を開く"),
    "SL-244": ("sales-invoice-fixed-data-view", "請求書固定項目設定・初回表示"),
}


def report_evidence(evidence, run, expected_files):
    before = BASE.read_json(BASE.evidence_path(evidence, run / "before.json"))
    after = BASE.read_json(BASE.evidence_path(evidence, run / "result.json"))["after"]
    seed_reports = {}
    expected_reports = {}
    changed = {}
    for name in expected_files:
        file = BASE.evidence_path(evidence, name)
        path = file.relative_to(run / "files")
        data = file.read_bytes()
        if hashlib.sha256(data).hexdigest() != after[str(path)]["sha256"]:
            raise ValueError(f"帳票の実測バイトが一致しません: {run.name}: {path}")
        if path.parent == PurePosixPath("ledgers/acas"):
            changed[str(path)] = data.hex()
    for name in expected_files:
        file = BASE.evidence_path(evidence, name)
        path = file.relative_to(run / "files")
        if path.parent != PurePosixPath("ledgers/acas"):
            if path.parts[0] != "spool" or changed.get(f"ledgers/acas/{path.name}") != file.read_bytes().hex():
                raise ValueError(f"照合できない帳票の証跡です: {run.name}: {path}")
    for name, metadata in before.items():
        path = PurePosixPath(name)
        if path.parent != PurePosixPath("ledgers/acas") or not path.name.startswith("prt-"):
            continue
        if name not in changed and after.get(name) != metadata:
            raise ValueError(f"到達確認の帳票が変化しました: {run.name}: {name}")
        source = BASE.evidence_path(evidence, run / "before-files" / name)
        if not source.is_file():
            continue
        data = source.read_bytes()
        if hashlib.sha256(data).hexdigest() != metadata["sha256"]:
            raise ValueError(f"帳票の証跡バイトが一致しません: {run.name}: {name}")
        seed_reports[name] = data.hex()
        if name not in changed:
            expected_reports[name] = data.hex()
    return seed_reports, expected_reports | changed


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


def save_business_customers(evidence, case, fixtures):
    run = BASE.evidence_path(evidence, case["legacy_result"]["evidence"][0])
    path = "ledgers/acas/salesled.dat"
    system_path = "ledgers/acas/system.dat"
    records = BASE.read_json(BASE.evidence_path(evidence, run / "after-records/records.json"))["files"][path]["records"]
    customers = {code: record["fields"]["name"] for code, record in records.items()}
    if sorted(customers.values()) != sorted(case["expected_result"]["names"]):
        raise ValueError("SL-090 の得意先名または件数が証跡と一致しません")
    system = BASE.evidence_path(evidence, run / "files" / system_path).read_bytes()
    seed = {"files": {
        system_path: {"type": "relative", "hex": system.hex()},
        path: {"type": "indexed", "records": [[record["hex"][:14], record["hex"]] for record in records.values()]},
    }}
    with BASE.evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        date = json.loads(recording.readline())["timestamp"]
    BASE.save(fixtures / "SL-090.json", {
        "id": "SL-090", "title": "業務用得意先マスター2件の投入",
        "workflow": "ui-test-only", "dateSeconds": date, "customers": customers,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": [], "reports": {},
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
        with BASE.evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
            date = json.loads(recording.readline())["timestamp"]
        seed_reports, reports = report_evidence(evidence, run, targets["report_files"])
        seed = json.loads(base64.b64decode(customer_seed(evidence, run)))
        if case_id == "SL-091":
            path = "ledgers/acas/analysis.dat"
            source = BASE.evidence_path(evidence, run / "before-files" / path)
            before = BASE.read_json(BASE.evidence_path(evidence, run / "before.json"))[path]
            after = BASE.read_json(BASE.evidence_path(evidence, run / "result.json"))["after"][path]
            if hashlib.sha256(source.read_bytes()).hexdigest() != before["sha256"]:
                raise ValueError(f"分析ファイルの証跡バイトが一致しません: {run.name}: {path}")
            dump = subprocess.run(["db_dump", str(source)], check=True, capture_output=True, text=True).stdout
            rows = dump.split("HEADER=END\n", 1)[1].splitlines()
            if not rows or rows.pop() != "DATA=END" or len(rows) % 2:
                raise ValueError("SL-091: 分析ファイルのレコードを読み取れません")
            records = [[key.strip(), value.strip()] for key, value in zip(rows[::2], rows[1::2])]
            if not records or any(len(bytes.fromhex(value)) != 66 for _, value in records) or before != after:
                raise ValueError("SL-091: 66バイトの分析レコードと更新なしの証跡が必要です")
            seed["files"][path] = {"type": "indexed", "records": records}
        seed["files"].update({name: {"type": "raw", "hex": data} for name, data in seed_reports.items()})
        BASE.save(fixtures / f"{case_id}.json", {
            "id": case_id, "title": title, "workflow": workflow, "dateSeconds": date,
            "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
            "changes": BASE.expected_changes(evidence, targets["keyed_record_diff"]),
            "reports": reports,
        })
    print(f"売掛元帳の画面到達確認用データ {len(CASES)} 件")
    save_business_customers(evidence, cases["SL-090"], fixtures)
    save_analysis_reports(evidence, cases, fixtures)
    print("売上分析コードの帳票比較用データ 3 件")


if __name__ == "__main__":
    main()
