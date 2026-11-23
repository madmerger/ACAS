"""XCUITest ログと録画時刻から、PL の CSV と報告を作成する。"""
import argparse
import csv
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


VERDICTS = {"match": "一致", "mismatch": "不一致", "out_of_scope": "対象外"}
VIDEO = "ACAS-PL.mp4"


def read_run(directory):
    recording = json.loads((directory / "recording.json").read_text())
    log = (directory / "xcodebuild.log").read_text(errors="replace")
    starts = {case: float(seconds) - recording["startEpoch"]
              for case, seconds in re.findall(r"^ACAS_PL_START\|(PL-\d{3})\|([\d.]+)$", log, re.M)}
    results = {case: (VERDICTS[verdict], reason)
               for case, verdict, reason in re.findall(r"^ACAS_PL_RESULT\|(PL-\d{3})\|case\.verdict\.(\w+)\|(.*)$", log, re.M)}
    tests = {}
    for case, body, outcome in re.findall(
            r"Test Case '-\[ACASUITests.PurchaseFlows testPL(\d{3})\]' started\.(.*?)"
            r"Test Case '-\[ACASUITests.PurchaseFlows testPL\1\]' (passed|failed|skipped)", log, re.S):
        case = f"PL-{case}"
        verdict, reason = results.get(case, ("未判定", "照合まで到達していません"))
        if outcome == "failed":
            errors = re.findall(r"error: .*? : (.*)", body)
            if verdict == "一致":
                verdict = "未判定"
            reason = " / ".join(filter(None, [reason, *errors])) or "UI テスト失敗"
        tests[case] = {"verdict": verdict, "reason": reason, "outcome": outcome, "start": starts.get(case)}
    return tests


def original_reports(case, root, actual_root, verdict):
    case_id = case["id"]
    if case_id == "PL-090" or verdict == "対象外":
        return []
    targets = case["legacy_result"]["comparison_targets"]["report_files"]
    results = []
    for target in targets:
        if "/files/ledgers/" not in target:
            continue
        expected = (root / target).read_bytes()
        name = Path(target).name
        actual_path = actual_root / case_id / name
        if not actual_path.exists():
            if case_id == "PL-413" and verdict == "一致":
                results.append("アプリ内で帳票原本とバイト比較（PL-413）")
            else:
                results.append(f"{name}: 書き出されていないため原本 {len(expected)} B と照合不能")
            continue
        actual = actual_path.read_bytes()
        if actual == expected:
            results.append(f"{name}: 原本と全 {len(expected)} B 一致")
        else:
            offset = next((i for i, (a, b) in enumerate(zip(actual, expected)) if a != b), min(len(actual), len(expected)))
            results.append(f"{name}: 原本 {len(expected)} B / 実測 {len(actual)} B、最初の差分オフセット {offset}")
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("actual_reports", type=Path)
    parser.add_argument("deliverables", type=Path)
    parser.add_argument("timeline", type=Path, help="run ディレクトリごとの trim と動画内 offset を記録した JSON")
    parser.add_argument("--diagnoses", type=Path, help="ケース ID ごとの原因・対処（JSON）")
    parser.add_argument("--sha", default="未 push")
    args = parser.parse_args()
    catalog = json.loads((args.evidence / "scenarios/catalog.json").read_text())["cases"]
    cases = sorted((c for c in catalog if c["id"].startswith("PL-")), key=lambda case: case["id"])
    diagnoses = json.loads(args.diagnoses.read_text()) if args.diagnoses else {}
    history = defaultdict(list)
    for part in json.loads(args.timeline.read_text()):
        for case, result in read_run(Path(part["run"])).items():
            if result["start"] is not None:
                result["start"] += part["offset"] - part["trim"]
            history[case].append(result)

    fields = ["ケースID", "移行後結果", "一致判定", "動画ファイル名", "動画開始時刻(秒)", "不一致原因・対処履歴"]
    verdict_counts = Counter()
    mismatches = []
    unverified = []
    excluded = []
    byte_checks = []
    with (args.deliverables / "ACAS-PL.csv").open("w", encoding="utf-8-sig", newline="") as output:
        writer = csv.writer(output)
        writer.writerow(fields)
        for case in cases:
            case_id = case["id"]
            attempts = history[case_id]
            current = attempts[-1] if attempts else dict(verdict="未実行", outcome="未実行", reason="", start=None)
            verdict = current["verdict"]
            verdict_counts[verdict] += 1
            details = [f"第{i}回: {item['verdict']}" + (f" — {item['reason']}" if item["reason"] else "")
                       + (f"（{item['start']:.2f}秒）" if item["start"] is not None else "")
                       for i, item in enumerate(attempts, 1)]
            reports = original_reports(case, args.evidence, args.actual_reports, verdict)
            diagnosis = diagnoses.get(case_id, "")
            if diagnosis:
                details.append(diagnosis)
            details.extend(reports)
            seconds = current["start"]
            writer.writerow([case_id, current["outcome"], verdict, VIDEO if seconds is not None else "",
                             f"{seconds:.2f}" if seconds is not None else "", " / ".join(details)])
            if verdict == "不一致":
                mismatches.append(f"- **{case_id}** {case['title']}：{' / '.join(details)}")
            if verdict in ("未判定", "未実行"):
                unverified.append(f"- **{case_id}** {case['title']}：{' / '.join(details) or verdict}")
            if verdict == "対象外":
                excluded.append(f"- {case_id}：{case['legacy_result']['reason']}")
            if reports:
                byte_checks.append(f"- {case_id}：{'、'.join(reports)}")
    sections = [
        "# 買掛元帳（PL）移行同一性確認",
        "・".join(f"{label} {verdict_counts[label]} 件" for label in ("一致", "不一致", "対象外", "未判定", "未実行")),
        f"push SHA: `{args.sha}`",
        "## 不一致", "\n".join(mismatches) if mismatches else "なし",
        "## 対象外", "\n".join(excluded) if excluded else "なし",
        "## 帳票照合", "\n".join(byte_checks) if byte_checks else "帳票原本なし",
        "## 未検証事項", "\n".join(unverified) if unverified else "照合未到達のケースなし。",
        "- レガシーで実際に記録された操作段階までを比較し、未到達の業務処理や存在しない帳票原本を合格扱いしない。"
        "\n- 到達確認のケースは、移行画面を実操作で開くところまで。確定操作は別途明記されたケースのみ。"
        "\n- 保存データは SQLite ファイルそのものではなく、レガシーと共通のキー付き論理レコードの内容を比較。"
        "\n- PL-090 は SYS-001 のうち仕入先2件のみ。SYS-001 の他台帳と帳票は対象外。",
        "\n- 帳票作成前の PL-018・PL-228 は、旧版の空ファイルと iPad の未作成を同じ『帳票なし』の状態として比較。"
        "\n- SQLite と Berkeley DB のコンテナ構造や、対応できない型の全ファイルについてはバイト一致を確認していない。",
    ]
    (args.deliverables / "ACAS-PL.md").write_text("\n\n".join(sections) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
