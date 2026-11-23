"""簡易記帳の転記をレガシー実測と照合する実画面用の入力を生成する。"""
import argparse
import base64
import json
import sys
from pathlib import Path

IPAD = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(IPAD / "scripts"))
from generate_cases import evidence_path, read_json, save, snapshot_seed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path, default=IPAD / ".generated" / "fixtures")
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    case = next(c for c in read_json(evidence_path(evidence, Path("scenarios/catalog.json")))["cases"]
                if c["id"] == "IRS-400")
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
    records = read_json(evidence_path(evidence, run / "before-records/records.json"))
    seed["files"][accounts] = {
        "type": "indexed",
        "records": [[key.encode().hex(), record["hex"]] for key, record in records["files"][accounts]["records"].items()],
    }
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
    print("簡易記帳の実画面用データ 1 件")


if __name__ == "__main__":
    main()
