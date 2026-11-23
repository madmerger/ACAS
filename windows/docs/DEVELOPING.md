# Windows 版 ACAS の開発手順

## ビルドと起動

Windows と .NET 8 SDK を使用します。リポジトリの `windows/` で実行します。

```powershell
dotnet build Acas.sln -c Release
dotnet test Acas.sln -c Release --no-build
dotnet run --project Acas.App -c Release --no-build -- --database "$HOME\acas-verification.db"
```

検証には業務用と異なるローカル SQLite ファイルを指定してください。並行で検証するときはケースまたはセッションごとにファイルを分けます。

## サブシステムを追加する

`devin/acas-windows-01-foundation` を起点に、担当分のファイルだけを追加できます。SDK が配下のソースを自動で取り込むため、`MainWindow.xaml.cs`、ソリューション、プロジェクトファイルに登録行を追加する必要はありません。

| 配置先 | 内容 |
| --- | --- |
| `Acas.Core/Programs/<担当>/` | レコード操作・業務ルール・帳票生成。端末や WPF に依存させない |
| `Acas.App/Subsystems/<担当>/` | 画面モデルを構成するクラスと、そのサブシステムの登録属性 |
| `Acas.Tests/<担当>/` | レコード差分・計算・帳票・画面遷移の xUnit テスト |

たとえば次を `Acas.App/Subsystems/Sales/SalesScreens.cs` に置きます。起動時にシェルがアプリ自身のアセンブリから登録属性を読み、数値順に業務メニューを並べます（例の `30` は表示順で、レガシーのメニュー番号ではありません）。`Db` はシェルが開いたものを受け取り、サブシステムでは開き直したり破棄したりしません。起動時の登録ではナビゲーションを構成するだけにし、入力や更新は操作時に行います。

```csharp
using Acas.App.Subsystems.Sales;
using Acas.Core;
using Acas.Core.Engine;

[assembly: SubsystemScreensAttribute<SalesScreens>(30)]

namespace Acas.App.Subsystems.Sales;

internal sealed class SalesScreens : ISubsystemScreens
{
    public MenuItem CreateNavigation(Db database) =>
        new("SalesNavigation", "売掛元帳", Open: () => new MenuScreen("売掛元帳",
        [
            new("SalesCustomerSearch", "得意先照会", 1, Open: () => Search(database))
        ]));

    private static Screen Search(Db database) => new FormScreen("得意先照会",
        [new TextField("SalesCustomerCode", "得意先コード", MaxLength: 6)],
        "照会", values =>
        {
            string code = values.Text("SalesCustomerCode");
            var record = database.Read("ledgers/acas/customer.dat", code);
            return new InformationScreen("照会結果",
                record == null ? "得意先が見つかりません。" : "得意先が見つかりました。");
        });
}
```

例は API の使い方を示すもので、実業務のファイル名・キー・メニュー番号は COBOL ソースと実測を参照してください。`MenuItem.Children` は左のツリー階層に、`MenuScreen.Items` は画面内の操作一覧に使用します。確認が必要な更新は、ツリー選択で直接実行せず、画面内のボタンから `ConfirmationScreen` へ進めます。

操作一覧から開いた業務画面は、ヘッダーの「メニューへ戻る」（`ScreenMenuBack`）で直前の操作一覧へ戻れます。左ツリーの同じ項目をクリックし直しても、その項目の最初の画面を開き直せます。

Windows の対話デスクトップで `powershell -File .\Acas.Tests\UiSmoke\Test-MenuReturn.ps1` を実行すると、テスト専用サブシステムでこの経路を実操作できます。既定では Windows の一時ディレクトリを使います。別の作業場所を使うには `-WorkDirectory` でローカルディレクトリを指定してください。通常のビルドにはテスト画面は含まれません。

## 画面モデルと表示

