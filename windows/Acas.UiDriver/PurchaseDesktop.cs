using System.Globalization;
using Acas.Core.Engine;
using Acas.Verify;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;

namespace Acas.UiDriver;

internal sealed partial class Desktop
{
    private static readonly DateTime PurchaseDate = new(2026, 11, 23);

    public static string PurchaseTitle(Scenario scenario) => scenario.Id switch
    {
        "PL-001" => "処理日入力 — 画面表示",
        "PL-002" => "仕入先マスター管理 — 画面表示",
        "PL-003" => "買掛残高・明細照会 — 画面表示",
        "PL-004" => "仕入取引入力 — 画面表示",
        "PL-005" => "仕入取引修正 — 画面表示",
        "PL-006" => "仕入取引削除 — 画面表示",
        "PL-007" => "仕入の検証帳票 — 画面表示",
        "PL-008" => "仕入転記 — 画面表示",
        "PL-009" => "支払入力 — 画面表示",
        "PL-010" => "支払修正 — 画面表示",
        "PL-011" => "支払の検証帳票 — 画面表示",
        "PL-012" => "支払転記 — 画面表示",
        "PL-013" => "仕入分析コード管理 — 画面表示",
        "PL-014" => "仕入分析帳票 — 画面表示",
        "PL-015" => "仕入日計帳 — 画面表示",
        "PL-016" => "買掛金年齢表 — 画面表示",
        "PL-017" => "仕入先名順一覧 — 画面表示",
        "PL-018" => "仕入先別取引帳票 — 画面表示",
        "PL-019" => "小切手・送金 — 画面表示",
        "PL-020" => "期間締め — 画面表示",
        "PL-021" => "仕入伝票の固定設定 — 画面表示",
        "PL-022" => "仕入先ファイル帳票 — 画面表示",
        "PL-234" => "小切手・銀行振込台帳印刷：到達確認",
        "PL-400" => "仕入先マスターの名称更新",
        "PL-401" => "残高ゼロの仕入先マスターを削除",
        "PL-402" => "存在しない仕入先コードを照会",
        "PL-403" => "仕入先マスターを新規登録",
        "PL-411" => "通常仕入請求書一件を保存（税抜額一〇〇・税額二〇）",
        "PL-413" => "保存済み仕入請求書の検証帳票",
        _ => scenario.Title
    };

    public Outcome RunPurchase(Scenario scenario, string evidence)
    {
        using var database = new Db(_databasePath);
        var observations = new List<string>();
        bool reached = false;
        var differences = PurchaseVerification.Compare(scenario.Id, scenario.LegacyTargets, evidence, database, errors =>
        {
            ExercisePurchase(scenario, database, observations, errors);
            reached = true;
        });
        return reached
            ? Outcome.Compare(scenario, differences.Count == 0, string.Join("／", observations), string.Join("／", differences), "実画面")
            : Outcome.Missing(scenario, string.Join("／", differences));
    }

    private void ExercisePurchase(Scenario scenario, Db database, List<string> observed, List<string> differences)
    {
        OpenTree("PurchaseNavigation");
        Check("PurchaseProcessingDate", "処理日");
        if (scenario.Id == "PL-241") return;
        var date = Child(Find("PurchaseProcessingDate"), c => c.ByControlType(FlaUI.Core.Definitions.ControlType.Edit), "処理日の入力欄").AsTextBox();
        date.Focus();
        Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.KEY_A);
        Keyboard.Type(PurchaseDate.ToString("yyyy/MM/dd", CultureInfo.InvariantCulture));
        Keyboard.Press(VirtualKeyShort.TAB);
        Submit();

