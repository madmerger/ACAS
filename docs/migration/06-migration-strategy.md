# 06. 移行方式の比較（全面書き換え vs ストラングラー）

## 1. 判断材料（Phase 0 の分析結果）

| # | 事実 | 根拠 | 移行方式への影響 |
|---|---|---|---|
| F1 | 機能の入口はメニューの動的 CALL（`MOVE "sl010" TO ws-called` → `CALL ws-called`）で、1 メニュー項目 = 1〜3 プログラム | `01-program-inventory.md` §3 | 機能単位の切り出し境界は明確 → どちらの方式でも「1 プログラム = 1 サービス」で進められる |
| F2 | 全業務プログラムが ISAM（BDB）/ RELATIVE / SEQUENTIAL ファイルを**直接** OPEN/READ/WRITE する。RDB 対応 DAL を持つのは在庫（`acas011` → `stockMT`）のみで、その先の MySQL DAL モジュール（`HandleDB` 等）はリポジトリに無い | `01-program-inventory.md` ⚠ 印、`02-file-layouts.md` | COBOL 側をそのまま RDB に向けられない。ストラングラーで COBOL と Java を並走させるにはファイル⇔RDB の同期が必要 |
| F3 | `batch.dat`・`posting.dat`（SL/PL → GL）、`postings2irs.dat`（SL/PL → IRS）、`stockctl.dat`（Stock ⇔ SL 請求書）、`purchled.dat`（PL ⇔ Stock）、`value`/`analysis`/`delivery`（SL ⇔ PL）がサブシステム間で共有 | `03-rdb-schema.md` §3 | サブシステム単位で切り替えても、共有ファイルは双方向同期が必要（SL を先に Java 化すると GL（COBOL）が読む batch/posting を Java から ISAM へ書き戻す必要がある） |
| F4 | ファイルはネイティブ LE 2 進・ビッグエンディアン COMP・COMP-3 が混在するバイナリ形式で、BDB のロック/索引も絡む | `04-type-mapping.md` §1 | 双方向同期ツールは「読む」だけでなく「COBOL 互換で書く」実装と検証が必要（工数・リスク大） |
| F5 | 画面は SCREEN SECTION / `DISPLAY ... AT` の端末 UI（32 プログラムが SCREEN SECTION）。印刷は 61 プログラムが `lpr` スプール | `01-program-inventory.md` §4 | UI を共存させる手段がない（端末 UI と Web UI の混在運用になる）。ストラングラーでも利用者は 2 つの UI を行き来する |
| F6 | レガシーは GnuCOBOL 3.1.2 で 115 本すべてビルド成功、起動確認済み | `07-legacy-build-report.md` | COBOL 版を「正解（オラクル）」として同一入力→同一出力の比較テストが可能 |
| F7 | 規模: 134 プログラム / 約 9.7 万行（派生版含む）。最大は `stockMT` 3,478 行、`sys002` 2,445 行、`sl920` 2,113 行 | `01-program-inventory.md` §1 | 一括切替でもモジュール順に実装・検証を積み上げられる規模 |

## 2. 方式比較

| 観点 | A. 全面書き換え（実装はモジュール順、切替は一括） | B. ストラングラー（サブシステム単位で順次本番切替） |
|---|---|---|
| データ | Java は RDB のみ。切替時に Phase 1 の移行ツール（ISAM → RDB 一方向）で一括移行 | 移行期間中は ISAM と RDB の**双方向同期**が必要（F2–F4）。Java→ISAM の COBOL 互換ライタも作る |
| 追加開発 | 一方向デコーダのみ | 双方向同期・競合制御・BDB ロック対応、COBOL メニューから Java 機能への遷移手段 |
| 検証 | COBOL 版をオラクルにした比較テスト（F6）を各モジュール完了時に実施 | 同左 + 同期の整合性検証（切替単位ごと） |
| 利用者影響 | 切替日に UI が端末 → Web へ一度だけ変わる | 移行期間中は端末 UI と Web UI を併用（F5） |
| リスク | 切替日に全機能を揃える必要（ビッグバン）。比較テストと切替リハーサルで低減 | 同期不具合による元帳不整合（会計データとして致命的） |
| 価値の出方 | 全機能完成まで本番価値なし（ただし Phase ごとに API/画面はデモ可能） | 早期から一部機能を本番利用可能 |
| ユーザー指定の Phase 順との整合 | Phase 1–5 の順そのまま | Phase 1 に同期基盤が加わり、各 Phase に切替作業が入る |

## 3. 推奨

**A. 全面書き換え（モジュール順に実装・比較検証し、切替は一括）を推奨**します。

- F2–F4 により、ストラングラーの前提となる「COBOL と Java が同じデータを安全に共有する」コストが大きく、会計データの整合性リスクが高い。
- F1・F6 により、全面書き換えでも 1 機能ずつ実装 → COBOL 版との比較テストで逐次検証でき、ビッグバンのリスクは「切替時のデータ移行」に限定できる。データ移行は Phase 1 のツールで何度でもリハーサルできる。
- ストラングラーを選ぶ場合は、最も独立性が高い **Stock（在庫）** から始めるのが妥当（既に `acas011` で DAL 分離の設計があり、共有ファイルが `stockctl.dat`/`purchled.dat`/`staudit.dat` に限られる）。ただしユーザー指定の優先順位（sales → purchase → …）とは異なる。

## 4. どちらの方式でも共通の進め方

1. Phase 1: `java/` に Maven（Spring Boot 3 / Java 17）プロジェクト、Flyway で `schema/acas-schema.sql`、JPA エンティティ + Spring Data リポジトリ、ISAM → RDB 移行ツール（codec は `04-type-mapping.md` に従う）。
2. Phase 2: `maps04`（日付）・`maps09`（チェックデジット）・`maps01`（パスワード → ハッシュ化）・`sys002`（システム設定）・`acas011`/`irsub*`（ファイルハンドラ → リポジトリ）をサービス化。
3. Phase 3 以降: メニュー対応表（`01-program-inventory.md` §3）の 1 行 = 1 機能として REST API 化。
4. Phase 5: 共通 `cases.json` を COBOL（実バイナリ）と Java の両方に流し、出力ファイル/帳票を比較。
