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

74件の証跡ケースだけを録画する場合は、先に `build-for-testing` し、テスト済みアプリを Simulator にインストールしてください。

```sh
xcrun simctl install "$UDID" ipad/.derived/Build/Products/Debug-iphonesimulator/ACAS.app
python3 ipad/ACASUITests/PL/record_equivalence.py "$UDID" ipad/.derived/Build/Products/*.xctestrun "$HOME/acas-pl-run-1"
```

不一致の修正後は、最後に `PL-414` のようなケース ID を指定すると該当分だけを実行します。各回のディレクトリは別にしてください。録画開始と各ケース開始は同じ時計で記録され、判定は Simulator のオーバーレイと実行ログに残ります。

帳票原本のある追加ケースは、アプリ内でサイズと SHA-256 を照合し、Simulator のアプリコンテナに実測バイトを書き出します。次のパスを `summarize_equivalence.py` の `actual_reports` に指定すると原本との直接比較を追加できます。

```sh
CONTAINER="$(xcrun simctl get_app_container "$UDID" jp.acas.ipad data)"
ls "$CONTAINER/Library/Caches/pl-evidence"
```

各回の実測帳票を保存してから同じケースを再実行してください。録画の結合と集計には
`ffmpeg` と `ffprobe` を使用します。実行ディレクトリは初回から時系列で指定します。

```sh
python3 ipad/ACASUITests/PL/assemble_equivalence.py "$DELIVERABLES" "$WORK" "$HOME/acas-pl-run-1" "$HOME/acas-pl-run-2"
python3 ipad/ACASUITests/PL/summarize_equivalence.py "$EVIDENCE" "$ACTUAL_REPORTS" "$DELIVERABLES" \
  "$WORK/timeline.json" --diagnoses "$WORK/diagnoses.json" --sha "$(git rev-parse HEAD)"
```
