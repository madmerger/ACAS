"""XCUITest ログと録画時刻から、PL の CSV と報告を作成する。"""
import argparse
import csv
import json
import re
import string
from collections import Counter, defaultdict
from pathlib import Path
from generate_fixtures import evidence_path, validate_case_id


VERDICTS = {"match": "一致", "mismatch": "不一致", "out_of_scope": "対象外"}
VIDEO = "ACAS-PL.mp4"
MENU_SCREENS = (
    "処理日入力", "仕入先マスター管理", "買掛残高・明細照会", "仕入取引入力",
    "仕入取引修正", "仕入取引削除", "仕入の検証帳票", "仕入転記", "支払入力・消込",
    "支払修正", "支払検証帳票", "支払転記", "仕入分析コード管理", "買掛分析帳票",
    "仕入日計帳", "買掛金年齢表", "仕入先名順一覧", "仕入先別取引帳票",
    "支払予定・小切手・送金", "買掛の期間締め", "仕入伝票の固定設定", "仕入先ファイル帳票",
)
SCREEN_NAMES = {
    "PL-200": "買掛元帳", "PL-220": "仕入分析コード管理", "PL-223": "仕入分析コード管理",
    "PL-239": "システム設定", "PL-240": "会社設定", "PL-241": "処理日入力",
}
MATCHED_ACTIONS = {
    "PL-090": "仕入先 SUPP018・SUPP026 を保存、各 300 B が原本と一致",
    "PL-206": "仕入先一覧帳票の登録日条件を確認、帳票未生成・保存差分なし",
    "PL-400": "仕入先 SUPP018 の名称を更新、保存レコードは原本と一致",
    "PL-401": "残高ゼロの仕入先 SUPP026 を削除、削除結果は原本と一致",
    "PL-402": "仕入先 MISS001 の照会で該当なしを表示",
    "PL-403": "仕入先 TEST011 を登録、保存レコードは原本と一致",
    "PL-411": "税抜100・税額20の仕入請求書1件を保存、保存レコードは原本と一致",
    "PL-412": "存在しない仕入先 MISS001 を指定し、該当なしを表示",
}


def comparison_note(reason):
    reason = re.sub(
        r"(\S+): 期待 (\d+) B / 実測 (なし|\d+)",
        lambda m: f"{m[1]}：原本 {int(m[2]):,} B、"
                  + ("移行版の出力なし" if m[3] == "なし" else f"実測 {int(m[3]):,} B"),
        reason,
    )
    if reason.startswith("ledgers/") and "：原本 " not in reason:
        return "差分のあった保存データのファイルとキー：" + reason.replace("; ", "、")
    return reason


def read_run(directory):
    recording = json.loads((directory / "recording.json").read_text())
    log = (directory / "xcodebuild.log").read_text(errors="replace")
    starts = {case: float(seconds) - recording["startEpoch"]
              for case, seconds in re.findall(r"^ACAS_PL_START\|(PL-\d{3})\|([\d.]+)$", log, re.M)}
    results = {case: (VERDICTS[verdict], reason)
               for case, verdict, reason in re.findall(r"^ACAS_PL_RESULT\|(PL-\d{3})\|case\.verdict\.(\w+)\|(.*)$", log, re.M)}
    screens = dict(re.findall(r"^ACAS_PL_SCREEN\|(PL-\d{3})\|(.*)$", log, re.M))
    tests = {}
    for case, body, outcome in re.findall(
            r"Test Case '-\[ACASUITests.PurchaseFlows testPL(\d{3})\]' started\.(.*?)"
            r"Test Case '-\[ACASUITests.PurchaseFlows testPL\1\]' (passed|failed|skipped)", log, re.S):
        case = f"PL-{case}"
        verdict, reason = results.get(case, ("未判定", "照合まで到達していません"))
        if case in screens:
            reason = "、".join(filter(None, [reason, screens[case]]))
        if outcome == "failed":
            errors = re.findall(r"error: .*? : (.*)", body)
            notes = [error for error in errors
                     if not error.startswith("XCTAssert") and re.search(r"[ぁ-んァ-ヶ一-龯]", error)]
            if verdict == "一致":
                verdict = "未判定"
            reason = "、".join(filter(None, [reason, *notes])) or "照合後のテスト確認で失敗"
        tests[case] = {"verdict": verdict, "reason": reason, "start": starts.get(case)}
    return tests


