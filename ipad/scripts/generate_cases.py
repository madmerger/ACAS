"""証跡台帳を変更せず、ケース一覧と実 UI テストの入力・期待値を生成する。"""
import argparse
import base64
import json
from pathlib import Path


WORKFLOWS = {
    "SYS-001": ("company", "会社・各台帳設定と業務用マスタ投入"),
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


def snapshot_seed(run):
    before = read_json(run / "before-records/records.json")
    files = {}
    for path, file in before["files"].items():
        name = Path(path).name
        if name == "system.dat":
            raw = (run / "before-files" / path).read_bytes()
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
        for change in read_json(evidence / path)["changes"]:
            name = Path(change["file"]).name
            before, after = (change[k]["hex"] if change[k] else None for k in ("before", "after"))
            key = change["key"]
            if name in KEY_LENGTHS:
                key = (after or before)[:KEY_LENGTHS[name] * 2]
            changes.append(dict(file=change["file"], key=key, before=before, after=after))
    return changes


def fixture(evidence, case):
    legacy = case["legacy_result"]
    targets = legacy.get("comparison_targets", {})
    workflow, title = WORKFLOWS[case["id"]]
    run = evidence / legacy["evidence"][0]
    reports = {
        str(Path(path).relative_to(Path(legacy["evidence"][0]) / "files")): (evidence / path).read_bytes().hex()
        for path in targets.get("report_files", [])
        if "/files/ledgers/" in path
    }
    for path in targets.get("report_files", []):
        if "/files/spool/" in path and (evidence / path).read_bytes().hex() not in reports.values():
            raise ValueError(f"帳票スプールと原本が一致しません: {path}")
    seed = snapshot_seed(run) if workflow == "sales-proof" else None
    with (run / "terminal.cast").open(encoding="utf-8") as recording:
        date = json.loads(recording.readline())["timestamp"]
    return {
        "id": case["id"],
        "workflow": workflow,
        "title": title,
        "dateSeconds": date,
        "seed": seed,
        "changes": expected_changes(evidence, targets.get("keyed_record_diff")),
        "reports": reports,
        "calculation": legacy.get("actual") if workflow == "check-digit" else None,
        "input": {
            "company": case["input_data"].get("text_inputs", [""])[0].split("\r")[0],
            "code": case["input_data"].get("code"),
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / ".generated")
    args = parser.parse_args()
    ledger = read_json(args.evidence / "scenarios/catalog.json")
    cases = ledger["cases"]
    ids = {case["id"] for case in cases}
    if len(cases) != 453 or len(ids) != len(cases) or not WORKFLOWS.keys() <= ids:
        parser.error("証跡台帳のケース件数または識別子が一致しません")
    fixtures = args.output / "fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    save(args.output / "cases.json", cases)
    for case in cases:
        if case["id"] in WORKFLOWS:
            save(fixtures / (case["id"] + ".json"), fixture(args.evidence, case))
    print(f"ケース台帳 {len(cases)} 件、実 UI 用データ {len(WORKFLOWS)} 件")


if __name__ == "__main__":
    main()
