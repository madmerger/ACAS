using System.Text;
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
        var output = new StringBuilder();
        var fields = new Dictionary<string, string>(StringComparer.Ordinal);
        string Used(bool enabled) => enabled ? "使用する" : "使用しない";
        void Line(string name, object? value) => fields.Add(name, $"{name}　{value}");
        string Field(string key) => fields.GetValueOrDefault(key, "");
        void Pair(string left, string right = "") =>
            output.AppendLine(right.Length == 0 ? left : left + new string(' ', Math.Max(1, 70 - Width(left))) + right);
        static int Width(string text) => text.Sum(ch => ch <= 'ÿ' ? 1 : 2);
        void Section(string left, string right)
        {
            Pair("");
            Pair(left, right);
            Pair(new string('*', Width(left)), new string('*', Width(right)));
            Pair("");
        }
        string ReportDate(DateTime? date) => LedgerReports.LegacyDate(system, date);
        void Page(int page)
        {
            Pair($"{title}　{page}ページ", ReportDate(Date(system, "Run-Date")));
        }
        void Number(string label, string field, string format = "0") =>
            Line(label, system.I(field).ToString(format, System.Globalization.CultureInfo.InvariantCulture));
        void Flag(string label, string field) => Line(label, Used(system.I(field) == 1));
        string PeriodName(string field) => system.S(field) switch
        {
            "M" => "月次", "Q" => "四半期", "W" => "週次", "Y" => "年次", _ => "未設定"
        };
        Line("会社名", system.St("Usera"));
        Line("住所1", system.St("Address-1"));
        Line("日付順", system.I("Date-Form") switch { 2 => "月・日・年", 3 => "年・月・日", _ => "日・月・年" });
        Line("期首日", ReportDate(Date(system, "Start-Date")));
        Line("期末日", ReportDate(Date(system, "End-Date")));
        Line("会計期間", system.I("Cyclea"));
        Line("周期区分", system.I("Period"));
        Line("四半期", system.I("Current-Quarter"));
        string Rate(int i) => LedgerReports.Money(system.N($"Vat-Rate-{i}"));
        Line("帳票の１ページあたりの行数", system.I("Page-Lines"));
        Line("利用形態", system.I("Host") == 1 ? "複数利用" : "単独利用");
        Line("旧環境の区分", system.I("Op-System"));
        Line("旧環境の入力方式", system.I("Data-Capture-Used"));
        bool single = system.I("Op-System") is 1 or 2 or 4;
        Line("共通の印刷先", single ? "使用しない" : system.St("Print-Spool-Name"));
        Line("総勘定元帳の印刷先", single ? "使用しない" : system.St("Print-Spool-Name2"));
        Line("買掛元帳の印刷先", single ? "使用しない" : system.St("Print-Spool-Name3"));
        if (system.I("Level-1") == 1)
        {
            Line("部門・拠点", system.S("P-C") switch { "P" => "部門", "B" => "拠点", _ => "使用しない" });
            Line("収益勘定のみに適用", Used(system.S("P-C-Level") == "R"));
            Line("部門・拠点のグループ化", Used(system.S("P-C-Grouped") == "Y"));
            Line("比較情報", Used(system.S("Comps") == "Y"));
            Line("二次索引", Used(system.S("Ledger-2nd-Index") == "Y"));
            Line("最小限の検証", Used(system.S("M-V") == "Y"));
            Line("締め処理時の仕訳保管", Used(system.S("Arch") == "Y"));
            Number("売掛勘定番号の先頭桁", "Sales-Range");
            Number("買掛勘定番号の先頭桁", "Purchase-Range");
            Line("消費税の自動計算", Used(system.S("Vat") == "Y"));
            Line("簡易記帳との連携", Used(system.S("Irs-Instead") == "Y"));
            Line("次回バッチ番号", system.I("Next-Batch"));
        }
        Line("買掛住所区切り", system.St("PL-Delim"));
        Number("買掛次回バッチ番号", "BL-Next-Batch", "00000");
        Number("買掛次回伝票番号", "Next-Folio", "00000000");
        Number("買掛支払勘定", "BL-Pay-Ac", "000000");
        Number("仕入元帳勘定", "BL-Purch-Ac", "000000");
        Number("買掛金勘定", "P-Creditors", "000000");
        Line("買掛と在庫の連携", Used(system.S("PL-Stock-Link") == "Y" && system.I("Level-4") == 1));
        Line("売掛請求書番号", system.S("SL-Own-Nos") == "N" ? "自動採番" : "手入力");
        Number("次回請求書番号", "Next-Invoice", "00000000");
        Flag("督促状", "SL-Dunning");
        Flag("延滞料", "SL-Charges");
        Number("売掛支払期限（日）", "SL-Credit");
        Number("請求書入力レベル", "Invoicer");
        Number("標準与信限度額", "SL-Limit");
        Line("標準値引率", LedgerReports.Money(system.N("SL-Disc")) + "％");
        Number("消費税勘定", "Vat-Ac", "000000");
        Line("税登録番号の印刷", Used(system.S("SL-VAT-Printed") == "Y"));
        Number("延滞対象最低残高", "SL-Min");
        Number("延滞料上限", "SL-Max");
        Line("延滞料率", LedgerReports.Money(system.N("SL-Late-Per")) + "％");
        if (system.S("Extra-Type") is "C" or "D")
        {
            var label = system.S("Extra-Type") == "C" ? "追加料金" : "追加値引";
            Line(label + "の説明", system.St("Extra-Desc"));
            Line(label + "率", LedgerReports.Money(system.N("Extra-Rate")) + "％");
            Number(label + "勘定", "Extra-Charge-Ac", "000000");
        }
        Line("売掛住所区切り", system.St("SL-Delim"));
        Number("売掛次回バッチ番号", "First-Sl-Batch", "00000");
        Number("仮請求書保管期間", "PF-Retention");
        Line("売掛と在庫の連携", Used(system.S("SL-Stock-Link") == "Y" && system.I("Level-4") == 1));
        foreach (var (label, field) in new[] { ("納品書", "Pick"), ("請求書", "Inv"), ("取引明細書", "Stat"), ("督促状", "Lets") })
            Line(label + "の社名印刷", Used(system.S("SL-Comp-Head-" + field) == "Y"));
        Number("売掛入金勘定", "SL-Pay-Ac", "000000");
        Number("売上元帳勘定", "SL-Sales-Ac", "000000");
        Number("売掛金勘定", "S-Debtors", "000000");
        Flag("在庫デバッグ", "Stk-Debug");
        Flag("製造管理", "Stk-Manu-Used");
        Flag("在庫監査", "Stk-Audit-Used");
        Flag("在庫移動監査", "Stk-Mov-Audit");
        Line("在庫当期区分", PeriodName("Stk-Period-Cur"));
        Line("在庫累計区分", PeriodName("Stk-Period-dat"));
        Flag("在庫平均原価", "Stk-Averaging");
        Number("在庫監査番号", "Stk-Audit-No", "00000000");
        Flag("受注管理", "Stk-OE-Used");
        Line("給与計算", Used(false));
        Line("ファイル状態", string.Concat(Enumerable.Range(1, 32).Select(i => system.S($"File-Status-{i}"))));
        Page(1);
        Section("利用者設定", "総勘定元帳設定");
        Pair(Field("会社名"), Field("部門・拠点"));
        bool divisions = system.S("P-C") is "P" or "B";
        Pair(Field("住所1"), divisions ? Field("収益勘定のみに適用") : "");
        Pair(system.St("Address-2"), divisions ? Field("部門・拠点のグループ化") : "");
        Pair(system.St("Address-3"), Field("比較情報"));
        Pair(string.Join(',', system.St("Address-4"), system.St("Post-Code"), system.St("Country")), Field("二次索引"));
        Pair(Field("日付順"));
        Pair(Field("期首日"), Field("最小限の検証"));
        Pair(Field("期末日"), Field("締め処理時の仕訳保管"));
        Pair($"税率1　{Rate(1)}／{Rate(4)}　税登録番号　{system.St("VAT-Reg-Number")}", Field("売掛勘定番号の先頭桁"));
        Pair($"税率2　{Rate(2)}／{Rate(5)}", Field("買掛勘定番号の先頭桁"));
        Pair($"税率3　{Rate(3)}", Field("消費税の自動計算"));
        Pair(Field("四半期"), Field("周期区分"));
        Pair(Field("会計期間"), Field("次回バッチ番号"));
        Pair(Field("帳票の１ページあたりの行数"), Field("簡易記帳との連携"));
        Section("運用環境設定", "買掛元帳設定");
        Pair(Field("利用形態"), Field("買掛住所区切り"));
        Pair(Field("旧環境の区分") + "　" + Field("旧環境の入力方式"), Field("買掛次回バッチ番号"));
        Pair(system.S("Maps-Ser-xx") == "mp" && system.I("Maps-Ser-nn") == 9999 ? "公開版" : "商用版", Field("買掛次回伝票番号"));
        bool relational = system.I("File-System-Used") == 1;
        Pair((relational ? "リレーショナルデータベース" : "旧データファイル") +
            "・重複ファイル処理：" + Used(system.I("File-Duplicates-In-Use") == 1), Field("買掛支払勘定"));
        Pair($"簡易記帳のパス　{Environment.GetEnvironmentVariable("ACAS_IRS") ?? "未設定"}", Field("仕入元帳勘定"));
        Pair($"台帳のパス　{Environment.GetEnvironmentVariable("ACAS_LEDGERS") ?? "未設定"}", Field("買掛金勘定"));
        Pair(Field("共通の印刷先"), Field("買掛と在庫の連携"));
        Pair(Field("総勘定元帳の印刷先"));
        Pair(Field("買掛元帳の印刷先"));
        Section("請求書設定", "売掛元帳設定");
        string extra = system.S("Extra-Type") == "C" ? "追加料金" : "追加値引";
        Pair(Field("次回請求書番号"), Field("売掛請求書番号"));
        Pair(Field(extra + "の説明"), Field("督促状"));
        Pair(Field(extra + "率"), Field("延滞料"));
        Pair(Field("請求書入力レベル"), Field("売掛支払期限（日）"));
        Pair(Field(extra + "勘定"), Field("標準与信限度額"));
        Pair(Field("消費税勘定"), Field("標準値引率"));
        Pair(Field("税登録番号の印刷"), Field("延滞対象最低残高"));
        Pair("", Field("延滞料上限"));
        Pair("", Field("延滞料率"));
        Pair("", Field("売掛住所区切り"));
        Pair(Field("仮請求書保管期間"), Field("売掛次回バッチ番号"));
        Pair(Field("納品書の社名印刷"), Field("売掛と在庫の連携"));
        Pair(Field("請求書の社名印刷"), Field("売掛入金勘定"));
        Pair(Field("取引明細書の社名印刷"), Field("売上元帳勘定"));
        Pair(Field("督促状の社名印刷"), Field("売掛金勘定"));
        output.Append('\f');
        Page(2);
        Section("在庫管理設定", "受注管理設定");
        Pair(Field("在庫デバッグ"), Field("受注管理"));
        foreach (var key in new[] { "製造管理", "在庫監査", "在庫移動監査", "在庫当期区分", "在庫累計区分", "在庫平均原価", "在庫監査番号" })
            Pair(Field(key));
        Section("給与設定", "データベース設定");
        Pair(Field("給与計算"), relational ? "スキーマ　" + system.St("RDBMS-DB-Name") : "");
        if (relational)
        {
            Pair("", "利用者名　" + system.St("RDBMS-User"));
            Pair("", "パスワード　非表示");
        }
        Section("システム状態", "");
        Pair(Field("ファイル状態"));
        Pair("");
        Pair("システム設定帳票 終わり");
        string body = output.ToString();
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
