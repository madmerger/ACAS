# ACAS COBOL → Java マイグレーション設計（Phase 0）

GnuCOBOL 版 ACAS を Java（Spring Boot + RDB）へ**手動移植**するための分析・設計成果物。

| # | 文書 | 内容 |
|---|---|---|
| 01 | [プログラム一覧と呼び出し関係](01-program-inventory.md) | 全 `.cbl` 134 本の一覧、モジュール依存図、メニュー → プログラム対応、CALL 先 |
| 02 | [ファイル（ISAM）構造とレコードレイアウト](02-file-layouts.md) | 28 論理ファイルの編成/キー、全レコードのオフセット・型・Java/SQL 対応 |
| 03 | [RDB スキーマ設計](03-rdb-schema.md) + [`schema/acas-schema.sql`](schema/acas-schema.sql) | 変換ルール、41 テーブルの DDL、モジュール間データ共有 |
| 04 | [COBOL 型 → Java/SQL 対応表](04-type-mapping.md) | COMP-3/COMP/BINARY-*/ゾーン 10 進 → BigDecimal 等、丸め・日付の再現ルール |
| 05 | [共通データ構造 → Java ドメイン/DTO](05-ws-domain-mapping.md) | `ws*.cob` の対応表、移植時の設計ルール（セキュリティ含む） |
| 06 | [移行方式の比較](06-migration-strategy.md) | 全面書き換え vs ストラングラー、推奨案 |
| 07 | [レガシービルド確認](07-legacy-build-report.md) | GnuCOBOL 3.1.2 で 115 本ビルド成功・起動確認 |

## 主要な数値

- プログラム: 134 本 / 96,741 行（`experimental-stuff/` 除く）。SCREEN SECTION 使用 32 本、印刷 61 本。
- データファイル: 28 論理ファイル（業務 21 + ソート作業 2 + IRS 5）。全レコード長を GnuCOBOL の `FUNCTION LENGTH` と照合し一致。
- RDB: 29 テーブル + OCCURS 子テーブル 12 = 41 テーブル。

## 再生成方法

`01`・`02`・`schema/acas-schema.sql`・`data/*.json` はソースから自動生成（手編集しない）。

```bash
python3 docs/migration/tools/gen_docs.py     # 01, 02, data/calls.json, data/menus.json
python3 docs/migration/tools/gen_schema.py   # schema/acas-schema.sql（標準出力に 03 のテーブル一覧行）
docs/migration/tools/verify_layout.sh copybooks/fdsl.cob ...   # cobc でレコード長を照合（GnuCOBOL 必須）
```

| ツール | 役割 |
|---|---|
| `tools/extract_calls.py` | 静的 `CALL "x"` と動的 `MOVE "x" TO var` + `CALL var` の抽出、COPY 一覧 |
| `tools/extract_menus.py` | メニュー（`GO TO ... DEPENDING ON`）のキー → 段落 → プログラム対応 |
| `tools/cobol_layout.py` | copybook のレイアウト解析（オフセット、長さ、OCCURS/REDEFINES、型対応） |
| `tools/gen_docs.py` / `tools/gen_schema.py` | 文書・DDL 生成 |
| `tools/verify_layout.sh` | 解析結果のレコード長を GnuCOBOL 実測値と照合 |
