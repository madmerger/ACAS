using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using Acas.Core;
using Acas.Core.Engine;
using Microsoft.Win32;
using NavigationItem = Acas.Core.MenuItem;
using TableRow = Acas.Core.TableRow;

namespace Acas.App;

public partial class MainWindow : Window
{
    private readonly Db _database;
    private MenuScreen? _screenMenu;

    public MainWindow(string? database = null)
    {
        InitializeComponent();
        var path = LocalDatabasePath.Resolve(database ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ACAS", "acas.db"));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        _database = new Db(path);
        Closed += (_, _) => _database.Dispose();

        var accounting = new AccountingScreens(_database);
        foreach (var item in accounting.Navigation()
            .Concat(SubsystemScreens.Load(typeof(MainWindow).Assembly, _database))
            .Append(new NavigationItem("MenuReports", "帳票", Open: OpenReports)))
            Navigation.Items.Add(CreateMenuItem(item));
        ShowScreen(accounting.Start());
    }

    private static T Identify<T>(T control, string id, string? name = null) where T : FrameworkElement
    {
        AutomationProperties.SetAutomationId(control, id);
        if (name != null) AutomationProperties.SetName(control, name);
        return control;
    }

    private static TreeViewItem CreateMenuItem(NavigationItem item)
    {
        var node = Identify(new TreeViewItem { Header = item.Caption, Tag = item }, item.Id);
        if (item.Children != null)
            foreach (var child in item.Children) node.Items.Add(CreateMenuItem(child));
        return node;
    }

    private void OpenNavigation(object sender, RoutedPropertyChangedEventArgs<object> e)
    {
        if (e.NewValue is TreeViewItem node)
            OpenNavigationItem(node, deferConfirmation: true);
    }

    private void ReopenSelectedNavigation(object sender, MouseButtonEventArgs e)
    {
        for (var element = e.OriginalSource as DependencyObject; element != null;)
        {
            if (element is ToggleButton) return;
            if (element is TreeViewItem node)
            {
                if (node.IsSelected && node.Tag is NavigationItem { Open: not null })
                {
                    e.Handled = true;
                    node.Focus();
                    OpenNavigationItem(node);
                }
                return;
            }
            element = element is Visual ? VisualTreeHelper.GetParent(element) : LogicalTreeHelper.GetParent(element);
        }
    }

    private void OpenNavigationItem(TreeViewItem node, bool deferConfirmation = false)
    {
        if (node.Tag is NavigationItem { Open: { } open })
        {
            _screenMenu = null;
            var screen = open();
            if (deferConfirmation && screen is ConfirmationScreen)
                Dispatcher.InvokeAsync(() =>
                {
                    if (ReferenceEquals(Navigation.SelectedItem, node)) ShowScreen(screen);
                });
            else
                ShowScreen(screen);
        }
    }

    private void ReturnToScreenMenu(object sender, RoutedEventArgs e)
    {
        if (_screenMenu is { } menu) ShowScreen(menu);
    }

    private Screen OpenReports()
    {
        var rows = _database.Spool().Select(entry =>
        {
            var created = entry.Created == DateTimeOffset.MinValue ? entry.Created : entry.Created.ToLocalTime();
            var title = $"帳票 {entry.Id}";
            return new TableRow([title, created.ToString("yyyy年M月d日 HH:mm")],
                () => new ReportScreen(title, entry.Body, OpenReports), [entry.Id, created]);
        }).ToArray();
        return new TableScreen("帳票一覧", "ReportList", ["帳票", "作成日時"], rows, "保存された帳票はありません。");
    }

    private void ShowScreen(Screen screen)
    {
        if (screen is MenuScreen activeMenu) _screenMenu = activeMenu;
        ScreenMenuBack.Visibility = _screenMenu != null && screen is not (MenuScreen or ConfirmationScreen)
            ? Visibility.Visible : Visibility.Collapsed;
        Status.Text = "";
        ScreenTitle.Text = screen.Title;
        ScreenContent.Content = screen switch
        {
            InformationScreen info => Identify(new TextBlock { Text = info.Message, TextWrapping = TextWrapping.Wrap }, "ScreenMessage"),
            MenuScreen menu => CreateMenu(menu),
            TableScreen table => CreateTable(table),
            FormScreen form => CreateForm(form),
            ReportScreen report => CreateReport(report),
            _ => null
        };
        if (screen is ConfirmationScreen confirmation)
            ShowScreen(Confirm(confirmation) ? confirmation.Confirm() : confirmation.Cancel());
        if (screen is FormScreen formWithError && formWithError.Error != null) Status.Text = formWithError.Error;
    }

    private Button ActionButton(string id, string label, Action action)
    {
        var button = Identify(new Button { Content = label }, id);
        button.Click += (_, _) => action();
        return button;
    }

    private FrameworkElement CreateMenu(MenuScreen menu)
    {
        var panel = new DockPanel();
        var list = Identify(new ListBox(), "ScreenMenu", menu.Title);
        foreach (var item in menu.Items)
            list.Items.Add(Identify(new ListBoxItem { Content = item.Caption, Tag = item }, item.Id));
        var open = ActionButton("ScreenMenuOpen", "開く", () =>
        {
            if (list.SelectedItem is ListBoxItem { Tag: NavigationItem { Open: { } action } })
                ShowScreen(action());
        });
        open.IsEnabled = false;
        list.SelectionChanged += (_, _) => open.IsEnabled =
            list.SelectedItem is ListBoxItem { Tag: NavigationItem { Open: not null } };
        open.Margin = new Thickness(0, 12, 0, 0);
        DockPanel.SetDock(open, Dock.Bottom);
        panel.Children.Add(open);
        panel.Children.Add(list);
        return panel;
    }

    private FrameworkElement CreateTable(TableScreen table)
    {
        var panel = new DockPanel();
        var grid = Identify(new DataGrid
        {
            AutoGenerateColumns = false, IsReadOnly = true, CanUserAddRows = false,
            SelectionMode = DataGridSelectionMode.Single, ItemsSource = table.Rows,
            ColumnWidth = new DataGridLength(1, DataGridLengthUnitType.Star),
            HeadersVisibility = DataGridHeadersVisibility.Column, GridLinesVisibility = DataGridGridLinesVisibility.Horizontal
        }, table.Id, table.Title);
        for (int i = 0; i < table.Columns.Count; i++)
            grid.Columns.Add(new DataGridTextColumn
            {
                Header = table.Columns[i], Binding = new Binding($"Cells[{i}]"), SortMemberPath = $"SortCells[{i}]"
            });

        var actions = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 0) };
        if (table.Rows.Any(row => row.Open != null))
        {
            var open = ActionButton(table.Id + "Open", "開く", () =>
            {
                if (grid.SelectedItem is TableRow { Open: { } selected }) ShowScreen(selected());
            });
            open.IsEnabled = false;
            grid.SelectionChanged += (_, _) => open.IsEnabled = grid.SelectedItem is TableRow { Open: not null };
            actions.Children.Add(open);
        }
        if (table.Rows.Count == 0)
            actions.Children.Add(Identify(new TextBlock { Text = table.EmptyMessage }, table.Id + "Empty"));
        if (table.Back != null)
            actions.Children.Add(ActionButton(table.Id + "Back", "戻る", () => ShowScreen(table.Back())));
        DockPanel.SetDock(actions, Dock.Bottom);
        panel.Children.Add(actions);
        panel.Children.Add(grid);
        return panel;
    }

    private FrameworkElement CreateForm(FormScreen form)
    {
        var fields = new StackPanel { MaxWidth = 540, HorizontalAlignment = HorizontalAlignment.Left };
        var readers = new Dictionary<string, Func<object?>>();
        foreach (var field in form.Fields)
        {
            Control control;
            switch (field)
            {
                case TextField text:
                    var textBox = new TextBox { Text = text.Value, MaxLength = text.MaxLength };
                    readers.Add(field.Id, () => textBox.Text);
                    control = textBox;
                    break;
                case PasswordField password:
                    var passwordBox = new PasswordBox { MaxLength = password.MaxLength };
                    readers.Add(field.Id, () => passwordBox.Password);
                    control = passwordBox;
                    break;
                case DateField date:
                    var datePicker = new DatePicker { SelectedDate = date.Value, SelectedDateFormat = DatePickerFormat.Short };
                    bool invalid = false;
                    datePicker.SelectedDateChanged += (_, _) => invalid = false;
                    datePicker.DateValidationError += (_, args) => { args.ThrowException = false; invalid = true; };
                    readers.Add(field.Id, () => invalid ? null : datePicker.SelectedDate);
                    control = datePicker;
                    break;
                case ChoiceField choice:
                    var comboBox = new ComboBox
                    {
                        DisplayMemberPath = nameof(Choice.Label), SelectedValuePath = nameof(Choice.Value),
                        ItemsSource = choice.Options, SelectedValue = choice.Value
                    };
                    readers.Add(field.Id, () => comboBox.SelectedValue);
                    control = comboBox;
                    break;
                default:
                    throw new NotSupportedException();
            }
            var label = Identify(new Label { Content = field.Label, Target = control }, field.Id + "Label");
            AutomationProperties.SetLabeledBy(control, label);
            control.MinWidth = 280;
            control.Margin = new Thickness(0, 0, 0, 12);
            fields.Children.Add(label);
            fields.Children.Add(Identify(control, field.Id));
        }
        var submit = ActionButton("FormSubmit", form.SubmitLabel, () =>
            ShowScreen(form.Submit(new FormValues(readers.ToDictionary(pair => pair.Key, pair => pair.Value())))));
        submit.IsDefault = true;
        var actions = new StackPanel { Orientation = Orientation.Horizontal };
        actions.Children.Add(submit);
        if (form.Back != null)
            actions.Children.Add(ActionButton("FormBack", "戻る", () => ShowScreen(form.Back())));
        fields.Children.Add(actions);
        return Identify(new ScrollViewer { Content = fields, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }, "Form");
    }

    private bool Confirm(ConfirmationScreen model)
    {
        var dialog = Identify(new Window
        {
            Owner = this, Title = model.Title, Width = 420, SizeToContent = SizeToContent.Height,
            WindowStartupLocation = WindowStartupLocation.CenterOwner, ResizeMode = ResizeMode.NoResize,
            ShowInTaskbar = false, FontSize = FontSize, Language = Language
        }, "Confirmation");
        var panel = new StackPanel { Margin = new Thickness(24) };
        panel.Children.Add(Identify(new TextBlock { Text = model.Message, TextWrapping = TextWrapping.Wrap }, "ConfirmationMessage"));
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 20, 0, 0) };
        var cancel = ActionButton("ConfirmationCancel", "取消", () => dialog.DialogResult = false);
        cancel.IsCancel = true;
        actions.Children.Add(cancel);
        actions.Children.Add(ActionButton("ConfirmationConfirm", model.ConfirmLabel, () => dialog.DialogResult = true));
        panel.Children.Add(actions);
        dialog.Content = panel;
        return dialog.ShowDialog() == true;
    }

    private FrameworkElement CreateReport(ReportScreen report)
    {
        FlowDocument Document()
        {
            var document = new FlowDocument { FontFamily = new FontFamily("ＭＳ ゴシック"), FontSize = 14, ColumnWidth = 1200 };
            var pages = report.Body.Split('\f');
            for (int i = 0; i < pages.Length; i++)
                document.Blocks.Add(new Paragraph(new Run(pages[i])) { BreakPageBefore = i > 0 });
            return document;
        }

        var panel = new DockPanel();
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 12) };
        if (report.Back != null)
            buttons.Children.Add(ActionButton("ReportBack", report.BackLabel, () => ShowScreen(report.Back())));
        buttons.Children.Add(ActionButton("ReportSave", "保存", () =>
        {
            var picker = new SaveFileDialog { Title = "帳票を保存", FileName = "帳票.txt", Filter = "テキスト文書 (*.txt)|*.txt" };
            if (picker.ShowDialog(this) != true) return;
            try
            {
                File.WriteAllText(picker.FileName, report.Body);
                Status.Text = "帳票を保存しました。";
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                Status.Text = "帳票を保存できませんでした。";
            }
        }));
        buttons.Children.Add(ActionButton("ReportPrint", "印刷", () =>
        {
            var dialog = new PrintDialog();
            if (dialog.ShowDialog() != true) return;
            try
            {
                var document = Document();
                var capabilities = dialog.PrintQueue.GetPrintCapabilities(dialog.PrintTicket);
                var imageable = capabilities.PageImageableArea;
                var left = imageable?.OriginWidth ?? 0;
                var top = imageable?.OriginHeight ?? 0;
                var width = imageable?.ExtentWidth ?? dialog.PrintableAreaWidth;
                var height = imageable?.ExtentHeight ?? dialog.PrintableAreaHeight;
                document.PageWidth = Math.Max(left + width, capabilities.OrientedPageMediaWidth ?? 0);
                document.PageHeight = Math.Max(top + height, capabilities.OrientedPageMediaHeight ?? 0);
                document.PagePadding = new Thickness(left, top, Math.Max(0, document.PageWidth - left - width),
                    Math.Max(0, document.PageHeight - top - height));
                document.ColumnWidth = width;
                dialog.PrintDocument(((IDocumentPaginatorSource)document).DocumentPaginator, report.Title);
            }
            catch (System.Printing.PrintSystemException)
            {
                Status.Text = "帳票を印刷できませんでした。";
            }
        }));
        DockPanel.SetDock(buttons, Dock.Top);
        panel.Children.Add(buttons);
        panel.Children.Add(Identify(new FlowDocumentScrollViewer { Document = Document(), IsToolBarVisible = false }, "ReportDocument", report.Title));
        return panel;
    }
}
