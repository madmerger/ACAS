"""売掛元帳の得意先操作に対応する基盤ハーネス用データを生成する。"""
import argparse
import base64
import importlib.util
import json
from pathlib import Path
import subprocess

IPAD = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("generate_cases", IPAD / "scripts/generate_cases.py")
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)

CASES = {
    "SL-400": ("edit", "得意先名称の変更"),
    "SL-401": ("remove", "残高がない得意先の削除"),
    "SL-402": ("view", "存在しない得意先の照会"),
    "SL-403": ("register", "新規得意先の登録"),
}
DELIVERY_PATH = "ledgers/acas/delivery.dat"


def customer_seed(run):
    base_seed = BASE.snapshot_seed(run)
    snapshot = BASE.read_json(run / "before-records/records.json")["files"]
    if DELIVERY_PATH in snapshot:
        records = [[value["hex"][:16], value["hex"]] for value in snapshot[DELIVERY_PATH]["records"].values()]
    elif (file := run / "before-files" / DELIVERY_PATH).is_file():
        dump = subprocess.run(["db_dump", str(file)], capture_output=True, text=True, check=True)
        _, data = dump.stdout.split("HEADER=END\n", 1)
        rows = data.splitlines()
        if not rows or rows.pop() != "DATA=END" or len(rows) % 2:
            raise ValueError(f"納品先・備考ファイルを読み取れません: {file}")
        records = [[key.strip(), value.strip()] for key, value in zip(rows[::2], rows[1::2])]
    else:
        return base_seed
    if any(len(bytes.fromhex(key)) != 8 or len(bytes.fromhex(value)) != 134 or not value.startswith(key)
           for key, value in records):
        raise ValueError(f"納品先・備考レコードの形式が一致しません: {run}")
    seed = json.loads(base64.b64decode(base_seed))
    seed["files"][DELIVERY_PATH] = {"type": "indexed", "records": records}
    return base64.b64encode(json.dumps(seed, separators=(",", ":")).encode()).decode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--simulator", help="指定した iPad Simulator で得意先の実 UI テストも実行する（端末 ID）")
    args = parser.parse_args()
    cases = {c["id"]: c for c in BASE.read_json(args.evidence / "scenarios/catalog.json")["cases"]}
    fixtures = IPAD / ".generated/fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    for case_id, (operation, title) in CASES.items():
        case = cases[case_id]
        legacy = case["legacy_result"]
        run = args.evidence / legacy["evidence"][0]
        with (run / "terminal.cast").open(encoding="utf-8") as recording:
            date = json.loads(recording.readline())["timestamp"]
        inputs = case["input_data"]["text_inputs"]
        values = {"code": inputs[4].strip()}
        if operation == "edit":
            values["name"] = inputs[5].strip()
        if operation == "register":
            values["name"], values["address"] = inputs[5].strip().split("\t", maxsplit=1)
        BASE.save(fixtures / (case_id + ".json"), {
            "id": case_id, "title": title, "workflow": "sales-customer-" + operation,
            "dateSeconds": date, "seed": customer_seed(run),
            "changes": BASE.expected_changes(args.evidence, legacy["comparison_targets"]["keyed_record_diff"]),
            "reports": {}, "input": values,
        })
    print(f"得意先の実 UI 用データ {len(CASES)} 件")
    if args.simulator:
        subprocess.run(["xcodegen", "generate", "--spec", str(IPAD / "project.yml")], check=True)
        subprocess.run([
            "xcodebuild", "-project", str(IPAD / "ACAS.xcodeproj"), "-scheme", "ACAS",
            "-destination", f"platform=iOS Simulator,id={args.simulator}",
            "-derivedDataPath", str(IPAD / ".derived"), "-parallel-testing-enabled", "NO",
            "-only-testing:ACASUITests/SalesCustomersFlows", "test",
        ], check=True)


if __name__ == "__main__":
    main()
