#!/usr/bin/env python3
"""レガシー証跡のベースライン（GnuCOBOL 索引/相対/行順ファイル）を
Web 版の初期データ JSON（{論理ファイル名: {キー16進: レコード16進}}）へ変換する開発用ツール。
使い方: dump_baselines.py <証跡展開ディレクトリ> <出力ディレクトリ(src/main/resources/baselines)>
GnuCOBOL 3.1.2 (cobc) が必要。コピー句はこのリポジトリの原本を使う。"""
import json, os, struct, subprocess, sys, tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
# 物理ファイル名: (コピー句, FD名, レコード名, 主キー, SELECT 追加句, FD 前置き)
INDEXED = {
    "acas/ledger.dat": ("general/fdledger.cob", "ledger-file", "ledger-record", "ledger-key", "", ""),
    "acas/salesled.dat": ("copybooks/fdsl.cob", "sales-file", "sales-record", "sales-key", "", ""),
    "acas/purchled.dat": ("copybooks/fdpl.cob", "purchase-file", "purch-record", "purch-key", "", ""),
    "acas/stockctl.dat": ("copybooks/fdstock.cob", "stock-file", "stock-record", "stock-key",
                          "alternate record key Stock-Abrev-Key alternate record key Stock-Desc with duplicates", ""),
    "acas/delivery.dat": ("copybooks/fddel.cob", "delivery-file", "delivery-record", "deliv-key", "", ""),
    "acas/analysis.dat": ("copybooks/fdanal.cob", "analysis-file", "analysis-record", "pa-code", "", ""),
    "acas/invoice.dat": ("sales/fdinv.cob", "invoice-file", "invoice-record", "invoice-key", "", ""),
    "acas/pinvoice.dat": ("purchase/fdpinv.cob", "invoice-file", "invoice-record", "invoice-key", "", ""),
    "acas/openitm3.dat": ("sales/fdoi3.cob", "open-item-file-3", "open-item-record-3", "oi3-key", "", ""),
    "irs/acnts.dat": ("incomplete_records_system/fdwsnl.cob", "nominal-ledger", "record-1", "key-1", "", "fd nominal-ledger."),
}

# FD の定義では開けない（FILE STATUS 39）ファイルを、実際に書かれているレコード定義で読むための代替定義。
# analysis.dat: 在庫メニュー（stock/wsnames.cob の file-defs）から sl070 を呼ぶと、sl070（sales/wsnames.cob）の
# file-13（value-file）が在庫側の 5 番目 = analysis.dat を指すため、value-record（66 バイト）が書かれている。
PHYSICAL = {
    "acas/analysis.dat": ("copybooks/fdval.cob", "value-file", "value-record", "va-code", "", ""),
}

def build(tmp, name, spec):
    copybook, file, record, key, alt, pre = spec
    code = f'''       >>source free
identification division.
program-id. dumper.
environment division.
input-output section.
file-control.
select {file} assign source-path organization indexed access dynamic record key {key} {alt} file status fs.
data division.
file section.
{pre}
copy "{copybook}".
working-storage section.
01 source-path pic x(1024).
01 fs pic xx.
01 i binary-long.
01 n binary-long.
01 hi binary-long.
01 lo binary-long.
01 digits-table pic x(16) value "0123456789abcdef".
01 hex-out pic x(65536).
procedure division.
accept source-path from argument-value
open input {file}
if fs not = '00' display 'OPEN-ERROR:' fs upon syserr move 1 to return-code goback end-if
move low-values to {key}
start {file} key not < {key} invalid key move '10' to fs end-start
perform until fs not = '00' and fs not = '02'
    read {file} next record at end move '10' to fs end-read
    if fs = '00' or fs = '02'
        perform varying i from 1 by 1 until i > function length({key})
            compute n = function ord({key}(i:1)) - 1
            divide n by 16 giving hi remainder lo
            move digits-table(hi + 1:1) to hex-out(i * 2 - 1:1)
            move digits-table(lo + 1:1) to hex-out(i * 2:1)
        end-perform
        compute n = function length({key}) * 2
        display hex-out(1:n) '|' with no advancing
        perform varying i from 1 by 1 until i > function length({record})
            compute n = function ord({record}(i:1)) - 1
            divide n by 16 giving hi remainder lo
            move digits-table(hi + 1:1) to hex-out(i * 2 - 1:1)
            move digits-table(lo + 1:1) to hex-out(i * 2:1)
        end-perform
        compute n = function length({record}) * 2
        display hex-out(1:n)
    end-if
end-perform
close {file}
goback.
'''
    src = tmp / (name.replace("/", "_") + ".cbl")
    src.write_text(code)
    exe = src.with_suffix("")
    subprocess.run(["cobc", "-x", "-I", str(REPO), "-I", str(REPO / "copybooks"), "-o", str(exe), str(src)],
                   cwd=REPO, check=True, capture_output=True)
    return exe

