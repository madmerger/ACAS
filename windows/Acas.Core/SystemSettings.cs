using Acas.Core.Engine;

namespace Acas.Core;

public sealed record CompanySetup(string Name, string PeriodPassword, bool General, bool Sales,
    bool Purchasing, bool Invoicing, bool Stock, bool Orders);

public sealed record CompanyParameters(string Name, DateTime Start, DateTime End,
    int Cycle, int Period, int PageLines, int DateFormat, bool SalesStockLink, CompanyContact? Contact = null)
{
    public IReadOnlyList<decimal>? TaxRates { get; init; }
    public int? Quarter { get; init; }
    public bool? PrintTaxNumber { get; init; }
}

public sealed record CompanyContact(string Address1, string Address2, string Address3, string Address4,
    string PostCode, string Country, string TaxRegistration);

public sealed record OperatingParameters(int Host, int System, int Capture, string Queue1, string Queue2, string Queue3);

public sealed record DefaultAccount(int Number, decimal Code, string Reference, string Tax);

public sealed record GeneralLedgerParameters(string Division, bool RevenueOnly, bool Grouped, bool Comparatives,
    bool SecondaryIndex, bool MinimumValidation, bool Archive, bool AutomaticTax, bool UseIncompleteRecords, int NextBatch);

public sealed class SystemSettings(Db database)
{
    public const string SystemFile = "ledgers/acas/system.dat";
    private const string SystemKey = "00000001", DefaultKey = "00000002";
    private static readonly DateTime Epoch = new(1600, 12, 31);
    private const string Alphabet = "CKQUAELSMWYIZJRPBXFVGNODTH";

    public Rec? Read() => database.Read(SystemFile, SystemKey) is { } bytes ? Layouts.System.From(bytes) : null;

    public static DateTime? Date(Rec system, string field)
    {
        int day = system.I(field);
        return day > 0 && day <= (DateTime.MaxValue.Date - Epoch).Days ? Epoch.AddDays(day) : null;
    }

    public bool Initialize(CompanySetup setup, DateTime today)
    {
        if (Read() != null || string.IsNullOrWhiteSpace(setup.Name) || !GeneralLedger.Fits(setup.Name, 32) ||
            setup.PeriodPassword.Length != 4 || setup.PeriodPassword.Any(ch => !char.IsAsciiLetter(ch)) || today.Date <= Epoch)
            return false;

        var system = Layouts.System.New();
        system.SetN("Version-Prime", 1);
        system.SetN("Version-Secondary", 1);
        system.SetN("Date-Form", 1);
        system.Set("Usera", setup.Name);
        system.Set("User-Code", EncodeName(setup.Name));
        system.Set("Pass-Word", EncodePassword(setup.PeriodPassword));
        system.Set("Sl-Own-Nos", "N");
        system.SetN("Run-Date", (today.Date - Epoch).Days);
        system.Set("Maps-Ser-xx", "mp");
        system.SetN("Maps-Ser-nn", 9999);
        system.SetN("Level-1", setup.General ? 1 : 0);
        system.SetN("Level-2", setup.Purchasing ? 1 : 0);
        system.SetN("Level-3", setup.Sales ? 1 : 0);
        system.SetN("Full-Invoicing", setup.Invoicing ? 1 : 0);
        system.SetN("Level-4", setup.Stock ? 1 : 0);
        system.SetN("Level-5", setup.Orders ? 1 : 0);
        foreach (var (field, value) in new (string, int)[]
        {
            ("Op-System", 1), ("Sales-Range", 1), ("Purchase-Range", 2), ("Next-Batch", 1),
            ("SL-Dunning", 1), ("SL-Charges", 1), ("SL-Credit", 30), ("Invoicer", 2)
        }) system.SetN(field, value);
        system.Set("SL-Delim", "\\");
        if (setup.Purchasing) system.Set("PL-Delim", "\\");
        Array.Fill(system.B, (byte)' ', 768, 256);

        var defaults = Layouts.Default.New().B;
        Array.Fill(defaults, (byte)' ', 132, defaults.Length - 132);
        var final = Enumerable.Repeat((byte)' ', 1024).ToArray();
        var balances = (byte[])final.Clone();
        for (int i = 0; i < 20; i++)
        {
            Array.Clear(balances, i * 6, 5);
            balances[i * 6 + 5] = 0x0c;
        }
        database.Atomic(() =>
        {
            database.Put(SystemFile, SystemKey, system.B);
            database.Put(SystemFile, DefaultKey, defaults);
            database.Put(SystemFile, "00000003", final);
            database.Put(SystemFile, "00000004", balances);
        });
        return true;
    }

