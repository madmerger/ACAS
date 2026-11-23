"""在庫監査帳票と入出庫のレガシー実測から実画面用の入力を生成する。"""
import argparse
import base64
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

IPAD = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(IPAD / "scripts"))
from generate_cases import evidence_path, expected_changes, read_json, save, snapshot_seed


REACH_CASES = {
    "ST-001": ("date.reopen", "在庫処理日の再表示"),
    "ST-002": ("master", "在庫品目マスター管理"),
    "ST-003": ("movements", "入出庫・発注記録"),
    "ST-004": ("reports", "在庫帳票メニュー"),
    "ST-005": ("closePeriod", "在庫期間締めの準備"),
    "ST-006": ("rebuild", "在庫ファイル圧縮の準備"),
    "ST-200": ("date.initial", "在庫開始時の処理日入力"),
    "ST-201": ("date.reopen", "在庫処理日の再表示"),
    "ST-202": ("master", "在庫品目マスター管理"),
    "ST-205": ("delete", "在庫品目削除"),
    "ST-206": ("renumber", "在庫コード変更"),
    "ST-207": ("lookup", "在庫品目照会"),
    "ST-209": ("movements", "入出庫・発注記録"),
    "ST-210": ("receive", "入庫入力"),
    "ST-211": ("issue", "出庫入力"),
    "ST-212": ("barcode", "バーコード入庫"),
    "ST-215": ("reports", "在庫帳票メニュー"),
    "ST-221": ("closePeriod", "在庫期間締めの準備"),
    "ST-224": ("rebuild", "在庫ファイル圧縮の準備"),
    "ST-226": ("date.initial", "在庫開始時の処理日入力"),
}

REPORTS = {
    "ST-216": ("valuation", "在庫評価帳票"),
    "ST-217": ("activity", "在庫活動帳票"),
    "ST-218": ("reorder", "発注点帳票"),
    "ST-219": ("history", "在庫履歴帳票"),
    "ST-220": ("listing", "在庫一覧帳票"),
}

OPERATIONS = {
    "ST-090": ("stock.create", "業務用在庫品目二件の登録"),
    "ST-203": ("stock.create", "在庫品目登録"),
    "ST-204": ("stock.edit.open", "在庫品目変更"),
    "ST-213": ("stock.order", "在庫発注記録"),
    "ST-222": ("stock.import", "在庫品目一括取込"),
    "ST-223": ("stock.close", "在庫管理を閉じる"),
    "ST-225": ("stock.settings.open", "共通設定を開く"),
}


def printed_time(report):
    printed = report.split(b"\n")[1][-16:].decode("ascii")
    return datetime.strptime(printed, "%d/%m/%Y %H:%M").replace(tzinfo=timezone.utc).timestamp()


def confirmed_report_fixture(evidence, run, case_id):
    route, title = REPORTS[case_id]
    path = "ledgers/acas/prt-1"
    result = read_json(evidence_path(evidence, run / "result.json"))
    report = evidence_path(evidence, run / "files" / path).read_bytes()
    spooled = [file for file in result["changed"] if file.startswith("spool/") and file.endswith("/prt-1")]
    changes = expected_changes(evidence, run / "record-diff.json")
    if result["error"] or not report or len(spooled) != 1 or changes:
        raise ValueError(f"{case_id}: 台帳差分のない帳票の原本とスプールが必要です")
    if report != evidence_path(evidence, run / "files" / spooled[0]).read_bytes():
        raise ValueError(f"{case_id}: 帳票原本がスプールと異なります")
    return {
        "id": case_id, "title": title, "workflow": "stock.report." + route, "dateSeconds": printed_time(report),
        "seed": snapshot_seed(evidence, run), "changes": changes, "reports": {path: report.hex()},
    }


def operation_fixture(evidence, run, case_id):
    workflow, title = OPERATIONS[case_id]
    result = read_json(evidence_path(evidence, run / "result.json"))
    if result["error"]:
        raise ValueError(f"{case_id}: レガシー実行に失敗しました")
    changes = expected_changes(evidence, run / "record-diff.json")
    record_files = None
    reports = {}
    seed = snapshot_seed(evidence, run)
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    if case_id == "ST-090":
        record_files = ["ledgers/acas/stockctl.dat"]
        changes = [change for change in changes if change["file"] in record_files]
        if len(changes) != 2 or any(change["before"] is not None for change in changes):
            raise ValueError("在庫品目二件の登録証跡が必要です")
    if case_id == "ST-204":
        path = "ledgers/acas/analysis.dat"
        source = evidence_path(evidence, run / "before-files" / path)
        dump = subprocess.run(["db_dump", str(source)], check=True, capture_output=True, text=True).stdout.splitlines()
        rows = [line.strip() for line in dump[dump.index("HEADER=END") + 1:dump.index("DATA=END")]]
        if changes or not rows or len(rows) % 2 or not any(len(bytes.fromhex(row)) != 36 for row in rows[1::2]):
            raise ValueError("在庫を更新せず中断した分析ファイルの証跡が必要です")
        snapshot = json.loads(base64.b64decode(seed))
        snapshot["files"][path] = {"type": "indexed", "records": list(zip(rows[::2], rows[1::2]))}
        seed = base64.b64encode(json.dumps(snapshot, separators=(",", ":")).encode()).decode()
    if case_id == "ST-213":
        path = "ledgers/acas/prt-1"
        report = evidence_path(evidence, run / "files" / path).read_bytes()
        spool, = [file for file in result["changed"] if file.startswith("spool/") and file.endswith("/prt-1")]
        if report != evidence_path(evidence, run / "files" / spool).read_bytes():
            raise ValueError(f"{case_id}: 帳票原本がスプールと異なります")
        timestamp = printed_time(report)
        reports[path] = report.hex()
        audit = "ledgers/acas/staudit.dat"
        reports[audit] = evidence_path(evidence, run / "files" / audit).read_bytes().hex()
    return {
        "id": case_id, "title": title, "workflow": workflow, "dateSeconds": timestamp,
        "seed": seed, "changes": changes, "recordFiles": record_files, "reports": reports,
    }