def seqkey(n): return struct.pack(">q", n).hex()


def validate_evidence(root):
    def reject_link(path):
        if path.is_symlink():
            raise SystemExit(f"証跡のシンボリックリンクは使用できません: {path}")

    def unreadable(error):
        raise error

    reject_link(root)
    for directory, dirs, files in os.walk(root, followlinks=False, onerror=unreadable):
        for entry in dirs + files:
            reject_link(Path(directory) / entry)


def main():
    evid, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    validate_evidence(evid)
    out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        exes = {n: build(tmp, n, s) for n, s in INDEXED.items()}
        phys = {n: build(tmp, n + ".phys", s) for n, s in PHYSICAL.items()}
        for base in sorted((evid / "baselines").iterdir()):
            data = {}
            root = base / "ledgers"
            for p in sorted(root.rglob("*")) if root.is_dir() else []:
                if not p.is_file(): continue
                rel = str(p.relative_to(root))
                if "temp-backups" in rel or rel.endswith("nohup.out") or rel[-2:] in (".1", ".2"): continue
                if rel in exes:
                    out = subprocess.run([str(exes[rel]), str(p)], capture_output=True, text=True, errors="replace")
                    if out.returncode and rel in phys:
                        # 宣言と実レコード長が違うファイルは実レコード長のまま取り込む（CobFile.open が 39 を返す）
                        alt = subprocess.run([str(phys[rel]), str(p)], capture_output=True, text=True, errors="replace")
                        if not alt.returncode:
                            data[rel] = dict(line.split("|") for line in alt.stdout.splitlines() if "|" in line); continue
                        raise SystemExit(f"{base.name}/{rel}: 索引レコード境界を確認できません: "
                                         f"{out.stderr.strip()} / {alt.stderr.strip()}")
                    if out.returncode: raise SystemExit(f"{base.name}/{rel}: {out.stderr.strip()}")
                    out = out.stdout
                    data[rel] = dict(line.split("|") for line in out.splitlines() if "|" in line)
                elif rel == "acas/system.dat":   # 相対編成: 8 バイト長 + レコード
                    raw, recs, pos, rrn = p.read_bytes(), {}, 0, 0
                    while pos + 8 <= len(raw):
                        size = struct.unpack("<q", raw[pos:pos + 8])[0]; rrn += 1
                        reclen = 1024
                        if size > 0: recs[seqkey(rrn)] = raw[pos + 8:pos + 8 + reclen].hex()
                        pos += 8 + reclen
                    data[rel] = recs
                elif p.name.startswith("prt-") or rel in ("irs/dflt.dat", "irs/system.dat"):   # 行順編成
                    lines = p.read_bytes().split(b"\n")
                    if lines and lines[-1] == b"": lines.pop()
                    data[rel] = {seqkey(i + 1): l.hex() for i, l in enumerate(lines)}
                else:
                    raise SystemExit(f"未対応ファイル: {base.name}/{rel}")
            (out_dir / f"{base.name}.json").write_text(json.dumps(data, indent=0, sort_keys=True))
            print(base.name, {k: len(v) for k, v in data.items()})

if __name__ == "__main__":
    main()
