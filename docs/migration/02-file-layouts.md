# 02. ファイル（ISAM）構造とレコードレイアウト

> `docs/migration/tools/gen_docs.py` により自動生成。オフセット/長さは `cobol_layout.py` で算出し、全レコード長を `verify_layout.sh`（GnuCOBOL `FUNCTION LENGTH`）で照合済み。

## 1. ファイル一覧

| 論理ファイル | 物理ファイル | 編成 | キー | 備考 | 定義 |
|---|---|---|---|---|---|
| system | `system.dat (file-0)` | RELATIVE | RRN 1=System-Record, 2=Default-Record, 3=Final-Record, 4=System-Record-4 (sys002.cbl:776-792) | 4 種のレコードを RRN で多重化 | `copybooks/selsys.cob` / `copybooks/wssystem.cob`, `copybooks/wsdflt.cob`, `copybooks/wsfinal.cob`, `copybooks/wssys4.cob` |
| ledger | `ledger.dat (file-5)` | INDEXED | ledger-key (ledger-nos 9(6) + ledger-pc 9(2)) | GL 勘定科目 | `general/seledger.cob` / `general/fdledger.cob` |
| posting | `posting.dat (file-6)` | RELATIVE | RRN（post-key = batch + post-number を内包） | GL 仕訳 | `copybooks/selpost.cob` / `copybooks/fdpost.cob` |
| batch | `batch.dat (file-7)` | INDEXED | batch-key (ledger 9 + batch-nos 9(5)) | GL/SL/PL バッチ | `copybooks/selbatch.cob` / `copybooks/fdbatch.cob` |
| irs-post (SL/PL→IRS) | `postings2irs.dat (file-8)` | SEQUENTIAL (optional) | なし | SL/PL から IRS への転記インタフェース | `copybooks/selpost-irs.cob` / `copybooks/fdpost-irs.cob` |
| stock-audit | `staudit.dat (file-10)` | SEQUENTIAL (optional) | なし | 在庫監査ログ | `copybooks/selaud.cob` / `copybooks/fdaudit.cob` |
| stock | `stockctl.dat (file-11)` | INDEXED | Stock-Key x(13); ALT Stock-Abrev-Key x(7); ALT Stock-Desc x(32) WITH DUPLICATES | 在庫マスタ | `copybooks/selstock.cob` / `copybooks/fdstock.cob` |
| sales (customer) | `salesled.dat (file-12)` | INDEXED | sales-key x(7)（6 桁 + チェックデジット） | 顧客マスタ | `copybooks/selsl.cob` / `copybooks/fdsl.cob` |
| value (SL/PL analysis totals) | `value.dat (file-13)` | INDEXED | va-code x(3) | 分析コード別集計 | `copybooks/selval.cob` / `copybooks/fdval.cob` |
| delivery | `delivery.dat (file-14)` | INDEXED | deliv-key (type x + account x(7)) | 配送先/メモ（顧客・仕入先共用） | `copybooks/seldel.cob` / `copybooks/fddel.cob` |
| analysis | `analysis.dat (file-15)` | INDEXED | pa-code x(3) | 分析コードマスタ | `copybooks/selanal.cob` / `copybooks/fdanal.cob` |
| sales invoice | `invoice.dat (file-16)` | INDEXED | invoice-key (invoice-nos 9(8) + invoice-let x + item-nos binary-char) | ヘッダ(item-nos=0)と明細(1..40)を同一キー空間で多重化 | `sales/selinv.cob` / `sales/fdinv2.cob` |
| sales deleted invoice nos | `delinvno.dat (file-17)` | SEQUENTIAL | なし | 削除済請求書番号 | `sales/seldnos.cob` / `sales/fddnos.cob` |
| sales open item (seq) | `openitm2.dat (file-18)` | SEQUENTIAL | なし | 転記前 OI（中身は wsoi oi-header） | `sales/seloi2.cob` / `sales/fdoi2.cob`, `sales/wsoi.cob` |
| sales open item | `openitm3.dat (file-19)` | INDEXED | oi3-key (customer x(7) + invoice binary-long) | 売掛オープンアイテム（中身は wsoi oi-header） | `sales/seloi3.cob` / `sales/fdoi3.cob`, `sales/wsoi.cob` |
| sales oi sort work | `oisort.wrk (file-20)` | SEQUENTIAL | なし | 作業ファイル（移行対象外） | `sales/selois.cob` / `sales/fdois.cob` |
| purchase (supplier) | `purchled.dat (file-22)` | INDEXED | purch-key x(7) | 仕入先マスタ | `copybooks/selpl.cob` / `copybooks/fdpl.cob` |
| purchase deleted folio nos | `delfolio.dat (file-23)` | SEQUENTIAL | なし | 削除済フォリオ番号 | `purchase/selpdnos.cob` / `purchase/fdpdnos.cob` |
| purchase invoice | `pinvoice.dat (file-26)` | INDEXED | invoice-key (invoice-nos 9(8) + item-nos binary-char) | ヘッダ/明細多重化 | `purchase/selpinv.cob` / `purchase/fdpinv2.cob` |
| purchase oi sort work | `poisort.wrk (file-27)` | SEQUENTIAL | なし | 作業ファイル（移行対象外） | `purchase/selois.cob` / `purchase/fdois.cob` |
| purchase open item (seq) | `openitm4.dat (file-28)` | SEQUENTIAL | なし | 転記前 OI | `purchase/seloi4.cob` / `purchase/fdoi4.cob`, `purchase/wsoi.cob` |
| purchase open item | `openitm5.dat (file-29)` | INDEXED | oi5-key (supplier x(7) + invoice binary-long) | 買掛オープンアイテム | `copybooks/seloi5.cob` / `purchase/fdoi5.cob`, `purchase/wsoi.cob` |
| pay | `pay.dat (file-32)` | INDEXED | pay-key (supplier x(7) + pay-nos binary-char) | 支払（明細 9 件 OCCURS） | `purchase/selpay.cob` / `purchase/fdpay.cob` |
| IRS nominal ledger | `acnts.dat` | INDEXED | key-1 (owning 9(5) + sub-nominal 9(5)) | IRS 勘定（owner/sub の REDEFINES） | `common/irsub1.cbl` / `incomplete_records_system/wsnl.cob` |
| IRS system | `system.dat (IRS)` | LINE SEQUENTIAL | なし（1 レコード） | ACAS の system.dat とは別形式 | `incomplete_records_system/irsub2.cbl` / `incomplete_records_system/wssystem.cob` |
| IRS defaults | `dflt.dat` | LINE SEQUENTIAL | なし（1 レコード） |  | `common/irsub3.cbl` / `incomplete_records_system/wsdflt.cob` |
| IRS posting | `post.dat` | INDEXED | post-key 9(5) |  | `common/irsub4.cbl` / `incomplete_records_system/wspost.cob` |
| IRS final accounts | `final.dat` | LINE SEQUENTIAL | なし（1 レコード） |  | `common/irsub5.cbl` / `incomplete_records_system/wsfinal.cob` |

上記以外に `copybooks/wsnames.cob` には `archive.dat`(file-2)、`final.dat`(file-3)、`tmp-stock.dat`(file-9)、`work.tmp`(file-21)、`cheque.dat`(file-33) 等の作業/出力ファイルが定義されている（業務データとしての移行対象外）。

## 2. レコードレイアウト

列: Off=0 始まりのバイトオフセット、Len=1 出現分の長さ、Occ=OCCURS 回数。codec はデータ移行ツールでのデコード方法。