def reach_fixture(evidence, case):
    destination, title = REACH_CASES[case["id"]]
    legacy = case["legacy_result"]
    run = evidence_path(evidence, legacy["evidence"][0])
    targets = legacy["comparison_targets"]
    changes = expected_changes(evidence, targets["keyed_record_diff"])
    if legacy["verdict"] != "合格" or changes or not targets["screen_text"]:
        raise ValueError(f'{case["id"]}: 台帳を更新しない画面到達のレガシー実測ではありません')
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    reports = {}
    if destination in {"receive", "issue", "barcode"}:
        report = "ledgers/acas/prt-1"
        if targets["report_files"] != [str(Path(legacy["evidence"][0]) / "files" / report)]:
            raise ValueError(f'{case["id"]}: 入出庫の帳票実測が必要です')
        original = evidence_path(evidence, run / "before-files" / report).read_bytes()
        seed["files"][report] = {"type": "raw", "hex": original.hex()}
        reports[report] = evidence_path(evidence, targets["report_files"][0]).read_bytes().hex()
        audit = "ledgers/acas/staudit.dat"
        if (run / "before-files" / audit).is_file():
            original = evidence_path(evidence, run / "before-files" / audit).read_bytes()
            seed["files"][audit] = {"type": "raw", "hex": original.hex()}
        reports[audit] = evidence_path(evidence, run / "files" / audit).read_bytes().hex()
    elif targets["report_files"]:
        raise ValueError(f'{case["id"]}: 画面到達で予期しない帳票が生成されました')
    return {
        "id": case["id"], "title": title + "への到達確認",
        "workflow": f"stock.{destination}.open", "dateSeconds": timestamp,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": changes, "reports": reports,
    }


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


def master_report_fixture(evidence, case):
    legacy = case["legacy_result"]
    run = evidence_path(evidence, legacy["evidence"][0])
    targets = legacy["comparison_targets"]
    report = "ledgers/acas/prt-1"
    original = evidence_path(evidence, run / "files" / report).read_bytes()
    spool = [evidence_path(evidence, path).read_bytes() for path in targets["report_files"] if "/files/spool/" in path]
    if legacy["verdict"] != "合格" or spool != [original]:
        raise ValueError(f'{case["id"]}: 帳票原本とスプールの実測が一致しません')
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    return {
        "id": case["id"], "title": "在庫品目帳票", "workflow": "stock.masterReport",
        "dateSeconds": timestamp, "seed": snapshot_seed(evidence, run),
        "changes": expected_changes(evidence, targets["keyed_record_diff"]), "reports": {report: original.hex()},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirmed-root", type=Path)
    parser.add_argument("--operations-root", type=Path)
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
    save(args.output / "ST-208.json", master_report_fixture(evidence, cases["ST-208"]))
    for case_id in REACH_CASES:
        save(args.output / (case_id + ".json"), reach_fixture(evidence, cases[case_id]))
    if args.confirmed_root:
        root = args.confirmed_root.resolve()
        for case_id in REPORTS:
            run = Path(case_id) / "confirmed"
            save(args.output / (case_id + ".json"), confirmed_report_fixture(root, run, case_id))
    if args.operations_root:
        for case_id in OPERATIONS:
            if case_id in ("ST-203", "ST-213"):
                root, run = args.operations_root.resolve(), Path(case_id) / "confirmed"
            elif case_id == "ST-090":
                root, run = evidence, Path("runs/SYS-001-all-recorded")
            else:
                root, run = evidence, Path(f"runs/{case_id}-breadth")
            save(args.output / (case_id + ".json"), operation_fixture(root, run, case_id))
    count = 6 + len(REACH_CASES) + (len(REPORTS) if args.confirmed_root else 0)
    print(f"在庫の実画面用データ {count + (len(OPERATIONS) if args.operations_root else 0)} 件")


if __name__ == "__main__":
    main()
