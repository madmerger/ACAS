namespace Acas.Core;

public sealed record MenuItem(string Id, string Label, int? Number = null,
    IReadOnlyList<MenuItem>? Children = null, Func<Screen>? Open = null)
{
    public string Caption => Number is int number ? $"{number}　{Label}" : Label;
}

public abstract record Screen(string Title);

public sealed record InformationScreen(string Title, string Message) : Screen(Title);

public sealed record MenuScreen(string Title, IReadOnlyList<MenuItem> Items) : Screen(Title);

public sealed record TableScreen(string Title, string Id, IReadOnlyList<string> Columns,
    IReadOnlyList<TableRow> Rows, string EmptyMessage = "表示するデータがありません。") : Screen(Title);

public sealed record TableRow(IReadOnlyList<string> Cells, Func<Screen>? Open = null, IReadOnlyList<object>? SortValues = null)
{
    public IReadOnlyList<object> SortCells => SortValues ?? Cells;
}

public abstract record Field(string Id, string Label);
public sealed record TextField(string Id, string Label, string Value = "", int MaxLength = 0) : Field(Id, Label);
public sealed record PasswordField(string Id, string Label, int MaxLength) : Field(Id, Label);
public sealed record DateField(string Id, string Label, DateTime? Value = null) : Field(Id, Label);
public sealed record ChoiceField(string Id, string Label, IReadOnlyList<Choice> Options, string? Value = null) : Field(Id, Label);
public sealed record Choice(string Value, string Label);

public sealed class FormValues
{
    private readonly IReadOnlyDictionary<string, object?> _values;

    public FormValues(IReadOnlyDictionary<string, object?> values) => _values = values;
    public string Text(string id) => (string)_values[id]!;
    public DateTime? Date(string id) => (DateTime?)_values[id];
    public string? Choice(string id) => (string?)_values[id];
}

public sealed record FormScreen(string Title, IReadOnlyList<Field> Fields, string SubmitLabel,
    Func<FormValues, Screen> Submit) : Screen(Title);

public sealed record ConfirmationScreen(string Title, string Message, string ConfirmLabel,
    Func<Screen> Confirm, Func<Screen> Cancel) : Screen(Title);

public sealed record ReportScreen(string Title, string Body, Func<Screen>? Back = null) : Screen(Title);
