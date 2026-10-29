# 03. RDB スキーマ設計

- DDL: [`schema/acas-schema.sql`](schema/acas-schema.sql)（PostgreSQL 方言、`tools/gen_schema.py` で `02-file-layouts.md` と同じレイアウト解析結果から生成。SQLite で構文検証済み、43 テーブル）。
- Phase 1 ではこの DDL を Flyway の `V1__init.sql` の初版とし、JPA エンティティを対応させる（H2/PostgreSQL で起動検証）。

## 1. 変換ルール

| COBOL の構造 | RDB での扱い | 理由 |
|---|---|---|
| INDEXED ファイルの RECORD KEY | `PRIMARY KEY`（キーグループの各要素を列に分解） | 例: `ledger-key` → `(ledger_nos, ledger_pc)` |
| ALTERNATE RECORD KEY | `UNIQUE INDEX`（`WITH DUPLICATES` は通常 `INDEX`） | `stock` の `Stock-Abrev-Key`（一意）、`Stock-Desc`（重複可） |
| RELATIVE ファイル | 業務キーがあればそれを PK（`posting.dat` → `(batch, post_number)`）。`system.dat` は RRN 1–4 の別レコードを **4 つの単一行テーブル**に分割 | RRN は物理位置であり業務上の意味を持たない |
| SEQUENTIAL ファイル | サロゲートキー `id`（ファイル内の出現順を保持） | `staudit.dat`、`postings2irs.dat`、削除番号ファイル |
| 1 ファイルに複数レコード型（ヘッダ/明細） | **テーブルを分割** | `invoice.dat` は `item-nos = 0` がヘッダ、1–40 が明細 → `sl_invoice_header` / `sl_invoice_line` |
| 同一レイアウトで状態だけ違うファイル | 別テーブル（転記前 = `*_open_item_staging`、サロゲート id。転記処理で staging → 本表へ移す） | `openitm2.dat`/`openitm4.dat`（転記前、順次）と `openitm3.dat`/`openitm5.dat`（転記済、索引）は同じ `oi-header` だがキー空間を共有しないため |
| OCCURS | 子テーブル（親 PK + `seq_no`、FK 付き） | `pay-record` の支払明細 ×9 → `pl_payment_line` |
| REDEFINES | 主定義のみ列化 | 別ビュー（例: 四半期売上の配列ビュー）は Java の getter で導出 |
| FILLER | 列化しない | |
| 金額 `COMP-3` | `NUMERIC(p, s)`（PIC の桁数そのまま） | 桁あふれ挙動を Java 側で再現するため精度を広げない |
| `BINARY-LONG` の日付 | `DATE`（COBOL 整数日付から変換、0 → NULL） | `04-type-mapping.md` §3 |
| 作業ファイル（`oisort.wrk`、`poisort.wrk`、`work.tmp` 等） | 移行対象外 | 処理中のみ使用 |

## 2. テーブル一覧

