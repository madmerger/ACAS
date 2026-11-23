"""買掛元帳の実測証跡から実 UI テスト用の入力と期待値を作成する。"""
import argparse
import base64
import hashlib
import json
import re
import subprocess
from pathlib import Path


WORKFLOWS = {
    "PL-400": "pl.supplier.edit",
    "PL-401": "pl.supplier.delete",
    "PL-402": "pl.supplier.lookup",
    "PL-403": "pl.supplier.add",
    "PL-411": "pl.transaction.save",
    "PL-412": "pl.transaction.reject",
    "PL-413": "pl.transaction.proof",
}
KEY_LENGTHS = {"purchled.dat": 7, "pinvoice.dat": 9, "analysis.dat": 3, "delivery.dat": 8,
               "batch.dat": 6}
RELATIVE_SIZES = {"posting.dat": 98}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


CASE_NAMES = read_json(Path(__file__).with_name("case_names_ja.json"))


def evidence_path(root, path):
    resolved = (root / path).resolve()
    if not resolved.is_relative_to(root):
        raise ValueError(f"証跡ルート外のパスです: {path}")
    return resolved


def validate_case_id(case_id):
    if not re.fullmatch(r"PL-[0-9]{3}", case_id):
        raise ValueError(f"不正な買掛ケース ID: {case_id}")
    return case_id


def purchase_case_ids():
    source = Path(__file__).with_name("PurchaseFlows.swift").read_text(encoding="utf-8")
    return {f"PL-{number}" for number in re.findall(r"^    func testPL([0-9]{3})\(", source, re.M)}


def check_required_cases(cases, output):
    missing = purchase_case_ids() - cases.keys()
    for path in output.glob("PL-*.json"):
        if re.fullmatch(r"PL-[0-9]{3}", path.stem) and (missing or path.stem not in cases):
            path.unlink()
    if missing:
        raise ValueError("必須の買掛ケースが台帳にありません: " + ", ".join(sorted(missing)))


def seed_files(root, run):
    files = {}
    for path, file in read_json(evidence_path(root, run / "before-records/records.json"))["files"].items():
        basename = Path(path).name
        if basename == "system.dat" or basename in RELATIVE_SIZES:
            source = evidence_path(root, run / "before-files" / path)
            files[path] = {"type": "relative", "hex": source.read_bytes().hex()}
        elif basename in KEY_LENGTHS:
            length = KEY_LENGTHS[basename] * 2
            files[path] = {"type": "indexed", "records": [
                [record["hex"][:length], record["hex"]] for record in file["records"].values()
            ]}
    return base64.b64encode(json.dumps({"files": files}, separators=(",", ":")).encode()).decode()


def fixture(root, case):
    legacy = case["legacy_result"]
    run = evidence_path(root, legacy["evidence"][0])
    targets = legacy["comparison_targets"]
    changes = []
    for change in read_json(evidence_path(root, targets["keyed_record_diff"]))["changes"]:
        path = change["file"]
        length = KEY_LENGTHS.get(Path(path).name)
        before, after = (change[k]["hex"] if change[k] else None for k in ("before", "after"))
        key = (after or before)[:2 * length] if length else change["key"]
        changes.append(dict(file=path, key=key, before=before, after=after))
    report_paths = {path: evidence_path(root, path) for path in targets["report_files"]}
    reports = {
        str(Path(path).relative_to(Path(legacy["evidence"][0]) / "files")): source.read_bytes().hex()
        for path, source in report_paths.items() if "/files/ledgers/" in path
    }
    for path, source in report_paths.items():
        if "/files/spool/" in path and source.read_bytes().hex() not in reports.values():
            raise ValueError(f"帳票スプールと原本が一致しません: {path}")
    with evidence_path(root, run / "terminal.cast").open(encoding="utf-8") as recording:
        date = json.loads(recording.readline())["timestamp"]
    workflow = WORKFLOWS[case["id"]]
    title = CASE_NAMES[case["id"]]
    return {
        "id": case["id"], "workflow": workflow, "title": title, "dateSeconds": date, "seed": seed_files(root, run),
        "changes": changes, "reports": reports, "calculation": None,
    }


def archived_records(path):
    dump = subprocess.check_output(["db_dump", str(path)], text=True)
    lines = dump.splitlines()
    records = [line.strip() for line in lines[lines.index("HEADER=END") + 1:lines.index("DATA=END")]]
    if len(records) % 2:
        raise ValueError(f"奇数行の論理レコード抽出です: {path}")
    return [(key.hex(), data.hex()) for key, data in zip(
        map(bytes.fromhex, records[::2]), map(bytes.fromhex, records[1::2]))]