- ナビゲーションは `MenuItem`／`MenuScreen`（WPF の `TreeView`／`ListBox`）。レガシーの階層・項目番号を保ちます。
- 入力は `FormScreen` と `TextField`／`DateField`／`ChoiceField`（ラベル付き `TextBox`／`DatePicker`／`ComboBox`）。`FormValues` から値を取り、検証後に業務処理を呼び出します。
- 一覧は `TableScreen`／`TableRow`（`DataGrid`）。日付や金額を表示文字列と異なる型で並べ替えるときは `SortValues` を渡します。行から詳細を開くときは `TableRow.Open` を用います。
- 確認は `ConfirmationScreen`（ダイアログ）。帳票は `ReportScreen`（`FlowDocumentScrollViewer`、保存・印刷付き）。再表示する帳票は `Db.AddSpool` で保存します。
- WebView、80×24端末の描画、行列座標からの変換表示は禁止です。座標・入力キーの記録は比較資料にとどめます。

## 自動操作 ID と日本語表示

- 業務要素の `AutomationId` はサブシステム名から始まる安定した PascalCase にします（例：`SalesCustomerCode`、`PurchaseInvoiceList`）。画面とツリーが同時に見える場合も ID を重複させません。表示文字、データ値、行順から ID を組み立てず、翻訳で変更しません。
- シェルが画面モデルの ID をコントロールに付与します。ラベルは入力 ID に `Label`、一覧の詳細ボタンは一覧 ID に `Open` を付けたものです。共通の `ScreenMenuOpen`、`FormSubmit`、`ConfirmationConfirm`、`ConfirmationCancel`、`ReportDocument` は対象画面・ダイアログ内で操作します。WPF 部品を直接追加する場合も操作対象に ID を付けます。
- 見出し・ラベル・選択肢・確認・エラー・帳票見出しは日本語とし、`Copyright`、`Return`、`Esc`、`(Y/N)`、`dd/mm/yyyy` などを表示しません。日付の内部書式や勘定コードなどの比較対象データは表示文言と分離します。勘定コード等や入力された業務データは翻訳しません。
- XAML だけでなく実行中の UIA 名称・画面表示も確認し、ASCII 英字が2文字以上連続する箇所を調べます。検査ツールの統合は後続です。

## 旧 PR #18 からの再利用と Verify

旧ブランチ `devin/1795411603-windows-native-wpf`（参照コミット `a808d48`、PR #18）の `windows/` を参照します。

| 担当 | 主な再利用元（`Acas.Core/Programs/`） |
| --- | --- |
| システム設定・総勘定 | `Sys002*.cs`、`General.cs`、`Gl*.cs` |
| 売掛 | `Sales.cs`、`Sl*.cs` |
| 買掛 | `Purchase.cs`、`PlChq.cs` |
| 在庫 | `Stock.cs`、`St010.cs`、`St020.cs` |
| 簡易記帳（IRS）・連携 | `Irs.cs`、`Irs010.cs`、`Irs020.cs`。連携処理は各業務側の呼び出しも参照 |
| 計算 | `Calc.cs` |

共通の固定長レコードと SQLite は新基盤の `Acas.Core/Engine/{Db,Layouts,Rec,PicEdit}.cs` を使います。旧 `Programs/` から業務条件・計算・更新だけを切り出し、`Crt`／`Scr`／`Ui`、`TerminalView`、端末の操作ループは WPF 側へ持ち込みません。旧実装と COBOL ソース／台帳の実測値に差がある場合、旧実装を正とはしません。

この基盤ブランチにはまだ `Acas.Verify` がありません。旧ハーネスの比較ロジックは `Acas.Core/Engine/CaseRunner.cs`、`Records.cs`、入口は `Acas.Verify/Program.cs` です。別の作業ツリーで旧ブランチを開き、その `windows/` から実行すると、担当分の参考結果を JSON に出力できます。

```powershell
$evidence = "$HOME\acas_evidence"
$ledger = Join-Path $evidence '入力\シナリオ台帳.json'
dotnet run --project Acas.Verify -c Release -- "$ledger" "$evidence" SL- --out "$HOME\acas-verify-sl.json"
```

接頭辞は複数指定でき、指定を省略すると全件です。グループは `SYS- GL-`／`SL-`／`PL-`／`ST- IRS- INT-`／`CALC-`。旧 Verify は端末再生であり、新 WPF の UI 操作結果ではありません。新 Verify は台帳の453件を判定し、`legacy_result.verdict` が「未実施」の16件のみを対象外にします。旧 Verify の対象外判定をそのまま新実装へ移植しないでください。
