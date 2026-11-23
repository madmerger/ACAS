using Acas.Core.Engine;
using Acas.Verify;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;

namespace Acas.UiDriver;

internal sealed partial class Desktop
{
    public Outcome RunGroupOne(Scenario scenario, string evidence, GroupOnePlan plan)
    {
        using var database = new Db(_databasePath);
        var before = database.Snapshot();
        var observations = new List<string>();
        var differences = new List<string>();
        foreach (var action in plan.Actions)
        {
            switch (action.Type)
            {
                case ActionType.Tree:
                    FindTree(action.Id);
                    OpenTree(action.Id);
                    break;
                case ActionType.Menu:
                    if (action.Id == "FormBack") Find(action.Id).AsButton().Invoke();
                    else SelectAction(action.Id);
                    break;
                case ActionType.Submit:
                    Find("FormSubmit").AsButton().Invoke();
                    break;
                case ActionType.Confirm or ActionType.Cancel:
                    var dialog = Wait(Confirmation, "確認画面");
                    string buttonId = action.Type == ActionType.Confirm ? "ConfirmationConfirm" : "ConfirmationCancel";
                    Wait(() => dialog.FindFirstDescendant(c => c.ByAutomationId(buttonId)), buttonId).AsButton().Invoke();
                    break;
                case ActionType.Text:
                    Find(action.Id).AsTextBox().Text = action.Value;
                    break;
                case ActionType.Choice:
                    SelectChoice(action.Id, action.Value);
                    break;
                case ActionType.TableRow:
                    var table = Find(action.Id).AsDataGridView();
                    var row = table.Rows.FirstOrDefault(item => item.Cells[0].Name == action.Value)
                        ?? throw new InvalidOperationException($"表の指定行が見つかりません：{action.Id}／{action.Value}");
                    row.Patterns.SelectionItem.Pattern.Select();
                    Find(action.Id + "Open").AsButton().Invoke();
                    break;
                case ActionType.Check:
                    CheckSurface(action, database, observations, differences);
                    break;
                default:
                    throw new InvalidOperationException($"未登録の画面操作：{action.Type}");
            }
        }
        return GroupOneVerification.Compare(scenario, evidence, plan, before, database, observations, differences, "実画面");
    }

    private void FindTree(string id)
    {
        if (id is "MenuSettings" or "MenuGeneral") return;
        if (!id.StartsWith("MenuCompany", StringComparison.Ordinal) &&
            id is not ("MenuSettingsReport" or "MenuOperatingParameters" or "MenuGeneralLedgerParameters"))
        {
            Find("MenuGeneral").AsTreeItem().Expand();
        }
        else Find("MenuSettings").AsTreeItem().Expand();
    }

    private void SelectChoice(string id, string value)
    {
        int index = id switch
        {
            "AccountType" => Array.IndexOf(new[] { "0", "1", "9" }, value),
            "AccountPlacement" when value.Length == 1 => value[0] - 'A',
            "AccountLevel" when int.TryParse(value, out int level) => level - 1,
            "DefaultAccountTax" or "JournalTemporaryTax" => Array.IndexOf(new[] { "I", "O", "N" }, value),
            "JournalSide" => Array.IndexOf(new[] { "CR", "DR" }, value),
            "SalesStockLink" => Array.IndexOf(new[] { "Y", "N" }, value),
            _ => -1
        };
        var combo = Find(id).AsComboBox();
        combo.Expand();
        if (index < 0 || index >= combo.Items.Length)
            throw new InvalidOperationException($"画面に選択肢がありません：{id}／{value}");
        combo.Select(index);
        combo.Collapse();
    }

    private void CheckSurface(ScreenAction action, Db database, List<string> observations, List<string> differences)
    {
        var element = action.Id == "Confirmation" ? Wait(Confirmation, "確認画面")
            .FindFirstDescendant(c => c.ByAutomationId("ConfirmationMessage"))
            ?? throw new InvalidOperationException("確認メッセージが見つかりません。")
            : Find(action.Id);
        if (action.Id == "ReportDocument")
        {
            string? text = element.Patterns.Text.IsSupported ? element.Patterns.Text.Pattern.DocumentRange.GetText(-1) : null;
            string? saved = database.Spool().LastOrDefault().Body;
            if (string.IsNullOrWhiteSpace(text) || saved is null || Normalize(saved) != Normalize(text))
                differences.Add("画面：表示された帳票本文が保存された帳票本文と一致しません。");
            else observations.Add(action.Id);
            return;
        }
        var values = element.Properties.ControlType.ValueOrDefault == ControlType.DataGrid
            ? element.AsDataGridView().Rows.SelectMany(row => row.Cells).Select(cell => cell.Name)
            : [element.Properties.Name.ValueOrDefault ?? ""];
        if (action.Value.Length != 0 && !values.Any(value => value.Contains(action.Value, StringComparison.Ordinal)))
            differences.Add($"画面：{action.Id} に「{action.Value}」が見つかりません。" +
                (action.Id == "Status" ? $"表示：{values.FirstOrDefault()}" : ""));
        else
            observations.Add(action.Value.Length == 0 ? action.Id : $"{action.Id}：{action.Value}");
    }

    private static string Normalize(string text) => string.Join(' ', text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
}
