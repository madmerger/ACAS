using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;
using Acas.Verify;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;

namespace Acas.UiDriver;

internal static partial class JapaneseAudit
{
    internal sealed record Finding(string Screen, string Element, string Text);
    internal sealed record Report(IReadOnlyList<string> Checked, IReadOnlyList<Finding> Findings, IReadOnlyList<string> Gaps);

    private static readonly HashSet<string> DisplayAttributes =
        ["Text", "Content", "Header", "Title", "ToolTip", "AutomationProperties.Name", "AutomationProperties.HelpText"];

    [GeneratedRegex("[A-Za-z]{2,}")]
    private static partial Regex English();

    public static Report Xaml(string directory)
    {
        var checkedFiles = new List<string>();
        var findings = new List<Finding>();
        var gaps = new List<string>();
        foreach (string file in Directory.EnumerateFiles(directory, "*.xaml", SearchOption.AllDirectories).Order())
        {
            string relative = Path.GetRelativePath(directory, file);
            if (relative.Split(Path.DirectorySeparatorChar).Any(s => s is "obj" or "bin")) continue;
            checkedFiles.Add(relative);
            var document = XDocument.Load(file, LoadOptions.SetLineInfo);
            foreach (var element in document.Descendants())
            {
                foreach (var attribute in element.Attributes().Where(a => DisplayAttributes.Contains(a.Name.LocalName)))
                    Inspect(attribute, attribute.Name.LocalName, attribute.Value);
                if (element.Name.LocalName is "TextBlock" or "Run" or "Button" or "Label" or "AccessText" or "String" ||
                    DisplayAttributes.Contains(element.Name.LocalName.Split('.').Last()) && element.Name.LocalName.Contains('.'))
                    foreach (var node in element.Nodes().OfType<XText>()) Inspect(node, element.Name.LocalName, node.Value);
            }
            void Inspect(XObject source, string element, string text)
            {
                if (text.StartsWith('{') && !text.StartsWith("{}")) return;
                if (English().IsMatch(text)) findings.Add(new(relative, $"{((IXmlLineInfo)source).LineNumber}：{element}", text.Trim()));
            }
        }
        if (checkedFiles.Count == 0) gaps.Add("監査対象の XAML がありません。");
        return new(checkedFiles, findings, gaps);
    }