    public bool SetRunDate(DateTime date)
    {
        if (date.Date <= Epoch || Read() is not { } system || system.I("Cyclea") == 0 || system.I("Level-1") != 1) return false;
        if (system.I("Date-Form") is < 1 or > 3) system.SetN("Date-Form", 1);
        system.SetN("Run-Date", (date.Date - Epoch).Days);
        database.Put(SystemFile, SystemKey, system.B);
        return true;
    }

    public bool SaveParameters(CompanyParameters parameters)
    {
        if (Read() is not { } system || string.IsNullOrWhiteSpace(parameters.Name) || !GeneralLedger.Fits(parameters.Name, 32) ||
            parameters.Start.Date <= Epoch || parameters.End.Date <= Epoch ||
            parameters.Cycle is < 0 or > 99 || parameters.DateFormat is < 1 or > 3 ||
            parameters.PageLines is < 29 or > 99 || parameters.Quarter is < 0 or > 4 ||
            (parameters.TaxRates is { } rates && (rates.Count != 5 || rates.Any(rate => rate is < 0 or > 99.99m)))) return false;
        if (parameters.Contact is { } contact)
        {
            (string Field, string Value, int Width)[] fields =
            [
                ("Address-1", contact.Address1, 24), ("Address-2", contact.Address2, 24),
                ("Address-3", contact.Address3, 24), ("Address-4", contact.Address4, 24),
                ("Post-Code", contact.PostCode, 12), ("Country", contact.Country, 24),
                ("VAT-Reg-Number", contact.TaxRegistration, 11)
            ];
            if (fields.Any(f => !GeneralLedger.Fits(f.Value, f.Width))) return false;
            foreach (var (field, value, _) in fields) system.Set(field, value);
        }
        system.Set("Usera", parameters.Name);
        system.SetN("Start-Date", (parameters.Start.Date - Epoch).Days);
        system.SetN("End-Date", (parameters.End.Date - Epoch).Days);
        system.SetN("Cyclea", parameters.Cycle);
        system.SetN("Period", parameters.Period is 6 or 13 ? parameters.Period : 3);
        system.SetN("Page-Lines", parameters.PageLines);
        system.SetN("Date-Form", parameters.DateFormat);
        if (parameters.Quarter is { } quarter) system.SetN("Current-Quarter", quarter);
        if (parameters.PrintTaxNumber is { } printTax) system.Set("SL-VAT-Printed", printTax ? "Y" : "N");
        if (parameters.TaxRates is { } taxRates)
            for (int i = 0; i < taxRates.Count; i++) system.SetN($"Vat-Rate-{i + 1}", taxRates[i]);
        if (system.I("Level-3") == 1)
            system.Set("SL-Stock-Link", parameters.SalesStockLink && system.I("Level-4") == 1 ? "Y" : "N");
        database.Put(SystemFile, SystemKey, system.B);
        return true;
    }

    public OperatingParameters? ReadOperatingParameters() => Read() is { } system
        ? new(system.I("Host"), system.I("Op-System"), system.I("Data-Capture-Used"),
            system.St("Print-Spool-Name"), system.St("Print-Spool-Name2"), system.St("Print-Spool-Name3"))
        : null;

