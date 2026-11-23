namespace Acas.Verify;

public enum ActionType { Tree, Menu, Submit, Confirm, Cancel, Text, Choice, Check, TableRow, DateText, Key, RejectChoice, Close }

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

        ScreenAction[] Setup()
        {
            string[] setup = Input(1), company = Input(2), operating = Input(4), queues = Input(5);
            return [
                Tree("MenuCompanySetup"), Check("CompanyName"), Text("CompanyName", setup[0]), Text("PeriodPassword", "AAAA"),
                Choice("EnableGeneral", setup[1]), Choice("EnableSales", setup[2]), Choice("EnablePurchasing", setup[3]),
                Choice("EnableInvoicing", setup[4]), Choice("EnableOrders", setup[5]), Choice("EnableStock", setup[6]), Submit, Confirm,
                Check("ParameterName"), Text("Address1", company[0]), Text("PostalCode", company[4]),
                Text("Country", company[5]), DateText("PeriodStart", company[7]), DateText("PeriodEnd", company[8]),
                Text("PageLines", company[9].TrimStart('0')), Text("CurrentCycle", company[15]), Text("TaxRegistration", company[16]),
                Text("CyclePeriod", company[20]), Choice("SalesStockLink", company[17]), Submit, Confirm,
                Tree("MenuOperatingParameters"), Check("OperatingSystem"), Choice("SystemHost", operating[0]),
                Choice("OperatingSystem", operating[1]), Choice("DataCapture", operating[2]), Submit,
                Check("Queue1"), Text("Queue1", queues[0]), Text("Queue2", queues[1]), Text("Queue3", queues[2]),
                Submit, Confirm, Tree("MenuSettingsReport"), Menu("CreateSettingsReport"), Check("Confirmation"),
                .. (scenario.Id == "SYS-001" ? new[] { Confirm, Check("ReportDocument") } : new[] { Cancel })
            ];
        }

        IEnumerable<ScreenAction> BusinessSetup()
        {
            string[] firstAccount = Input(29), accounts = Input(30);
            IEnumerable<ScreenAction> Account(string[] code)
            {
                yield return Tree(chart);
                yield return Menu("ChartAdd");
                foreach (var action in AccountCode(code)) yield return action;
                if (code[1] == "00")
                    foreach (var action in AccountFields(code)) yield return action;
                else yield return Text("AccountName", code[2]);
                yield return Submit;
                yield return Check("ScreenMessage|登録しました");
            }
            foreach (var action in Account(firstAccount)) yield return action;
            for (int index = 0; index + 2 < accounts.Length;)
            {
                int count = accounts[index + 1] == "00" ? 6 : 3;
                foreach (var action in Account(accounts[index..(index + count)])) yield return action;
                index += count;
            }
            foreach (var (index, correctedAddress) in new[] { (39, 54), (42, 57) })
            {
                string[] customer = Input(index + 1);
                yield return Tree("SalesNavigation");
                yield return DateText("SalesStartDate", Input(22)[0]);
                yield return Submit;
                yield return Menu("SalesCustomers");
                yield return Menu("SalesCustomerCreate");
                yield return Text("SalesNewCustomerCode", Input(index)[0]);
                yield return Text("SalesCustomerName", customer[0]);
                yield return Text("SalesCustomerAddress1", Input(correctedAddress)[1]);
                if (index == 39) yield return Text("SalesCustomerAddress2", customer[2]);
                if (customer.Length > 12)
                {
                    yield return Text("SalesCustomerPhone", customer[8]);
                    yield return Text("SalesCustomerEmail", customer[11]);
                    yield return Text("SalesCustomerCreditDays", customer[16]);
                    yield return Text("SalesCustomerCreditLimit", customer[20]);
                }
                yield return Submit;
                yield return Confirm;
                yield return Check("SalesCustomerDetail|" + customer[0]);
            }
            yield return Tree("PurchaseNavigation");
            yield return DateText("PurchaseProcessingDate", Input(22)[0]);
            yield return Submit;
            foreach (int index in new[] { 67, 70 })
            {
                string[] supplier = Input(index + 1);
                if (index == 70) yield return Tree("PurchaseNavigation");
                yield return Menu("PurchaseMenuB");
                yield return Menu("PurchaseMenuB1");
                yield return Text("PurchaseSupplierCode", Input(index)[0]);
                yield return Submit;
                yield return Text("PurchaseSupplierName", supplier[0]);
                yield return Text("PurchaseSupplierAddressFirst", supplier[1]);
                yield return Submit;
                yield return Confirm;
                yield return Check("ScreenMessage|仕入先を保存しました");
            }
            foreach (int index in new[] { 79, 86 })
            {
                string[] item = Input(index + 2);
                yield return Tree("StockNavigation");
                yield return DateText("StockRunDate", Input(22)[0]);
                yield return Submit;
                yield return Menu("StockMaintenance");
                if (index == 86) yield return Menu("StockItemCreate");
                yield return Text("StockKey", Input(index)[0]);
                yield return Text("StockAbrev", Input(index + 1)[0]);
                yield return Text("StockDesc", item[0]);
                yield return Text("StockLocation", item[1]);
                yield return Text("StockReorderPoint", item[8]);
                yield return Text("StockStdReorder", item[10]);
                yield return Text("StockRetail", Input(index + 3)[0].TrimStart('0'));
                yield return Text("StockCost", Input(index + 4)[0].TrimStart('0'));
                yield return Submit;
                yield return Check("Confirmation|を登録しました");
                yield return Cancel;
            }
        }

        switch (scenario.Id)
        {
            case "SYS-200": return new("ACAS System Menu", [Check("MenuGeneral"), Check("MenuSettings")]);
            case "SYS-001":
                return new("User Data", [.. Setup(), .. BusinessSetup()]);
            case "SYS-201" or "SYS-207" or "SYS-208" or "SYS-209" or "SYS-210" or "SYS-211":
                return new(scenario.Id switch
                {
                    "SYS-209" or "SYS-210" => "OPS  Data", "SYS-211" => "Do you want printed copy", _ => "User Data"
                }, Setup());
            case "SYS-202": return View("Sorry, not", "MenuOrders", "ScreenMessage|利用できません");
            case "SYS-203": return View("Sorry, not", "MenuPayroll", "ScreenMessage|利用できません");
            case "SYS-204": return View("Sorry, not", "MenuPointOfSale", "ScreenMessage|利用できません");
            case "SYS-205": return new("ACAS System Menu", [Check("MenuGeneral"), new(ActionType.Close)]);
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
            case "GL-028" or "GL-029" or "GL-030" or "GL-031":
            {
                string[] values = Input(5);
                var (field, index, marker) = scenario.Id switch
                {
                    "GL-028" => ("AccountType", 3, "Invalid type!"),
                    "GL-029" => ("AccountPlacement", 4, "Invalid Placement!"),
                    _ => ("AccountLevel", 5, "Invalid!")
                };
                return new(marker, [Tree(chart), Menu("ChartAdd"), .. AccountCode(values), Text("AccountName", values[2]),
                    .. (index >= 4 ? new[] { Choice("AccountType", values[3]) } : []),
                    .. (index == 5 ? new[] { Choice("AccountPlacement", values[4]) } : []),
                    new(ActionType.RejectChoice, field, values[index])]);
            }
            case "GL-033" or "GL-206": return MenuView("Chart Of Account Utilities", chart, "ChartPrint", "ReportDocument");
            case "GL-034" or "GL-225": return MenuView("Trial Balance", trial, "DetailedTrialBalance", "ReportDocument");
            case "GL-035": return View("Ok to continue", "MenuFinancialStatements", "ReportDocument", Submit, Confirm);
            case "GL-036":
                return View("GL009", "MenuGeneralDate", "Status|有効な処理日",
                    DateText("RunDate", Input(4)[0].TrimStart('\u001b', 'O', 'H')), Submit);
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
            case "GL-050" or "GL-051":
            {
                string[] header = Input(11);
                return new("Posting Input", [Tree(journal), Menu("NewJournalBatch"),
                    Text("JournalTemporaryCode", Input(6)[0]), Choice("JournalTemporaryTax", Input(7)[0]),
                    Text("JournalTemporaryReference", Input(8)[0]), Choice("JournalSide", Input(9)[0]),
                    Text("JournalCycle", header[0]), Text("JournalItems", header[1]), Text("JournalGross", header[2]),
                    Text("JournalTax", header[3]), Text("JournalDescription", header[4]), Submit,
                    Menu("JournalLineAdd"), new(ActionType.Key, "JournalLineDate", scenario.Id == "GL-050" ? "Escape" : "F1"),
                    Check("JournalLineDate"), Check("JournalLineAccount")]);
            }
            case "GL-203": return MenuView("Chart of Accounts Set-Up", chart, "ChartAdd", "LedgerCode");
            case "GL-204": return MenuView("Chart Of Accounts Update", chart, "ChartEdit", "LedgerCode");
            case "GL-205": return MenuView("Chart Of Account Utilities", chart, "ChartList", "StartAccount");
            case "GL-208": return MenuView("Default Accounts Set-Up", defaults, "DefaultsAdd", "Confirmation|既存の既定勘定に追加");
            case "GL-209": return MenuView("Default File Utilities", defaults, "DefaultsEdit", "DefaultAccountList");
            case "GL-211":
                return new("Sorry not yet available", [Tree("MenuGeneralDate"), Submit, Menu("GeneralFinalSetup"), Check("ScreenMessage|利用できません")]);
            case "GL-213": return MenuView("Posting Set-Up", journal, "NewJournalBatch", "JournalDefault");
            case "GL-215": return MenuView("Batch Amendment", proof, "EditJournalBatch", "JournalBatchNumber");
            case "GL-216": return MenuView("Batch Amendment", proof, "ProofAllBatches", "Confirmation");
            case "GL-217": return MenuView("Batch Amendment", proof, "ProofOneBatch", "JournalBatchNumber");
            case "GL-218": return MenuView("Batch Amendment", proof, "PrintTransactions", "ReportDocument");
            case "GL-220": return MenuView("Batch Status Report", batch, "DisplayBatchStatus", "BatchStatusList");
            case "GL-221": return MenuView("Batch Status Report", batch, "PrintBatchStatus", "ReportDocument");
            case "GL-226": return MenuView("Trial Balance", trial, "StructuredTrialBalance", "ReportDocument");
            case "GL-229":
                return new("General Ledger System Menu", [Tree(chart), Menu("ChartBack"), Menu("GeneralFinalPrint"), Check("GeneralFinalPrint")]);
            case "GL-230":
                return new("ACAS System Menu", [Tree(chart), Menu("ChartBack"), Menu("GeneralBack"), Check("ScreenTitle|業務メニュー")]);
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
    private static ScreenAction DateText(string id, string value) => new(ActionType.DateText, id, value);
    private static ScreenAction Choice(string id, string value) => new(ActionType.Choice, id, value);
    private static readonly ScreenAction Submit = new(ActionType.Submit);
    private static readonly ScreenAction Confirm = new(ActionType.Confirm);
    private static readonly ScreenAction Cancel = new(ActionType.Cancel);
}
