"""証跡台帳を変更せず、ケース一覧と実 UI テストの入力・期待値を生成する。"""
import argparse
import base64
import json
import subprocess
from pathlib import Path


WORKFLOWS = {
    "SYS-001": ("company", "会社・各台帳設定と業務用マスタ投入"),
    "SYS-002": ("system-company-data", "会社の登録内容を表示"),
    "SYS-003": ("system-company-cancel", "会社設定を保存せずに戻る"),
    "SYS-004": ("system-company-report", "有効な台帳の設定を確認して帳票を出力"),
    "SYS-005": ("system-company-page-lines", "印刷行数に28行を入力"),
    "SYS-006": ("system-company-page-lines", "印刷行数に29行を入力"),
    "SYS-007": ("system-company-period", "会計サイクルの周期に13を入力"),
    "SYS-008": ("system-company-period", "会計サイクルの周期に06を入力"),
    "SYS-009": ("system-company-period", "会計サイクルの周期に99を入力"),
    "SYS-010": ("system-company-report", "売掛元帳と在庫管理の連携を無効にする"),
    "SYS-200": ("system-main-menu", "会計管理のメニューを表示"),
    "SYS-202": ("system-unavailable-orders", "受注管理が利用できないことを確認"),
    "SYS-203": ("system-unavailable-payroll", "給与管理が利用できないことを確認"),
    "SYS-204": ("system-unavailable-retail", "店頭販売が利用できないことを確認"),
    "SYS-206": ("system-company-data", "会社・期間設定の表示を確認"),
    "GL-001": ("gl-business-date", "処理日入力を開く"),
    "GL-008": ("gl-cycle-close-menu", "期間締めの確認画面を表示"),
    "GL-020": ("gl-account-add", "新規の見出し勘定を登録"),
    "GL-021": ("gl-account-edit", "既存の見出し勘定の名称を変更"),
    "GL-022": ("gl-account-delete", "残高ゼロの明細勘定を削除"),
    "GL-023": ("gl-chart-inquiry", "指定した勘定科目を起点に照会"),
    "GL-033": ("gl-chart-print", "勘定科目一覧を出力"),
    "GL-034": ("gl-trial-balance-detail", "詳細試算表を出力"),
    "GL-036": ("gl-business-date-invalid", "存在しない処理日を拒否する"),
    "GL-037": ("gl-cycle-close-cancel", "期間締めを中止して総勘定元帳に戻る"),
    "GL-200": ("gl-business-date", "総勘定元帳を開いて処理日入力へ進む"),
    "GL-201": ("gl-business-date", "総勘定元帳メニューから処理日入力を開く"),
    "GL-204": ("gl-account-edit-menu", "勘定科目の変更・削除画面を表示"),
    "GL-205": ("gl-chart-inquiry-menu", "勘定科目一覧の照会画面を表示"),
    "GL-206": ("gl-chart-print", "勘定科目一覧の帳票を確認"),
    "GL-219": ("gl-batch-status-menu", "バッチ状況メニューを表示"),
    "GL-220": ("gl-batch-status-display", "バッチ状況を照会"),
    "GL-221": ("gl-batch-status-print", "バッチ状況帳票を出力"),
    "GL-222": ("gl-posting-menu", "仕訳転記のバッチ確認に到達"),
    "GL-223": ("gl-cycle-close-menu", "期間締めの事前確認を表示"),
    "GL-224": ("gl-trial-balance-menu", "試算表メニューを表示"),
    "GL-225": ("gl-trial-balance-detail", "詳細試算表の帳票を確認"),
    "GL-230": ("gl-close-ledger", "総勘定元帳を閉じて会計管理メニューに戻る"),
    "GL-231": ("system-company-data", "総勘定元帳から会社・期間設定を開く"),
    "GL-232": ("gl-business-date", "総勘定元帳開始時の処理日入力を確認"),
    "SL-104": ("sales-proof", "印刷済み請求書の未転記売上取引確認帳票"),
    "CALC-200": ("check-digit", "得意先コードのチェックディジット"),
}
KEY_LENGTHS = {
    "ledger.dat": 8, "purchled.dat": 7, "salesled.dat": 7, "stockctl.dat": 13, "invoice.dat": 10,
}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def evidence_path(evidence, path):
    resolved = (evidence / path).resolve()
    if not resolved.is_relative_to(evidence):
        raise ValueError(f"証跡ルート外のパスです: {path}")
    return resolved