        if (scenario.Id == "PL-090")
        {
            Open("Z");
            Submit();
            Accept();
            Open("B");
            foreach (var (code, name, address) in new[]
            {
                ("SUPP01", "ALPHA SUPPLIER", @"1 SUPPLY ROAD\LONDON\UK"),
                ("SUPP02", "BETA SUPPLIER", @"2 SUPPLY ROAD\LONDON\UK")
            })
            {
                Open("B1");
                Text("SupplierCode", code);
                Submit();
                Text("SupplierName", name);
                Text("SupplierAddressFirst", address);
                Submit();
                Accept();
                Message("仕入先を保存しました。");
                Find("ScreenMenuBack").AsButton().Invoke();
            }
            return;
        }

        string operation = "";
        foreach (string part in scenario.MenuPath.Skip(1))
        {
            operation += part;
            Open(operation);
        }

        switch (scenario.Id)
        {
            case "PL-400":
                Text("SupplierCode", "SUPP018");
                Submit();
                Text("SupplierName", "EQUIV UPDATED SUPPLIER");
                Submit();
                Accept();
                Message("仕入先を保存しました。");
                return;
            case "PL-401":
                Text("SupplierCode", "SUPP026");
                Submit();
                Choose("SupplierRemovalAction", "完全に削除");
                Submit();
                Accept();
                Message("仕入先を削除しました。");
                return;
            case "PL-402":
                Text("SupplierCode", "MISS001");
                Submit();
                Message("仕入先が見つかりません。");
                return;
            case "PL-403":
                Text("SupplierCode", "TEST01");
                Submit();
                Text("SupplierName", "EQUIV NEW SUPPLIER");
                Text("SupplierAddressFirst", @"1 TEST ROAD\LONDON\UK");
                Submit();
                Accept();
                Message("仕入先を保存しました。");
                return;
            case "PL-410":
                Text("AnalysisCode", "Z");
                Submit();
                if (Element("PurchaseAnalysisAccount") is not null)
                {
                    Text("AnalysisAccount", "500001");
                    Text("AnalysisDescription", "PURCHASES");
                    Text("AnalysisReference", "P");
                    Submit();
                    Accept();
                }
                Message("分析ファイルのレコード長が定義と一致しません。");
                return;
            case "PL-411":
                Text("InvoiceSupplier", "SUPP018");
                Text("InvoiceOrder", "PL-ORDER");
                Text("InvoiceReference", "PL-REF");
                Submit();
                SelectAction("PurchaseInvoiceAddLine");
                Text("LineAnalysis", "a1");
                Text("LineNet", "100.00");
                Choose("LineTaxCode", "税区分一");
                Text("LineTax", "20.00");
                Submit();
                SelectAction("PurchaseInvoiceTotals");
                Submit();
                Accept();
                Message("仕入取引を保存しました。");
                return;
            case "PL-412":
                Text("InvoiceSupplier", "MISS001");
                Submit();
                Message("仕入先が見つかりません。");
                return;
            case "PL-413":
                Submit();
                Report("ALPHA SUPPLIER", "120.00");
                return;
            case "PL-414":
                Submit();
                Accept();
                Report();
                return;
        }

