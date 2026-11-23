# iPad 版実装規約

## 並行作業の境界

各機能担当は `ACAS/Sources/Features/<機能>/`、`ACASCore/Sources/ACASCore/Programs/<機能>/`、`ACASUITests/<機能>/` のみを編集する。基盤担当が `project.yml`、`Sources/Foundation/`、`Runtime/`、共通リソース、検証・集約スクリプト、およびルート登録を統合する。画面の機能メニューは `Workspace` を受け取り、セクションごとに基盤担当へ登録を依頼する。追加する翻訳は機能専用の `ja.lproj/<機能>.strings` とし、キーに機能の接頭辞を付ける。

| 担当 | 境界 |
|---|---|
| 売掛元帳 | `SL`。顧客・請求・入金・帳票。前半／後半 PR に分ける場合は同じ担当が契約を管理する。 |
| 買掛元帳 | `PL`。仕入先・請求・支払・帳票。前半／後半も同様。 |
| 在庫管理 | `Stock`。品目・入出庫・在庫評価。 |
| 簡易記帳・連携 | `IRS`、`Integration`。各台帳の内部レイアウトを複製せず、担当の公開サービスで連携する。 |
| システム設定・総勘定元帳 | `System`、`GL`。会社・台帳設定、勘定科目・仕訳・残高・決算。 `SYS-001` の残作業を担当する。 |

## 業務サービスと日本語 UI

SwiftUI のリスト、フォーム、テーブル等に専念させ、入力・取消・確定を型付きの業務操作に結び付ける。業務サービスは `BusinessContext` の SQLite と時計を使用する。端末座標・キー列を実装に持ち込まない。日本語 UI にプログラム ID、英字の操作案内、端末の日付書式を出さない。固有名・取引コード等はデータのまま表示する。索引キー、固定長バイト列、符号、スケール、COBOL の丸めと出力順序は実測と照合する。帳票プレビューは日本語の列を使い、互換出力には原本と比較できるバイト列を保持する。

## チェック

SYS-001 の証跡生成には、Berkeley DB の索引ファイルを読み出す `db_dump` が必要。
macOS では `command -v db_dump` で確認し、未導入なら `brew install berkeley-db` を実行して
`$(brew --prefix berkeley-db)/bin` を `PATH` に追加する。

```sh
# UDID は xcrun simctl list devices available で確認する。
UDID='<iPadのUUID>'
DESTINATION="platform=iOS Simulator,id=$UDID"
python3 ipad/scripts/generate_cases.py "$HOME/acas-ipad-oracle"
xcodegen generate --spec ipad/project.yml
swift test --package-path ipad/ACASCore
xcodebuild -project ipad/ACAS.xcodeproj -scheme ACAS \
  -destination "$DESTINATION" -derivedDataPath ipad/.derived build-for-testing
xcodebuild -project ipad/ACAS.xcodeproj -scheme ACAS \
  -destination "$DESTINATION" -derivedDataPath ipad/.derived \
  -parallel-testing-enabled NO test-without-building
```

録画は別のターミナルで、テスト対象アプリのインストール後にケース ID が表示されてから開始する。判定表示まで記録して Ctrl+C で終了する。

```sh
xcrun simctl io "$UDID" recordVideo --codec=h264 "<ケースID>.mov"
ffmpeg -i "<ケースID>.mov" -vf 'scale=1600:-2' -c:v libx264 \
  -pix_fmt yuv420p -movflags +faststart "<ケースID>.mp4"
```

生成した `.generated/cases.json` は453件の台帳、`.generated/fixtures/` は現時点の実 UI テスト用入力とレガシー実測値。製品ビルドに同梱しない。テスト時の DB はサンドボックス内の専用 SQLite を使う。判定は画面の項目・遷移を XCUITest、前後の論理レコードと帳票バイトを比較器で確認する。旧画面の英語や端末の桁位置は比較しない。

基盤段階の `SYS-001` は会社名の保存のみで、台帳の設定・マスタ投入・設定帳票は未移植。テストは保存まで実操作し、オラクルとの差を不一致として記録する。ケースそのものの合格を表すものではない。