### `System-Record` — `copybooks/wssystem.cob`（1024 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 384 |  | **System-Data-Block** | group | | | |
| 0 | 1 |  | &nbsp;&nbsp;System-Record-Version-Prime | `binary-char` | int | SMALLINT | native LE int8 |
| 1 | 1 |  | &nbsp;&nbsp;System-Record-Version-Secondary | `binary-char` | int | SMALLINT | native LE int8 |
| 2 | 10 |  | **&nbsp;&nbsp;Vat-Rates** | group | | | |
| 2 | 2 |  | &nbsp;&nbsp;&nbsp;&nbsp;Vat-Rate-1 | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 4 | 2 |  | &nbsp;&nbsp;&nbsp;&nbsp;Vat-Rate-2 | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 6 | 2 |  | &nbsp;&nbsp;&nbsp;&nbsp;Vat-Rate-3 | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 8 | 2 |  | &nbsp;&nbsp;&nbsp;&nbsp;Vat-Rate-4 | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 10 | 2 |  | &nbsp;&nbsp;&nbsp;&nbsp;Vat-Rate-5 | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 2 | 2 | 5 | &nbsp;&nbsp;Vat-Rate *(REDEFINES Vat-Rates)* | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 12 | 1 |  | &nbsp;&nbsp;Cyclea | `binary-char` | int | SMALLINT | native LE int8 |
| 12 | 1 |  | &nbsp;&nbsp;Scycle *(REDEFINES cyclea)* | `binary-char` | int | SMALLINT | native LE int8 |
| 13 | 1 |  | &nbsp;&nbsp;Period | `binary-char` | int | SMALLINT | native LE int8 |
| 14 | 1 |  | &nbsp;&nbsp;Page-Lines | `binary-char unsigned` | int | SMALLINT | native LE int8 unsigned |
| 15 | 4 |  | &nbsp;&nbsp;Next-Invoice | `binary-long` | int | INTEGER | native LE int32 |
| 19 | 4 |  | &nbsp;&nbsp;Run-Date | `binary-long` | int | INTEGER | native LE int32 |
| 23 | 4 |  | &nbsp;&nbsp;Start-Date | `binary-long` | int | INTEGER | native LE int32 |
| 27 | 4 |  | &nbsp;&nbsp;End-Date | `binary-long` | int | INTEGER | native LE int32 |
| 31 | 32 |  | **&nbsp;&nbsp;Suser** | group | | | |
| 31 | 32 |  | &nbsp;&nbsp;&nbsp;&nbsp;Usera | `PIC x(32)` | String | VARCHAR(32) | text (trailing spaces trimmed) |
| 63 | 32 |  | &nbsp;&nbsp;User-Code | `PIC x(32)` | String | VARCHAR(32) | text (trailing spaces trimmed) |
| 95 | 24 |  | &nbsp;&nbsp;Address-1 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 119 | 24 |  | &nbsp;&nbsp;Address-2 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 143 | 24 |  | &nbsp;&nbsp;Address-3 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 167 | 24 |  | &nbsp;&nbsp;Address-4 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 191 | 12 |  | &nbsp;&nbsp;Post-Code | `PIC x(12)` | String | VARCHAR(12) | text (trailing spaces trimmed) |
| 203 | 24 |  | &nbsp;&nbsp;Country | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 227 | 48 |  | &nbsp;&nbsp;Print-Spool-Name | `PIC x(48)` | String | VARCHAR(48) | text (trailing spaces trimmed) |
| 275 | 32 |  | **&nbsp;&nbsp;File-Statuses** | group | | | |
| 275 | 1 | 32 | &nbsp;&nbsp;&nbsp;&nbsp;File-Status | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 307 | 1 |  | &nbsp;&nbsp;Pass-Value | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 308 | 6 |  | **&nbsp;&nbsp;Level** | group | | | |
| 308 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;Level-1 | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 309 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;Level-2 | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 310 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;Level-3 | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 311 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;Level-4 | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 312 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;Level-5 | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 313 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;Level-6 | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 314 | 4 |  | &nbsp;&nbsp;Pass-Word | `PIC x(4)` | String | VARCHAR(4) | text (trailing spaces trimmed) |
| 318 | 1 |  | &nbsp;&nbsp;Host | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 319 | 1 |  | &nbsp;&nbsp;Op-System | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 320 | 1 |  | &nbsp;&nbsp;Current-Quarter | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 321 | 2 |  | **&nbsp;&nbsp;RDBMS-Flat-Statuses** | group | | | |
| 321 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;File-System-Used | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 322 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;File-Duplicates-In-Use | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 323 | 4 |  | **&nbsp;&nbsp;Maps-Ser** | group | | | |
| 323 | 2 |  | &nbsp;&nbsp;&nbsp;&nbsp;Maps-Ser-xx | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 325 | 2 |  | &nbsp;&nbsp;&nbsp;&nbsp;Maps-Ser-nn | `binary-short` | short | SMALLINT | native LE int16 |
| 327 | 1 |  | &nbsp;&nbsp;Date-Form | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 328 | 1 |  | &nbsp;&nbsp;Data-Capture-Used | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 329 | 12 |  | &nbsp;&nbsp;RDBMS-DB-Name | `PIC x(12)` | String | VARCHAR(12) | text (trailing spaces trimmed) |
| 341 | 12 |  | &nbsp;&nbsp;RDBMS-User | `PIC x(12)` | String | VARCHAR(12) | text (trailing spaces trimmed) |
| 353 | 12 |  | &nbsp;&nbsp;RDBMS-Passwd | `PIC x(12)` | String | VARCHAR(12) | text (trailing spaces trimmed) |
| 365 | 11 |  | &nbsp;&nbsp;VAT-Reg-Number | `PIC x(11)` | String | VARCHAR(11) | text (trailing spaces trimmed) |
| 376 | 8 |  | &nbsp;&nbsp;filler | `PIC x(08)` | String | VARCHAR(8) | text (trailing spaces trimmed) |
| 384 | 80 |  | **General-Ledger-Block** | group | | | |
| 384 | 1 |  | &nbsp;&nbsp;P-C | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 385 | 1 |  | &nbsp;&nbsp;P-C-Grouped | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 386 | 1 |  | &nbsp;&nbsp;P-C-Level | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 387 | 1 |  | &nbsp;&nbsp;Comps | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 388 | 1 |  | &nbsp;&nbsp;Comps-Active | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 389 | 1 |  | &nbsp;&nbsp;M-V | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 390 | 1 |  | &nbsp;&nbsp;Arch | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 391 | 1 |  | &nbsp;&nbsp;Trans-Print | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 392 | 1 |  | &nbsp;&nbsp;Trans-Printed | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 393 | 1 |  | &nbsp;&nbsp;Header-Level | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 394 | 1 |  | &nbsp;&nbsp;Sales-Range | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 395 | 1 |  | &nbsp;&nbsp;Purchase-Range | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 396 | 1 |  | &nbsp;&nbsp;Vat | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 397 | 1 |  | &nbsp;&nbsp;Batch-Id | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 398 | 1 |  | &nbsp;&nbsp;Ledger-2nd-Index | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 399 | 1 |  | &nbsp;&nbsp;Irs-Instead | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 400 | 2 |  | &nbsp;&nbsp;Ledger-Sec | `binary-short` | short | SMALLINT | native LE int16 |
| 402 | 2 |  | &nbsp;&nbsp;Updates | `binary-short` | short | SMALLINT | native LE int16 |
| 404 | 2 |  | &nbsp;&nbsp;Postings | `binary-short` | short | SMALLINT | native LE int16 |
| 406 | 2 |  | &nbsp;&nbsp;Next-Batch | `binary-short` | short | SMALLINT | native LE int16 |
| 408 | 4 |  | &nbsp;&nbsp;Extra-Charge-Ac | `binary-long` | int | INTEGER | native LE int32 |
| 412 | 4 |  | &nbsp;&nbsp;Vat-Ac | `binary-long` | int | INTEGER | native LE int32 |
| 416 | 48 |  | &nbsp;&nbsp;Print-Spool-Name2 | `PIC x(48)` | String | VARCHAR(48) | text (trailing spaces trimmed) |
| 464 | 88 |  | **Purchase-Ledger-Block** | group | | | |
| 464 | 4 |  | &nbsp;&nbsp;Next-Folio | `binary-long` | int | INTEGER | native LE int32 |
| 468 | 4 |  | &nbsp;&nbsp;BL-Pay-Ac | `binary-long` | int | INTEGER | native LE int32 |
| 472 | 4 |  | &nbsp;&nbsp;P-Creditors | `binary-long` | int | INTEGER | native LE int32 |
| 476 | 4 |  | &nbsp;&nbsp;BL-Purch-Ac | `binary-long` | int | INTEGER | native LE int32 |
| 480 | 4 |  | &nbsp;&nbsp;BL-End-Cycle-Date | `binary-long` | int | INTEGER | native LE int32 |
| 484 | 2 |  | &nbsp;&nbsp;BL-Next-Batch | `binary-short` | short | SMALLINT | native LE int16 |
| 486 | 1 |  | &nbsp;&nbsp;Age-To-Pay | `binary-char` | int | SMALLINT | native LE int8 |
| 487 | 1 |  | &nbsp;&nbsp;Purchase-Ledger | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 488 | 1 |  | &nbsp;&nbsp;PL-Delim | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 489 | 1 |  | &nbsp;&nbsp;Entry-Level | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 490 | 1 |  | &nbsp;&nbsp;P-Flag-A | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 491 | 1 |  | &nbsp;&nbsp;P-Flag-I | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 492 | 1 |  | &nbsp;&nbsp;P-Flag-P | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 493 | 1 |  | &nbsp;&nbsp;PL-Stock-Link | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 494 | 48 |  | &nbsp;&nbsp;Print-Spool-Name3 | `PIC x(48)` | String | VARCHAR(48) | text (trailing spaces trimmed) |
| 542 | 10 |  | &nbsp;&nbsp;filler | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 552 | 128 |  | **Sales-Ledger-Block** | group | | | |
| 552 | 1 |  | &nbsp;&nbsp;Sales-Ledger | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 553 | 1 |  | &nbsp;&nbsp;SL-Delim | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 554 | 1 |  | &nbsp;&nbsp;Oi-3-Flag | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 555 | 1 |  | &nbsp;&nbsp;Cust-Flag | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 556 | 1 |  | &nbsp;&nbsp;Oi-5-Flag | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 557 | 1 |  | &nbsp;&nbsp;S-Flag-Oi-3 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 558 | 1 |  | &nbsp;&nbsp;Full-Invoicing | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 559 | 1 |  | &nbsp;&nbsp;S-Flag-A | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 560 | 1 |  | &nbsp;&nbsp;S-Flag-I | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 561 | 1 |  | &nbsp;&nbsp;S-Flag-P | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 562 | 1 |  | &nbsp;&nbsp;SL-Dunning | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 563 | 1 |  | &nbsp;&nbsp;SL-Charges | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 564 | 1 |  | &nbsp;&nbsp;Sl-Own-Nos | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 565 | 1 |  | &nbsp;&nbsp;SL-Stats-Run | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 566 | 1 |  | &nbsp;&nbsp;Sl-Day-Book | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 567 | 1 |  | &nbsp;&nbsp;invoicer | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 568 | 14 |  | &nbsp;&nbsp;Extra-Desc | `PIC x(14)` | String | VARCHAR(14) | text (trailing spaces trimmed) |
| 582 | 1 |  | &nbsp;&nbsp;Extra-Type | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 583 | 1 |  | &nbsp;&nbsp;Extra-Print | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 584 | 1 |  | &nbsp;&nbsp;SL-Stock-Link | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 585 | 1 |  | &nbsp;&nbsp;SL-Stock-Audit | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 586 | 2 |  | &nbsp;&nbsp;SL-Late-Per | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 588 | 2 |  | &nbsp;&nbsp;SL-Disc | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 590 | 2 |  | &nbsp;&nbsp;Extra-Rate | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 592 | 1 |  | &nbsp;&nbsp;SL-Days-1 | `binary-char` | int | SMALLINT | native LE int8 |
| 593 | 1 |  | &nbsp;&nbsp;SL-Days-2 | `binary-char` | int | SMALLINT | native LE int8 |
| 594 | 1 |  | &nbsp;&nbsp;SL-Days-3 | `binary-char` | int | SMALLINT | native LE int8 |
| 595 | 1 |  | &nbsp;&nbsp;SL-Credit | `binary-char` | int | SMALLINT | native LE int8 |
| 596 | 2 |  | &nbsp;&nbsp;filler | `binary-short` | short | SMALLINT | native LE int16 |
| 598 | 2 |  | &nbsp;&nbsp;SL-Min | `binary-short` | short | SMALLINT | native LE int16 |
| 600 | 2 |  | &nbsp;&nbsp;SL-Max | `binary-short` | short | SMALLINT | native LE int16 |
| 602 | 2 |  | &nbsp;&nbsp;PF-Retention | `binary-short` | short | SMALLINT | native LE int16 |
| 604 | 2 |  | &nbsp;&nbsp;First-Sl-Batch | `binary-short` | short | SMALLINT | native LE int16 |
| 606 | 4 |  | &nbsp;&nbsp;First-Sl-Inv | `binary-long` | int | INTEGER | native LE int32 |
| 610 | 4 |  | &nbsp;&nbsp;SL-Limit | `binary-long` | int | INTEGER | native LE int32 |
| 614 | 4 |  | &nbsp;&nbsp;SL-Pay-Ac | `binary-long` | int | INTEGER | native LE int32 |
| 618 | 4 |  | &nbsp;&nbsp;S-Debtors | `binary-long` | int | INTEGER | native LE int32 |
| 622 | 4 |  | &nbsp;&nbsp;SL-Sales-Ac | `binary-long` | int | INTEGER | native LE int32 |
| 626 | 4 |  | &nbsp;&nbsp;S-End-Cycle-Date | `binary-long` | int | INTEGER | native LE int32 |
| 630 | 1 |  | &nbsp;&nbsp;SL-Comp-Head-Pick | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 631 | 1 |  | &nbsp;&nbsp;SL-Comp-Head-Inv | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 632 | 1 |  | &nbsp;&nbsp;SL-Comp-Head-Stat | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 633 | 1 |  | &nbsp;&nbsp;SL-Comp-Head-Lets | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 634 | 1 |  | &nbsp;&nbsp;SL-VAT-Printed | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 635 | 45 |  | &nbsp;&nbsp;filler | `PIC x(45)` | String | VARCHAR(45) | text (trailing spaces trimmed) |
| 680 | 88 |  | **Stock-Control-Block** | group | | | |
| 680 | 6 |  | &nbsp;&nbsp;Stk-Abrev-Ref | `PIC x(6)` | String | VARCHAR(6) | text (trailing spaces trimmed) |
| 686 | 1 |  | &nbsp;&nbsp;Stk-Debug | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 687 | 1 |  | &nbsp;&nbsp;Stk-Manu-Used | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 688 | 1 |  | &nbsp;&nbsp;Stk-OE-Used | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 689 | 1 |  | &nbsp;&nbsp;Stk-Audit-Used | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 690 | 1 |  | &nbsp;&nbsp;Stk-Mov-Audit | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 691 | 1 |  | &nbsp;&nbsp;Stk-Period-Cur | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 692 | 1 |  | &nbsp;&nbsp;Stk-Period-dat | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 693 | 1 |  | &nbsp;&nbsp;filler | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 694 | 1 |  | &nbsp;&nbsp;Stock-Control | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 695 | 1 |  | &nbsp;&nbsp;Stk-Averaging | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 696 | 1 |  | &nbsp;&nbsp;Stk-Activity-Rep-Run | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 697 | 1 |  | &nbsp;&nbsp;filler | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 698 | 1 |  | &nbsp;&nbsp;Stk-Page-Lines | `binary-char unsigned` | int | SMALLINT | native LE int8 unsigned |
| 699 | 1 |  | &nbsp;&nbsp;Stk-Audit-No | `binary-char unsigned` | int | SMALLINT | native LE int8 unsigned |
| 700 | 68 |  | &nbsp;&nbsp;filler | `PIC x(68)` | String | VARCHAR(68) | text (trailing spaces trimmed) |
| 768 | 128 |  | **Order-Entry-Block** | group | | | |
| 768 | 128 |  | &nbsp;&nbsp;filler-Dummy | `PIC x(128)` | String | VARCHAR(128) | text (trailing spaces trimmed) |
| 896 | 128 |  | **IRS-Data-Block** | group | | | |
| 896 | 128 |  | &nbsp;&nbsp;filler-dummy4 | `PIC x(128)` | String | VARCHAR(128) | text (trailing spaces trimmed) |
| 896 | 128 |  | **IRS-Entry-Block *(REDEFINES IRS-Data-Block)*** | group | | | |
| 896 | 24 |  | &nbsp;&nbsp;Client | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 920 | 48 |  | **&nbsp;&nbsp;System-Files** | group | | | |
| 920 | 9 |  | &nbsp;&nbsp;&nbsp;&nbsp;fn-1 | `PIC x(9)` | String | VARCHAR(9) | text (trailing spaces trimmed) |
| 929 | 10 |  | &nbsp;&nbsp;&nbsp;&nbsp;fn-2 | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 939 | 8 |  | &nbsp;&nbsp;&nbsp;&nbsp;fn-3 | `PIC x(8)` | String | VARCHAR(8) | text (trailing spaces trimmed) |
| 947 | 8 |  | &nbsp;&nbsp;&nbsp;&nbsp;fn-4 | `PIC x(8)` | String | VARCHAR(8) | text (trailing spaces trimmed) |
| 955 | 12 |  | &nbsp;&nbsp;&nbsp;&nbsp;fn-5 | `PIC x(12)` | String | VARCHAR(12) | text (trailing spaces trimmed) |
| 967 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;System-Ops | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 968 | 5 |  | &nbsp;&nbsp;Next-Post | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 973 | 12 |  | **&nbsp;&nbsp;Vat-Rates2** | group | | | |
| 973 | 4 |  | &nbsp;&nbsp;&nbsp;&nbsp;vat1 | `PIC 99v99` | BigDecimal | NUMERIC(4,2) | zoned decimal 4 digits, scale 2 |
| 977 | 4 |  | &nbsp;&nbsp;&nbsp;&nbsp;vat2 | `PIC 99v99` | BigDecimal | NUMERIC(4,2) | zoned decimal 4 digits, scale 2 |
| 981 | 4 |  | &nbsp;&nbsp;&nbsp;&nbsp;vat3 | `PIC 99v99` | BigDecimal | NUMERIC(4,2) | zoned decimal 4 digits, scale 2 |
| 973 | 12 |  | **&nbsp;&nbsp;Vat-Group *(REDEFINES Vat-Rates2)*** | group | | | |
| 973 | 4 | 3 | &nbsp;&nbsp;&nbsp;&nbsp;Vat-Psent | `PIC 99v99` | BigDecimal | NUMERIC(4,2) | zoned decimal 4 digits, scale 2 |
| 985 | 1 |  | &nbsp;&nbsp;IRS-Pass-Value | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 986 | 1 |  | &nbsp;&nbsp;save-sequ | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 987 | 18 |  | &nbsp;&nbsp;system-work-group | `PIC x(18)` | String | VARCHAR(18) | text (trailing spaces trimmed) |
| 1005 | 1 |  | &nbsp;&nbsp;PL-App-Created | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 1006 | 5 |  | &nbsp;&nbsp;PL-Approp-AC | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 1011 | 1 |  | &nbsp;&nbsp;1st-Time-Flag | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 1012 | 12 |  | &nbsp;&nbsp;filler | `PIC x(12)` | String | VARCHAR(12) | text (trailing spaces trimmed) |