def equivalence_fixture(root, case):
    case_id = case["id"]
    legacy = case["legacy_result"]
    run_path = Path(legacy["evidence"][0])
    run = evidence_path(root, run_path)
    targets = legacy["comparison_targets"]
    changes = []
    excluded_paths = set()
    for change in read_json(evidence_path(root, targets["keyed_record_diff"]))["changes"]:
        path = change["file"]
        if case_id == "PL-090" and Path(path).name != "purchled.dat":
            excluded_paths.add(path)
            continue
        before, after = (change[k]["hex"] if change[k] else None for k in ("before", "after"))
        length = KEY_LENGTHS.get(Path(path).name)
        key = (after or before)[:2 * length] if length else change["key"]
        changes.append(dict(file=path, key=key, before=before, after=after))
    cleared_files = []
    if case_id == "PL-414":
        archive = "ledgers/acas/openitm5.dat"
        for key, data in archived_records(evidence_path(root, run / "files" / archive)):
            changes.append(dict(file=archive, key=key, before=None, after=data))
        excluded_paths.update(f"ledgers/acas/{name}" for name in ("analysis.dat", "value.dat", "system.dat"))
        staged = "ledgers/acas/openitm4.dat"
        if evidence_path(root, run / "files" / staged).stat().st_size == 0:
            cleared_files.append(staged)
    reports = {}
    for path in targets["report_files"]:
        source = evidence_path(root, path)
        if case_id != "PL-090" and "/files/ledgers/" in path:
            data = source.read_bytes()
            reports[str(Path(path).relative_to(run_path / "files"))] = {
                "count": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            }
    if case_id != "PL-090":
        for path in targets["report_files"]:
            if "/files/spool/" in path:
                digest = hashlib.sha256(evidence_path(root, path).read_bytes()).hexdigest()
                if digest not in {r["sha256"] for r in reports.values()}:
                    raise ValueError(f"帳票スプールと原本が一致しません: {path}")
    out_of_scope = legacy["reason"] if legacy["verdict"] == "未実施" else None
    checkpoint = None
    if legacy["verdict"] != "合格" and not changes and not reports and not out_of_scope:
        screens = [evidence_path(root, path).read_text(errors="replace") for path in targets["screen_text"]]
        final = screens[-1]
        if error := re.search(r"T-[0-9]{3}(?= Error)", final):
            checkpoint = {"kind": "blocked", "detail": f"旧版は {error[0]} で拒否、対象画面には進まない"}
        elif "Purchase Ledger System Menu" in final:
            checkpoint = {"kind": "purchaseMenu", "detail": "旧証跡は買掛元帳メニューまで"}
        elif "Cheque Menu" in final:
            checkpoint = {"kind": "chequeMenu", "detail": "旧証跡は支払予定・小切手メニューまで"}
        elif "Report Attributes" in final and "Supplier Number" in final:
            checkpoint = {"kind": "supplierReport", "detail": "旧証跡は仕入先帳票の条件画面まで、帳票未生成"}
        elif case_id == "PL-410" and any(re.search(r"\[Z \]\s+\[500001\]\s+\[PURCHASES\s+\]\s+\[P\s+\]", screen)
                                         for screen in screens):
            checkpoint = {"kind": "analysisDraft", "detail": "分析コード Z・勘定 500001・名称 PURCHASES・分類 P、保存なし"}
        else:
            raise ValueError(f"比較する旧証跡の画面を特定できません: {case_id}")
    with evidence_path(root, run / "terminal.cast").open(encoding="utf-8") as recording:
        date = json.loads(recording.readline())["timestamp"]
    return {
        "id": case_id, "title": CASE_NAMES[case_id], "workflow": "pl.equivalence", "dateSeconds": date,
        "seed": seed_files(root, run), "changes": changes, "reports": {}, "calculation": None,
        "equivalence": {"reportDigests": reports, "outOfScope": out_of_scope,
                        "checkpoint": checkpoint,
                        "clearedFiles": cleared_files,
                        "unprintedReports": [path for path, report in reports.items() if report["count"] == 0]
                        if case_id in ("PL-018", "PL-228") else [],
                        "excludedPaths": sorted(excluded_paths),
                        "relativeRecordSizes": {f"ledgers/acas/{name}": size
                                                for name, size in RELATIVE_SIZES.items()}},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[2] / ".generated/fixtures")
    args = parser.parse_args()
    root = args.evidence.resolve()
    cases = {c["id"]: c for c in read_json(evidence_path(root, "scenarios/catalog.json"))["cases"]}
    pl_cases = [case for case in cases.values() if case["id"].startswith("PL-")]
    for case in pl_cases:
        validate_case_id(case["id"])
    check_required_cases(cases, args.output)
    args.output.mkdir(parents=True, exist_ok=True)
    output = args.output.resolve()
    for case in pl_cases:
        generate = fixture if case["id"] in WORKFLOWS else equivalence_fixture
        result = generate(root, case)
        evidence_path(output, f"{case['id']}.json").write_text(
            json.dumps(result, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"買掛元帳 実 UI 用データ {len(pl_cases)} 件")


if __name__ == "__main__":
    main()
