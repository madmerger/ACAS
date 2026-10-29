# 04. COBOL データ型 → Java / SQL 対応表

対象: `copybooks/`・各サブシステムの `fd*.cob` / `ws*.cob` に現れる全 PIC/USAGE（`02-file-layouts.md` の codec 列はこの表に従う）。
バイト長は GnuCOBOL 3.1.2（`cobc --info`: binary-size 1-2-4-8、indexed = BDB）で `FUNCTION LENGTH` により実測・照合済み（`tools/verify_layout.sh`）。

## 1. 型対応表

| COBOL 定義（例） | 格納形式 / バイト長 | Java 型 | SQL 型 | 移行ツール codec | 出現数* |
|---|---|---|---|---|---:|
| `PIC X(n)` | 表示文字 n バイト | `String` | `CHAR(1)` / `VARCHAR(n)` | 右側空白を除去。キー項目は除去しない | 300+ |
| `PIC 9(n)`（n ≤ 4） | ゾーン 10 進 n バイト | `int` | `SMALLINT` | ASCII 数字 | 94 |
| `PIC 9(n)`（5 ≤ n ≤ 9） | ゾーン 10 進 n バイト | `int` | `INTEGER` | ASCII 数字 | 37 |
| `PIC 9(n)V9(m)` / `PIC S9(n)V9(m)` | ゾーン 10 進、符号は末尾オーバーパンチ（`SIGN LEADING` 指定時は先頭） | `BigDecimal`（scale = m） | `NUMERIC(n+m, m)` | ゾーン→BigDecimal（符号ニブル） | 17 |
| `PIC S9(n)V9(m) COMP-3` | パック 10 進 `(n+m)/2+1` バイト、末尾ニブル符号 | `BigDecimal`（scale = m） | `NUMERIC(n+m, m)` | packed decimal | 120 |
| `PIC 9(n)V9(m) COMP-3`（符号なし） | 同上 | `BigDecimal` | `NUMERIC(n+m, m)` | packed decimal（unsigned） | 8 |
| `PIC 9(n) COMP` / `S9(n) COMP` | **ビッグエンディアン** 2 進、桁数で 1/2/4/8 バイト（`999`→2、`9(5)`→4、`9(8)V99`→8） | `int` / `long` | `SMALLINT` / `INTEGER` / `BIGINT` | big-endian int | 30 |
| `PIC 99V99 COMP` 等（小数付き COMP） | ビッグエンディアン 2 進（暗黙小数点） | `BigDecimal`（unscaled 値 ÷ 10^m） | `NUMERIC(p, m)` | big-endian int + scale | 27 |
| `BINARY-CHAR` [`UNSIGNED`] | 1 バイト（既定は符号付き） | `int`（`byte` は使わない） | `SMALLINT` | int8 / uint8 | 36 |
| `BINARY-SHORT` | **ネイティブ（x86_64 = リトルエンディアン）** 2 バイト | `short` | `SMALLINT` | LE int16 | 15 |
| `BINARY-LONG` [`UNSIGNED`] | ネイティブ LE 4 バイト | `int`（unsigned は `long`） | `INTEGER` / `BIGINT` | LE int32 | 74 |
| `BINARY-LONG` で名前に *date* を含む | COBOL 整数日付（下記 §3） | `LocalDate`（0 → `null`） | `DATE` | `FUNCTION DATE-OF-INTEGER` 相当 | — |
| `OCCURS n` | n 回の連続領域 | `List<T>` / 配列 | 子テーブル（親 PK + `seq_no`） | 繰り返しデコード | — |
| `REDEFINES` | 同一領域の別ビュー | 主定義のみ保持（別ビューは getter で導出） | 列化しない | 主定義でデコード | — |
| `88` レベル | 値の条件名 | `enum` / `boolean` メソッド | `CHECK` 制約候補 | — | — |
| `FILLER` | 予備領域 | 保持しない | 列化しない | スキップ（空白/ゼロ以外ならログ） | — |

\* 出現数は `02-file-layouts.md` 掲載のファイルレコード（データ移行対象）内の項目数。