### `Default-Record` — `copybooks/wsdflt.cob`（231 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 4 | 33 | Def-Acs | `PIC 9(4)v99 COMP` | BigDecimal | NUMERIC(6,2) | big-endian binary 4 bytes, scale 2, unsigned |
| 132 | 2 | 33 | Def-Codes | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 198 | 1 | 33 | Def-Vat | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |

### `Final-Record` — `copybooks/wsfinal.cob`（416 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 16 | 26 | ar1 | `PIC x(16)` | String | VARCHAR(16) | text (trailing spaces trimmed) |

### `System-Record-4` — `copybooks/wssys4.cob`（1024 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 60 |  | **Sales-Ledger-Data** | group | | | |
| 0 | 6 |  | &nbsp;&nbsp;sl-os-bal-last-month | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 6 | 6 |  | &nbsp;&nbsp;sl-os-bal-this-month | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 12 | 6 |  | &nbsp;&nbsp;sl-invoices-this-month | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 18 | 6 |  | &nbsp;&nbsp;sl-credit-notes-this-month | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 24 | 6 |  | &nbsp;&nbsp;sl-variance | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 30 | 6 |  | &nbsp;&nbsp;sl-credit-deductions | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 36 | 6 |  | &nbsp;&nbsp;sl-cn-unappl-this-month | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 42 | 6 |  | &nbsp;&nbsp;sl-payments | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 48 | 6 |  | &nbsp;&nbsp;sl4-spare1 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 54 | 6 |  | &nbsp;&nbsp;sl4-spare2 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 60 | 60 |  | **Purchase-Ledger-Data** | group | | | |
| 60 | 6 |  | &nbsp;&nbsp;pl-os-bal-last-month | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 66 | 6 |  | &nbsp;&nbsp;pl-os-bal-this-month | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 72 | 6 |  | &nbsp;&nbsp;pl-invoices-this-month | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 78 | 6 |  | &nbsp;&nbsp;pl-credit-notes-this-month | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 84 | 6 |  | &nbsp;&nbsp;pl-variance | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 90 | 6 |  | &nbsp;&nbsp;pl-credit-deductions | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 96 | 6 |  | &nbsp;&nbsp;pl-cn-unappl-this-month | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 102 | 6 |  | &nbsp;&nbsp;pl-payments | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 108 | 6 |  | &nbsp;&nbsp;sl4-spare3 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 114 | 6 |  | &nbsp;&nbsp;sl4-spare4 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 120 | 904 |  | filler | `PIC x(904)` | String | VARCHAR(904) | text (trailing spaces trimmed) |

### `ledger-record` — `general/fdledger.cob`（126 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 8 |  | **ledger-key** | group | | | |
| 0 | 6 |  | &nbsp;&nbsp;ledger-nos | `PIC 9(6)` | int | INTEGER | zoned decimal 6 digits, scale 0 |
| 0 | 6 |  | **&nbsp;&nbsp;filler *(REDEFINES ledger-nos)*** | group | | | |
| 0 | 4 |  | &nbsp;&nbsp;&nbsp;&nbsp;ledger-n | `PIC 9(4)` | int | SMALLINT | zoned decimal 4 digits, scale 0 |
| 4 | 2 |  | &nbsp;&nbsp;&nbsp;&nbsp;ledger-s | `PIC 9(2)` | int | SMALLINT | zoned decimal 2 digits, scale 0 |
| 6 | 2 |  | &nbsp;&nbsp;ledger-pc | `PIC 9(2)` | int | SMALLINT | zoned decimal 2 digits, scale 0 |
| 8 | 1 |  | ledger-type | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 9 | 1 |  | ledger-place | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 10 | 1 |  | ledger-level | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 11 | 5 |  | filler | `PIC x(5)` | String | VARCHAR(5) | text (trailing spaces trimmed) |
| 16 | 24 |  | ledger-name | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 40 | 6 |  | ledger-balance | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 46 | 6 |  | ledger-last | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 52 | 24 |  | **quarters** | group | | | |
| 52 | 6 |  | &nbsp;&nbsp;ledger-q1 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 58 | 6 |  | &nbsp;&nbsp;ledger-q2 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 64 | 6 |  | &nbsp;&nbsp;ledger-q3 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 70 | 6 |  | &nbsp;&nbsp;ledger-q4 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 52 | 24 |  | **filler *(REDEFINES quarters)*** | group | | | |
| 52 | 6 | 4 | &nbsp;&nbsp;ledger-q | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 76 | 50 |  | filler | `PIC x(50)` | String | VARCHAR(50) | text (trailing spaces trimmed) |