def original_reports(case, root, actual_root, verdict):
    case_id = validate_case_id(case["id"])
    if case_id == "PL-090" or verdict in ("対象外", "未実行"):
        return []
    targets = case["legacy_result"]["comparison_targets"]["report_files"]
    results = []
    for target in targets:
        if "/files/ledgers/" not in target:
            continue
        expected = evidence_path(root.resolve(), target).read_bytes()
        name = Path(target).name
        actual_path = evidence_path(actual_root.resolve(), Path(case_id) / name)
        if not actual_path.exists():
            if verdict == "一致":
                results.append((f"帳票 {len(expected):,} B をアプリ内で原本照合",
                                f"{name}：アプリ内で原本 {len(expected):,} B と照合、直接照合用の出力なし", False))
            else:
                results.append(("", f"{name}：移行版の書き出しがなく原本 {len(expected):,} B と直接照合できず", False))
            continue
        actual = actual_path.read_bytes()
        if actual == expected:
            summary = f"帳票 {len(actual):,} B を生成、原本と一致"
            if not actual:
                summary = "帳票は 0 B、原本と一致"
            results.append((summary, f"{name}：原本と全 {len(expected):,} B 一致", False))
        else:
            offset = next((i for i, (a, b) in enumerate(zip(actual, expected)) if a != b), min(len(actual), len(expected)))
            if offset == min(len(actual), len(expected)):
                difference = "短い方は全バイト一致、長さが相違"
            else:
                difference = f"{offset + 1:,} バイト目が最初の差分（原本 {expected[offset]:02X}、移行版 {actual[offset]:02X}）"
            results.append((f"帳票 {len(actual):,} B を生成、原本 {len(expected):,} B",
                            f"{name}：原本 {len(expected):,} B、実測 {len(actual):,} B、先頭 {offset:,} B 一致、{difference}", True))
    return results


def compare_attempt(case, root, attempt):
    reports = original_reports(case, root, attempt["run"] / "reports", attempt["verdict"])
    differences = [detail for _, detail, differs in reports if differs]
    if differences:
        attempt = {**attempt, "verdict": "不一致",
                   "reason": "、".join(filter(None, [attempt["reason"], *differences]))}
    return attempt, reports


def observed_summary(case, current, reports):
    case_id = case["id"]
    verdict, reason = current["verdict"], current["reason"]
    if verdict == "未実行":
        return "移行版は未実行"
    if verdict == "未判定":
        return "移行版の操作・照合を確定できず"
    if verdict == "一致" and case_id in MATCHED_ACTIONS:
        return MATCHED_ACTIONS[case_id]
    if verdict == "一致" and (warning := re.search(r"移行版の警告：(T-[0-9]{3}：[^、]+)", reason)):
        return f"{warning[1]} 対象画面へ進まず、保存差分なし"
    if verdict == "一致" and reason.startswith("条件画面到達：帳票未作成"):
        return "帳票条件画面に到達、帳票未作成（原本 0 B）"
    if verdict == "一致" and reason.startswith("旧証跡は"):
        return reason.replace("旧証跡は", "", 1) + "で一致、保存差分なし"
    if verdict == "一致" and reason.startswith("分析コード Z"):
        return reason + "、保存差分なし"
    if verdict == "対象外":
        program = re.fullmatch(r"到達先ヘッダに無い: (\w+)", reason)
        if program:
            return f"{program[1]} 画面に到達、旧証跡では未実施"
        if case_id == "PL-410":
            return "仕入分析コード登録画面で項目を入力、旧証跡に保存データの更新なし"
        if reason == "帳票出力が生成されていない":
            return "仕入先ファイル帳票画面に到達、旧証跡に帳票出力なし"
        return "移行版の画面に到達、旧証跡との照合は対象外"
    summaries = [summary for summary, _, _ in reports if summary]
    if verdict == "不一致" and reason.startswith("ledgers/") and ": 期待 " not in reason:
        summaries.append("保存データの照合で差分あり")
    if summaries:
        return "／".join(summaries)
    if verdict == "不一致":
        return comparison_note(reason) or "原本との照合で差分あり"
    number = int(case_id.removeprefix("PL-"))
    if 1 <= number <= len(MENU_SCREENS):
        screen = MENU_SCREENS[number - 1]
    else:
        screen = SCREEN_NAMES.get(case_id) or re.sub(r"^PL-\S+ |：到達確認$", "", case["title"])
    return f"「{screen}」画面に到達"


def csv_cell(value):
    return "'" + value if value.lstrip().startswith(("=", "+", "-", "@")) else value


def markdown_text(value):
    return "".join("\\" + char if char in string.punctuation else char
                   for char in " ".join(value.splitlines()))