    public bool SaveOperatingParameters(OperatingParameters parameters)
    {
        if (Read() is not { } system || parameters.Host is < 0 or > 1 ||
            parameters.System < (parameters.Host == 1 ? 2 : 1) || parameters.System > 6 ||
            parameters.Capture is < 0 or > 2) return false;
        if (parameters.System is 3 or 5 or 6)
        {
            if (string.IsNullOrWhiteSpace(parameters.Queue1) ||
                !GeneralLedger.Fits(parameters.Queue1, 48) || !GeneralLedger.Fits(parameters.Queue2, 48) ||
                !GeneralLedger.Fits(parameters.Queue3, 48)) return false;
            system.Set("Print-Spool-Name", parameters.Queue1);
            system.Set("Print-Spool-Name2", string.IsNullOrWhiteSpace(parameters.Queue2) ? parameters.Queue1 : parameters.Queue2);
            system.Set("Print-Spool-Name3", string.IsNullOrWhiteSpace(parameters.Queue3) ? parameters.Queue1 : parameters.Queue3);
        }
        system.SetN("Host", parameters.Host);
        system.SetN("Op-System", parameters.System);
        system.SetN("Data-Capture-Used", parameters.Capture);
        database.Put(SystemFile, SystemKey, system.B);
        return true;
    }