### `posting-record` — `copybooks/fdpost.cob`（98 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 10 |  | **post-key** | group | | | |
| 0 | 5 |  | &nbsp;&nbsp;batch | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 5 | 5 |  | &nbsp;&nbsp;post-number | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 10 | 2 |  | post-code | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 12 | 8 |  | post-date | `PIC x(8)` | String | VARCHAR(8) | text (trailing spaces trimmed) |
| 20 | 6 |  | post-dr | `PIC 9(6)` | int | INTEGER | zoned decimal 6 digits, scale 0 |
| 26 | 2 |  | dr-pc | `PIC 99` | int | SMALLINT | zoned decimal 2 digits, scale 0 |
| 28 | 6 |  | post-cr | `PIC 9(6)` | int | INTEGER | zoned decimal 6 digits, scale 0 |
| 34 | 2 |  | cr-pc | `PIC 99` | int | SMALLINT | zoned decimal 2 digits, scale 0 |
| 36 | 10 |  | post-amount | `PIC s9(8)v99` | BigDecimal | NUMERIC(10,2) | zoned decimal 10 digits, scale 2, trailing overpunch sign |
| 46 | 32 |  | post-legend | `PIC x(32)` | String | VARCHAR(32) | text (trailing spaces trimmed) |
| 78 | 6 |  | vat-ac | `PIC 9(6)` | int | INTEGER | zoned decimal 6 digits, scale 0 |
| 84 | 2 |  | vat-pc | `PIC 99` | int | SMALLINT | zoned decimal 2 digits, scale 0 |
| 86 | 2 |  | post-vat-side | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 88 | 10 |  | vat-amount | `PIC s9(8)v99` | BigDecimal | NUMERIC(10,2) | zoned decimal 10 digits, scale 2, trailing overpunch sign |

### `batch-record` — `copybooks/fdbatch.cob`（96 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 6 |  | **batch-key** | group | | | |
| 0 | 1 |  | &nbsp;&nbsp;ledger | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 1 | 5 |  | &nbsp;&nbsp;batch-nos | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 6 | 2 |  | items | `PIC 99` | int | SMALLINT | zoned decimal 2 digits, scale 0 |
| 8 | 1 |  | batch-status | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 9 | 1 |  | cleared-status | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 10 | 2 |  | bcycle | `PIC 99` | int | SMALLINT | zoned decimal 2 digits, scale 0 |
| 12 | 16 |  | **dates** | group | | | |
| 12 | 4 |  | &nbsp;&nbsp;entered | `binary-long` | int | INTEGER | native LE int32 |
| 16 | 4 |  | &nbsp;&nbsp;proofed | `binary-long` | int | INTEGER | native LE int32 |
| 20 | 4 |  | &nbsp;&nbsp;posted | `binary-long` | int | INTEGER | native LE int32 |
| 24 | 4 |  | &nbsp;&nbsp;stored | `binary-long` | int | INTEGER | native LE int32 |
| 28 | 24 |  | **amounts** | group | | | |
| 28 | 6 |  | &nbsp;&nbsp;input-gross | `PIC 9(9)v99 COMP-3` | BigDecimal | NUMERIC(11,2) | packed decimal 11 digits, scale 2 |
| 34 | 6 |  | &nbsp;&nbsp;input-vat | `PIC 9(9)v99 COMP-3` | BigDecimal | NUMERIC(11,2) | packed decimal 11 digits, scale 2 |
| 40 | 6 |  | &nbsp;&nbsp;actual-gross | `PIC 9(9)v99 COMP-3` | BigDecimal | NUMERIC(11,2) | packed decimal 11 digits, scale 2 |
| 46 | 6 |  | &nbsp;&nbsp;actual-vat | `PIC 9(9)v99 COMP-3` | BigDecimal | NUMERIC(11,2) | packed decimal 11 digits, scale 2 |
| 52 | 24 |  | description | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 76 | 15 |  | **posting-data** | group | | | |
| 76 | 2 |  | &nbsp;&nbsp;bdefault | `PIC 99` | int | SMALLINT | zoned decimal 2 digits, scale 0 |
| 78 | 2 |  | &nbsp;&nbsp;convention | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 80 | 6 |  | &nbsp;&nbsp;batch-def-ac | `PIC 9(6)` | int | INTEGER | zoned decimal 6 digits, scale 0 |
| 86 | 2 |  | &nbsp;&nbsp;batch-def-pc | `PIC 99` | int | SMALLINT | zoned decimal 2 digits, scale 0 |
| 88 | 2 |  | &nbsp;&nbsp;batch-def-code | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 90 | 1 |  | &nbsp;&nbsp;batch-def-vat | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 91 | 5 |  | batch-start | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |

### `irs-posting-record` — `copybooks/fdpost-irs.cob`（84 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 10 |  | **irs-post-key** | group | | | |
| 0 | 5 |  | &nbsp;&nbsp;irs-batch | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 5 | 5 |  | &nbsp;&nbsp;irs-post-number | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 10 | 2 |  | irs-post-code | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 12 | 8 |  | irs-post-date | `PIC x(8)` | String | VARCHAR(8) | text (trailing spaces trimmed) |
| 20 | 5 |  | irs-post-dr | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 25 | 5 |  | irs-post-cr | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 30 | 9 |  | irs-post-amount | `PIC s9(7)v99` | BigDecimal | NUMERIC(9,2) | zoned decimal 9 digits, scale 2, sign leading overpunch |
| 39 | 32 |  | irs-post-legend | `PIC x(32)` | String | VARCHAR(32) | text (trailing spaces trimmed) |
| 71 | 2 |  | irs-vat-ac-def | `PIC 99` | int | SMALLINT | zoned decimal 2 digits, scale 0 |
| 73 | 2 |  | irs-post-vat-side | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 75 | 9 |  | irs-vat-amount | `PIC s9(7)v99` | BigDecimal | NUMERIC(9,2) | zoned decimal 9 digits, scale 2, sign leading overpunch |

### `Stock-Audit-Record` — `copybooks/fdaudit.cob`（104 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 1 |  | Audit-Type | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 1 | 8 |  | Audit-Invoice-PO | `PIC 9(8)` | int | INTEGER | zoned decimal 8 digits, scale 0 |
| 9 | 8 |  | Audit-Cr-for-Invoice | `PIC 9(8)` | int | INTEGER | zoned decimal 8 digits, scale 0 |
| 17 | 13 |  | Audit-Stock-Key | `PIC x(13)` | String | VARCHAR(13) | text (trailing spaces trimmed) |
| 30 | 32 |  | Audit-Desc | `PIC x(32)` | String | VARCHAR(32) | text (trailing spaces trimmed) |
| 62 | 10 |  | Audit-Process-Date | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 72 | 1 |  | Audit-Reverse-Transaction | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 73 | 6 |  | Audit-Transaction-Qty | `PIC s9(6)` | int | INTEGER | zoned decimal 6 digits, scale 0, trailing overpunch sign |
| 79 | 10 |  | Audit-Unit-Cost | `PIC s9(6)v9999` | BigDecimal | NUMERIC(10,4) | zoned decimal 10 digits, scale 4, trailing overpunch sign |
| 89 | 10 |  | Audit-Stock-Value-Change | `PIC s9(8)v99` | BigDecimal | NUMERIC(10,2) | zoned decimal 10 digits, scale 2, trailing overpunch sign |
| 99 | 5 |  | Audit-No | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |

### `Stock-Record` — `copybooks/fdstock.cob`（400 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 13 |  | Stock-Key | `PIC x(13)` | String | VARCHAR(13) | text (trailing spaces trimmed) |
| 13 | 7 |  | Stock-Abrev-Key | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 20 | 21 |  | **Stock-Suppliers-Group** | group | | | |
| 20 | 7 |  | &nbsp;&nbsp;Stock-Supplier-P1 | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 27 | 7 |  | &nbsp;&nbsp;Stock-Supplier-P2 | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 34 | 7 |  | &nbsp;&nbsp;Stock-Supplier-P3 | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 20 | 21 |  | **filler *(REDEFINES Stock-Suppliers-Group)*** | group | | | |
| 20 | 7 | 3 | &nbsp;&nbsp;Stock-Suppliers | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 41 | 32 |  | Stock-Desc | `PIC x(32)` | String | VARCHAR(32) | text (trailing spaces trimmed) |
| 73 | 13 |  | Stock-Construct-Item | `PIC x(13)` | String | VARCHAR(13) | text (trailing spaces trimmed) |
| 86 | 10 |  | Stock-Location | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 96 | 3 |  | **Stock-PA-Code** | group | | | |
| 96 | 1 |  | &nbsp;&nbsp;Stock-pa-System | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 97 | 2 |  | **&nbsp;&nbsp;Stock-pa-Group** | group | | | |
| 97 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;Stock-pa-First | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 98 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;Stock-pa-Second | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 99 | 3 |  | **Stock-SA-Code** | group | | | |
| 99 | 1 |  | &nbsp;&nbsp;Stock-sa-System | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 100 | 2 |  | **&nbsp;&nbsp;Stock-sa-Group** | group | | | |
| 100 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;Stock-sa-First | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 101 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;Stock-sa-Second | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 102 | 1 |  | Stock-Services-Flag | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 103 | 5 |  | Stock-Last-Actual-Cost | `PIC 9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2 |
| 108 | 8 |  | filler | `PIC x(8)` | String | VARCHAR(8) | text (trailing spaces trimmed) |
| 116 | 4 |  | Stock-Construct-Bundle | `PIC s9(6) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, signed |
| 120 | 4 |  | Stock-Under-Construction | `PIC s9(6) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, signed |
| 124 | 4 |  | Stock-Work-in-Progress | `PIC s9(6) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, signed |
| 128 | 4 |  | Stock-ReOrder-Pnt | `PIC s9(6) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, signed |
| 132 | 4 |  | Stock-Std-ReOrder | `PIC s9(6) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, signed |
| 136 | 4 |  | Stock-Back-Ordered | `PIC s9(6) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, signed |
| 140 | 4 |  | Stock-On-Order | `PIC s9(6) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, signed |
| 144 | 4 |  | Stock-Held | `PIC s9(6) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, signed |
| 148 | 4 |  | Stock-Pre-Sales | `PIC s9(6) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, signed |
| 152 | 5 |  | Stock-Retail | `PIC 9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2 |
| 157 | 6 |  | Stock-Cost | `PIC 9(7)v9999 COMP-3` | BigDecimal | NUMERIC(11,4) | packed decimal 11 digits, scale 4 |
| 163 | 6 |  | Stock-Value | `PIC 9(9)v99 COMP-3` | BigDecimal | NUMERIC(11,2) | packed decimal 11 digits, scale 2 |
| 169 | 4 |  | Stock-Order-Due | `PIC 9(8) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 173 | 4 |  | Stock-Order-Date | `PIC 9(8) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 177 | 16 |  | **Stock-Mthly-Running-Totals** | group | | | |
| 177 | 4 |  | &nbsp;&nbsp;Stock-Adds | `PIC 9(8) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 181 | 4 |  | &nbsp;&nbsp;Stock-Deducts | `PIC 9(8) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 185 | 4 |  | &nbsp;&nbsp;Stock-Wip-Adds | `PIC 9(8) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 189 | 4 |  | &nbsp;&nbsp;Stock-Wip-Deds | `PIC 9(8) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 193 | 192 |  | **Stock-History** | group | | | |
| 193 | 16 | 12 | **&nbsp;&nbsp;Stock-History-Data** | group | | | |
| 193 | 4 |  | &nbsp;&nbsp;&nbsp;&nbsp;Stock-TD-Adds | `PIC 9(8) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 197 | 4 |  | &nbsp;&nbsp;&nbsp;&nbsp;Stock-TD-Deds | `PIC 9(8) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 201 | 4 |  | &nbsp;&nbsp;&nbsp;&nbsp;Stock-TD-Wip-Adds | `PIC 9(8) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 205 | 4 |  | &nbsp;&nbsp;&nbsp;&nbsp;Stock-TD-Wip-Deds | `PIC 9(8) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 385 | 15 |  | filler | `PIC x(15)` | String | VARCHAR(15) | text (trailing spaces trimmed) |

### `Sales-Record` — `copybooks/fdsl.cob`（300 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 7 |  | Sales-Key | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 7 | 30 |  | Sales-Name | `PIC x(30)` | String | VARCHAR(30) | text (trailing spaces trimmed) |
| 37 | 96 |  | **Sales-Address** | group | | | |
| 37 | 48 |  | &nbsp;&nbsp;Sales-Addr1 | `PIC x(48)` | String | VARCHAR(48) | text (trailing spaces trimmed) |
| 85 | 48 |  | &nbsp;&nbsp;Sales-Addr2 | `PIC x(48)` | String | VARCHAR(48) | text (trailing spaces trimmed) |
| 133 | 13 |  | Sales-Phone | `PIC x(13)` | String | VARCHAR(13) | text (trailing spaces trimmed) |
| 146 | 4 |  | Sales-Ext | `PIC x(4)` | String | VARCHAR(4) | text (trailing spaces trimmed) |
| 150 | 30 |  | Sales-Email | `PIC x(30)` | String | VARCHAR(30) | text (trailing spaces trimmed) |
| 180 | 13 |  | Sales-Fax | `PIC x(13)` | String | VARCHAR(13) | text (trailing spaces trimmed) |
| 193 | 1 |  | Sales-Status | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 194 | 1 |  | Sales-Late | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 195 | 1 |  | Sales-Dunning | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 196 | 1 |  | Email-Invoice | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 197 | 1 |  | Email-Statement | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 198 | 1 |  | Email-Letters | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 199 | 1 |  | Delivery-Tag | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 200 | 1 |  | Notes-Tag | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 201 | 3 |  | filler | `PIC xxx` | String | VARCHAR(3) | text (trailing spaces trimmed) |
| 204 | 2 |  | Sales-Credit | `PIC 99` | int | SMALLINT | zoned decimal 2 digits, scale 0 |
| 206 | 2 |  | Sales-Discount | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 208 | 2 |  | Sales-Late-Min | `binary-short` | short | SMALLINT | native LE int16 |
| 210 | 2 |  | Sales-Late-Max | `binary-short` | short | SMALLINT | native LE int16 |
| 212 | 4 |  | Sales-Limit | `binary-long` | int | INTEGER | native LE int32 |
| 216 | 4 |  | Sales-Activety | `binary-long` | int | INTEGER | native LE int32 |
| 220 | 4 |  | Sales-Last-Inv | `binary-long` | int | INTEGER | native LE int32 |
| 224 | 4 |  | Sales-Last-Pay | `binary-long` | int | INTEGER | native LE int32 |
| 228 | 4 |  | Sales-Average | `binary-long` | int | INTEGER | native LE int32 |
| 232 | 4 |  | Sales-Pay-Activety | `binary-long` | int | INTEGER | native LE int32 |
| 236 | 4 |  | Sales-Pay-Average | `binary-long` | int | INTEGER | native LE int32 |
| 240 | 4 |  | Sales-Pay-Worst | `binary-long` | int | INTEGER | native LE int32 |
| 244 | 4 |  | Sales-Create-Date | `binary-long` | int | INTEGER | native LE int32 |
| 248 | 6 |  | Sales-Current | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 254 | 6 |  | Sales-Last | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 260 | 24 |  | **Quarters** | group | | | |
| 260 | 6 |  | &nbsp;&nbsp;Turnover-Q1 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 266 | 6 |  | &nbsp;&nbsp;Turnover-Q2 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 272 | 6 |  | &nbsp;&nbsp;Turnover-Q3 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 278 | 6 |  | &nbsp;&nbsp;Turnover-Q4 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 260 | 24 |  | **filler *(REDEFINES Quarters)*** | group | | | |
| 260 | 6 | 4 | &nbsp;&nbsp;STurnover-Q | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 284 | 6 |  | Sales-Unapplied | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 290 | 10 |  | filler | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |

### `value-record` — `copybooks/fdval.cob`（66 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 3 |  | **va-code** | group | | | |
| 0 | 1 |  | &nbsp;&nbsp;va-system | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 1 | 2 |  | **&nbsp;&nbsp;va-group** | group | | | |
| 1 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;va-first | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 2 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;va-second | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 3 | 6 |  | va-gl | `PIC 9(6)` | int | INTEGER | zoned decimal 6 digits, scale 0 |
| 9 | 24 |  | va-desc | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 33 | 3 |  | va-print | `PIC xxx` | String | VARCHAR(3) | text (trailing spaces trimmed) |
| 36 | 4 |  | va-t-this | `PIC 9(5) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 40 | 4 |  | va-t-last | `PIC 9(5) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 44 | 4 |  | va-t-year | `PIC 9(5) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 48 | 6 |  | va-v-this | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 54 | 6 |  | va-v-last | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 60 | 6 |  | va-v-year | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |

### `delivery-record` — `copybooks/fddel.cob`（134 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 8 |  | **deliv-key** | group | | | |
| 0 | 1 |  | &nbsp;&nbsp;Deliv-Key-Type | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 1 | 7 |  | **&nbsp;&nbsp;Deliv-Sales-Key** | group | | | |
| 1 | 7 |  | &nbsp;&nbsp;&nbsp;&nbsp;Deliv-Purchase-key | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 8 | 30 |  | deliv-name | `PIC x(30)` | String | VARCHAR(30) | text (trailing spaces trimmed) |
| 38 | 96 |  | **deliv-address** | group | | | |
| 38 | 48 |  | &nbsp;&nbsp;deliv-addr1 | `PIC x(48)` | String | VARCHAR(48) | text (trailing spaces trimmed) |
| 86 | 48 |  | &nbsp;&nbsp;deliv-addr2 | `PIC x(48)` | String | VARCHAR(48) | text (trailing spaces trimmed) |

### `analysis-record` — `copybooks/fdanal.cob`（36 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 3 |  | **pa-code** | group | | | |
| 0 | 1 |  | &nbsp;&nbsp;pa-system | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 1 | 2 |  | **&nbsp;&nbsp;pa-group** | group | | | |
| 1 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;pa-first | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 2 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;pa-second | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 3 | 6 |  | pa-gl | `PIC 9(6)` | int | INTEGER | zoned decimal 6 digits, scale 0 |
| 9 | 24 |  | pa-desc | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 33 | 3 |  | pa-print | `PIC xxx` | String | VARCHAR(3) | text (trailing spaces trimmed) |

### `invoice-record` — `sales/fdinv2.cob`（134 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 10 |  | **invoice-key** | group | | | |
| 0 | 8 |  | &nbsp;&nbsp;invoice-nos | `PIC 9(8)` | int | INTEGER | zoned decimal 8 digits, scale 0 |
| 8 | 1 |  | &nbsp;&nbsp;invoice-let | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 9 | 1 |  | &nbsp;&nbsp;item-nos | `binary-char` | int | SMALLINT | native LE int8 |
| 10 | 7 |  | invoice-customer | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 17 | 4 |  | invoice-date | `binary-long` | int | INTEGER | native LE int32 |
| 21 | 10 |  | filler | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 31 | 1 |  | invoice-type | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 32 | 10 |  | filler | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 42 | 92 |  | filler | `PIC x(92)` | String | VARCHAR(92) | text (trailing spaces trimmed) |

