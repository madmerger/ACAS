using System.Text.RegularExpressions;
using Acas.Core;

internal static class PurchaseScreenAudit
{
    public static MenuItem Navigation(MenuItem menu)
    {
        CheckIds(Flatten(menu).Select(item => item.Id));
        foreach (var item in Flatten(menu)) CheckLabel(item.Caption);
        return menu;

        static IEnumerable<MenuItem> Flatten(MenuItem item) =>
            new[] { item }.Concat((item.Children ?? []).SelectMany(Flatten));
    }

    public static Screen Check(Screen screen)
    {
        CheckLabel(screen.Title);
        switch (screen)
        {
            case MenuScreen menu:
                CheckIds(menu.Items.Select(item => item.Id));
                foreach (var item in menu.Items) CheckLabel(item.Caption);
                break;
            case FormScreen form:
                CheckIds(form.Fields.SelectMany(field => new[] { field.Id, field.Id + "Label" }).Append("FormSubmit"));
                CheckLabel(form.SubmitLabel);
                foreach (var field in form.Fields)
                {
                    CheckLabel(field.Label);
                    if (field is ChoiceField choice && choice.Id != "PurchaseSupplierSelectedCode")
                        foreach (var option in choice.Options) CheckLabel(option.Label);
                }
                break;
            case TableScreen table:
                CheckIds([table.Id]);
                foreach (var column in table.Columns) CheckLabel(column);
                CheckLabel(table.EmptyMessage);
                break;
            case InformationScreen info:
                CheckLabel(WithoutRecordIdentifiers(info.Message));
                break;
            case ConfirmationScreen confirmation:
                CheckLabel(WithoutRecordIdentifiers(confirmation.Message));
                CheckLabel(confirmation.ConfirmLabel);
                break;
        }
        return screen;
    }

    private static void CheckIds(IEnumerable<string> ids)
    {
        var known = new HashSet<string>(StringComparer.Ordinal);
        foreach (string id in ids)
            if (string.IsNullOrWhiteSpace(id) || !known.Add(id))
                throw new InvalidOperationException("操作対象の識別子が空、または重複しています。");
    }

    private static string WithoutRecordIdentifiers(string label) => Regex.Replace(label, "「[A-Z0-9-]{7,8}」", "「」");

    private static void CheckLabel(string label)
    {
        if (Regex.IsMatch(label, "[A-Za-zＡ-Ｚａ-ｚ]"))
            throw new InvalidOperationException("画面ラベルに英字が含まれています。");
    }
}
