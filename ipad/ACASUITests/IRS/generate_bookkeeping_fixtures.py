"""簡易記帳の転記をレガシー実測と照合する実画面用の入力を生成する。"""
import argparse
import base64
import json
import sys
from pathlib import Path

IPAD = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(IPAD / "scripts"))
from generate_cases import evidence_path, expected_changes, read_json, save, snapshot_seed


REACH_CASES = {
    "IRS-002": ("accounts", "勘定科目管理"),
    "IRS-003": ("defaults", "既定勘定管理"),
    "IRS-010": ("recalculate", "元帳再計算の認証"),
    "IRS-200": ("menu", "簡易記帳メニュー"),
    "IRS-202": ("accounts", "勘定科目管理"),
    "IRS-205": ("accountList", "科目表表示"),
    "IRS-209": ("defaults", "既定勘定管理"),
    "IRS-211": ("defaultEdit", "既定勘定変更"),
    "IRS-212": ("defaultList", "既定勘定表示"),
    "IRS-221": ("recalculate", "元帳再計算の認証"),
}

REPORT_CASES = {
    "IRS-206": ("accountPrint", "科目表印刷"),
    "IRS-213": ("defaultPrint", "既定勘定印刷"),
}


def exit_fixture(evidence, case):
    legacy = case["legacy_result"]
    run = evidence_path(evidence, Path(legacy["evidence"][0]))
    result = read_json(evidence_path(evidence, run / "result.json"))
    changes = expected_changes(evidence, legacy["comparison_targets"]["keyed_record_diff"])
    if legacy["verdict"] != "合格" or changes or result["exitstatus"] != 0 or result["changed"] or result["deleted"]:
        raise ValueError("IRS-222: 台帳を更新せず終了したレガシー実測が必要です")
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    return {
        "id": case["id"], "title": "簡易記帳を閉じる", "workflow": "irs.close",
        "dateSeconds": timestamp, "seed": snapshot_seed(evidence, run),
        "changes": changes, "reports": {},
    }


def seeded_accounts(evidence, run):
    records = read_json(evidence_path(evidence, run / "before-records/records.json"))
    return {
        "type": "indexed",
        "records": [[key.encode().hex(), record["hex"]]
                    for key, record in records["files"]["ledgers/irs/acnts.dat"]["records"].items()],
    }


def report_fixture(evidence, case):
    destination, title = REPORT_CASES[case["id"]]
    legacy = case["legacy_result"]
    run = evidence_path(evidence, legacy["evidence"][0])
    targets = legacy["comparison_targets"]
    report = "ledgers/irs/prt-1"
    original = evidence_path(evidence, run / "files" / report).read_bytes()
    spool = [evidence_path(evidence, path).read_bytes() for path in targets["report_files"] if "/files/spool/" in path]
    if legacy["verdict"] != "合格" or spool != [original]:
        raise ValueError(f'{case["id"]}: 帳票原本とスプールの実測が一致しません')
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    seed["files"]["ledgers/irs/acnts.dat"] = seeded_accounts(evidence, run)
    for name in ("system.dat", "dflt.dat"):
        path = "ledgers/irs/" + name
        contents = evidence_path(evidence, run / "before-files" / path).read_bytes()
        seed["files"][path] = {"type": "raw", "hex": contents.hex()}
    return {
        "id": case["id"], "title": title, "workflow": f"irs.{destination}", "dateSeconds": timestamp,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": expected_changes(evidence, targets["keyed_record_diff"]),
        "reports": {report: original.hex()},
    }


def reach_fixture(evidence, case):
    destination, title = REACH_CASES[case["id"]]
    legacy = case["legacy_result"]
    run = evidence_path(evidence, legacy["evidence"][0])
    targets = legacy["comparison_targets"]
    changes = expected_changes(evidence, targets["keyed_record_diff"])
    if legacy["verdict"] != "合格" or changes or targets["report_files"] or not targets["screen_text"]:
        raise ValueError(f'{case["id"]}: 画面到達のみのレガシー実測ではありません')
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    reports = {}
    if destination == "accountList":
        seed["files"]["ledgers/irs/acnts.dat"] = seeded_accounts(evidence, run)
    if destination in {"defaultEdit", "defaultList"}:
        defaults = "ledgers/irs/dflt.dat"
        data = evidence_path(evidence, run / "before-files" / defaults).read_bytes()
        seed["files"][defaults] = {"type": "raw", "hex": data.hex()}
        reports[defaults] = data.hex()
    return {
        "id": case["id"], "title": title + "への到達確認",
        "workflow": f"irs.{destination}.open", "dateSeconds": timestamp,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": changes, "reports": reports,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path, default=IPAD / ".generated" / "fixtures")
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    cases = {c["id"]: c for c in read_json(evidence_path(evidence, Path("scenarios/catalog.json")))["cases"]}
    case = cases["IRS-400"]
    run = evidence_path(evidence, Path(case["legacy_result"]["evidence"][0]))
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        date = json.loads(recording.readline())["timestamp"]
    inputs = [value.strip() for value in case["input_data"]["text_inputs"]]
    prefix = "ledgers/irs/"
    accounts = prefix + "acnts.dat"
    defaults = prefix + "dflt.dat"
    journal = prefix + "post.dat"
    system = prefix + "system.dat"
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    seed["files"][accounts] = seeded_accounts(evidence, run)
    seed["files"][defaults] = {"type": "raw", "hex": evidence_path(evidence, run / "before-files" / defaults).read_bytes().hex()}
    changes = [
        {"file": accounts, "key": entry["key"].encode().hex(), "before": entry["before"]["hex"], "after": entry["after"]["hex"]}
        for entry in read_json(evidence_path(evidence, run / "record-diff.json"))["changes"] if entry["file"] == accounts
    ]
    indexed_journal = evidence_path(evidence, run / "files" / journal).read_bytes()
    legend = inputs[8].encode("shift_jis").ljust(32)
    if indexed_journal.count(legend) != 1:
        parser.error("実測の転記明細を一意に特定できません")
    offset = indexed_journal.index(legend) - 34
    posting = indexed_journal[offset:offset + 79]
    if offset < 0 or len(posting) != 79 or not posting[:5].isdigit():
        parser.error("実測の転記明細が不正です")
    changes.append({"file": journal, "key": posting[:5].hex(), "before": None, "after": posting.hex()})
    args.output.mkdir(parents=True, exist_ok=True)
    save(args.output / "IRS-400.json", {
        "id": case["id"], "title": "既定の銀行勘定から売上勘定へ仕訳を転記する",
        "workflow": "irs.post", "dateSeconds": date,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": changes,
        "reports": {system: evidence_path(evidence, run / "files" / system).read_bytes().hex()},
        "input": {"account": inputs[7], "description": inputs[8], "amount": inputs[9],
                  "defaultSide": "貸方" if inputs[5] == "DR" else "借方"},
    })
    for case_id in REACH_CASES:
        save(args.output / (case_id + ".json"), reach_fixture(evidence, cases[case_id]))
    for case_id in REPORT_CASES:
        save(args.output / (case_id + ".json"), report_fixture(evidence, cases[case_id]))
    save(args.output / "IRS-222.json", exit_fixture(evidence, cases["IRS-222"]))
    print(f"簡易記帳の実画面用データ {2 + len(REACH_CASES) + len(REPORT_CASES)} 件")


if __name__ == "__main__":
    main()