### `invoice-header` — `sales/fdinv2.cob`（137 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 42 |  | **ih-prime** | group | | | |
| 0 | 8 |  | &nbsp;&nbsp;ih-invoice | `PIC 9(8)` | int | INTEGER | zoned decimal 8 digits, scale 0 |
| 8 | 1 |  | &nbsp;&nbsp;ih-letter | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 9 | 1 |  | &nbsp;&nbsp;ih-test | `binary-char` | int | SMALLINT | native LE int8 |
| 10 | 7 |  | **&nbsp;&nbsp;ih-customer** | group | | | |
| 10 | 6 |  | &nbsp;&nbsp;&nbsp;&nbsp;ih-nos | `PIC x(6)` | String | VARCHAR(6) | text (trailing spaces trimmed) |
| 16 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;ih-check | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 17 | 4 |  | &nbsp;&nbsp;ih-date | `binary-long` | int | INTEGER | native LE int32 |
| 21 | 10 |  | &nbsp;&nbsp;ih-order | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 31 | 1 |  | &nbsp;&nbsp;ih-type | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 32 | 10 |  | &nbsp;&nbsp;ih-ref | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 42 | 95 |  | **ih-sub-prime** | group | | | |
| 42 | 32 |  | &nbsp;&nbsp;ih-description | `PIC x(32)` | String | VARCHAR(32) | text (trailing spaces trimmed) |
| 74 | 40 |  | **&nbsp;&nbsp;ih-fig** | group | | | |
| 74 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;ih-p-c | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 79 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;ih-net | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 84 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;ih-extra | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 89 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;ih-carriage | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 94 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;ih-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 99 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;ih-discount | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 104 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;ih-e-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 109 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;ih-c-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 114 | 1 |  | &nbsp;&nbsp;ih-status | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 115 | 1 |  | &nbsp;&nbsp;ih-status-P | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 116 | 1 |  | &nbsp;&nbsp;ih-status-L | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 117 | 1 |  | &nbsp;&nbsp;ih-status-C | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 118 | 1 |  | &nbsp;&nbsp;ih-status-A | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 119 | 1 |  | &nbsp;&nbsp;ih-status-I | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 120 | 1 |  | &nbsp;&nbsp;ih-lines | `binary-char` | int | SMALLINT | native LE int8 |
| 121 | 1 |  | &nbsp;&nbsp;ih-deduct-days | `binary-char` | int | SMALLINT | native LE int8 |
| 122 | 4 |  | &nbsp;&nbsp;ih-deduct-amt | `PIC 999v99 COMP` | BigDecimal | NUMERIC(5,2) | big-endian binary 4 bytes, scale 2, unsigned |
| 126 | 4 |  | &nbsp;&nbsp;ih-deduct-vat | `PIC 999v99 COMP` | BigDecimal | NUMERIC(5,2) | big-endian binary 4 bytes, scale 2, unsigned |
| 130 | 1 |  | &nbsp;&nbsp;ih-days | `binary-char` | int | SMALLINT | native LE int8 |
| 131 | 4 |  | &nbsp;&nbsp;ih-cr | `binary-long` | int | INTEGER | native LE int32 |
| 135 | 1 |  | &nbsp;&nbsp;ih-day-book-flag | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 136 | 1 |  | &nbsp;&nbsp;ih-update | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |

### `invoice-line` — `sales/fdinv2.cob`（80 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 8 |  | il-invoice | `PIC 9(8)` | int | INTEGER | zoned decimal 8 digits, scale 0 |
| 8 | 1 |  | il-letter | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 9 | 1 |  | il-line | `binary-char` | int | SMALLINT | native LE int8 |
| 10 | 13 |  | il-product | `PIC x(13)` | String | VARCHAR(13) | text (trailing spaces trimmed) |
| 23 | 2 |  | il-pa | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 25 | 2 |  | il-qty | `binary-short` | short | SMALLINT | native LE int16 |
| 27 | 1 |  | il-type | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 28 | 32 |  | il-description | `PIC x(32)` | String | VARCHAR(32) | text (trailing spaces trimmed) |
| 60 | 5 |  | il-net | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 65 | 5 |  | il-unit | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 70 | 2 |  | il-discount | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 72 | 5 |  | il-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 77 | 1 |  | il-vat-code | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 78 | 1 |  | il-update | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 79 | 1 |  | filler | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |

### `del-inv-nos-record` — `sales/fddnos.cob`（19 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 8 |  | del-inv-nos | `PIC 9(8)` | int | INTEGER | zoned decimal 8 digits, scale 0 |
| 8 | 4 |  | del-inv-dat | `binary-long` | int | INTEGER | native LE int32 |
| 12 | 7 |  | del-inv-cus | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |

### `open-item-record-2` — `sales/fdoi2.cob`（114 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|

