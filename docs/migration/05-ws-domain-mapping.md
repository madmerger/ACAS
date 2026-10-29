# 05. 共通データ構造（`ws*.cob`）→ Java ドメインクラス / DTO 対応表

Java パッケージ（予定）: `java/` 配下の Spring Boot プロジェクト `com.acas` 以下。`domain` = JPA エンティティ、`dto` = REST 入出力、`service` = 移植したロジック、`legacy` = COBOL 互換レイヤ（codec・ファイル状態コード等）。
「利用数」は当該ファイル名を `COPY` しているプログラム数（同名の IRS 版を含む）。

## 1. システム共通（`copybooks/`）

| copybook | レコード（バイト） | 利用数 | 内容 | Java 対応 | 種別 |
|---|---|---:|---|---|---|
| `wssystem.cob` | `System-Record` (1024) | 108 | 会社情報、VAT 率 ×5、期間/サイクル、運用日付、ユーザー権限レベル、OS/ファイルシステム種別、RDB 接続情報、GL/PL/SL/Stock/IRS 各設定 | `domain.SystemParameter`（+ `@Embeddable` `VatRates`、`LedgerSettings` 等に分割）／`dto.SystemSettingsDto` | Entity（1 行） |
| `wsdflt.cob` | `Default-Record` (231) | 21 | 既定勘定科目・コード・VAT コード（OCCURS） | `domain.DefaultAccounts` + 子 `DefaultAccount`、`DefaultCode`、`DefaultVat` | Entity |
| `wsfinal.cob` | `Final-Record` (416) | 13 | 決算書レイアウト定義（OCCURS） | `domain.FinalAccountsLayout` + 子 | Entity |
| `wssys4.cob` | `System-Record-4` (1024) | 16 | 追加システム設定（第 4 レコード） | `domain.SystemParameterExt` | Entity（1 行） |
| `wscall.cob` | `ws-calling-data` (28) | 95 | プログラム間呼び出しパラメータ（呼出し元、終了コード `ws-term-code`、パス値） | `service.CallContext`（record）— REST ではリクエストスコープの文脈に置換 | DTO / 値オブジェクト |
| `wsfnctn.cob` | `File-Access` (628) | 124 | ファイル操作要求（function: open/read/write/rewrite/delete/start、アクセス種別、キー、RRN、DB/SQL エラー） | **移植しない**。Spring Data リポジトリ呼び出しに置換。エラー情報のみ `legacy.FileStatus`（`fs-reply` 互換コード）として残す | — |
| `wsnames.cob` | `file-defs` (16492) | 96 | 物理ファイル名 file-0〜file-33 とパス | `config.AcasFileProperties`（`@ConfigurationProperties`、データ移行ツールの入力パス） | 設定 |
| `wstime.cob` | `ws-time` (22) / `wse-date-block` (21) | 5 | 現在日時の分解 | `java.time` + `Clock` 注入 | 標準ライブラリ |
| `wsmaps01.cob` | `maps01-ws` (37) | 15 | パスワード/暗号化（`maps01`）の入出力 | `service.PasswordService`（**ハッシュ化に置換**。§3 参照） | Service I/F |
| `wsmaps03.cob` | `maps03-ws` (14) | 70 | 日付変換（`maps04`）の入出力 | `service.DateFormatService`（`LocalDate` ⇔ 表示文字列） | Service I/F |
| `wsmaps09.cob` | `maps09-ws` (8) | 11 | 顧客/仕入先キーのチェックデジット（`maps09`） | `service.AccountKeyService.checkDigit()` | Service I/F |
| `wsstock.cob` | `WS-Stock-Record` (400) | 2 | 在庫レコードの WS 版（`fdstock` と同一レイアウト） | `domain.StockItem`（共用） | Entity |
| `screenio.cpy` | 定数のみ | 多数 | F1–F60 等のキーコード、色定数 | フロントエンド側のキー割当のみ。サービス層では使わない | — |
| `print-spool-command*.cob` | 定数/コマンド | 61 (印刷系) | `lpr` 印刷コマンド構築 | `report.ReportService`（PDF 生成）に置換 | Service |