    public string? PrintSettings()
    {
        if (Read() is not { } system) return null;
        const string title = "システム設定帳票";
        var lines = new List<string>();
        string S(string field) => system.St(field);
        int I(string field) => system.I(field);
        string N(string field, int width = 1, bool zeros = false) =>
            I(field).ToString(zeros ? new string('0', width) : "0", System.Globalization.CultureInfo.InvariantCulture).PadLeft(width);
        string Rate(string field) => LedgerReports.Money(system.N(field)).PadLeft(5);
        string DateValue(string field) => LedgerReports.LegacyDate(system, Date(system, field));
        string Yes(bool enabled) => enabled ? "はい" : "いいえ";
        string Flag(string field) => Yes(I(field) == 1);
        string On(string field) => Yes(S(field) == "Y");
        string StockLink(string field) => Yes(S(field) == "Y" && I("Level-4") == 1);
        string StockPeriod(string field) => S(field) switch
        {
            "M" => "月次", "Q" => "四半期", "Y" => "年次", _ => "未設定"
        };
        void Row(params (int Column, string Value)[] cells) => lines.Add(FixedReportLine.Format(cells));
        void Blank() => lines.Add("");
        void Data(string label = "", string value = "", string right = "", int rightValueColumn = 120, string rightValue = "") =>
            Row((10, label), (27, value), (70, right), (rightValueColumn, rightValue));
        void Section(string left, string right, int leftColumn = 24)
        {
            Blank();
            Row((leftColumn, left), (80, right));
            Row((leftColumn, new string('*', 40 - leftColumn)), (80, new string('*', 16)));
            Blank();
        }
        void Page(int page) => Row((0, "設定"), (50, title), (110, DateValue("Run-Date")), (126, "頁"), (131, page.ToString()));
        string PathValue(string key) => Environment.GetEnvironmentVariable(key) is { Length: > 0 } path ? path : "環境変数未設定";
        string Abbreviate(string field) => S(field).Split("  ", StringSplitOptions.None)[0];
        bool divided = S("P-C") is "P" or "B";
        bool relational = I("File-System-Used") == 1;
        bool single = I("Op-System") is 1 or 2 or 4;
        string extra = S("Extra-Type") switch { "C" => "追加料金", "D" => "追加値引", _ => "" };

        Page(1);
        Section("利用者設定", "総勘定元帳設定");
        Data("会社名", S("Usera"), S("P-C") switch { "P" => "部門を使用", "B" => "拠点を使用", _ => "部門・拠点なし" });
        Data("住所1", S("Address-1"), divided ? S("P-C-Level") == "R" ? "収益勘定のみ" : "全勘定" : "");
        Data(value: S("Address-2"), right: divided ? S("P-C-Grouped") == "Y" ? "先頭桁で区分" : "先頭桁で区分しない" : "");
        Data(value: S("Address-3"), right: "比較情報 " + On("Comps"));
        Data(value: string.Join(',', Abbreviate("Address-4"), Abbreviate("Post-Code"), Abbreviate("Country")),
            right: "二次索引 " + On("Ledger-2nd-Index"));
        Data("日付順", I("Date-Form") switch { 2 => "月・日・年", 0 or 1 => "日・月・年", _ => "年・月・日" });
        Data("期首日", DateValue("Start-Date"), S("M-V") == "Y" ? "最小限の入力検証" : "完全な入力検証");
        Data("期末日", DateValue("End-Date"), S("Arch") == "Y" ? "締め時に仕訳を保管" : "締め時に仕訳を削除");
        Row((10, "税率1/4"), (27, Rate("Vat-Rate-1") + " / " + Rate("Vat-Rate-4")), (42, "税番号"), (51, S("VAT-Reg-Number")),
            (70, I("Sales-Range") == 0 ? "売掛勘定番号の先頭桁なし" : "売掛勘定番号の先頭桁"), (110, I("Sales-Range") == 0 ? "" : N("Sales-Range")));
        Data("税率2/5", Rate("Vat-Rate-2") + " / " + Rate("Vat-Rate-5"),
            I("Purchase-Range") == 0 ? "買掛勘定番号の先頭桁なし" : "買掛勘定番号の先頭桁", 110, I("Purchase-Range") == 0 ? "" : N("Purchase-Range"));
        Data("税率3", Rate("Vat-Rate-3"), S("Vat") == "Y" ? "消費税を自動計算" : "消費税を手計算");
        Data("四半期", N("Current-Quarter", 2), "四半期内の会計期間数", 91, N("Period", 5));
        Data("会計期間", N("Cyclea", 2), "次回バッチ番号", 91, N("Next-Batch", 5));
        Data("印刷行数", N("Page-Lines", 3), "簡易記帳との連携", 96, On("Irs-Instead"));

        Section("運用環境設定", "買掛元帳設定");
        Data("利用形態", I("Host") == 1 ? "複数利用" : "単独利用", "住所区切り", 98, S("PL-Delim"));
        string operating = I("Op-System") switch { 1 => "DOS", 2 => "Windows", 4 => "OS/2", 5 => "Unix", 6 => "Linux", _ => "" };
        operating += I("Data-Capture-Used") switch { 1 => "・画面表示", 2 => "・部品表示", _ => "" };
        Data("旧環境の区分", operating, "次回バッチ番号", 94, N("BL-Next-Batch", 5, true));
        Data("版", S("Maps-Ser-xx") == "mp" && I("Maps-Ser-nn") == 9999 ? "公開版" : "商用版",
            "次回伝票番号", 91, N("Next-Folio", 8, true));
        Data(value: (relational ? "データベース" : "旧データファイル") + "／重複処理 " + Flag("File-Duplicates-In-Use"),
            right: "支払勘定", rightValueColumn: 93, rightValue: N("BL-Pay-Ac", 6, true));
        Data("簡易記帳のパス", PathValue("ACAS_IRS"), "仕入元帳勘定", 93, N("BL-Purch-Ac", 6, true));
        Data("台帳のパス", PathValue("ACAS_LEDGERS"), "買掛金勘定", 93, N("P-Creditors", 6, true));
        Data("共通の印刷先", single ? "使用しない" : S("Print-Spool-Name"), "在庫連携", 96, StockLink("PL-Stock-Link"));
        Data("総勘定元帳印刷先", single ? "使用しない" : S("Print-Spool-Name2"));
        Data("買掛元帳の印刷先", single ? "使用しない" : S("Print-Spool-Name3"));

        Section("請求書設定", "売掛元帳設定");
        Data("次回請求書番号", N("Next-Invoice", 8, true), S("SL-Own-Nos") == "N" ? "請求書番号を自動採番" : "請求書番号を手入力");
        Data(extra.Length == 0 ? "" : extra + "説明", extra.Length == 0 ? "" : S("Extra-Desc"), "督促状 " + Flag("SL-Dunning"));
        Data(extra.Length == 0 ? "" : extra + "率", extra.Length == 0 ? "" : Rate("Extra-Rate"), "延滞料 " + Flag("SL-Charges"));
        Data("請求書入力段階", N("Invoicer"), "支払期限", 84, N("SL-Credit", 2) + " 日");
        Data(extra.Length == 0 ? "" : extra + "勘定", extra.Length == 0 ? "" : N("Extra-Charge-Ac", 6, true),
            "標準与信限度額", 92, N("SL-Limit", 7));
        Data("消費税勘定", N("Vat-Ac", 6, true), "標準値引率", 93, Rate("SL-Disc") + "%");
        Data("税登録番号印刷", On("SL-VAT-Printed"), "延滞対象最低残高", 94, N("SL-Min", 5));
        Data(right: "延滞料上限", rightValueColumn: 94, rightValue: N("SL-Max", 5));
        Data(right: "延滞料率", rightValueColumn: 93, rightValue: Rate("SL-Late-Per") + "%");
        Data(right: "住所区切り", rightValueColumn: 98, rightValue: S("SL-Delim"));
        Data("仮請求書保管期間", N("PF-Retention", 3), "次回バッチ番号", 94, N("First-Sl-Batch", 5, true));
        Row((10, "納品書の社名印刷"), (49, S("SL-Comp-Head-Pick")), (70, "在庫連携"), (96, StockLink("SL-Stock-Link")));
        Row((10, "請求書の社名印刷"), (49, S("SL-Comp-Head-Inv")), (70, "入金勘定"), (93, N("SL-Pay-Ac", 6, true)));
        Row((10, "取引明細書の社名印刷"), (49, S("SL-Comp-Head-Stat")), (70, "売上元帳勘定"), (93, N("SL-Sales-Ac", 6, true)));
        Row((10, "督促状の社名印刷"), (49, S("SL-Comp-Head-Lets")), (70, "売掛金勘定"), (93, N("S-Debtors", 6, true)));

        lines[^1] += "\f";
        Page(2);
        Section("在庫管理設定", "受注管理設定");
        Data("デバッグ", Flag("Stk-Debug"), "受注管理", 94, Flag("Stk-OE-Used"));
        Data("製造管理", Flag("Stk-Manu-Used"));
        Data("在庫監査", Flag("Stk-Audit-Used"));
        Data("移動監査", Flag("Stk-Mov-Audit"));
        Data("在庫当期区分", StockPeriod("Stk-Period-Cur"));
        Data("在庫累計区分", StockPeriod("Stk-Period-dat"));
        Data("平均原価", Flag("Stk-Averaging"));
        Data("在庫監査番号", N("Stk-Audit-No", 8, true));
        Section("給与設定", "データベース設定", 22);
        Data("給与計算", Yes(false), relational ? "スキーマ" : "", 90, relational ? S("RDBMS-DB-Name") : "");
        if (relational)
        {
            Data(right: "利用者名", rightValueColumn: 90, rightValue: S("RDBMS-User"));
            Row((24, "システム状態"), (70, "パスワード"), (90, "非表示"));
        }
        else
        {
            Blank();
            Row((24, "システム状態"));
        }
        Row((24, new string('*', 16)));
        Blank();
        Data("ファイル状態", string.Concat(Enumerable.Range(1, 32).Select(i => system.S($"File-Status-{i}"))));
        Blank();
        Row((51, "システム設定帳票 終わり"));
        Row((51, new string('=', 30)));

        string body = string.Join("\n", lines).Replace("\f\n", "\f", StringComparison.Ordinal) + "\n";
        database.AddSpool(title, body);
        return body;
    }

