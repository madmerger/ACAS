"""買掛元帳の実測証跡から実 UI テスト用の入力と期待値を作成する。"""
import argparse
import base64
import json
from pathlib import Path


WORKFLOWS = {
    "PL-400": ("pl.supplier.edit", "仕入先名を更新"),
    "PL-401": ("pl.supplier.delete", "残高ゼロの仕入先を削除"),
    "PL-402": ("pl.supplier.lookup", "存在しない仕入先を照会"),
    "PL-403": ("pl.supplier.add", "仕入先を新規登録"),
    "PL-411": ("pl.transaction.save", "税抜百・税額二十の仕入請求書を保存"),
    "PL-412": ("pl.transaction.reject", "未登録の仕入先を拒否"),
    "PL-413": ("pl.transaction.proof", "未転記の仕入取引の検証帳票"),
}
KEY_LENGTHS = {"purchled.dat": 7, "pinvoice.dat": 9, "analysis.dat": 3, "delivery.dat": 8}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def seed_files(run):
    files = {}
    for path, file in read_json(run / "before-records/records.json")["files"].items():
        basename = Path(path).name
        if basename == "system.dat":
            files[path] = {"type": "relative", "hex": (run / "before-files" / path).read_bytes().hex()}
        elif basename in KEY_LENGTHS:
            length = KEY_LENGTHS[basename] * 2
            files[path] = {"type": "indexed", "records": [
                [record["hex"][:length], record["hex"]] for record in file["records"].values()
            ]}
    return base64.b64encode(json.dumps({"files": files}, separators=(",", ":")).encode()).decode()


def fixture(root, case):
    legacy = case["legacy_result"]
    run = root / legacy["evidence"][0]
    targets = legacy["comparison_targets"]
    changes = []
    for change in read_json(root / targets["keyed_record_diff"])["changes"]:
        path = change["file"]
        length = KEY_LENGTHS.get(Path(path).name)
        before, after = (change[k]["hex"] if change[k] else None for k in ("before", "after"))
        key = (after or before)[:2 * length] if length else change["key"]
        changes.append(dict(file=path, key=key, before=before, after=after))
    reports = {
        str(Path(path).relative_to(Path(legacy["evidence"][0]) / "files")): (root / path).read_bytes().hex()
        for path in targets["report_files"] if "/files/ledgers/" in path
    }
    for path in targets["report_files"]:
        if "/files/spool/" in path and (root / path).read_bytes().hex() not in reports.values():
            raise ValueError(f"帳票スプールと原本が一致しません: {path}")
    with (run / "terminal.cast").open(encoding="utf-8") as recording:
        date = json.loads(recording.readline())["timestamp"]
    workflow, title = WORKFLOWS[case["id"]]
    return {
        "id": case["id"], "workflow": workflow, "title": title, "dateSeconds": date, "seed": seed_files(run),
        "changes": changes, "reports": reports, "calculation": None,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[2] / ".generated/fixtures")
    args = parser.parse_args()
    cases = {c["id"]: c for c in read_json(args.evidence / "scenarios/catalog.json")["cases"]}
    args.output.mkdir(parents=True, exist_ok=True)
    for case_id in WORKFLOWS:
        result = fixture(args.evidence, cases[case_id])
        (args.output / f"{case_id}.json").write_text(json.dumps(result, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"買掛元帳 実 UI 用データ {len(WORKFLOWS)} 件")


if __name__ == "__main__":
    main()
