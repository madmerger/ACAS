# Windows 版の検証手順

Windows の対話デスクトップで、`windows/` から実行します。.NET 8 SDK とデスクトップランタイムが必要です。証跡 ZIP を解凍し、`入力/シナリオ台帳.json` と `runs/` が同じ展開先にあることを確認します。

```powershell
dotnet build Acas.sln -c Release
dotnet test Acas.sln -c Release --no-build
$evidence = 'C:\検証\証跡'
$ledger = Join-Path $evidence '入力\シナリオ台帳.json'
$app = Resolve-Path 'Acas.App\bin\Release\net8.0-windows\Acas.App.exe'
$driver = Resolve-Path 'Acas.UiDriver\bin\Release\net8.0-windows\Acas.UiDriver.exe'
```

## ヘッドレス比較

```powershell
dotnet run --project Acas.Verify -c Release --no-build -- $ledger $evidence --out verify.json
dotnet run --project Acas.Verify -c Release --no-build -- $ledger $evidence --group ⑤ --out verify-5.json
```

グループは①（共通・総勘定元帳）、②（売掛）、③（買掛）、④（在庫・簡易記帳・連携）、⑤（計算）です。数字の `1`〜`5` でも指定できます。指定を省略すると全453件が結果に含まれます。台帳の `legacy_result.verdict` が `未実施` の16件だけを「対象外」とし、実行手順がないケースは「未検証」にします。⑤はレガシーの `00-output.txt` と新しい計算の出力を比較します。

①〜④の旧移植版との参考比較を再現するには、旧ブランチ `devin/1795411603-windows-native-wpf`（確認済みコミット `a808d48`）を別の作業ツリーに置き、そちらの `windows/Acas.Verify` を Release ビルドします。その DLL を次のように指定します。

```powershell
dotnet run --project Acas.Verify -c Release --no-build -- $ledger $evidence --out verify-reference.json --reference 'C:\旧版\windows\Acas.Verify\bin\Release\net8.0\Acas.Verify.dll'
```

`source` が「旧移植版・参考」の結果は新アプリの同一性を証明しません。旧ハーネス由来の不一致は `reason` に差分を保存します。終了コード `0` は新実装の比較がすべて一致または対象外、`1` は不一致・未検証・参考値あり、`2` は検証処理そのもののエラーです。

## FlaUI による実画面の比較と録画

```powershell
& $driver $ledger $evidence --app $app --group ⑤ --out ui-5.json
```

ドライバ自身が新しいローカルの検証用 SQLite を用意してアプリを起動します。通常の業務用データベースは指定も使用もしません。⑤では、画面上のメニューを選択し、入力欄を設定して計算し、表示された結果とレガシー証跡を照合します。①〜④も選択できますが、実画面用の手順が未登録のケースは「未検証」です。旧端末のキー列や参考値を実画面の結果として使いません。

画面のオーバーレイにケース ID、台帳のケース名称、判定を表示します。JSON の `videoSeconds` はドライバ起動からケース開始までの秒数です。録画と同時に起動できなかった場合は録画の先頭との差を足してください。録画はビルド完了後、他のアプリを閉じて、実際の画面範囲を確認してから開始します。FFmpeg の例（ディスプレイ領域が1600×1200の場合）：

```powershell
ffmpeg -f gdigrab -framerate 12 -video_size 1600x1200 -i desktop -t 115 -c:v libx264 -preset ultrafast -pix_fmt yuv420p ui-5.mkv
```

①〜⑤を並行する場合、画面を互いに奪わないよう別々の Windows 対話セッションで実行し、JSON・動画の出力先を分けます。

## 日本語表示の監査

```powershell
& $driver --audit-xaml Acas.App --out xaml-audit.json
& $driver --audit-ui $app --out ui-audit.json
```

ASCII 英字が2文字以上連続する表示候補を検出します。XAML では表示用属性と表示要素を調べ、内部 ID・バインディング式は対象外です。実画面では検証用データベースでメニューから到達する画面の UI オートメーション名と帳票本文を調べ、入力値や表のデータセルは対象外です。実行結果には確認した画面、検出箇所、巡回時の失敗を記録します。フォームに個別データを入力した先の画面、各種の状況依存エラー、Windows の印刷・保存ダイアログは自動巡回の対象外です。結果がゼロでも全状態の日本語表示を証明するものではありません。

監査専用の一時データベースでは、社名・住所・印刷先などの利用者データに数値のダミー値を使い、帳票の固定文言は変更せずに検査します。システム設定帳票のほか、監査用仕訳を全バッチ検証、転記、保管の順に画面で処理し、締め処理の中断画面と、並べ替え後の保管仕訳元帳の本文まで確認します。