### `oi-header` — `sales/wsoi.cob`（114 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 11 |  | **oi-key** | group | | | |
| 0 | 7 |  | **&nbsp;&nbsp;oi-customer** | group | | | |
| 0 | 6 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-nos | `PIC x(6)` | String | VARCHAR(6) | text (trailing spaces trimmed) |
| 6 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-check | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 7 | 4 |  | &nbsp;&nbsp;oi-invoice | `binary-long` | int | INTEGER | native LE int32 |
| 11 | 103 |  | **filler** | group | | | |
| 11 | 4 |  | &nbsp;&nbsp;oi-date | `binary-long` | int | INTEGER | native LE int32 |
| 15 | 6 |  | **&nbsp;&nbsp;oi-batch** | group | | | |
| 15 | 4 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-b-nos | `PIC 9(5) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 19 | 2 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-b-item | `PIC 999 COMP` | int | SMALLINT | big-endian binary 2 bytes, scale 0, unsigned |
| 21 | 1 |  | &nbsp;&nbsp;oi-type | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 22 | 25 |  | &nbsp;&nbsp;oi-description | `PIC x(25)` | String | VARCHAR(25) | text (trailing spaces trimmed) |
| 47 | 1 |  | &nbsp;&nbsp;oi-hold-flag | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 48 | 1 |  | &nbsp;&nbsp;oi-unapl | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 49 | 45 |  | **&nbsp;&nbsp;filler** | group | | | |
| 49 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-p-c | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 54 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-net | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 54 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-approp *(REDEFINES oi-net)* | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 59 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-extra | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 64 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-carriage | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 69 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 74 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-discount | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 79 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-e-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 84 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-c-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 89 | 5 |  | &nbsp;&nbsp;&nbsp;&nbsp;oi-paid | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 94 | 1 |  | &nbsp;&nbsp;oi-status | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 95 | 1 |  | &nbsp;&nbsp;oi-deduct-days | `binary-char` | int | SMALLINT | native LE int8 |
| 96 | 4 |  | &nbsp;&nbsp;oi-deduct-amt | `PIC s999v99 COMP` | BigDecimal | NUMERIC(5,2) | big-endian binary 4 bytes, scale 2, signed |
| 100 | 4 |  | &nbsp;&nbsp;oi-deduct-vat | `PIC s999v99 COMP` | BigDecimal | NUMERIC(5,2) | big-endian binary 4 bytes, scale 2, signed |
| 104 | 1 |  | &nbsp;&nbsp;oi-days | `binary-char` | int | SMALLINT | native LE int8 |
| 105 | 4 |  | &nbsp;&nbsp;oi-cr | `binary-long` | int | INTEGER | native LE int32 |
| 109 | 1 |  | &nbsp;&nbsp;oi-applied | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 110 | 4 |  | &nbsp;&nbsp;oi-date-cleared | `binary-long` | int | INTEGER | native LE int32 |

### `open-item-record-3` — `sales/fdoi3.cob`（114 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 11 |  | **oi3-key** | group | | | |
| 0 | 7 |  | &nbsp;&nbsp;oi3-customer | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 7 | 4 |  | &nbsp;&nbsp;oi3-invoice | `binary-long` | int | INTEGER | native LE int32 |
| 11 | 4 |  | oi3-date | `binary-long` | int | INTEGER | native LE int32 |
| 15 | 99 |  | filler | `PIC x(99)` | String | VARCHAR(99) | text (trailing spaces trimmed) |

### `open-item-record-s` — `sales/fdois.cob`（114 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|

### `Purch-Record` — `copybooks/fdpl.cob`（300 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 7 |  | Purch-Key | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 7 | 1 |  | purch-status | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 8 | 1 |  | Purch-Notes-Tag | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 9 | 30 |  | purch-name | `PIC x(30)` | String | VARCHAR(30) | text (trailing spaces trimmed) |
| 39 | 96 |  | **purch-address** | group | | | |
| 39 | 48 |  | &nbsp;&nbsp;purch-addr1 | `PIC x(48)` | String | VARCHAR(48) | text (trailing spaces trimmed) |
| 87 | 48 |  | &nbsp;&nbsp;purch-addr2 | `PIC x(48)` | String | VARCHAR(48) | text (trailing spaces trimmed) |
| 135 | 13 |  | purch-phone | `PIC x(13)` | String | VARCHAR(13) | text (trailing spaces trimmed) |
| 148 | 4 |  | purch-ext | `PIC x(4)` | String | VARCHAR(4) | text (trailing spaces trimmed) |
| 152 | 13 |  | purch-fax | `PIC x(13)` | String | VARCHAR(13) | text (trailing spaces trimmed) |
| 165 | 30 |  | purch-email | `PIC x(30)` | String | VARCHAR(30) | text (trailing spaces trimmed) |
| 195 | 2 |  | purch-discount | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 197 | 1 |  | purch-credit | `binary-char` | int | SMALLINT | native LE int8 |
| 198 | 4 |  | purch-sortcode | `binary-long` | int | INTEGER | native LE int32 |
| 202 | 4 |  | purch-accountno | `binary-long` | int | INTEGER | native LE int32 |
| 206 | 4 |  | purch-limit | `binary-long` | int | INTEGER | native LE int32 |
| 210 | 4 |  | purch-activety | `binary-long` | int | INTEGER | native LE int32 |
| 214 | 4 |  | purch-last-inv | `binary-long` | int | INTEGER | native LE int32 |
| 218 | 4 |  | purch-last-pay | `binary-long` | int | INTEGER | native LE int32 |
| 222 | 4 |  | purch-average | `binary-long` | int | INTEGER | native LE int32 |
| 226 | 4 |  | purch-create-date | `binary-long` | int | INTEGER | native LE int32 |
| 230 | 4 |  | purch-pay-activety | `binary-long` | int | INTEGER | native LE int32 |
| 234 | 4 |  | purch-pay-average | `binary-long` | int | INTEGER | native LE int32 |
| 238 | 4 |  | purch-pay-worst | `binary-long` | int | INTEGER | native LE int32 |
| 242 | 6 |  | purch-current | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 248 | 6 |  | purch-last | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 254 | 24 |  | **quarters** | group | | | |
| 254 | 6 |  | &nbsp;&nbsp;turnover-q1 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 260 | 6 |  | &nbsp;&nbsp;turnover-q2 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 266 | 6 |  | &nbsp;&nbsp;turnover-q3 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 272 | 6 |  | &nbsp;&nbsp;turnover-q4 | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 254 | 24 |  | **filler *(REDEFINES quarters)*** | group | | | |
| 254 | 6 | 4 | &nbsp;&nbsp;pturnover-q | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 278 | 6 |  | purch-unapplied | `PIC s9(8)v99 COMP-3` | BigDecimal | NUMERIC(10,2) | packed decimal 10 digits, scale 2, signed |
| 284 | 16 |  | filler | `PIC x(16)` | String | VARCHAR(16) | text (trailing spaces trimmed) |

### `del-inv-nos-record` — `purchase/fdpdnos.cob`（19 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 8 |  | del-inv-nos | `PIC 9(8)` | int | INTEGER | zoned decimal 8 digits, scale 0 |
| 8 | 4 |  | del-inv-dat | `binary-long` | int | INTEGER | native LE int32 |
| 12 | 7 |  | del-inv-cus | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |

### `invoice-record` — `purchase/fdpinv2.cob`（129 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 9 |  | **invoice-key** | group | | | |
| 0 | 8 |  | &nbsp;&nbsp;invoice-nos | `PIC 9(8)` | int | INTEGER | zoned decimal 8 digits, scale 0 |
| 8 | 1 |  | &nbsp;&nbsp;item-nos | `binary-char` | int | SMALLINT | native LE int8 |
| 9 | 7 |  | invoice-supplier | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 16 | 4 |  | invoice-date | `binary-long` | int | INTEGER | native LE int32 |
| 20 | 10 |  | inv-order | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 30 | 1 |  | invoice-type | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 31 | 10 |  | filler | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 41 | 88 |  | filler | `PIC x(88)` | String | VARCHAR(88) | text (trailing spaces trimmed) |

### `invoice-header` — `purchase/fdpinv2.cob`（129 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 8 |  | ih-invoice | `PIC 9(8)` | int | INTEGER | zoned decimal 8 digits, scale 0 |
| 8 | 1 |  | ih-test | `binary-char` | int | SMALLINT | native LE int8 |
| 9 | 7 |  | **ih-supplier** | group | | | |
| 9 | 6 |  | &nbsp;&nbsp;ih-nos | `PIC x(6)` | String | VARCHAR(6) | text (trailing spaces trimmed) |
| 15 | 1 |  | &nbsp;&nbsp;ih-check | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 16 | 4 |  | ih-date | `binary-long` | int | INTEGER | native LE int32 |
| 20 | 10 |  | ih-order | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 30 | 1 |  | ih-type | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 31 | 10 |  | ih-ref | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 41 | 40 |  | **ih-fig** | group | | | |
| 41 | 5 |  | &nbsp;&nbsp;ih-p-c | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 46 | 5 |  | &nbsp;&nbsp;ih-net | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 51 | 5 |  | &nbsp;&nbsp;ih-extra | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 56 | 5 |  | &nbsp;&nbsp;ih-carriage | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 61 | 5 |  | &nbsp;&nbsp;ih-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 66 | 5 |  | &nbsp;&nbsp;ih-discount | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 71 | 5 |  | &nbsp;&nbsp;ih-e-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 76 | 5 |  | &nbsp;&nbsp;ih-c-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 81 | 1 |  | ih-status | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 82 | 1 |  | ih-lines | `binary-char` | int | SMALLINT | native LE int8 |
| 83 | 1 |  | ih-deduct-days | `binary-char` | int | SMALLINT | native LE int8 |
| 84 | 4 |  | ih-deduct-amt | `PIC 999v99 COMP` | BigDecimal | NUMERIC(5,2) | big-endian binary 4 bytes, scale 2, unsigned |
| 88 | 4 |  | ih-deduct-vat | `PIC 999v99 COMP` | BigDecimal | NUMERIC(5,2) | big-endian binary 4 bytes, scale 2, unsigned |
| 92 | 1 |  | ih-days | `binary-char` | int | SMALLINT | native LE int8 |
| 93 | 4 |  | ih-cr | `binary-long` | int | INTEGER | native LE int32 |
| 97 | 1 |  | ih-day-book-flag | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 98 | 1 |  | ih-update | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 99 | 30 |  | filler | `PIC x(30)` | String | VARCHAR(30) | text (trailing spaces trimmed) |

### `invoice-line` — `purchase/fdpinv2.cob`（74 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 8 |  | il-invoice | `PIC 9(8)` | int | INTEGER | zoned decimal 8 digits, scale 0 |
| 8 | 1 |  | il-line | `binary-char` | int | SMALLINT | native LE int8 |
| 9 | 13 |  | il-product | `PIC x(13)` | String | VARCHAR(13) | text (trailing spaces trimmed) |
| 22 | 2 |  | il-pa | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 24 | 2 |  | filler | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 26 | 2 |  | il-qty | `binary-short` | short | SMALLINT | native LE int16 |
| 28 | 1 |  | il-type | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 29 | 24 |  | il-description | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 53 | 2 |  | filler | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 55 | 5 |  | il-net | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 60 | 5 |  | il-unit | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 65 | 2 |  | il-discount | `PIC 99v99 COMP` | BigDecimal | NUMERIC(4,2) | big-endian binary 2 bytes, scale 2, unsigned |
| 67 | 5 |  | il-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 72 | 1 |  | il-vat-code | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 73 | 1 |  | il-update | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |

### `open-item-record-s` — `purchase/fdois.cob`（109 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|

### `open-item-record-4` — `purchase/fdoi4.cob`（109 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|

### `oi-header` — `purchase/wsoi.cob`（109 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 7 |  | **oi-key** | group | | | |
| 0 | 7 |  | **&nbsp;&nbsp;oi-customer** | group | | | |
| 0 | 7 |  | **&nbsp;&nbsp;&nbsp;&nbsp;oi-Supplier** | group | | | |
| 0 | 6 |  | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;oi-nos | `PIC x(6)` | String | VARCHAR(6) | text (trailing spaces trimmed) |
| 6 | 1 |  | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;oi-check | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 7 | 4 |  | oi-invoice | `binary-long` | int | INTEGER | native LE int32 |
| 11 | 4 |  | oi-date | `binary-long` | int | INTEGER | native LE int32 |
| 15 | 6 |  | **oi-batch** | group | | | |
| 15 | 4 |  | &nbsp;&nbsp;oi-b-nos | `PIC 9(5) COMP` | int | INTEGER | big-endian binary 4 bytes, scale 0, unsigned |
| 19 | 2 |  | &nbsp;&nbsp;oi-b-item | `PIC 999 COMP` | int | SMALLINT | big-endian binary 2 bytes, scale 0, unsigned |
| 21 | 1 |  | oi-type | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 22 | 10 |  | oi-ref | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 32 | 10 |  | oi-order | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 42 | 1 |  | oi-hold-flag | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 43 | 1 |  | oi-unapl | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 44 | 45 |  | **filler** | group | | | |
| 44 | 5 |  | &nbsp;&nbsp;oi-p-c | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 49 | 5 |  | &nbsp;&nbsp;oi-net | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 49 | 5 |  | &nbsp;&nbsp;oi-approp *(REDEFINES oi-net)* | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 54 | 5 |  | &nbsp;&nbsp;oi-extra | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 59 | 5 |  | &nbsp;&nbsp;oi-carriage | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 64 | 5 |  | &nbsp;&nbsp;oi-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 69 | 5 |  | &nbsp;&nbsp;oi-discount | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 74 | 5 |  | &nbsp;&nbsp;oi-e-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 79 | 5 |  | &nbsp;&nbsp;oi-c-vat | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 84 | 5 |  | &nbsp;&nbsp;oi-paid | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 89 | 1 |  | oi-status | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 90 | 1 |  | oi-deduct-days | `binary-char` | int | SMALLINT | native LE int8 |
| 91 | 4 |  | oi-deduct-amt | `PIC s999v99 COMP` | BigDecimal | NUMERIC(5,2) | big-endian binary 4 bytes, scale 2, signed |
| 95 | 4 |  | oi-deduct-vat | `PIC s999v99 COMP` | BigDecimal | NUMERIC(5,2) | big-endian binary 4 bytes, scale 2, signed |
| 99 | 1 |  | oi-days | `binary-char` | int | SMALLINT | native LE int8 |
| 100 | 4 |  | oi-cr | `binary-long` | int | INTEGER | native LE int32 |
| 104 | 1 |  | oi-applied | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 105 | 4 |  | oi-date-cleared | `binary-long` | int | INTEGER | native LE int32 |

### `open-item-record-5` — `purchase/fdoi5.cob`（109 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 11 |  | **oi5-key** | group | | | |
| 0 | 7 |  | &nbsp;&nbsp;oi5-supplier | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 7 | 4 |  | &nbsp;&nbsp;oi5-invoice | `binary-long` | int | INTEGER | native LE int32 |
| 11 | 4 |  | oi5-date | `binary-long` | int | INTEGER | native LE int32 |
| 15 | 94 |  | filler | `PIC x(94)` | String | VARCHAR(94) | text (trailing spaces trimmed) |

### `pay-record` — `purchase/fdpay.cob`（237 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 8 |  | **pay-key** | group | | | |
| 0 | 7 |  | &nbsp;&nbsp;pay-supl-key | `PIC x(7)` | String | VARCHAR(7) | text (trailing spaces trimmed) |
| 7 | 1 |  | &nbsp;&nbsp;pay-nos | `binary-char` | int | SMALLINT | native LE int8 |
| 8 | 1 |  | pay-cont | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 9 | 4 |  | pay-date | `binary-long` | int | INTEGER | native LE int32 |
| 13 | 4 |  | pay-cheque | `binary-long` | int | INTEGER | native LE int32 |
| 17 | 4 |  | pay-sortcode | `binary-long` | int | INTEGER | native LE int32 |
| 21 | 4 |  | pay-account | `binary-long` | int | INTEGER | native LE int32 |
| 25 | 5 |  | pay-gross | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 30 | 23 | 9 | **filler** | group | | | |
| 30 | 4 |  | &nbsp;&nbsp;pay-folio | `binary-long` | int | INTEGER | native LE int32 |
| 34 | 1 |  | &nbsp;&nbsp;pay-period | `binary-char` | int | SMALLINT | native LE int8 |
| 35 | 5 |  | &nbsp;&nbsp;pay-value | `PIC s9(7)v99 COMP-3` | BigDecimal | NUMERIC(9,2) | packed decimal 9 digits, scale 2, signed |
| 40 | 3 |  | &nbsp;&nbsp;pay-deduct | `PIC s999v99 COMP-3` | BigDecimal | NUMERIC(5,2) | packed decimal 5 digits, scale 2, signed |
| 43 | 10 |  | &nbsp;&nbsp;pay-invoice | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |

### `nl-record` — `incomplete_records_system/wsnl.cob`（116 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 10 |  | **nl-key** | group | | | |
| 0 | 5 |  | &nbsp;&nbsp;nl-owning | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 5 | 5 |  | &nbsp;&nbsp;nl-sub-nominal | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 10 | 1 |  | nl-type | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 11 | 105 |  | **nl-data** | group | | | |
| 11 | 24 |  | &nbsp;&nbsp;nl-name | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 35 | 8 |  | &nbsp;&nbsp;nl-dr | `PIC 9(8)v99 COMP` | BigDecimal | NUMERIC(10,2) | big-endian binary 8 bytes, scale 2, unsigned |
| 43 | 8 |  | &nbsp;&nbsp;nl-cr | `PIC 9(8)v99 COMP` | BigDecimal | NUMERIC(10,2) | big-endian binary 8 bytes, scale 2, unsigned |
| 51 | 8 | 4 | &nbsp;&nbsp;nl-dr-last | `PIC 9(8)v99 COMP` | BigDecimal | NUMERIC(10,2) | big-endian binary 8 bytes, scale 2, unsigned |
| 83 | 8 | 4 | &nbsp;&nbsp;nl-cr-last | `PIC 9(8)v99 COMP` | BigDecimal | NUMERIC(10,2) | big-endian binary 8 bytes, scale 2, unsigned |
| 115 | 1 |  | &nbsp;&nbsp;nl-ac | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 11 | 5 |  | **filler *(REDEFINES nl-data)*** | group | | | |
| 11 | 5 |  | &nbsp;&nbsp;nl-pointer | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |

### `system-record` — `incomplete_records_system/wssystem.cob`（312 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 8 |  | run-date | `PIC x(8)` | String | VARCHAR(8) | text (trailing spaces trimmed) |
| 8 | 24 |  | suser | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 32 | 24 |  | client | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 56 | 24 |  | address-1 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 80 | 24 |  | address-2 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 104 | 24 |  | address-3 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 128 | 24 |  | address-4 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 152 | 8 |  | start-date | `PIC x(8)` | String | VARCHAR(8) | text (trailing spaces trimmed) |
| 160 | 8 |  | end-date | `PIC x(8)` | String | VARCHAR(8) | text (trailing spaces trimmed) |
| 168 | 49 |  | **system-files** | group | | | |
| 168 | 9 |  | &nbsp;&nbsp;fn-1 | `PIC x(9)` | String | VARCHAR(9) | text (trailing spaces trimmed) |
| 177 | 10 |  | &nbsp;&nbsp;fn-2 | `PIC x(10)` | String | VARCHAR(10) | text (trailing spaces trimmed) |
| 187 | 8 |  | &nbsp;&nbsp;fn-3 | `PIC x(8)` | String | VARCHAR(8) | text (trailing spaces trimmed) |
| 195 | 8 |  | &nbsp;&nbsp;fn-4 | `PIC x(8)` | String | VARCHAR(8) | text (trailing spaces trimmed) |
| 203 | 12 |  | &nbsp;&nbsp;fn-5 | `PIC x(12)` | String | VARCHAR(12) | text (trailing spaces trimmed) |
| 215 | 1 |  | &nbsp;&nbsp;filler | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 216 | 1 |  | &nbsp;&nbsp;system-ops | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 217 | 4 |  | pass-word | `PIC x(4)` | String | VARCHAR(4) | text (trailing spaces trimmed) |
| 221 | 5 |  | next-post | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 226 | 12 |  | **vat-rates** | group | | | |
| 226 | 4 |  | &nbsp;&nbsp;vat | `PIC 99v99` | BigDecimal | NUMERIC(4,2) | zoned decimal 4 digits, scale 2 |
| 230 | 4 |  | &nbsp;&nbsp;vat2 | `PIC 99v99` | BigDecimal | NUMERIC(4,2) | zoned decimal 4 digits, scale 2 |
| 234 | 4 |  | &nbsp;&nbsp;vat3 | `PIC 99v99` | BigDecimal | NUMERIC(4,2) | zoned decimal 4 digits, scale 2 |
| 226 | 12 |  | **vat-group *(REDEFINES vat-rates)*** | group | | | |
| 226 | 4 | 3 | &nbsp;&nbsp;vat-psent | `PIC 99v99` | BigDecimal | NUMERIC(4,2) | zoned decimal 4 digits, scale 2 |
| 238 | 1 |  | pass-value | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 239 | 1 |  | save-sequ | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 240 | 18 |  | system-work-group | `PIC x(18)` | String | VARCHAR(18) | text (trailing spaces trimmed) |
| 258 | 1 |  | PL-App-Created | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 259 | 5 |  | PL-Approp-AC | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 264 | 32 |  | Print-Spool-Name | `PIC x(32)` | String | VARCHAR(32) | text (trailing spaces trimmed) |
| 296 | 1 |  | First-Time-FLag | `PIC 9` | int | SMALLINT | zoned decimal 1 digits, scale 0 |
| 297 | 7 |  | filler | `PIC 9(7)` | int | INTEGER | zoned decimal 7 digits, scale 0 |
| 304 | 8 |  | filler | `PIC x(8)` | String | VARCHAR(8) | text (trailing spaces trimmed) |

### `default-record` — `incomplete_records_system/wsdflt.cob`（256 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 5 | 32 | def-acs | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 160 | 2 | 32 | def-codes | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 224 | 1 | 32 | def-vat | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |

### `posting-record` — `incomplete_records_system/wspost.cob`（79 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 5 |  | post-key | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 5 | 2 |  | post-code | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 7 | 8 |  | post-date | `PIC x(8)` | String | VARCHAR(8) | text (trailing spaces trimmed) |
| 15 | 5 |  | post-dr | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 20 | 5 |  | post-cr | `PIC 9(5)` | int | INTEGER | zoned decimal 5 digits, scale 0 |
| 25 | 9 |  | post-amount | `PIC s9(7)v99` | BigDecimal | NUMERIC(9,2) | zoned decimal 9 digits, scale 2, sign leading overpunch |
| 34 | 32 |  | post-legend | `PIC x(32)` | String | VARCHAR(32) | text (trailing spaces trimmed) |
| 66 | 2 |  | vat-ac-def | `PIC 99` | int | SMALLINT | zoned decimal 2 digits, scale 0 |
| 68 | 2 |  | post-vat-side | `PIC xx` | String | VARCHAR(2) | text (trailing spaces trimmed) |
| 70 | 9 |  | vat-amount | `PIC s9(7)v99` | BigDecimal | NUMERIC(9,2) | zoned decimal 9 digits, scale 2, sign leading overpunch |

### `Final-Record` — `incomplete_records_system/wsfinal.cob`（655 バイト）

| Off | Len | Occ | 項目 | COBOL | Java | SQL | codec |
|---:|---:|---:|---|---|---|---|---|
| 0 | 624 |  | **ar1-fields** | group | | | |
| 0 | 24 |  | &nbsp;&nbsp;ar1-1 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 24 | 24 |  | &nbsp;&nbsp;ar1-2 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 48 | 24 |  | &nbsp;&nbsp;ar1-3 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 72 | 24 |  | &nbsp;&nbsp;ar1-4 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 96 | 24 |  | &nbsp;&nbsp;ar1-5 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 120 | 24 |  | &nbsp;&nbsp;ar1-6 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 144 | 24 |  | &nbsp;&nbsp;ar1-7 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 168 | 24 |  | &nbsp;&nbsp;ar1-8 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 192 | 24 |  | &nbsp;&nbsp;ar1-9 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 216 | 24 |  | &nbsp;&nbsp;ar1-10 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 240 | 24 |  | &nbsp;&nbsp;ar1-11 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 264 | 24 |  | &nbsp;&nbsp;ar1-12 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 288 | 24 |  | &nbsp;&nbsp;ar1-13 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 312 | 24 |  | &nbsp;&nbsp;ar1-14 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 336 | 24 |  | &nbsp;&nbsp;ar1-15 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 360 | 24 |  | &nbsp;&nbsp;ar1-16 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 384 | 24 |  | &nbsp;&nbsp;ar1-17 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 408 | 24 |  | &nbsp;&nbsp;ar1-18 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 432 | 24 |  | &nbsp;&nbsp;ar1-19 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 456 | 24 |  | &nbsp;&nbsp;ar1-20 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 480 | 24 |  | &nbsp;&nbsp;ar1-21 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 504 | 24 |  | &nbsp;&nbsp;ar1-22 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 528 | 24 |  | &nbsp;&nbsp;ar1-23 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 552 | 24 |  | &nbsp;&nbsp;ar1-24 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 576 | 24 |  | &nbsp;&nbsp;ar1-25 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 600 | 24 |  | &nbsp;&nbsp;ar1-26 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 0 | 624 |  | **filler *(REDEFINES ar1-fields)*** | group | | | |
| 0 | 24 | 26 | &nbsp;&nbsp;ar1 | `PIC x(24)` | String | VARCHAR(24) | text (trailing spaces trimmed) |
| 624 | 26 |  | **ar2-fields** | group | | | |
| 624 | 1 |  | &nbsp;&nbsp;ar2-1 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 625 | 1 |  | &nbsp;&nbsp;ar2-2 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 626 | 1 |  | &nbsp;&nbsp;ar2-3 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 627 | 1 |  | &nbsp;&nbsp;ar2-4 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 628 | 1 |  | &nbsp;&nbsp;ar2-5 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 629 | 1 |  | &nbsp;&nbsp;ar2-6 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 630 | 1 |  | &nbsp;&nbsp;ar2-7 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 631 | 1 |  | &nbsp;&nbsp;ar2-8 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 632 | 1 |  | &nbsp;&nbsp;ar2-9 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 633 | 1 |  | &nbsp;&nbsp;ar2-10 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 634 | 1 |  | &nbsp;&nbsp;ar2-11 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 635 | 1 |  | &nbsp;&nbsp;ar2-12 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 636 | 1 |  | &nbsp;&nbsp;ar2-13 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 637 | 1 |  | &nbsp;&nbsp;ar2-14 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 638 | 1 |  | &nbsp;&nbsp;ar2-15 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 639 | 1 |  | &nbsp;&nbsp;ar2-16 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 640 | 1 |  | &nbsp;&nbsp;ar2-17 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 641 | 1 |  | &nbsp;&nbsp;ar2-18 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 642 | 1 |  | &nbsp;&nbsp;ar2-19 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 643 | 1 |  | &nbsp;&nbsp;ar2-20 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 644 | 1 |  | &nbsp;&nbsp;ar2-21 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 645 | 1 |  | &nbsp;&nbsp;ar2-22 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 646 | 1 |  | &nbsp;&nbsp;ar2-23 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 647 | 1 |  | &nbsp;&nbsp;ar2-24 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 648 | 1 |  | &nbsp;&nbsp;ar2-25 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 649 | 1 |  | &nbsp;&nbsp;ar2-26 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 624 | 26 |  | **filler *(REDEFINES ar2-fields)*** | group | | | |
| 624 | 1 | 26 | &nbsp;&nbsp;ar2 | `PIC x` | String | CHAR(1) | text (trailing spaces trimmed) |
| 650 | 5 |  | ar3 | `PIC x(5)` | String | VARCHAR(5) | text (trailing spaces trimmed) |