    public static Report Runtime(Desktop desktop)
    {
        var checkedScreens = new List<string>();
        var findings = new List<Finding>();
        var gaps = new List<string>();
        var menus = new HashSet<string>(StringComparer.Ordinal);
        Inspect("起動画面", desktop.Window);
        var navigation = desktop.Find("Navigation");
        foreach (var root in TreeItems(navigation))
        {
            string? id = root.Properties.AutomationId.ValueOrDefault;
            if (string.IsNullOrEmpty(id)) continue;
            try
            {
                Visit(id, []);
                if (!root.Patterns.ExpandCollapse.IsSupported) continue;
                var expand = root.Patterns.ExpandCollapse.Pattern;
                if (expand.ExpandCollapseState.Value == ExpandCollapseState.LeafNode) continue;
                expand.Expand();
                foreach (var child in TreeItems(root))
                {
                    string? childId = child.Properties.AutomationId.ValueOrDefault;
                    if (string.IsNullOrEmpty(childId)) continue;
                    try { Visit(childId, []); }
                    catch (Exception e) { gaps.Add($"{childId}：{e.Message}"); }
                }
                expand.Collapse();
            }
            catch (Exception e) { gaps.Add($"{id}：{e.Message}"); }
        }
        return new(checkedScreens, findings.Distinct().ToArray(), gaps);

        void Visit(string tree, string[] actions)
        {
            desktop.OpenTree(tree);
            string route = string.Join(" / ", actions.Prepend(tree));
            foreach (string action in actions)
            {
                var previousMenu = desktop.Find("ScreenMenu");
                desktop.SelectAction(action);
                for (int attempt = 0; attempt < 12; attempt++)
                {
                    if (desktop.Confirmation() is not null ||
                        desktop.Window.FindFirstDescendant(c => c.ByAutomationId("ScreenMenu")) is not { } next ||
                        !next.Equals(previousMenu)) break;
                    Thread.Sleep(50);
                }
            }
            if (desktop.Confirmation() is { } dialog)
            {
                Inspect(route, dialog.AsWindow());
                bool opensReport = actions.LastOrDefault() == "CreateSettingsReport";
                string buttonId = opensReport ? "ConfirmationConfirm" : "ConfirmationCancel";
                (dialog.FindFirstDescendant(c => c.ByAutomationId(buttonId)) ??
                    throw new InvalidOperationException("確認画面の操作が見つかりません。")).AsButton().Invoke();
                for (int attempt = 0; attempt < 12 && desktop.Confirmation() is not null; attempt++) Thread.Sleep(50);
                if (opensReport)
                {
                    var document = desktop.Find("ReportDocument");
                    if (!document.Patterns.Text.IsSupported ||
                        string.IsNullOrWhiteSpace(document.Patterns.Text.Pattern.DocumentRange.GetText(-1)))
                        gaps.Add($"{route}：確認後の帳票本文を取得できません。");
                    else
                        Inspect(route + " / 確認後の帳票", desktop.Window);
                }
                else
                    gaps.Add($"{route}：確認後の画面は未監査です（取消）。");
                return;
            }
            Inspect(route, desktop.Window);
            if (actions.Length >= 4)
            {
                if (desktop.Window.FindFirstDescendant(c => c.ByAutomationId("ScreenMenu")) is not null)
                    gaps.Add($"{route}：メニューの巡回上限に達しました。");
                return;
            }
            if (desktop.Window.FindFirstDescendant(c => c.ByAutomationId("ReportListOpen")) is { IsEnabled: false } reportButton &&
                desktop.Window.FindFirstDescendant(c => c.ByAutomationId("ReportList"))?.AsDataGridView().Rows.FirstOrDefault() is { } row)
            {
                row.Patterns.SelectionItem.Pattern.Select();
                reportButton.AsButton().Invoke();
                Inspect(route + " / 帳票閲覧", desktop.Window);
            }
            if (desktop.Window.FindFirstDescendant(c => c.ByAutomationId("ScreenMenu")) is not { } menu) return;
            var items = menu.FindAllChildren(c => c.ByControlType(ControlType.ListItem))
                .Select(item => item.Properties.AutomationId.ValueOrDefault).ToArray();
            if (!menus.Add(string.Join("|", items.Prepend(tree)))) return;
            foreach (string? item in items)
                if (!string.IsNullOrEmpty(item) && !item.EndsWith("Back", StringComparison.Ordinal) && !actions.Contains(item))
                {
                    try { Visit(tree, [.. actions, item]); }
                    catch (Exception e) { gaps.Add($"{route} / {item}：{e.Message}"); }
                }
        }

        void Inspect(string screen, Window window)
        {
            checkedScreens.Add(screen);
            foreach (var element in window.FindAllDescendants().Prepend(window))
            {
                var type = element.Properties.ControlType.ValueOrDefault;
                string id = element.Properties.AutomationId.ValueOrDefault ?? "";
                if (type is ControlType.Button or ControlType.CheckBox or ControlType.ComboBox or ControlType.HeaderItem or
                    ControlType.Hyperlink or ControlType.ListItem or ControlType.RadioButton or ControlType.TabItem or
                    ControlType.Text or ControlType.TreeItem or ControlType.Window)
                {
                    var parentType = element.Parent?.Properties.ControlType.ValueOrDefault;
                    string? name = element.Properties.Name.ValueOrDefault;
                    if (parentType is not (ControlType.TitleBar or ControlType.DataItem) &&
                        !(type == ControlType.Text && id.Length == 0 && parentType == ControlType.Custom) &&
                        !string.IsNullOrEmpty(name) && English().IsMatch(name)) findings.Add(new(screen, id, name));
                }
                if (id == "ReportDocument" && element.Patterns.Text.IsSupported)
                {
                    string text = element.Patterns.Text.Pattern.DocumentRange.GetText(-1);
                    foreach (string line in text.Split('\n').Where(l => English().IsMatch(l)))
                        findings.Add(new(screen, id, line.Trim()));
                }
            }
        }
    }

    private static AutomationElement[] TreeItems(AutomationElement parent) =>
        parent.FindAllChildren(c => c.ByControlType(ControlType.TreeItem));

    public static int Write(string path, Report report)
    {
        File.WriteAllText(path, JsonSerializer.Serialize(report, Outcome.JsonOptions));
        Console.WriteLine($"監査 {report.Checked.Count} / 英字検出 {report.Findings.Count} / 巡回失敗 {report.Gaps.Count}");
        return report.Findings.Count == 0 && report.Gaps.Count == 0 ? 0 : 1;
    }
}