def video_start(part, case, start):
    if case in part.get("caseStarts", {}):
        return part["offset"] + part["caseStarts"][case]
    return None if start is None else part["offset"] + start - part["trim"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("deliverables", type=Path)
    parser.add_argument("timeline", type=Path, help="run ディレクトリごとの trim と動画内 offset を記録した JSON")
    parser.add_argument("--diagnoses", type=Path, help="ケース ID ごとの原因・対処（JSON）")
    parser.add_argument("--sha", default="未 push")
    args = parser.parse_args()
    catalog = json.loads(evidence_path(args.evidence.resolve(), "scenarios/catalog.json").read_text())["cases"]
    cases = sorted((c for c in catalog if c["id"].startswith("PL-")), key=lambda case: case["id"])
    for case in cases:
        validate_case_id(case["id"])
    diagnoses = json.loads(args.diagnoses.read_text()) if args.diagnoses else {}
    history = defaultdict(list)
    for part in json.loads(args.timeline.read_text()):
        run = Path(part["run"])
        for case, result in read_run(run).items():
            result["start"] = video_start(part, case, result["start"])
            history[case].append({**result, "run": run})

    fields = ["ケースID", "移行後結果", "一致判定", "動画ファイル名", "動画開始時刻(秒)", "不一致原因・対処履歴"]
    verdict_counts = Counter()
    mismatches = []
    unverified = []
    excluded = []
    byte_checks = []
    supplier_rerun = []
    corrected = []
    with (args.deliverables / "ACAS-PL.csv").open("w", encoding="utf-8-sig", newline="") as output:
        writer = csv.writer(output)
        writer.writerow(fields)
        for case in cases:
            case_id = case["id"]
            attempts = [compare_attempt(case, args.evidence, attempt) for attempt in history[case_id]]
            current, reports = attempts[-1] if attempts else (dict(verdict="未実行", reason="", start=None), [])
            verdict = current["verdict"]
            verdict_counts[verdict] += 1
            details = [f"第{i}回：{item['verdict']}" + (f" — {comparison_note(item['reason'])}" if item["reason"] else "")
                       + (f"（{item['start']:.2f}秒）" if item["start"] is not None else "")
                       for i, (item, _) in enumerate(attempts, 1)]
            diagnosis = diagnoses.get(case_id, "")
            if diagnosis:
                details.append(diagnosis)
            seconds = current["start"]
            summary = observed_summary(case, current, reports)
            writer.writerow(map(csv_cell, [case_id, summary, verdict, VIDEO if seconds is not None else "",
                                           f"{seconds:.2f}" if seconds is not None else "", " / ".join(details)]))
            if case_id == "PL-090" and len(attempts) > 1 and seconds is not None:
                supplier_rerun = ["## PL-090 再実行", f"- {markdown_text(summary)}。{markdown_text(diagnosis)}\n"
                                  f"- 動画 `{VIDEO}` の最終再実行開始は **{seconds:.2f}秒**。各試行の履歴はCSVに記録。"]
            if verdict == "不一致":
                mismatches.append(f"- **{case_id}** {markdown_text(case['title'])}："
                                  + " / ".join(map(markdown_text, details)))
            if verdict == "一致" and diagnosis and len(attempts) > 1 and attempts[-2][0]["verdict"] == "不一致":
                corrected.append(f"- **{case_id}**：{markdown_text(diagnosis)}"
                                 + (f"（{seconds:.2f}秒）" if seconds is not None else ""))
            if verdict in ("未判定", "未実行"):
                unverified.append(f"- **{case_id}** {markdown_text(case['title'])}："
                                  + (" / ".join(map(markdown_text, details)) or verdict))
            if verdict == "対象外":
                excluded.append(f"- {case_id}：{markdown_text(case['legacy_result']['reason'])}")
            if reports:
                byte_checks.append(f"- {case_id}：{'、'.join(markdown_text(detail) for _, detail, _ in reports)}")
    sections = [
        "# 買掛元帳（PL）移行同一性確認",
        "・".join(f"{label} {verdict_counts[label]} 件" for label in ("一致", "不一致", "対象外", "未判定", "未実行")),
        f"push SHA: `{args.sha}`",
        *supplier_rerun,
        "## 不一致", "\n".join(mismatches) if mismatches else "なし",
        *(["## 修正後の再実行", "\n".join(corrected)] if corrected else []),
        "## 対象外", "\n".join(excluded) if excluded else "なし",
        "## 再判定と比較範囲",
        "\n".join(f"- {case_id}：{markdown_text(diagnoses[case_id])}"
                  for case_id in ("PL-222", "PL-232", "PL-414") if case_id in diagnoses) or "追加事項なし",
        "## 帳票照合", "\n".join(byte_checks) if byte_checks else "帳票原本なし",
        "## 未検証事項", "\n".join(unverified) if unverified else "照合未到達のケースなし。",
        "- 判定はケースごとの最終実行に基づく。再実行しなかったケースは前回の結果を引き継ぐ。"
        "\n- レガシーで実際に記録された操作段階までを比較し、未到達の業務処理や存在しない帳票原本を合格扱いしない。"
        "\n- レガシー未実施のみを対象外とし、実測のあるケースは証跡時点の画面・入力・保存差分・帳票を比較。"
        "\n- 保存データは SQLite ファイルそのものではなく、レガシーと共通のキー付き論理レコードの内容を比較。"
        "\n- PL-090 は SYS-001 のうち仕入先2件のみ。SYS-001 の他台帳と帳票は対象外。",
        "\n- 帳票作成前の PL-018・PL-228 は、旧版の空ファイルと iPad の未作成を同じ『帳票なし』の状態として比較。"
        "\n- SQLite と Berkeley DB のコンテナ構造や、対応できない型の全ファイルについてはバイト一致を確認していない。",
    ]
    (args.deliverables / "ACAS-PL.md").write_text("\n\n".join(sections) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
