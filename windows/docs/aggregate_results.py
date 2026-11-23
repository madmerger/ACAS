import argparse
from collections import Counter, defaultdict
from datetime import datetime, timedelta
import json
import math
from pathlib import Path

from openpyxl import load_workbook


GROUPS = {"SYS": 1, "GL": 1, "SL": 2, "PL": 3, "ST": 4, "IRS": 4, "INT": 4, "CALC": 5}
VERDICTS = ("一致", "不一致", "対象外", "未検証")


def read_json(path):
    return Path(path).read_text(encoding="utf-8-sig")


def results(path, ledger):
    rows = json.loads(read_json(path))
    if not isinstance(rows, list) or not rows:
        raise ValueError(f"{path}: 結果は空でない JSON 配列で指定してください")
    seen = set()
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError(f"{path}: 結果配列にオブジェクト以外の値があります")
        case_id = row.get("id")
        if not isinstance(case_id, str) or case_id not in ledger or case_id in seen:
            raise ValueError(f"{path}: 不明または重複するケース ID: {case_id}")
        seen.add(case_id)
        case = ledger[case_id]
        verdict = row.get("verdict")
        excluded = case["legacy_result"]["verdict"] == "未実施"
        if (row.get("group") != GROUPS[case["subsystem"]] or row.get("subsystem") != case["subsystem"]
                or verdict not in VERDICTS or (verdict == "対象外") != excluded
                or row.get("source") == "旧移植版・参考"):
            raise ValueError(f"{path}: 台帳に合わない結果、または旧移植版の参考値: {case_id}")
        if any(not isinstance(row.get(key), str) for key in ("result", "reason", "source")):
            raise ValueError(f"{path}: result、reason、source は文字列で指定してください: {case_id}")
        seconds = row.get("videoSeconds")
        if seconds is not None and (type(seconds) not in (int, float) or not math.isfinite(seconds) or seconds < 0):
            raise ValueError(f"{path}: 無効な videoSeconds: {case_id}")
    return {row["id"]: row for row in rows}


def put_text(cell, value):
    cell.value = value
    cell.data_type = "s"


def append(sheet, values):
    sheet.append(values)
    for cell in sheet[sheet.max_row]:
        if isinstance(cell.value, str):
            cell.data_type = "s"


def aggregate(args):
    ledger = {case["id"]: case for case in json.loads(read_json(args.ledger))["cases"]}
    selected = {}
    for group, path in enumerate(args.results, 1):
        rows = results(path, ledger)
        if set(rows) != {key for key, case in ledger.items() if GROUPS[case["subsystem"]] == group}:
            raise ValueError(f"{path}: グループ {group} の全ケースが必要です")
        selected.update({key: (row, Path(path).resolve()) for key, row in rows.items()})
    for path in args.rerun:
        selected.update({key: (row, Path(path).resolve()) for key, row in results(path, ledger).items()})

    known = {Path(path).resolve() for path in args.results + args.rerun}
    videos = {}
    for path, filename, start, offset in args.video:
        source = Path(path).resolve()
        started = datetime.fromisoformat(start)
        delay = float(offset)
        if source not in known or source in videos or started.utcoffset() is None or not math.isfinite(delay) or delay < 0:
            raise ValueError(f"{path}: 録画指定が無効または重複しています")
        videos[source] = filename, started, delay

    book = load_workbook(args.template)
    detail = book["テストシナリオ一覧"]
    ids = [detail.cell(i, 1).value for i in range(2, detail.max_row + 1)]
    if len(ids) != len(ledger) or set(ids) != set(ledger):
        raise ValueError("Excel のケース ID と台帳が一致しません")
    sheets = {
        "Windows集計": ["サブシステム", "件数", *VERDICTS],
        "Windows_不一致": ["ケースID", "サブシステム", "名称", "結果", "理由"],
        "Windows_対象外": ["ケースID", "サブシステム", "名称", "理由"],
        "Windows_未検証": ["ケースID", "サブシステム", "名称", "理由"],
        "Windows動画時刻": ["ケースID", "グループ", "名称", "判定", "動画",
                         "録画開始時刻", "ドライバ起動からの秒数", "動画内開始秒", "ケース開始時刻", "結果JSON"],
    }
    for name, headers in sheets.items():
        if name in book:
            del book[name]
        sheet = book.create_sheet(name)
        sheet.append(headers)
        sheet.freeze_panes = "A2"

    put_text(detail["S1"], "移行後結果")
    put_text(detail["T1"], "一致判定")
    counts = defaultdict(Counter)
    for index, key in enumerate(ids, 2):
        row, path = selected[key]
        case = ledger[key]
        verdict = row["verdict"]
        system, title = case["subsystem"], case["title"]
        result = " ／ ".join(x for x in (row["result"], row["reason"]) if x) or verdict
        put_text(detail.cell(index, 19), result)
        put_text(detail.cell(index, 20), verdict)
        counts[system][verdict] += 1
        if verdict == "不一致":
            append(book["Windows_不一致"], [key, system, title, row["result"], row["reason"]])
        if verdict in ("対象外", "未検証"):
            append(book[f"Windows_{verdict}"], [key, system, title, row["reason"]])

        seconds = row.get("videoSeconds")
        if seconds is not None:
            video, started, delay = videos.get(path, ("", None, 0))
            video_seconds = round(seconds + delay, 3) if started is not None else None
            case_start = (started + timedelta(seconds=video_seconds)).isoformat(timespec="milliseconds") if started else ""
            append(book["Windows動画時刻"], [key, row["group"], title, verdict, video,
                   started.isoformat(timespec="milliseconds") if started else "", seconds, video_seconds, case_start, path.name])

    for system, count in sorted(counts.items()) + [("合計", sum(counts.values(), Counter()))]:
        append(book["Windows集計"], [system, sum(count.values()), *(count[v] for v in VERDICTS)])
    for name in sheets:
        book[name].auto_filter.ref = book[name].dimensions
    if Path(args.template).resolve() == Path(args.out).resolve():
        raise ValueError("入力 Excel と出力 Excel は別のパスを指定してください")
    book.save(args.out)
    print(f"{len(selected)} cases: {args.out}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--template", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--results", nargs=5, required=True, metavar=("GROUP1", "GROUP2", "GROUP3", "GROUP4", "GROUP5"))
    parser.add_argument("--rerun", action="append", default=[], metavar="JSON")
    parser.add_argument("--video", nargs=4, action="append", default=[],
                        metavar=("JSON", "VIDEO", "START_ISO8601", "DRIVER_DELAY_SECONDS"))
    try:
        aggregate(parser.parse_args())
    except (OSError, ValueError, KeyError) as error:
        parser.exit(2, f"{error}\n")
