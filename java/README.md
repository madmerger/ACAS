# ACAS Web 版（Spring Boot 3 / Java 21）

レガシー GnuCOBOL 版 ACAS（システム設定、総勘定元帳、売掛元帳、買掛元帳、在庫管理、簡易会計）の Web 版です。
業務メニューはボタン、入力はフォーム、一覧はテーブル、帳票はダイアログで操作します。業務データは H2 に保存します。

## ビルドと起動

```
cd java
mvn package                      # Java 21 が必要
java -jar target/acas-web-1.0.0.jar      # http://localhost:8080/
```

| プロパティ | 既定 | 説明 |
|---|---|---|
| `acas.data-dir` | `./data` | H2 データベースの保存先 |
| `server.address` | `127.0.0.1` | 待ち受けアドレス。ループバック以外ではサーバー側で TLS を構成 |
| `ACAS_WEB_PASSWORD_HASH` | 空 | Web 利用者 `acas` の BCrypt パスワードハッシュ。未設定時はログイン不可 |
| `acas.initial-baseline` | 空 | DB が空のとき投入する初期データ名。検証用途では `biz` 等を指定 |
| `acas.test-api` | `false` | 同一性検証モード。ループバックの待ち受けとインメモリの H2 を指定して起動 |
| `ACAS_TEST_API_TOKEN` | 空 | 同一性検証モードの全リクエストを認証する32文字以上のトークン。半角英数字・記号を使い、空白は含めない。サーバーと再生スクリプトに同じ値を渡す |
| `acas.fixed-date` | なし | システム日付の固定（`yyyy-MM-dd`、検証用） |

## 構成

- `jp.co.acas.core` … COBOL 実行モデルの移植基盤
  - `Layout` / `Rec`: Maven が既存の COBOL ソースツリーから取り込むコピー句を解析し、固定長レコードを保持
  - `CobFile` / `Store`: 索引・相対・順・行順ファイルの入出力（FILE STATUS 互換）。H2 に保存
  - `Terminal`: レガシーの対話状態を保持し、照合用テキストとフォーム・選択肢・表示項目を出力
  - `Messages`: 英語から日本語への文言対応表（`resources/i18n/*.tsv`）
  - `Program` / `Ctx`: COBOL 1 プログラム = 1 クラス。`call("gl030")` は `jp.co.acas.<sys|gl|sl|pl|st|irs|calc>.Gl030` を呼ぶ
- `jp.co.acas.web` … REST API（`/api/sessions` ほか）と静的 UI（`resources/static/`）
- `jp.co.acas.sys|gl|sl|pl|st|irs|calc` … 各サブシステムの業務プログラム
- `tools/` … ベースライン変換（`dump_baselines.py`）、同一性確認ハーネス（`replay.py`）

## 移植規約（実装者向け）

1. COBOL プログラム `xx999.cbl` → クラス `jp.co.acas.<pkg>.Xx999 extends Program`。段落の流れ・入力順・キー判定を原文どおりに移す。
2. 固定文言は **英語原文のまま** `display(line, col, "原文")` に渡す（英語面に原文、日本語面に対応表の訳が出る）。
   データ（レコード値・数値・日付）は `show(line, col, 値)` で表示する（翻訳しない）。
   文言＋データを連結した 1 つの DISPLAY は、文言部分と値部分に分けて同じ桁位置へ出す。
   SCREEN SECTION の画面は、固定文言を `display`、項目値を `show` で描画し、入力項目（USING / TO）を
   `acceptScreen(List.of(field(line, col, size, 値), ...))` で受ける（TAB で次項目、ENTER で確定。結果は各 `Field.value`）。
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

同一性確認の手順は、検証 API と再生スクリプトを含む [同一性テストの実行基盤](https://github.com/madmerger/ACAS/pull/27) を統合した構成で実行します。DB は既定でファイル保存されるため、以下の起動引数でインメモリ H2 に切り替えます。

```
java -jar target/acas-web-1.0.0.jar --server.port=18080 --acas.test-api=true \
     --acas.fixed-date=2026-11-23 --spring.datasource.url='jdbc:h2:mem:acas;DB_CLOSE_DELAY=-1'
ACAS_VIDEO=web.mp4 python3 tools/ui_replay.py <証跡展開dir> --out 結果.json GL-020 SL-
```

ブラウザーで操作を再生し、同じ業務処理が出力する照合用テキスト、レコードの差分、帳票をレガシー実測と比較します。
実行前に、サーバーと再生スクリプトを起動する環境に同じ `ACAS_TEST_API_TOKEN` を設定してください。
録画には Playwright の Chromium と FFmpeg が必要です。レガシー側の入力制限に合わせて、業務フォームは半角文字を受け付けます。