    public GeneralLedgerParameters? ReadGeneralLedgerParameters() => Read() is { } system && system.I("Level-1") == 1
        ? new(system.S("P-C"), system.S("P-C-Level") == "R", system.S("P-C-Grouped") == "Y",
            system.S("Comps") == "Y", system.S("Ledger-2nd-Index") == "Y", system.S("M-V") == "Y",
            system.S("Arch") == "Y", system.S("Vat") == "Y", system.S("Irs-Instead") == "Y", system.I("Next-Batch"))
        : null;

    public bool SaveGeneralLedgerParameters(GeneralLedgerParameters parameters)
    {
        if (Read() is not { } system || system.I("Level-1") != 1 ||
            parameters.Division is not (" " or "P" or "B") || parameters.NextBatch is < 0 or > short.MaxValue)
            return false;
        system.Set("P-C", parameters.Division);
        system.Set("P-C-Level", parameters.Division != " " && parameters.RevenueOnly ? "R" : " ");
        system.Set("P-C-Grouped", parameters.Grouped ? "Y" : " ");
        system.Set("Comps", parameters.Comparatives ? "Y" : " ");
        system.Set("Ledger-2nd-Index", parameters.SecondaryIndex ? "Y" : " ");
        system.Set("M-V", parameters.MinimumValidation ? "Y" : " ");
        system.Set("Arch", parameters.Archive ? "Y" : " ");
        system.Set("Vat", parameters.AutomaticTax ? "Y" : " ");
        system.Set("Irs-Instead", parameters.UseIncompleteRecords ? "Y" : "N");
        system.SetN("Next-Batch", parameters.NextBatch);
        database.Put(SystemFile, SystemKey, system.B);
        return true;
    }