        switch (operation)
        {
            case "": Menu(24, "買掛元帳"); break;
            case "A": Check("PurchaseProcessingDate"); break;
            case "B": Menu(6, "仕入先マスター管理"); break;
            case "B1": case "B2": case "B3": case "B5": Check("PurchaseSupplierCode"); break;
            case "B4": case "Q": case "V": Check("PurchaseSupplierReportStatus"); break;
            case "R": Check("PurchaseSupplierReportActivityLabel", "請求件数"); break;
            case "C": case "I": case "J": case "K": case "P": Message("未決済明細ファイルがありません。"); break;
            case "D": Check("PurchaseInvoiceDate"); Check("PurchaseInvoiceSupplier"); break;
            case "E": Check("PurchaseInvoiceFolio"); break;
            case "F": case "O": Message("仕入伝票ファイルがありません。"); break;
            case "G": Message("検証する仕入取引がありません。"); break;
            case "H": Message("転記する仕入取引がありません。"); break;
            case "L": Message("転記待ちの支払がありません。"); break;
            case "M": Menu(6, "仕入分析コード管理"); break;
            case "M1": case "M2": Check("PurchaseAnalysisCode"); break;
            case "M3": case "M4": Accept(); Report(); break;
            case "M5": Check("PurchaseAnalysisList"); break;
            case "N": Message("集計データがありません。"); break;
            case "S": case "S6": Menu(7, "小切手・送金"); break;
            case "S1": Check("PurchaseChequeAge"); break;
            case "S2": Check("PurchaseChequeSupplier"); break;
            case "S3": Check("ScreenTitle", "支払予定の検証"); Report(); break;
            case "S4": Message("処理するデータがありません。"); break;
            case "S5": case "T":
                Submit();
                var confirmation = Wait(Confirmation, "確認画面");
                var message = Child(confirmation, c => c.ByAutomationId("ConfirmationMessage"), "確認メッセージ");
                observed.Add(message.Name);
                Child(confirmation, c => c.ByAutomationId("ConfirmationCancel"), "取消ボタン").AsButton().Invoke();
                break;
            case "U": Check("PurchaseNextFolio"); break;
            case "X": Message("買掛元帳を閉じました。"); break;
            case "Z":
                foreach (string field in new[] { "Usera", "StartDate", "PageLines", "Tax5" }) Check("PurchaseSetup" + field);
                break;
            default: throw new InvalidOperationException($"未登録の買掛メニューです：{operation}");
        }

        AutomationElement? Element(string id) => Window.FindFirstDescendant(c => c.ByAutomationId(id));
        void Open(string id) => SelectAction("PurchaseMenu" + id);
        void Submit() => Find("FormSubmit").AsButton().Invoke();
        void Accept() => Child(Wait(Confirmation, "確認画面"), c => c.ByAutomationId("ConfirmationConfirm"), "確定ボタン").AsButton().Invoke();
        void Text(string id, string value) => Find("Purchase" + id).AsTextBox().Text = value;
        void Choose(string id, string value)
        {
            var combo = Find("Purchase" + id).AsComboBox();
            combo.Expand();
            var option = combo.Select(value);
            combo.Collapse();
            if (option is null || !option.IsSelected)
                throw new InvalidOperationException($"選択肢が見つかりません：{value}");
        }
        void Message(string expected) => Check("ScreenMessage", expected);
        void Check(string id, string? expected = null)
        {
            var element = Find(id);
            string name = element.Name;
            if (expected is not null && !name.Contains(expected, StringComparison.Ordinal))
                differences.Add($"画面表示：「{name}」／期待：「{expected}」");
            observed.Add(string.IsNullOrEmpty(name) ? Find("ScreenTitle").Name : name);
        }
        void Menu(int count, string title)
        {
            var list = Find("ScreenMenu").AsListBox();
            if (list.Items.Length != count || list.Name != title)
                differences.Add($"操作一覧：「{list.Name}」{list.Items.Length} 件／期待：「{title}」{count} 件");
            observed.Add($"{list.Name}：{list.Items.Length} 件");
        }
        void Report(params string[] expected)
        {
            var element = Find("ReportDocument");
            string? text = element.Patterns.Text.IsSupported ? element.Patterns.Text.Pattern.DocumentRange.GetText(-1) : null;
            string? saved = database.Spool().LastOrDefault().Body;
            if (string.IsNullOrWhiteSpace(text) || saved is null || Normalize(text) != Normalize(saved) ||
                expected.Any(value => !text.Contains(value, StringComparison.Ordinal)))
                differences.Add("画面で確認した帳票本文が保存された本文または期待する明細と一致しません。");
            observed.Add(element.Name);
        }
    }

    private static AutomationElement Child(AutomationElement parent,
        Func<FlaUI.Core.Conditions.ConditionFactory, FlaUI.Core.Conditions.ConditionBase> condition, string name) =>
        Wait(() => parent.FindFirstDescendant(condition), name);
}