def snapshot_seed(evidence, run):
    before = read_json(evidence_path(evidence, run / "before-records/records.json"))
    files = {}
    for path, file in before["files"].items():
        name = Path(path).name
        if name == "system.dat":
            raw = evidence_path(evidence, run / "before-files" / path).read_bytes()
            files[path] = {"type": "relative", "hex": raw.hex()}
        elif name in KEY_LENGTHS:
            length = KEY_LENGTHS[name] * 2
            files[path] = {"type": "indexed", "records": [
                [value["hex"][:length], value["hex"]] for value in file["records"].values()
            ]}
    return base64.b64encode(json.dumps({"files": files}, separators=(",", ":")).encode()).decode()


def expected_changes(evidence, path):
    changes = []
    if path:
        for change in read_json(evidence_path(evidence, path))["changes"]:
            name = Path(change["file"]).name
            before, after = (change[k]["hex"] if change[k] else None for k in ("before", "after"))
            key = change["key"]
            if name in KEY_LENGTHS:
                key = (after or before)[:KEY_LENGTHS[name] * 2]
            changes.append(dict(file=change["file"], key=key, before=before, after=after))
    return changes


def analysis_changes(evidence, run):
    path = "ledgers/acas/analysis.dat"
    source = evidence_path(evidence, run / "files" / path)
    output = subprocess.run(["db_dump", str(source)], check=True, capture_output=True, text=True).stdout
    lines = output.splitlines()
    items = [bytes.fromhex(line) for line in lines[lines.index("HEADER=END") + 1:lines.index("DATA=END")]]
    if len(items) % 2 or not items:
        raise ValueError("分析ファイルに有効な索引レコードがありません")
    changes = []
    for key, value in zip(items[::2], items[1::2]):
        if len(key) != 3 or len(value) != 66 or not value.startswith(key):
            raise ValueError("分析ファイルのレコード長または索引キーが一致しません")
        changes.append(dict(file=path, key=key.hex(), before=None, after=value.hex()))
    return changes


def fixture(evidence, case):
    legacy = case["legacy_result"]
    targets = legacy.get("comparison_targets", {})
    workflow, title = WORKFLOWS[case["id"]]
    run = evidence_path(evidence, legacy["evidence"][0])
    report_paths = {path: evidence_path(evidence, path) for path in targets.get("report_files", [])}
    reports = {
        str(Path(path).relative_to(Path(legacy["evidence"][0]) / "files")): source.read_bytes().hex()
        for path, source in report_paths.items()
        if "/files/ledgers/" in path
    }
    for path, source in report_paths.items():
        if "/files/spool/" in path and source.read_bytes().hex() not in reports.values():
            raise ValueError(f"帳票スプールと原本が一致しません: {path}")
    seeded = workflow == "sales-proof" or workflow.startswith(
        (
            "system-", "gl-account-", "gl-chart-", "gl-batch-status-", "gl-business-date",
            "gl-close-ledger", "gl-cycle-close-", "gl-posting-", "gl-trial-balance-",
        )
    )
    seed = snapshot_seed(evidence, run) if seeded else None
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        date = json.loads(recording.readline())["timestamp"]
    inputs = case["input_data"]
    text_inputs = inputs.get("text_inputs") or [""]
    values = {
        "company": text_inputs[0].split("\r")[0],
        "code": inputs.get("code"),
    }
    if workflow == "gl-account-add":
        major, minor, name, _, placement, _ = text_inputs[3].split("\r")[:-1]
        values.update(account=major + minor, name=name, placement=placement)
    changes = expected_changes(evidence, targets.get("keyed_record_diff"))
    if workflow == "company":
        changes += analysis_changes(evidence, run)
    return {
        "id": case["id"],
        "workflow": workflow,
        "title": title,
        "dateSeconds": date,
        "seed": seed,
        "changes": changes,
        "reports": reports,
        "calculation": legacy.get("actual") if workflow == "check-digit" else None,
        "input": values,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / ".generated")
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    ledger = read_json(evidence_path(evidence, "scenarios/catalog.json"))
    cases = ledger["cases"]
    ids = {case["id"] for case in cases}
    if len(cases) != 453 or len(ids) != len(cases) or not WORKFLOWS.keys() <= ids:
        parser.error("証跡台帳のケース件数または識別子が一致しません")
    generated = {case["id"]: fixture(evidence, case) for case in cases if case["id"] in WORKFLOWS}
    fixtures = args.output / "fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    save(args.output / "cases.json", cases)
    for case_id, data in generated.items():
        save(fixtures / (case_id + ".json"), data)
    print(f"ケース台帳 {len(cases)} 件、実 UI 用データ {len(WORKFLOWS)} 件")


if __name__ == "__main__":
    main()
