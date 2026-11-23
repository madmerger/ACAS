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

帳票原本のある追加ケースは、アプリ内でサイズと SHA-256 を照合します。録画コマンドは実測バイトを試行ごとの `reports/` に保存し、集計時に同じ試行の帳票だけを原本と直接比較します。以前の録画で `reports/` がない場合は、直接照合できなかった旨を記載し、ログの判定を使います。

旧版がエラーや条件画面で止まったケースは、その操作段階まで比較します。ケースを対象外にするのは旧版が「未実施」の場合だけです。PL-414 のフィクスチャ生成には、証跡の Berkeley DB から論理レコードを読むために `db_dump` が必要です。

録画の結合と集計には
`ffmpeg` と `ffprobe` を使用します。実行ディレクトリは初回から時系列で指定します。

```sh
mkdir -p "$DELIVERABLES" "$WORK"
python3 ipad/ACASUITests/PL/assemble_equivalence.py "$DELIVERABLES" "$WORK" "$HOME/acas-pl-run-1" "$HOME/acas-pl-run-2"
python3 ipad/ACASUITests/PL/summarize_equivalence.py "$EVIDENCE" "$DELIVERABLES" \
  "$WORK/timeline.json" --sha "$(git rev-parse HEAD)"
```

調査済みの原因・対処を追記する場合のみ、ケース ID から日本語の説明文字列への JSON オブジェクトを作成し、`--diagnoses "$WORK/diagnoses.json"` を追加します。診断ファイルがなければこの指定は不要です。

### PL-232：支払予定検証の帳票差分

旧証跡の実行前ファイル一覧と移行版のシードのどちらにも `ledgers/acas/pay.dat` はありません。旧版の `purchase/selpay.cob:2–6` と `copybooks/file32.cob:1` が、このファイルを非 OPTIONAL の索引ファイルとして割り当てます。`purchase/pl930.cbl:220–232` は OPEN 失敗と AT END 以外の READ エラーを検査せず、空白行を印字する処理へ進みます。支払明細がなければ `:248–250,300–309` で次の READ に戻ります。

GnuCOBOL 3.2.0 で、証跡の `purchled.dat` と `pay.dat` 不在を再現すると、OPEN は 35、READ は 47 で AT END に分岐しません。無改変の PL930 でも、出力を 16,384 B に制限したところ、その全バイトが旧原本の先頭と一致しました。一方、存在する空の `pay.dat` を与えると READ は 10（AT END）となり、`pl930.cbl:186–193,321–330` の区切り罫線・合計が出力され、その 799 B は移行版と全バイト一致しました。

605 バイト目（第5固定幅レコードの72桁目）は、旧原本では `pl930.cbl:230–232` の空白（0x20）、移行版では `pl930.cbl:188,328` に相当する区切り罫線の先頭（0x2D）です。固定幅は `copybooks/fdprint.cob:2–4` の 132 B です。旧採取当時の状態コードは未記録ですが、不在時のエラーに伴う反復印字は再現できています。移行版にその反復処理は追加せず、PL-232 は不一致のままとします。