注意:
- `COMP`（= `BINARY`、ビッグエンディアン）と `BINARY-SHORT/LONG`（ネイティブ）は**エンディアンが逆**。同じレコード内に混在する（例: `Sales-Record` の `Sales-Discount PIC 99V99 COMP` と `Sales-Limit BINARY-LONG`）。データ移行ツールは項目単位で codec を切り替える。
- ネイティブ型は実行マシン依存のため、データファイルを作成したマシンのアーキテクチャ（本環境は x86_64 = LE）を移行ツールの入力パラメータにする。
- パック 10 進の符号ニブル（正 `C` / 負 `D` / 符号なし `F`）とゾーン 10 進のオーバーパンチ文字は、Phase 1 で GnuCOBOL が書いた実データとの往復テスト（COBOL で書く→Java で読む→Java で書く→COBOL で読む）で確定させる。

## 2. 数値演算・丸めの再現ルール（Java 実装規約）

| COBOL の挙動 | Java での再現 |
|---|---|
| `COMPUTE`/`MULTIPLY`/`DIVIDE` で `ROUNDED` なし → 受け側の小数桁で**切り捨て** | `setScale(m, RoundingMode.DOWN)` |
| `ROUNDED`（GnuCOBOL 既定 = NEAREST-AWAY-FROM-ZERO） | `setScale(m, RoundingMode.HALF_UP)` |
| 受け側の整数桁を超える値 → 上位桁が**切り捨て**（`ON SIZE ERROR` 無し時） | `CobolNumeric.truncateHigh(value, intDigits)` を共通ユーティリティとして用意し明示的に呼ぶ |
| 符号なし項目への負値 MOVE → 絶対値が格納される | `abs()` を明示 |
| 中間結果の精度（GnuCOBOL は十分大きい精度で中間計算） | `BigDecimal` で計算し、代入時のみ上記ルールを適用（`double` は使わない） |
| `PIC 99V99 COMP` 等の 2 進小数（VAT 率・割引率） | unscaled int と scale を保持し `BigDecimal` に変換 |

Phase 5 で `ROUNDED` 有無・桁あふれ・負値を含む計算（VAT、割引、残高集計）を COBOL/Java 比較ケースとして `cases.json` に入れる。

## 3. 日付・時刻（`wstime.cob`、`maps04.cbl`）

| COBOL | 意味 | Java |
|---|---|---|
| `BINARY-LONG` の日付項目（`Run-Date`、`Sales-Create-Date`、`invoice-date`、`pay-date` 等） | `FUNCTION INTEGER-OF-DATE` の値（1 = 1601-01-01）。`maps04.cbl:152/170` が `INTEGER-OF-DATE` / `DATE-OF-INTEGER` で変換 | `LocalDate.of(1600, 12, 31).plusDays(n)`、逆変換は `ChronoUnit.DAYS.between`。0 は未設定 → `null` |
| `ws-time.wsa-date`（`PIC 9(6)` YYMMDD） | `ACCEPT ... FROM DATE`（2 桁年） | 世紀補完は COBOL と同じ規則で実装し、比較テストで確認 |
| `wse-date-block`（`9(8)` YYYYMMDD + hhmmss） | `FUNCTION CURRENT-DATE` 先頭部 | `LocalDateTime`（テスト時は `Clock` 注入で固定） |
| 画面上の日付文字列 `x(10)` | `System-Record` の日付形式（UK `dd/mm/yyyy`、USA `mm/dd/yyyy`、Intl `yyyy/mm/dd`）に従い `maps04` が検証・変換 | `DateFormatService`（`maps04` 移植）で形式ごとに parse/format。不正日付は COBOL と同じエラーコードを返す |

## 4. 文字列

- `PIC X` は ASCII/Latin-1 前提。移行ツールは ISO-8859-1 でデコードし、RDB は UTF-8 で格納する。
- 大文字化（`FUNCTION UPPER-CASE`）・左右寄せ・空白埋めは表示ロジックではなくキー生成（例: 顧客キー 6 桁 + チェックデジット、`maps09`）に使われる箇所があり、サービス層に移す。
