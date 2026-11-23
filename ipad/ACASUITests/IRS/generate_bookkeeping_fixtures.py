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
    "IRS-001": ("settings", "簡易記帳設定の認証画面"),
    "IRS-002": ("accounts", "勘定科目管理"),
    "IRS-003": ("defaults", "既定勘定管理"),
    "IRS-004": ("post", "転記の実行方法"),
    "IRS-005": ("trialBalance", "試算表"),
    "IRS-006": ("audit", "転記帳票の出力条件"),
    "IRS-010": ("recalculate", "元帳再計算の認証"),
    "IRS-200": ("menu", "簡易記帳メニュー"),
    "IRS-201": ("settings", "簡易記帳設定の認証画面"),
    "IRS-202": ("accounts", "勘定科目管理"),
    "IRS-205": ("accountList", "科目表表示"),
    "IRS-209": ("defaults", "既定勘定管理"),
    "IRS-211": ("defaultEdit", "既定勘定変更"),
    "IRS-212": ("defaultList", "既定勘定表示"),
    "IRS-215": ("post", "転記の実行方法"),
    "IRS-217": ("audit", "転記帳票の出力条件"),
    "IRS-221": ("recalculate", "元帳再計算の認証"),
    "IRS-223": ("settings", "簡易記帳設定の認証画面"),
}

REPORT_CASES = {
    "IRS-206": ("accountPrint", "科目表印刷"),
    "IRS-213": ("defaultPrint", "既定勘定印刷"),
}

MISSING_POSTING_CASES = {
    "IRS-008": ("amendment", "転記修正", "error code = 35"),
    "IRS-009": ("analysis", "分析帳票", "Error opening postings = 35"),
    "IRS-219": ("amendment", "転記修正", "error code = 35"),
    "IRS-220": ("analysis", "分析帳票", "Error opening postings = 35"),
}