## 2. サブシステム固有

| copybook | レコード（バイト） | 内容 | Java 対応 |
|---|---|---|---|
| `sales/wsoi.cob` | `oi-header` (114) | 売掛オープンアイテム（openitm2/3 の実体） | `sales.domain.SalesOpenItem` |
| `sales/wssoi.cob` | `si-header` (114) | ソート用オープンアイテム | 同上（ソートは JPA クエリの `ORDER BY` に置換） |
| `sales/wsinv.cob` | `sinvoice-header` (137) + `sInvoice-Bodies` (3200 = 40 行 × 80) | 請求書入力中のヘッダ＋明細配列 | `sales.dto.InvoiceDraftDto`（header + `List<InvoiceLineDto>` 最大 40） |
| `purchase/wsoi.cob` | `oi-header` (109) | 買掛オープンアイテム | `purchase.domain.PurchaseOpenItem` |
| `purchase/wssoi.cob` | `si-header` (109) | ソート用 | 同上 |
| `purchase/wspinv.cob` | `invoice-header` (100) + `Pinvoice-lines` (3000) | 仕入請求書入力中 | `purchase.dto.PurchaseInvoiceDraftDto` |
| `general/wspc.cob` | `p-c-branches` (107) | プロフィットセンター/支店表 | `gl.domain.ProfitCentre`（`gl_ledger.ledger_pc` と対応） |
| `general/wspint.cob` | `posting-array` (990) | 仕訳入力中の配列 | `gl.dto.PostingBatchDto` |
| `incomplete_records_system/wssystem.cob` | `system-record` (312) | IRS 専用システム設定（ACAS 版とは別形式） | `irs.domain.IrsSystem` |
| `incomplete_records_system/wsnl.cob` | `nl-record` (116) | IRS 勘定（owning/sub、REDEFINES） | `irs.domain.NominalAccount` |
| `incomplete_records_system/wspost.cob` | `posting-record` (79) | IRS 仕訳 | `irs.domain.IrsPosting` |
| `incomplete_records_system/wsdflt.cob` / `wsfinal.cob` | 256 / 655 | IRS 既定科目 / 決算書 | `irs.domain.IrsDefaults` / `IrsFinalAccounts` |
| `incomplete_records_system/wsfnctn.cob` | `file-access` (54) | IRS 版ファイル操作要求 | 移植しない（リポジトリに置換） |

## 3. 移植時の設計ルール

1. **ファイル I/O 抽象（`File-Access` + `fs-reply`）はリポジトリに置換**する。COBOL の `fs-reply`（"00"/"23"/"10" 等）に依存した分岐は、`Optional`/例外に読み替え、比較テストでは `legacy.FileStatus` に再変換して出力を合わせる。
2. **画面専用項目と業務項目を分ける**: `ws*.cob` のうち画面表示用（編集済み数値 `Z(n)9.99`、表示文字列）は DTO/フロントエンド、計算・判定に使う項目はドメイン/サービスへ。
3. **`System-Record` は単一行エンティティ**として扱い、各サービスには必要な部分（VAT 率、期間、日付形式）だけを `@Embeddable` 単位で注入する。
4. **セキュリティ**: `System-Record` の `Pass-Word x(4)` やメニュー権限レベル（`Level-1..6`）は平文・短長。Java 側では平文を移行せず、Spring Security のパスワードハッシュ（BCrypt）＋ロールに置換する（初回ログイン時にパスワード再設定）。IRS メニューの `|`（任意プログラム名を CALL）は移植しない。
5. 1 プログラム = 1 サービスクラス、COBOL 段落 = private メソッド（`aa010-...` → `aa010...()`）とし、メソッドの Javadoc に元段落名と行番号を記載する（Phase 3）。
