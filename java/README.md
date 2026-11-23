# ACAS Web 版（Spring Boot 3 / Java 21）

レガシー GnuCOBOL 版 ACAS（システム設定 / GL / SL / PL / 在庫 / IRS）を、サーバー側に業務ロジックと DB（H2）を持つ
Web アプリへ移行したもの。画面・メニュー・メッセージ・帳票は日本語で表示し、メニュー階層・キー・入力順・計算・データ更新は
レガシーと同一に保つ。

## ビルドと起動

```
cd java
mvn package                      # Java 21 が必要
java -jar target/acas-web-1.0.0.jar      # http://localhost:8080/
```

| プロパティ | 既定 | 説明 |
|---|---|---|
| `acas.data-dir` | `./data` | H2 データベースの保存先 |
| `acas.initial-baseline` | `biz` | DB が空のとき投入する初期データ（`empty` で投入なし） |
| `acas.test-api` | `false` | 同一性確認用 API（`/api/test/**`）を有効化。本番では無効のままにする |
| `acas.fixed-date` | なし | システム日付の固定（`yyyy-MM-dd`、検証用） |

## 構成

- `jp.co.acas.core` … COBOL 実行モデルの移植基盤
  - `Layout` / `Rec`: コピー句（`resources/copybooks/`）を実行時に解析し、固定長レコードをレガシーと同じバイト列で保持
  - `CobFile` / `Store`: 索引・相対・順・行順ファイルの入出力（FILE STATUS 互換）。H2 に保存
  - `Terminal`: 80x24 画面。レガシー原文（英語）面と日本語面の 2 面を持ち、ブラウザには日本語面を表示
  - `Messages`: 英語→日本語の文言対応表（`resources/i18n/*.tsv`、画面 `/messages.html` で閲覧可能）
  - `Program` / `Ctx`: COBOL 1 プログラム = 1 クラス。`call("gl030")` は `jp.co.acas.<sys|gl|sl|pl|st|irs|calc>.Gl030` を呼ぶ
- `jp.co.acas.web` … REST API（`/api/sessions` ほか）と静的 UI（`resources/static/`）
- `jp.co.acas.sys|gl|sl|pl|st|irs|calc` … 各サブシステムの業務プログラム
- `tools/` … ベースライン変換（`dump_baselines.py`）、同一性確認ハーネス（`replay.py`）

## 移植規約（実装者向け）

1. COBOL プログラム `xx999.cbl` → クラス `jp.co.acas.<pkg>.Xx999 extends Program`。段落の流れ・入力順・キー判定を原文どおりに移す。
2. 固定文言は **英語原文のまま** `display(line, col, "原文")` に渡す（英語面に原文、日本語面に対応表の訳が出る）。
   データ（レコード値・数値・日付）は `show(line, col, 値)` で表示する（翻訳しない）。
   文言＋データを連結した 1 つの DISPLAY は、文言部分と値部分に分けて同じ桁位置へ出す。
3. 訳語は `resources/i18n/<pkg>.tsv`（`英語<TAB>日本語`）へ追加。日本語の表示幅（全角 = 2 桁）は原文の桁数以下にする。
   `GET /api/test/untranslated` が空になること。エラーコード（`SL003` 等）は訳文でも保持する。
4. レコードは `Layout.of("copybooks/fdsl.cob", "sales-record").newRec()` のようにコピー句から生成し、
   `rec.str/num/set/setNum/setRounded` で読み書きする。COMPUTE の丸め有無（ROUNDED）と桁あふれ切捨ては原文に合わせる。
5. ファイルは `CobFile.indexed(ctx.store, ctx.path("salesled.dat"), rec, "sales-key")` 等で開く。
   ファイル名は `copybooks/wsnames.cob` の論理名（`ledger.dat`、`prt-1` など）を使う。IRS は `ctx.irsPath(...)`。
6. 帳票は行順ファイル（`prt-1` 等）へ `writeLine` し、印刷指示（lpr 呼出し）は `ctx.spool(file, command)`。
   帳票の固定文言も対応表で日本語化される（`/reports.html`）。
7. 共有システムレコードは `SystemFile.shared(ctx)`、日付変換は `Maps04`、チェックディジットは `Maps09`。

## 同一性確認

```
java -jar target/acas-web-1.0.0.jar --server.port=18080 --acas.test-api=true \
     --acas.fixed-date=2026-11-23 --acas.data-dir=/tmp/acas-test
python3 tools/replay.py <証跡展開dir> -v GL-020 SL-        # ID または接頭辞（末尾 -）
```

レガシー実測（`runs/<ケース>/` の画面テキスト・レコード差分・帳票）と、Web 版の英語原文面・レコード 16 進・帳票を比較する。