| テーブル | 元ファイル | 元レコード | 列数 | PK | 子テーブル（OCCURS） |
|---|---|---|---:|---|---|
| `system_record` | system.dat RRN 1 | `System-Record (copybooks/wssystem.cob)` | 139 | id | `system_record_file_status` |
| `default_record` | system.dat RRN 2 | `Default-Record (copybooks/wsdflt.cob)` | 1 | id | `default_record_def_acs`, `default_record_def_codes`, `default_record_def_vat` |
| `final_record` | system.dat RRN 3 | `Final-Record (copybooks/wsfinal.cob)` | 1 | id | `final_record_ar1` |
| `system_record_4` | system.dat RRN 4 | `System-Record-4 (copybooks/wssys4.cob)` | 21 | id | - |
| `gl_ledger` | ledger.dat | `ledger-record (general/fdledger.cob)` | 12 | ledger_nos, ledger_pc | - |
| `gl_posting` | posting.dat | `posting-record (copybooks/fdpost.cob)` | 14 | batch, post_number | - |
| `batch` | batch.dat | `batch-record (copybooks/fdbatch.cob)` | 22 | ledger, batch_nos | - |
| `irs_interface_posting` | postings2irs.dat (sequential, surrogate id) | `irs-posting-record (copybooks/fdpost-irs.cob)` | 12 | id | - |
| `stock_audit` | staudit.dat (sequential, surrogate id) | `Stock-Audit-Record (copybooks/fdaudit.cob)` | 12 | id | - |
| `stock` | stockctl.dat | `Stock-Record (copybooks/fdstock.cob)` | 34 | stock_key | `stock_stock_history_data` |
| `sl_customer` | salesled.dat | `Sales-Record (copybooks/fdsl.cob)` | 36 | sales_key | - |
| `analysis_value` | value.dat | `value-record (copybooks/fdval.cob)` | 12 | va_system, va_first, va_second | - |
| `delivery` | delivery.dat | `delivery-record (copybooks/fddel.cob)` | 5 | deliv_key_type, deliv_purchase_key | - |
| `analysis_code` | analysis.dat | `analysis-record (copybooks/fdanal.cob)` | 6 | pa_system, pa_first, pa_second | - |
| `sl_invoice_header` | invoice.dat (item-nos = 0) | `invoice-header (sales/fdinv2.cob)` | 32 | ih_invoice, ih_letter, ih_test | - |
| `sl_invoice_line` | invoice.dat (item-nos 1..40) | `invoice-line (sales/fdinv2.cob)` | 14 | il_invoice, il_letter, il_line | - |
| `sl_open_item` | openitm3.dat | `oi-header (sales/wsoi.cob)` | 27 | oi_nos, oi_check, oi_invoice | - |
| `sl_open_item_staging` | openitm2.dat (sequential, before posting) | `oi-header (sales/wsoi.cob)` | 28 | id | - |
| `sl_deleted_invoice_no` | delinvno.dat (sequential, surrogate id) | `del-inv-nos-record (sales/fddnos.cob)` | 4 | id | - |
| `pl_supplier` | purchled.dat | `Purch-Record (copybooks/fdpl.cob)` | 30 | purch_key | - |
| `pl_invoice_header` | pinvoice.dat (item-nos = 0) | `invoice-header (purchase/fdpinv2.cob)` | 25 | ih_invoice, ih_test | - |
| `pl_invoice_line` | pinvoice.dat (item-nos 1..) | `invoice-line (purchase/fdpinv2.cob)` | 13 | il_invoice, il_line | - |
| `pl_open_item` | openitm5.dat | `oi-header (purchase/wsoi.cob)` | 28 | oi_nos, oi_check, oi_invoice | - |
| `pl_open_item_staging` | openitm4.dat (sequential, before posting) | `oi-header (purchase/wsoi.cob)` | 29 | id | - |
| `pl_deleted_folio_no` | delfolio.dat (sequential, surrogate id) | `del-inv-nos-record (purchase/fdpdnos.cob)` | 4 | id | - |
| `pl_payment` | pay.dat | `pay-record (purchase/fdpay.cob)` | 8 | pay_supl_key, pay_nos | `pl_payment_line` |
| `irs_nominal` | acnts.dat | `nl-record (incomplete_records_system/wsnl.cob)` | 7 | nl_owning, nl_sub_nominal | `irs_nominal_nl_dr_last`, `irs_nominal_nl_cr_last` |
| `irs_system` | IRS system.dat | `system-record (incomplete_records_system/wssystem.cob)` | 27 | id | - |
| `irs_default` | dflt.dat | `default-record (incomplete_records_system/wsdflt.cob)` | 1 | id | `irs_default_def_acs`, `irs_default_def_codes`, `irs_default_def_vat` |
| `irs_posting` | post.dat | `posting-record (incomplete_records_system/wspost.cob)` | 10 | post_key | - |
| `irs_final` | final.dat | `Final-Record (incomplete_records_system/wsfinal.cob)` | 54 | id | - |

## 3. モジュール間のデータ共有（移行順序に影響）

`sel*.cob` の COPY から集計した、ファイルを利用するサブシステム（Report Writer 版等の派生を除く）:

| ファイル | 利用サブシステム |
|---|---|
| `system.dat` | 全サブシステム（root, common, sales, purchase, stock, general） |
| `stockctl.dat` | stock, sales（請求書入力 sl910/sl920 が在庫を引当）, common |
| `purchled.dat` | purchase, stock（st010 が仕入先を参照）, common |
| `value.dat` / `analysis.dat` | sales, purchase（stock も analysis を参照） |
| `batch.dat` / `posting.dat` | sales, purchase → **general**（SL/PL の転記結果を GL が取り込む） |
| `postings2irs.dat` | sales, purchase → **IRS** |
| `delivery.dat` | sales, purchase |
| `staudit.dat` | sales, stock |
| 上記以外（`salesled`、`invoice`、`openitm*`、`pay`、`ledger` 等） | 単一サブシステム内（+ `common/xl150` の期末処理） |

## 4. 未決事項 / Phase 1 で確定するもの

- 金額以外の `PIC 9` フラグ列（`Sales-Status` 等）を `SMALLINT` のままにするか `BOOLEAN`/enum にするか — 88 レベル定義を確認して Phase 1 のエンティティで決める（DDL は `SMALLINT` のまま）。
- `System-Record` 内のパスワード（`Pass-Word x(4)`）は移行しない（`05-ws-domain-mapping.md` §3）。DDL からも `pass_word` 列を除外する。`RDBMS-Passwd`（DB 接続パスワード）も DDL から除外し、Java では環境変数/シークレットストアで渡す。
- `invoice-record`（134 バイト）と `invoice-header`（137 バイト）の長さ差: FD のレコード長は最大の 137 バイトになる（コメントの「134 bytes」は古い）。移行ツールは 137 バイト単位で読む。
