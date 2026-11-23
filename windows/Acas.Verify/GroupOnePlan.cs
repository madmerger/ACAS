namespace Acas.Verify;

public enum ActionType { Tree, Menu, Submit, Confirm, Cancel, Text, Choice, Check, TableRow }

public sealed record ScreenAction(ActionType Type, string Id = "", string Value = "");

public sealed record GroupOnePlan(string LegacyScreen, IReadOnlyList<ScreenAction> Actions)
{
    public static GroupOnePlan? For(Scenario scenario)
    {
        GroupOnePlan View(string legacy, string tree, string target, params ScreenAction[] tail) =>
            new(legacy, [Tree(tree), .. tail, Check(target)]);
        GroupOnePlan MenuView(string legacy, string tree, string action, string target) =>
            View(legacy, tree, target, Menu(action));

        string[] Input(int index) => scenario.Steps[index].GetProperty("text").GetString()!.Split('\t', '\r', '\n');
        ScreenAction[] AccountCode(string[] values) => [Text("LedgerCode", values[0]), Text("SubCode", values[1])];
        ScreenAction[] AccountFields(string[] values) => [Text("AccountName", values[2]), Choice("AccountType", values[3]),
            Choice("AccountPlacement", values[4]), Choice("AccountLevel", values[5])];
        const string chart = "MenuChart", defaults = "MenuDefaults", journal = "MenuJournalEntry", proof = "MenuJournalProof";
        const string batch = "MenuBatchStatus", trial = "MenuTrialBalance", close = "MenuJournalClose";

        switch (scenario.Id)
        {
            case "SYS-200": return new("ACAS System Menu", [Check("MenuGeneral"), Check("MenuSettings")]);
            case "SYS-002" or "SYS-206" or "GL-231": return View("User Data", "MenuCompanyParameters", "ParameterName");
            case "SYS-003": return View("ACAS System Menu", "MenuCompanyParameters", "SettingsCompany", Menu("FormBack"));
            case "SYS-004":
                return new("Do you want printed copy", [Tree("MenuSettingsReport"), Menu("CreateSettingsReport"), Confirm, Check("ReportDocument")]);
            case "SYS-010":
                return new("S-L Data Complete", [Tree("MenuCompanyParameters"), Choice("SalesStockLink", "N"),
                    Submit, Confirm, Check("ScreenMessage|設定を保存しました"),
                    Tree("MenuSettingsReport"), Menu("CreateSettingsReport"), Confirm, Check("ReportDocument")]);
            case "SYS-005":
                return View("SY105", "MenuCompanyParameters", "Status|２９以上", Text("PageLines", Input(2)[9]), Submit);
            case "SYS-006" or "SYS-007" or "SYS-008" or "SYS-009":
                return View(scenario.Id switch { "SYS-006" => "User Data Complete", "SYS-007" => "Weekly", "SYS-008" => "Fortnightly", _ => "Monthly" },
                    "MenuCompanyParameters", "Confirmation", Text(scenario.Id == "SYS-006" ? "PageLines" : "CyclePeriod",
                        scenario.Id switch { "SYS-006" => "29", "SYS-007" => "13", "SYS-008" => "06", _ => "99" }), Submit);
            case "GL-001" or "GL-200" or "GL-201" or "GL-232": return View("Start Of Day", "MenuGeneralDate", "RunDate");
            case "GL-002" or "GL-202": return View("Chart Of Account Utilities", chart, "ChartAdd");
            case "GL-003" or "GL-207": return View("Default File Utilities", defaults, "DefaultsEdit");
            case "GL-004" or "GL-212": return View("Transaction Entry Functions", journal, "NewJournalBatch");
            case "GL-005" or "GL-214": return View("Batch Amendment", proof, "EditJournalBatch");
            case "GL-006" or "GL-219": return View("Batch Status Report", batch, "DisplayBatchStatus");
            case "GL-007" or "GL-222":
                return MenuView("Transaction Posting", "MenuJournalPost", "JournalPostConfirm", "Confirmation");
            case "GL-008" or "GL-223":
                return MenuView("End Of Cycle Processing", close, "JournalCloseBackup", "Confirmation");
            case "GL-009" or "GL-224": return View("Trial Balance", trial, "DetailedTrialBalance");
            case "GL-010" or "GL-227": return View("P&L and Balance Sheet", "MenuFinancialStatements", "FinancialStatementsDate");
            case "GL-011" or "GL-228": return View("Ledger Print", "MenuArchivedLedger", "SortArchivedLedger");
            case "GL-020" or "GL-021" or "GL-022" or "GL-038":
            {
                string[] values = Input(5);
                if (scenario.Id == "GL-038") return new("NEW DETAIL",
                    [Tree(chart), Menu("ChartAdd"), .. AccountCode(values), Text("AccountName", values[2]), Submit,
                     Check("ScreenMessage|登録しました")]);
                if (scenario.Id == "GL-020") return new("TEST HEADER",
                    [Tree(chart), Menu("ChartAdd"), .. AccountCode(values), .. AccountFields(values), Submit, Check("ScreenMessage|登録しました")]);
                return new("Chart Of Accounts Update",
                    [Tree(chart), Menu("ChartEdit"), .. AccountCode(values), Submit,
                     Menu(scenario.Id == "GL-021" ? "UpdateAccount" : "DeleteAccount"),
                     .. (scenario.Id == "GL-021" ? [.. AccountFields(values), Submit] : new[] { Confirm }),
                     Check(scenario.Id == "GL-021" ? "ScreenMessage|変更しました" : "ScreenMessage|削除しました")]);
            }
            case "GL-023": return View("BANK", chart, "AccountList|BANK", Menu("ChartList"), Text("StartAccount", Input(5)[0]), Submit);
            case "GL-024" or "GL-025" or "GL-026" or "GL-027":
            {
                string[] values = Input(5);
                return new(scenario.Id switch { "GL-024" => "GL102", "GL-025" => "Is reserved!", _ => "Invalid start number!" },
                    [Tree(chart), Menu("ChartAdd"), Text("LedgerCode", values[0]), Text("AccountName", "検証"),
                     Submit, Check(scenario.Id switch { "GL-024" => "Status|１０００以上", "GL-025" => "Status|予約済み", _ => "Status|予約範囲" })]);
            }
            case "GL-032": return new("Does not exist!",
                [Tree(chart), Menu("ChartEdit"), .. AccountCode(Input(5)), Submit, Check("Status|存在しません")]);
            case "GL-033" or "GL-206": return MenuView("Chart Of Account Utilities", chart, "ChartPrint", "ReportDocument");
            case "GL-034" or "GL-225": return MenuView("Trial Balance", trial, "DetailedTrialBalance", "ReportDocument");
            case "GL-035": return View("Ok to continue", "MenuFinancialStatements", "ReportDocument", Submit, Confirm);
            case "GL-037": return View("General Ledger System Menu", close, "JournalCloseBackup", Menu("JournalCloseBackup"), Cancel);
            case "GL-040" or "GL-041":
            {
                string[] values = Input(5);
                bool update = scenario.Id == "GL-040";
                return new("Enter Number To Alter",
                    [Tree(defaults), Menu("DefaultsEdit"), new(ActionType.TableRow, "DefaultAccountList", "1"),
                     Text("DefaultAccountCode", values[1]),
                     .. (update ? new[] { Text("DefaultAccountReference", values[2]), Choice("DefaultAccountTax", values[3]) } : []),
                     Submit, Check(update ? "DefaultAccountList|BK" : "DefaultAccountList|8888.88")]);
            }
            case "GL-042" or "GL-210": return MenuView("Default File Utilities", defaults, "DefaultsList", "DefaultAccountList");
            case "GL-043" or "GL-044" or "GL-046" or "GL-047" or "GL-048" or "GL-049":
            {
                string[] header = Input(11);
                bool invalidCycle = scenario.Id is "GL-043" or "GL-044";
                ScreenAction[] start = [Tree(journal), Menu("NewJournalBatch"),
                    Text("JournalTemporaryCode", Input(6)[0]), Choice("JournalTemporaryTax", Input(7)[0]),
                    Text("JournalTemporaryReference", Input(8)[0]), Choice("JournalSide", Input(9)[0]),
                    Text("JournalCycle", header[0])];
                if (invalidCycle)
                    return new(scenario.Id == "GL-043" ? "GL108" : "GL109",
                        [.. start, Submit, Check("Status|会計期間")]);
                string[] line = Input(12);
                return new(scenario.Id == "GL-048" ? "Invalid A/C number" : "Posting Input",
                    [.. start, Text("JournalItems", header[1]), Text("JournalGross", header[2]),
                     Text("JournalTax", header[3]), Text("JournalDescription", header[4]), Submit,
                     Menu("JournalLineAdd"), Text("JournalLineAccount", line[1]), Text("JournalLineAmount", line[2]),
                     .. (scenario.Id is "GL-046" or "GL-047" ? new[] { Text("JournalLineDescription", line[3]) } : []),
                     Submit, .. (scenario.Id is "GL-046" or "GL-047"
                        ? new[] { Menu(scenario.Id == "GL-046" ? "JournalSave" : "JournalDiscard"), Confirm, Check("NewJournalBatch") }
                        : new[] { Check("Status|明細") })]);
            }
            case "GL-045":
                return new("Posting Set-Up", [Tree(journal), Menu("NewJournalBatch"), Menu("FormBack"), Confirm, Check("GeneralJournalEntry")]);
            case "GL-203": return MenuView("Chart of Accounts Set-Up", chart, "ChartAdd", "LedgerCode");
            case "GL-204": return MenuView("Chart Of Accounts Update", chart, "ChartEdit", "LedgerCode");
            case "GL-205": return MenuView("Chart Of Account Utilities", chart, "ChartList", "StartAccount");
            case "GL-209": return MenuView("Default File Utilities", defaults, "DefaultsEdit", "DefaultAccountList");
            case "GL-213": return MenuView("Posting Set-Up", journal, "NewJournalBatch", "JournalDefault");
            case "GL-215": return MenuView("Batch Amendment", proof, "EditJournalBatch", "JournalBatchNumber");
            case "GL-216": return MenuView("Batch Amendment", proof, "ProofAllBatches", "Confirmation");
            case "GL-217": return MenuView("Batch Amendment", proof, "ProofOneBatch", "JournalBatchNumber");
            case "GL-218": return MenuView("Batch Amendment", proof, "PrintTransactions", "ReportDocument");
            case "GL-220": return MenuView("Batch Status Report", batch, "DisplayBatchStatus", "BatchStatusList");
            case "GL-221": return MenuView("Batch Status Report", batch, "PrintBatchStatus", "ReportDocument");
            case "GL-226": return MenuView("Trial Balance", trial, "StructuredTrialBalance", "ReportDocument");
            default: return null;
        }
    }

    private static ScreenAction Tree(string id) => new(ActionType.Tree, id);
    private static ScreenAction Menu(string id) => new(ActionType.Menu, id);
    private static ScreenAction Check(string target)
    {
        string[] parts = target.Split('|', 2);
        return new(ActionType.Check, parts[0], parts.Length == 1 ? "" : parts[1]);
    }
    private static ScreenAction Text(string id, string value) => new(ActionType.Text, id, value);
    private static ScreenAction Choice(string id, string value) => new(ActionType.Choice, id, value);
    private static readonly ScreenAction Submit = new(ActionType.Submit);
    private static readonly ScreenAction Confirm = new(ActionType.Confirm);
    private static readonly ScreenAction Cancel = new(ActionType.Cancel);
}
