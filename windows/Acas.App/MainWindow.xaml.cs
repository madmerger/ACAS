using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Documents;
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

    public MainWindow(string? database = null)
    {
        InitializeComponent();
        var path = LocalDatabasePath.Resolve(database ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ACAS", "acas.db"));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        _database = new Db(path);
        Closed += (_, _) => _database.Dispose();
        TrackTemplateIds(Navigation);
        TrackTemplateIds(ScreenContent);

        var subsystems = new List<ISubsystemScreens>();
        foreach (var item in SubsystemScreens.Load(typeof(MainWindow).Assembly, _database, subsystems.Add)
            .Append(new NavigationItem("MenuReports", "帳票", Open: OpenReports)))
            Navigation.Items.Add(CreateMenuItem(item));
        ShowScreen(new InformationScreen("業務メニュー", "左側のメニューから操作を選択してください。"));
        Closing += (_, e) =>
        {
            foreach (var subsystem in subsystems)
                if (!subsystem.TryClose())
                {
                    e.Cancel = true;
                    MessageBox.Show(this, "元帳の終了状態を保存できませんでした。", "会計管理");
                    break;
                }
        };
    }

    private static T Identify<T>(T control, string id, string? name = null) where T : FrameworkElement
    {
        AutomationProperties.SetAutomationId(control, id);
        if (name != null) AutomationProperties.SetName(control, name);
        return control;
    }

    private static void TrackTemplateIds(FrameworkElement root)
    {
        root.LayoutUpdated += (_, _) => Visit(root, AutomationProperties.GetAutomationId(root));

        static void Visit(DependencyObject parent, string path)
        {
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
            {
                var child = VisualTreeHelper.GetChild(parent, i);
                var id = AutomationProperties.GetAutomationId(child);
                var part = id.Length == 0 ? $"{path}_{child.GetType().Name}{i}" : id;
                if (id.Length == 0 && child is TextBlock or Thumb)
                    AutomationProperties.SetAutomationId(child, part);
                Visit(child, part);
            }
        }
    }

    private static TreeViewItem CreateMenuItem(NavigationItem item)
    {
        var caption = Identify(new TextBlock { Text = item.Caption }, item.Id + "Caption");
        var node = Identify(new TreeViewItem { Header = caption, Tag = item, IsExpanded = true }, item.Id, item.Caption);
        if (item.Children != null)
            foreach (var child in item.Children) node.Items.Add(CreateMenuItem(child));
        return node;
    }

    private void OpenNavigation(object sender, RoutedPropertyChangedEventArgs<object> e)
    {
        if (e.NewValue is TreeViewItem { Tag: NavigationItem { Open: { } open } })
            ShowScreen(open());
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
    }

    private Button ActionButton(string id, string label, Action action)
    {
        var button = Identify(new Button { Content = Identify(new TextBlock { Text = label }, id + "Caption") }, id, label);
        button.Click += (_, _) => action();
        return button;
    }

    private FrameworkElement CreateMenu(MenuScreen menu)
    {
        var panel = new DockPanel();
        var list = Identify(new ListBox(), "ScreenMenu", menu.Title);
        foreach (var item in menu.Items)
        {
            var caption = Identify(new TextBlock { Text = item.Caption }, item.Id + "Caption");
            list.Items.Add(Identify(new ListBoxItem { Content = caption, Tag = item }, item.Id, item.Caption));
        }
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
        {
            var headerStyle = new Style(typeof(DataGridColumnHeader), grid.ColumnHeaderStyle);
            headerStyle.Setters.Add(new Setter(AutomationProperties.AutomationIdProperty, $"{table.Id}Column{i + 1}"));
            grid.Columns.Add(new DataGridTextColumn
            {
                Header = table.Columns[i], HeaderStyle = headerStyle, Binding = new Binding($"Cells[{i}]"), SortMemberPath = $"SortCells[{i}]"
            });
        }

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
                    readers.Add(field.Id, () => datePicker.SelectedDate);
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
            var label = Identify(new Label
            {
                Content = Identify(new TextBlock { Text = field.Label }, field.Id + "LabelCaption"), Target = control
            }, field.Id + "Label", field.Label);
            AutomationProperties.SetLabeledBy(control, label);
            control.MinWidth = 280;
            control.Margin = new Thickness(0, 0, 0, 12);
            fields.Children.Add(label);
            fields.Children.Add(Identify(control, field.Id));
        }
        var submit = ActionButton("FormSubmit", form.SubmitLabel, () =>
            ShowScreen(form.Submit(new FormValues(readers.ToDictionary(pair => pair.Key, pair => pair.Value())))));
        submit.IsDefault = true;
        submit.HorizontalAlignment = HorizontalAlignment.Left;
        fields.Children.Add(submit);
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
        TrackTemplateIds(dialog);
        return dialog.ShowDialog() == true;
    }

    private FrameworkElement CreateReport(ReportScreen report)
    {
        const double fontSize = 14;
        var font = new FontFamily("ＭＳ ゴシック");
        var typeface = new Typeface(font, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        double dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        double lineWidth = report.Body.Split('\r', '\n', '\f').Max(line =>
            new FormattedText(line, Language.GetSpecificCulture(), FlowDirection.LeftToRight, typeface, fontSize, Brushes.Black, dpi)
                .WidthIncludingTrailingWhitespace);
        FlowDocument Document(double size)
        {
            var document = new FlowDocument { FontFamily = font, FontSize = size, ColumnWidth = double.PositiveInfinity };
            var pages = report.Body.Split('\f');
            for (int i = 0; i < pages.Length; i++)
                document.Blocks.Add(new Paragraph(new Run(pages[i])) { BreakPageBefore = i > 0 });
            return document;
        }

        var panel = new DockPanel();
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 12) };
        if (report.Back != null)
            buttons.Children.Add(ActionButton("ReportBack", "帳票一覧へ戻る", () => ShowScreen(report.Back())));
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
                var capabilities = dialog.PrintQueue.GetPrintCapabilities(dialog.PrintTicket);
                var imageable = capabilities.PageImageableArea;
                var left = imageable?.OriginWidth ?? 0;
                var top = imageable?.OriginHeight ?? 0;
                var width = imageable?.ExtentWidth ?? dialog.PrintableAreaWidth;
                var height = imageable?.ExtentHeight ?? dialog.PrintableAreaHeight;
                var document = Document(width > 0 && lineWidth + 4 > width ? fontSize * width / (lineWidth + 4) : fontSize);
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
        var preview = Document(fontSize);
        AutomationProperties.SetAutomationId(preview, "ReportDocumentContent");
        preview.MinPageWidth = lineWidth + 36;
        preview.PagePadding = new Thickness(16);
        panel.Children.Add(Identify(new FlowDocumentScrollViewer { Document = preview, IsToolBarVisible = false,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto }, "ReportDocument", report.Title));
        return panel;
    }
}