    public IReadOnlyList<DefaultAccount> DefaultAccounts()
    {
        var data = ReadDefaults();
        return Enumerable.Range(1, 32).Select(i => new DefaultAccount(i, data.N("acs" + i), data.St("code" + i), data.St("vat" + i))).ToArray();
    }

    public bool AmendDefault(DefaultAccount account)
    {
        int i = account.Number;
        if (Read() == null || i is < 1 or > 32 || account.Code is < 0 or > 9999.99m ||
            !GeneralLedger.Fits(account.Reference, 2) || account.Tax is not ("I" or "O" or "N")) return false;
        var data = ReadDefaults();
        data.SetN("acs" + i, account.Code);
        var key = Cob.P9(Cob.Trunc(account.Code * 100, 0), 6) + "00";
        if (database.Read(GeneralLedger.LedgerFile, key) != null)
        {
            data.Set("code" + i, account.Reference);
            data.Set("vat" + i, account.Tax);
        }
        database.Put(SystemFile, DefaultKey, data.B);
        return true;
    }

    public bool ResetDefaults(string password)
    {
        if (Read() is not { } system || password.Length != 4 || password.Any(ch => !char.IsAsciiLetter(ch)) ||
            system.S("Pass-Word") != EncodePassword(password)) return false;
        var defaults = ReadDefaults();
        for (int i = 1; i <= 33; i++)
        {
            defaults.SetN("acs" + i, 0);
            defaults.Set("code" + i, "");
            defaults.Set("vat" + i, "");
        }
        database.Put(SystemFile, DefaultKey, defaults.B);
        return true;
    }

    private Rec ReadDefaults() => database.Read(SystemFile, DefaultKey) is { } bytes ? Layouts.Default.From(bytes) : Layouts.Default.New();

    private static int Index(char ch) => Alphabet.IndexOf(char.ToUpperInvariant(ch)) + 1;

    private static string EncodeName(string name)
    {
        var result = Enumerable.Repeat(' ', 32).ToArray();
        for (int i = 1; i <= Math.Min(name.Length, 31); i++)
        {
            int a = Index(name[i - 1]);
            if (a == 0) continue;
            int b = (int)Cob.Round((i + 51m) / i, 0);
            if (b > 25) b -= 26;
            int z = Math.Abs(a + b - 27);
            if (z > 26) z -= 26;
            if (z != 0) result[i - 1] = Alphabet[z - 1];
        }
        return new string(result);
    }

    private static string EncodePassword(string password)
    {
        var result = new char[4];
        for (int i = 1; i <= 4; i++)
        {
            int z = Math.Abs(Index(password[i - 1]) + i * i + 3 - 26);
            result[4 - i] = z == 0 ? ' ' : Alphabet[z - 1];
        }
        return new string(result);
    }
}
