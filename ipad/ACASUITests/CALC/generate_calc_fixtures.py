"""基盤が生成したケース台帳から、CALC の実 UI テスト入力を作る。"""
import argparse
import json
import re
from pathlib import Path


FUNCTIONS = {
    "drv09": ("checkDigit", ("code",)),
    "drv04": ("date", ("date",)),
    "drvvat": ("vat", ("net", "rate")),
    "drvage": ("age", ("days",)),
    "drvavg": ("average", ("value", "qty")),
}
EXCLUDED_TITLES = (
    "初回セットアップ後の自動ログイン",
    "設定保存後の再読込",
    "誤パスワードによる認証エラー",
    "正しいパスワードでの認証",
    "６回目の誤パスワードによる制限",
    "パスワード変更後の旧トークン無効化",
    "未初期化での設定照会",
    "接続停止時の案内と再試行",
    "トップメニューの到達",
    "売掛元帳の到達",
    "買掛元帳の到達",
    "総勘定元帳の到達",
    "在庫管理の到達",
    "簡易記帳の到達",
)


def display_values(function, actual):
    def text(value):
        return json.dumps(value) if isinstance(value, bool) else str(value)

    if function == "checkDigit":
        return {"calculation.result": text(actual["check"]), "calculation.valid": "有効なコードです"} \
            if actual["valid"] else {"calc.invalidCode": "入力したコードは無効です"}
    if function == "date":
        if not actual["valid"]:
            return {"calc.invalidDate": "入力した日付は無効です"}
        day, month, year = actual["normalized"].split("/")
        return {
            "calc.result.normalized": f"{year}年{month}月{day}日",
            "calc.result.serial": text(actual["integer"]),
        }
    if function == "vat":
        return {"calc.result.tax": actual["vat"]}
    if function == "age":
        return {"calc.result.bucket": f'{actual["bucket"]}日'}
    return {"calc.result.cost": actual["cost"]}


def build(case, excluded_titles):
    legacy = case["legacy_result"]
    if legacy["verdict"] == "未実施":
        return {"id": case["id"], "title": next(excluded_titles)}
    function, keys = FUNCTIONS[case["programs"][0]]
    title = case["title"].split(" ", 1)[1].replace("VAT", "付加価値税").replace("ディ9ジット", "ディジット")
    if function == "date":
        title = re.sub(r"([0-9A-Z]{1,2})[/.,-](\d{1,2})[/.,-](\d{2,4})(/?)",
                       lambda m: f"{m[3]}年{m[2]}月{m[1]}日" + ("（末尾区切り）" if m[4] else ""),
                       title.removesuffix(" (末尾区切り)"))
    actual = legacy["actual"]
    expected = {}
    for key, value in actual.items():
        if key == "vat":
            key = "tax"
        expected[key] = "" if value is None else json.dumps(value) if isinstance(value, bool) else str(value)
    return {
        "id": case["id"],
        "title": title,
        "function": function,
        "inputs": [str(case["input_data"][key]) for key in keys],
        "expected": expected,
        "visible": display_values(function, actual),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ledger", type=Path)
    parser.add_argument("--only", nargs="+", help="個別再試験のケース ID")
    args = parser.parse_args()
    cases = [case for case in json.loads(args.ledger.read_text(encoding="utf-8")) if case["subsystem"] == "CALC"]
    ids = {case["id"] for case in cases}
    if len(cases) != 123 or len(ids) != 123 or sum(c["legacy_result"]["verdict"] == "未実施" for c in cases) != 14:
        parser.error("CALC 台帳の件数が一致しません")
    if args.only and not set(args.only) <= ids:
        parser.error("台帳にないケース ID")
    excluded_titles = iter(EXCLUDED_TITLES)
    fixtures = [build(case, excluded_titles) for case in cases]
    if args.only:
        fixtures = [case for case in fixtures if case["id"] in args.only]
    output = args.ledger.parent / "fixtures" / "calc-suite.json"
    output.write_text(json.dumps(fixtures, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"CALC 実 UI 用データ {len(fixtures)} 件（対象外 {sum('expected' not in c for c in fixtures)} 件）")


if __name__ == "__main__":
    main()
