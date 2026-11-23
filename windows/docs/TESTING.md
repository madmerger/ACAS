# Windows 版の検証手順

Windows の対話デスクトップで、`windows/` から実行します。.NET 8 SDK とデスクトップランタイム、録画には FFmpeg が必要です。

- [レガシー証跡 ZIP](https://devin-gtm.devinenterprise.com/attachments/8f301e54-81c4-4b3a-8331-2082453ceab7/acas-windows-verification-evidence.zip)：ローカルディスクへ展開し、`入力/シナリオ台帳.json`、`runs/`、`baselines/` が同じ展開先にあることを確認します。
- [集約用 Excel の入力元](https://devin-gtm.devinenterprise.com/attachments/35c545a1-67d2-429b-8cbc-2ce971475024/ACAS_Windows_%E5%90%8C%E4%B8%80%E6%80%A7%E7%A2%BA%E8%AA%8D%E7%B5%90%E6%9E%9C.xlsx)：`テストシナリオ一覧` の A 列に台帳と同じケース ID が入ったブックです。既存の S/T 列は集約時に上書きします。
- [統合検証の作業用 Excel](https://devin-gtm.devinenterprise.com/attachments/d119f02e-b598-4764-8e10-ee3e55d44992/ACAS_Windows_%E7%B5%B1%E5%90%88%E6%A4%9C%E8%A8%BC_%E4%BD%9C%E6%A5%AD%E7%94%A8.xlsx)：引き継ぎ時点の途中結果で、確定版ではありません。

子セッションでは上記の添付から取得してください。同じ Windows 環境では、`$HOME/acas-windows-verification-evidence.zip`、`$HOME/ACAS_Windows_同一性確認結果.xlsx`、`$HOME/ACAS_Windows_統合検証_作業用.xlsx` も参照できます。以下は証跡を `C:\検証\証跡` に展開した例です。

```powershell
dotnet build Acas.sln -c Release
dotnet test Acas.sln -c Release --no-build
$evidence = 'C:\検証\証跡'
$ledger = Join-Path $evidence '入力\シナリオ台帳.json'
$out = 'C:\検証\結果'
New-Item -ItemType Directory -Force $out | Out-Null
$app = Resolve-Path 'Acas.App\bin\Release\net8.0-windows\Acas.App.exe'
$driver = Resolve-Path 'Acas.UiDriver\bin\Release\net8.0-windows\Acas.UiDriver.exe'
```

この VM のように .NET が `C:\dotnet` にある場合は、先に `$env:DOTNET_ROOT = 'C:\dotnet'; $env:Path = "C:\dotnet;$env:Path"` を設定します。

## ヘッドレス比較

```powershell
dotnet run --project Acas.Verify -c Release --no-build -- $ledger $evidence --group 1 --out "$out/verify-1.json"
dotnet run --project Acas.Verify -c Release --no-build -- $ledger $evidence --group 2 --out "$out/verify-2.json"
dotnet run --project Acas.Verify -c Release --no-build -- $ledger $evidence --group 3 --out "$out/verify-3.json"
dotnet run --project Acas.Verify -c Release --no-build -- $ledger $evidence --group 4 --out "$out/verify-4.json"
dotnet run --project Acas.Verify -c Release --no-build -- $ledger $evidence --group 5 --out "$out/verify-5.json"
```

グループは①（共通・総勘定元帳）、②（売掛）、③（買掛）、④（在庫・簡易記帳・連携）、⑤（計算）です。数字の `1`〜`5` でも指定できます。指定を省略すると全453件が結果に含まれます。台帳の `legacy_result.verdict` が `未実施` の16件だけを「対象外」とし、実行手順がないケースは「未検証」にします。⑤はレガシーの `00-output.txt` と新しい計算の出力を比較します。

①〜④の旧移植版との参考比較を再現するには、旧ブランチ `devin/1795411603-windows-native-wpf`（確認済みコミット `a808d48`）を別の作業ツリーに置き、そちらの `windows/Acas.Verify` を Release ビルドします。その DLL を次のように指定します。

```powershell
dotnet run --project Acas.Verify -c Release --no-build -- $ledger $evidence --out verify-reference.json --reference 'C:\旧版\windows\Acas.Verify\bin\Release\net8.0\Acas.Verify.dll'
```

`source` が「旧移植版・参考」の結果は新アプリの同一性を証明しません。旧ハーネス由来の不一致は `reason` に差分を保存します。終了コード `0` は新実装の比較がすべて一致または対象外、`1` は不一致・未検証・参考値あり、`2` は検証処理そのもののエラーです。

## FlaUI による実画面の比較と録画

```powershell
& $driver $ledger $evidence --app $app --group 1 --out "$out/ui-1.json"
& $driver $ledger $evidence --app $app --group 2 --out "$out/ui-2.json"
& $driver $ledger $evidence --app $app --group 3 --out "$out/ui-3.json"
& $driver $ledger $evidence --app $app --group 4 --out "$out/ui-4.json"
& $driver $ledger $evidence --app $app --group 5 --out "$out/ui-5.json"
```

ドライバ自身が新しいローカルの検証用 SQLite を用意してアプリを起動します。通常の業務用データベースは指定も使用もしません。⑤では、画面上のメニューを選択し、入力欄を設定して計算し、表示された結果とレガシー証跡を照合します。①〜④も選択できますが、実画面用の手順が未登録のケースは「未検証」です。旧端末のキー列や参考値を実画面の結果として使いません。

画面のオーバーレイにケース ID、台帳のケース名称、判定を表示します。JSON の `videoSeconds` はドライバ起動からケース開始までの秒数です。録画と同時に起動できなかった場合は録画の先頭との差を足してください。録画はビルド完了後、他のアプリを閉じて、実際の画面範囲を確認してから開始します。FFmpeg の例（ディスプレイ領域が1600×1200の場合）：

```powershell
$group = 1  # 1〜5 を順に指定して、グループごとに別ファイルへ録画
ffmpeg -f gdigrab -framerate 12 -video_size 1600x1200 -i desktop -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$out/ui-$group.mkv"
```

FFmpeg が録画を始めたら、同じ対話セッションの別 PowerShell から対応する `--group` の UI ドライバを起動します。端末をアプリに重ねず、最終判定の表示後に FFmpeg 側で `q` を押して終了します。録画は H.264・1280×720 以上とし、各グループの `ui-N.json` と `ui-N.mkv` をセットで保管します。録画開始日時（タイムゾーン付き）と録画開始からドライバ開始までの秒差も記録します。①〜⑤を並行する場合は別々の Windows 対話セッションを使い、出力先を分けます。

## ケース指定と再実行

`--case` を繰り返し指定すると、修正対象だけを再実行できます。グループも指定した場合、ケースはそのグループに属していなければなりません。

```powershell
dotnet run --project Acas.Verify -c Release --no-build -- $ledger $evidence --group 1 --case GL-020 --case GL-021 --out "$out/verify-1-rerun.json"
& $driver $ledger $evidence --app $app --group 1 --case GL-020 --case GL-021 --out "$out/ui-1-rerun.json"
```

全件 JSON は保存し、部分再実行は別 JSON・別録画に保存します。集約時に `--rerun` を古いものから順に追加すると、該当 ID だけを後の結果で置き換えます。ヘッドレスと実画面の再実行はそれぞれ対応するブックに反映してください。

## Excel への集約

Python 3 と `openpyxl`（`python -m pip install openpyxl`）を使用します。`--results` はグループ **①、②、③、④、⑤の順に5本**、各グループの全ケースを1件ずつ含む JSON を指定します。`ui-1.json`〜`ui-5.json` を `verify-1.json`〜`verify-5.json` に置き換えれば、ヘッドレス版を別ブックに集約できます。

入力は `Acas.Verify` または `Acas.UiDriver` の UTF-8 JSON 配列です。各要素は `id`（台帳 ID）、`subsystem`（例 `GL`）、`group`（数値 `1`〜`5`）、`verdict`（`一致`／`不一致`／`対象外`／`未検証`）、文字列の `result`、`reason`、`source`、任意の `videoSeconds`（非負の秒数または `null`）を持ちます。追加の `title` や `match` は無視します。`legacy_result.verdict` が `未実施` のケースだけを `対象外` にできます。サブシステム専用 Verify の独自形式はそのままでは受け付けません。使う場合はこの形式に変換し、グループ全件を揃えてください。旧移植版の参考結果は入力に使えません。

```powershell
$template = 'C:\検証\ACAS_Windows_同一性確認結果.xlsx'
python docs/aggregate_results.py --ledger $ledger --template $template --out "$out/ui-集約.xlsx" `
  --results "$out/ui-1.json" "$out/ui-2.json" "$out/ui-3.json" "$out/ui-4.json" "$out/ui-5.json"
```

必要なら末尾に `--rerun "$out/ui-1-rerun.json"` を追加します。録画情報は JSON ごとに `--video JSON 動画ファイル 開始日時 秒差` で追加します。例えば録画開始1.25秒後にドライバが始まった場合は `--video "$out/ui-1.json" "$out/ui-1.mkv" '2026-11-23T15:20:00+09:00' 1.25` です。再実行分も対応する JSON と動画を指定します。指定しなければ JSON の `videoSeconds` のみ記録し、動画内開始秒や日時は空欄にします。

出力は `テストシナリオ一覧` の S 列（移行後結果）・T 列（一致判定）、`Windows集計`（サブシステム別と全体）、`Windows_不一致`、`Windows_対象外`、`Windows_未検証`、`Windows動画時刻`（録画開始日時、動画内のケース開始秒、ケース開始日時）です。5本を揃えても未検証ケースの判定は変わりません。

## 日本語表示の監査

```powershell
& $driver --audit-xaml Acas.App --out xaml-audit.json
& $driver --audit-ui $app --out ui-audit.json
```

ASCII 英字が2文字以上連続する表示候補を検出します。XAML では表示用属性と表示要素を調べ、内部 ID・バインディング式は対象外です。実画面では検証用データベースでメニューから到達する画面の UI オートメーション名と帳票本文を調べ、入力値や表のデータセルは対象外です。実行結果には確認した画面、検出箇所、巡回時の失敗を記録します。フォームに個別データを入力した先の画面、各種の状況依存エラー、Windows の印刷・保存ダイアログは自動巡回の対象外です。結果がゼロでも全状態の日本語表示を証明するものではありません。

監査専用の一時データベースでは、社名・住所・印刷先などの利用者データに数値のダミー値を使い、帳票の固定文言は変更せずに検査します。システム設定帳票のほか、監査用仕訳を全バッチ検証、転記、保管の順に画面で処理し、締め処理の中断画面と、並べ替え後の保管仕訳元帳の本文まで確認します。
