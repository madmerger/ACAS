# 買掛元帳（PL）の実 UI テスト

リポジトリのルートで、展開済みの実測証跡ディレクトリ（`scenarios/catalog.json` と `runs/` を含む）を指定して実行します。共通のケース生成だけでは、買掛元帳のフィクスチャは生成されません。Xcode プロジェクトを生成する前に、両方の生成コマンドを実行してください。

```sh
EVIDENCE="$HOME/acas-ipad-oracle"
python3 ipad/scripts/generate_cases.py "$EVIDENCE"
python3 ipad/ACASUITests/PL/generate_fixtures.py "$EVIDENCE"
xcodegen generate --spec ipad/project.yml
```

`xcrun simctl list devices available` で調べた iPad Simulator の UUID を指定します。

```sh
xcodebuild -project ipad/ACAS.xcodeproj -scheme ACAS \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath ipad/.derived \
  -parallel-testing-enabled NO -only-testing:ACASUITests/PurchaseFlows test
```
