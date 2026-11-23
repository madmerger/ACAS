"""証跡の Berkeley DB・順編成ファイルからグループ④の未採取レコードを補完する。"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


CASES = {
    "ST-400": ("ledgers/acas/staudit.dat",),
    "ST-402": ("ledgers/acas/staudit.dat",),
    "IRS-400": ("ledgers/irs/post.dat",),
    "INT-405": ("ledgers/acas/openitm4.dat", "ledgers/acas/openitm5.dat"),
}


def dump(path):
    linux_path = subprocess.check_output(["wsl.exe", "--", "wslpath", "-a", path.as_posix()], text=True).strip()
    lines = subprocess.check_output(["wsl.exe", "--", "db5.3_dump", linux_path], text=True).splitlines()
    entries = lines[lines.index("HEADER=END") + 1 : lines.index("DATA=END")]
    if len(entries) % 2:
        raise ValueError(f"キーとレコードが対になっていません：{path}")
    return [(bytes.fromhex(key), record.strip()) for key, record in zip(entries[::2], entries[1::2])]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    ledger = json.loads((evidence / "入力" / "シナリオ台帳.json").read_text(encoding="utf-8-sig"))
    for case in ledger["cases"]:
        if case["id"] not in CASES:
            continue
        run = evidence / case["legacy_result"]["evidence"][0]
        before = json.loads((run / "before.json").read_text(encoding="utf-8"))
        after = json.loads((run / "result.json").read_text(encoding="utf-8"))["after"]
        records = {}
        for file in CASES[case["id"]]:
            if file in before:
                raise ValueError(f"実行前のレコードが存在します：{file}")
            path = run / "files" / file
            content = path.read_bytes()
            if hashlib.sha256(content).hexdigest() != after[file]["sha256"]:
                raise ValueError(f"原本のハッシュが一致しません：{path}")
            if file.endswith("staudit.dat"):
                length = 104
                if len(content) % length:
                    raise ValueError(f"在庫監査のレコード長が不正です：{path}")
                records[file] = {
                    f"{i // length + 1:08}": content[i : i + length].hex()
                    for i in range(0, len(content), length)
                }
                print(f"{case['id']}：{file}　{len(records[file])}件")
                continue
            rows = {}
            for key, record in dump(path) if content else []:
                if file.endswith("openitm5.dat"):
                    if len(key) != 11:
                        raise ValueError(f"未決済明細キーの長さが不正です：{path}")
                    invoice = int.from_bytes(key[7:], "little")
                    identifier = f"{key[:7].decode('ascii')}/{invoice:08}"
                else:
                    identifier = key.decode("ascii")
                if identifier in rows:
                    raise ValueError(f"重複キーです：{identifier}")
                rows[identifier] = record
            records[file] = rows
            print(f"{case['id']}：{file}　{len(rows)}件")
        (run / "record-diff.bdb.json").write_text(json.dumps(records, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