def missing_posting_fixture(evidence, case):
    destination, title, message = MISSING_POSTING_CASES[case["id"]]
    legacy = case["legacy_result"]
    run = evidence_path(evidence, Path(legacy["evidence"][0]))
    targets = legacy["comparison_targets"]
    result = read_json(evidence_path(evidence, run / "result.json"))
    before = read_json(evidence_path(evidence, run / "before-records/records.json"))
    changes = expected_changes(evidence, targets["keyed_record_diff"])
    if (legacy["verdict"] != "相違" or changes or result["changed"] or result["deleted"]
            or targets["report_files"] or "ledgers/irs/post.dat" in before["files"]
            or not any(message in evidence_path(evidence, Path(screen)).read_text(encoding="utf-8")
                       for screen in targets["screen_text"])):
        raise ValueError(f'{case["id"]}: 転記ファイル未作成による状態コード35の実測が必要です')
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    seed["files"]["ledgers/irs/acnts.dat"] = seeded_accounts(evidence, run)
    unchanged = {}
    for name in ("system.dat", "dflt.dat"):
        path = "ledgers/irs/" + name
        contents = evidence_path(evidence, run / "before-files" / path).read_bytes().hex()
        seed["files"][path] = {"type": "raw", "hex": contents}
        unchanged[path] = contents
    return {
        "id": case["id"], "title": title + "：転記ファイル未作成",
        "workflow": f"irs.{destination}.missingPosting", "dateSeconds": timestamp,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": changes, "reports": unchanged,
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
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    seed["files"]["ledgers/irs/acnts.dat"] = seeded_accounts(evidence, run)
    unchanged = {}
    for name in ("dflt.dat", "system.dat"):
        path = "ledgers/irs/" + name
        contents = evidence_path(evidence, run / "before-files" / path).read_bytes()
        seed["files"][path] = {"type": "raw", "hex": contents.hex()}
        unchanged[path] = contents.hex()
    return {
        "id": case["id"], "title": "簡易記帳を閉じる", "workflow": "irs.close",
        "dateSeconds": timestamp, "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": changes, "reports": unchanged,
    }


def seeded_accounts(evidence, run):
    records = read_json(evidence_path(evidence, run / "before-records/records.json"))
    return {
        "type": "indexed",
        "records": [[key.encode().hex(), record["hex"]]
                    for key, record in records["files"]["ledgers/irs/acnts.dat"]["records"].items()],
    }


def setup_fixture(evidence, case):
    legacy = case["legacy_result"]
    run = evidence_path(evidence, Path(legacy["evidence"][0]))
    path = "ledgers/irs/system.dat"
    result = read_json(evidence_path(evidence, run / "result.json"))
    if legacy["verdict"] != "合格" or result["lifecycle"] != "normal-exit" or set(result["changed"]) != {path}:
        raise ValueError("IRS-090: システム設定を保存したレガシー実測が必要です")
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    original = evidence_path(evidence, run / "files" / path).read_bytes()
    fields = {
        name: original[start:end].decode("shift_jis").rstrip()
        for name, start, end in (
            ("operatorName", 8, 32), ("client", 32, 56), ("street", 56, 80), ("city", 80, 104),
            ("country", 104, 128), ("postcode", 128, 152), ("startDate", 152, 160), ("endDate", 160, 168),
            ("printDestination", 264, 296),
        )
    }
    if original[226:230] != b"0000" or original[217:221] != b"    ":
        raise ValueError("IRS-090: 税率ゼロ・パスワード未登録の初期設定実測が必要です")
    return {
        "id": case["id"], "title": "簡易記帳の初期設定を保存する", "workflow": "irs.settings",
        "dateSeconds": timestamp, "seed": snapshot_seed(evidence, run),
        "changes": [], "reports": {path: original.hex()}, "input": fields,
    }


def initial_accounts_fixture(evidence, case):
    legacy = case["legacy_result"]
    run = evidence_path(evidence, Path(legacy["evidence"][0]))
    target = legacy["comparison_targets"]["keyed_record_diff"]
    all_changes = read_json(evidence_path(evidence, Path(target)))["changes"]
    accounts = "ledgers/irs/acnts.dat"
    defaults = "ledgers/irs/dflt.dat"
    if legacy["verdict"] != "合格" or any(change["before"] for change in all_changes) or {
        change["file"] for change in all_changes
    } != {accounts, defaults}:
        raise ValueError("IRS-091: 科目表と既定勘定の初回登録の実測が必要です")
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    input_accounts = []
    changes = []
    for entry in all_changes:
        if entry["file"] != accounts:
            continue
        row = bytes.fromhex(entry["after"]["hex"])
        if len(row) != 116 or row[5:11] != b"00000O":
            raise ValueError("IRS-091: 主勘定の登録実測が必要です")
        input_accounts.append({"code": entry["key"][:5], "name": row[11:35].decode("shift_jis").rstrip(),
                               "category": chr(row[-1])})
        changes.append({"file": accounts, "key": entry["key"].encode().hex(),
                        "before": None, "after": row.hex()})
    default_data = evidence_path(evidence, run / "files" / defaults).read_bytes()
    input_defaults = []
    for slot in range(32):
        code = default_data[slot * 5:slot * 5 + 5].decode("ascii")
        if code != "00000":
            tax = chr(default_data[224 + slot])
            if tax not in "INO":
                raise ValueError(f'IRS-091: 登録番号 {slot + 1} の付加価値税区分が不正です')
            input_defaults.append({"slot": slot + 1, "code": code,
                                   "label": default_data[160 + slot * 2:162 + slot * 2].decode("shift_jis"),
                                   "tax": tax})
    return {
        "id": case["id"], "title": "科目表と既定勘定を登録する", "workflow": "irs.defaults",
        "dateSeconds": timestamp, "seed": snapshot_seed(evidence, run),
        "changes": changes, "reports": {defaults: default_data.hex()},
        "input": {"accounts": input_accounts, "defaults": input_defaults},
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
    if destination in {"accountList", "settings", "post", "trialBalance", "audit"}:
        seed["files"]["ledgers/irs/acnts.dat"] = seeded_accounts(evidence, run)
    raw_names = {
        "settings": ("system.dat", "dflt.dat"),
        "defaultEdit": ("dflt.dat",),
        "defaultList": ("dflt.dat",),
        "post": ("system.dat", "dflt.dat"),
        "trialBalance": ("system.dat", "dflt.dat"),
        "audit": ("system.dat", "dflt.dat"),
    }
    for name in raw_names.get(destination, ()):
        path = "ledgers/irs/" + name
        data = evidence_path(evidence, run / "before-files" / path).read_bytes()
        seed["files"][path] = {"type": "raw", "hex": data.hex()}
        reports[path] = data.hex()
    return {
        "id": case["id"], "title": title + "への到達確認",
        "workflow": f"irs.{destination}.open", "dateSeconds": timestamp,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": changes, "reports": reports,
    }


def statement_settings_fixture(evidence):
    run = Path("runs/IRS-214-linux-confirmed")
    result = read_json(evidence_path(evidence, run / "result.json"))
    path = "ledgers/irs/final.dat"
    if result["error"] or set(result["changed"]) != {path} or result["deleted"]:
        raise ValueError("IRS-214: 決算書設定保存後の実測が必要です")
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    before = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    before["files"]["ledgers/irs/acnts.dat"] = seeded_accounts(evidence, run)
    raw = {}
    for name in ("system.dat", "dflt.dat"):
        key = "ledgers/irs/" + name
        raw[key] = evidence_path(evidence, run / "before-files" / key).read_bytes().hex()
        before["files"][key] = {"type": "raw", "hex": raw[key]}
    data = evidence_path(evidence, run / "files" / path).read_bytes()
    heading = data[:24].rstrip(b" \n").decode("shift_jis")
    if not heading or data != heading.encode("shift_jis") + b"\n":
        raise ValueError("IRS-214: 見出しのみを設定した実測が必要です")
    return {
        "id": "IRS-214", "title": "決算書の見出しを保存する", "workflow": "irs.statementSettings",
        "dateSeconds": timestamp, "seed": base64.b64encode(json.dumps(before, separators=(",", ":")).encode()).decode(),
        "changes": [], "reports": {**raw, path: data.hex()}, "input": {"heading": heading},
    }


def archive_fixture(evidence, case_id):
    exporting = case_id == "IRS-207"
    run = Path("linux-x64/confirm-archive") / case_id
    path = "ledgers/irs/coa-archived.txt"
    result = read_json(evidence_path(evidence, run / "result.json"))
    if result["error"] or set(result["changed"]) != {path if exporting else "ledgers/irs/acnts.dat"}:
        raise ValueError(f"{case_id}: 科目表の確定後の実測が必要です")
    data = evidence_path(evidence, run / ("files" if exporting else "before-files") / path).read_bytes()
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    seed["files"]["ledgers/irs/acnts.dat"] = seeded_accounts(evidence, run)
    reports = {path: data.hex()} if exporting else {}
    for name in ("system.dat", "dflt.dat"):
        key = "ledgers/irs/" + name
        contents = evidence_path(evidence, run / "before-files" / key).read_bytes().hex()
        seed["files"][key] = {"type": "raw", "hex": contents}
        reports[key] = contents
    return {
        "id": case_id, "title": "科目表書き出し" if exporting else "科目表取込",
        "workflow": "irs.accountExport" if exporting else "irs.accountImport",
        "dateSeconds": timestamp, "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": expected_changes(evidence, run / "record-diff.json"),
        "reports": reports, "input": {"contents": data.decode("shift_jis"), "count": len(data.splitlines())},
    }


def account_edit_fixture(evidence, case_id):
    editing = case_id == "IRS-204"
    run = Path("linux-x64/confirm-account-edit") / case_id
    path = "ledgers/irs/acnts.dat"
    result = read_json(evidence_path(evidence, run / "result.json"))
    changes = expected_changes(evidence, run / "record-diff.json")
    if (result["error"] or set(result["changed"]) != {path} or len(changes) != 1
            or changes[0]["file"] != path or bool(changes[0]["before"]) != editing):
        raise ValueError(f"{case_id}: 主勘定の保存実測が必要です")
    row = bytes.fromhex(changes[0]["after"])
    original = bytes.fromhex(changes[0]["before"]) if editing else b""
    if len(row) != 116 or row[5:11] != b"00000O":
        raise ValueError(f"{case_id}: 主勘定の固定長レコードが必要です")
    changes[0]["key"] = row[:10].hex()
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    seed["files"][path] = seeded_accounts(evidence, run)
    raw = {}
    for name in ("system.dat", "dflt.dat"):
        key = "ledgers/irs/" + name
        raw[key] = evidence_path(evidence, run / "before-files" / key).read_bytes().hex()
        seed["files"][key] = {"type": "raw", "hex": raw[key]}
    return {
        "id": case_id, "title": "勘定科目の変更" if editing else "勘定科目の登録",
        "workflow": "irs.accounts", "dateSeconds": timestamp,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": changes, "reports": raw,
        "input": {"code": row[:5].decode("ascii"), "name": row[11:35].decode("shift_jis").rstrip(),
                  "category": chr(row[-1]), "original": original[11:35].decode("shift_jis").rstrip()},
    }


def default_registration_fixture(evidence):
    run = Path("linux-x64/confirm-entry/IRS-210")
    path = "ledgers/irs/dflt.dat"
    result = read_json(evidence_path(evidence, run / "result.json"))
    if result["error"] or set(result["changed"]) != {path}:
        raise ValueError("IRS-210: 既定勘定登録後の実測が必要です")
    before = evidence_path(evidence, run / "before-files" / path).read_bytes()
    after = evidence_path(evidence, run / "files" / path).read_bytes()
    if len(before) != 257 or len(after) != 257:
        raise ValueError("IRS-210: 既定勘定ファイルのレコード長が不正です")
    rows = []
    for i in range(32):
        c, n, t = slice(5 * i, 5 * i + 5), slice(160 + 2 * i, 162 + 2 * i), 224 + i
        if (before[c], before[n], before[t]) != (after[c], after[n], after[t]):
            rows.append({"slot": i + 1, "code": after[c].decode("ascii"), "originalCode": before[c].decode("ascii"),
                         "originalLabel": before[n].decode("shift_jis").rstrip(), "label": after[n].decode("shift_jis").rstrip(),
                         "tax": chr(after[t])})
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    seed["files"]["ledgers/irs/acnts.dat"] = seeded_accounts(evidence, run)
    system = "ledgers/irs/system.dat"
    original_system = evidence_path(evidence, run / "before-files" / system).read_bytes().hex()
    seed["files"][system] = {"type": "raw", "hex": original_system}
    seed["files"][path] = {"type": "raw", "hex": before.hex()}
    return {
        "id": "IRS-210", "title": "既定勘定登録", "workflow": "irs.defaults", "dateSeconds": timestamp,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": [], "reports": {system: original_system, path: after.hex()}, "input": {"rows": rows},
    }


def trial_balance_fixture(evidence):
    run = Path("linux-x64/confirm-runs/IRS-216")
    result = read_json(evidence_path(evidence, run / "result.json"))
    report = "ledgers/irs/prt-1"
    spool, = [path for path in result["changed"] if path.startswith("spool/") and path.endswith("/prt-1")]
    expected = evidence_path(evidence, run / "files" / report).read_bytes()
    if result["error"] or expected != evidence_path(evidence, run / "files" / spool).read_bytes():
        raise ValueError("IRS-216: 試算表原本とスプールの実測が必要です")
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    seed["files"]["ledgers/irs/acnts.dat"] = seeded_accounts(evidence, run)
    reports = {report: expected.hex()}
    for name in ("system.dat", "dflt.dat"):
        path = "ledgers/irs/" + name
        data = evidence_path(evidence, run / "before-files" / path).read_bytes().hex()
        seed["files"][path] = {"type": "raw", "hex": data}
        reports[path] = data
    return {
        "id": "IRS-216", "title": "試算表印刷", "workflow": "irs.trialBalance", "dateSeconds": timestamp,
        "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": [], "reports": reports,
    }


def statement_entry_fixture(evidence, case):
    legacy = case["legacy_result"]
    run = Path(legacy["evidence"][0])
    result = read_json(evidence_path(evidence, run / "result.json"))
    work = "ledgers/irs/worksort.tmp"
    if result["error"] or set(result["changed"]) != {work}:
        raise ValueError(f'{case["id"]}: 決算書の比較対象入力画面と並べ替えファイルの実測が必要です')
    with evidence_path(evidence, run / "terminal.cast").open(encoding="utf-8") as recording:
        timestamp = json.loads(recording.readline())["timestamp"]
    seed = json.loads(base64.b64decode(snapshot_seed(evidence, run)))
    seed["files"]["ledgers/irs/acnts.dat"] = seeded_accounts(evidence, run)
    reports = {work: evidence_path(evidence, run / "files" / work).read_bytes().hex()}
    for name in ("system.dat", "dflt.dat"):
        path = "ledgers/irs/" + name
        data = evidence_path(evidence, run / "before-files" / path).read_bytes().hex()
        seed["files"][path] = {"type": "raw", "hex": data}
        reports[path] = data
    return {
        "id": case["id"], "title": "決算書比較対象の入力画面", "workflow": "irs.statements.prepare",
        "dateSeconds": timestamp, "seed": base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode(),
        "changes": expected_changes(evidence, legacy["comparison_targets"]["keyed_record_diff"]),
        "reports": reports,
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
    for case_id in MISSING_POSTING_CASES:
        save(args.output / (case_id + ".json"), missing_posting_fixture(evidence, cases[case_id]))
    save(args.output / "IRS-222.json", exit_fixture(evidence, cases["IRS-222"]))
    save(args.output / "IRS-090.json", setup_fixture(evidence, cases["IRS-090"]))
    save(args.output / "IRS-091.json", initial_accounts_fixture(evidence, cases["IRS-091"]))
    if (evidence / "runs/IRS-214-linux-confirmed").is_dir():
        save(args.output / "IRS-214.json", statement_settings_fixture(evidence))
    for case_id in ("IRS-207", "IRS-208"):
        if (evidence / "linux-x64" / "confirm-archive" / case_id).is_dir():
            save(args.output / (case_id + ".json"), archive_fixture(evidence, case_id))
    for case_id in ("IRS-203", "IRS-204"):
        if (evidence / "linux-x64" / "confirm-account-edit" / case_id).is_dir():
            save(args.output / (case_id + ".json"), account_edit_fixture(evidence, case_id))
    if (evidence / "linux-x64" / "confirm-entry/IRS-210").is_dir():
        save(args.output / "IRS-210.json", default_registration_fixture(evidence))
    if (evidence / "linux-x64" / "confirm-runs/IRS-216").is_dir():
        save(args.output / "IRS-216.json", trial_balance_fixture(evidence))
    for case_id in ("IRS-007", "IRS-218"):
        save(args.output / (case_id + ".json"), statement_entry_fixture(evidence, cases[case_id]))
    print(f"簡易記帳の実画面用データ {4 + len(REACH_CASES) + len(REPORT_CASES) + len(MISSING_POSTING_CASES)} 件")


if __name__ == "__main__":
    main()
