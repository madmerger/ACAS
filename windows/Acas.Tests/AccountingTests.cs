using Acas.Core;
using Acas.Core.Engine;

namespace Acas.Tests;

public class AccountingTests
{
    private static readonly DateTime Start = new(2025, 4, 1);
    private static readonly CompanySetup Company = new("Example", "ABCD", true, true, true, true, true, true);
    private static readonly CompanyParameters Parameters = new("Example", Start, Start.AddYears(1).AddDays(-1),
        1, 3, 48, 1, false);

    [Fact]
    public void 元帳設定は部門区分に応じて収益勘定の制限と仕訳保管を保存する()
    {
        using var db = new Db();
        var settings = new SystemSettings(db);
        Assert.Null(settings.ReadGeneralLedgerParameters());
        Assert.True(settings.Initialize(Company, Start));
        var original = settings.ReadGeneralLedgerParameters()!;
        Assert.True(settings.SaveGeneralLedgerParameters(original with
            { Division = "B", RevenueOnly = true, Archive = true, NextBatch = 31 }));
        Assert.Equal("R", settings.Read()!.S("P-C-Level"));
        Assert.Equal("Y", settings.Read()!.S("Arch"));
        Assert.Equal(31, settings.ReadGeneralLedgerParameters()!.NextBatch);
        Assert.True(settings.SaveGeneralLedgerParameters(original with { Division = " ", RevenueOnly = true }));
        Assert.Equal(" ", settings.Read()!.S("P-C-Level"));
        Assert.Equal(" ", settings.Read()!.S("Arch"));
    }

    [Fact]
    public void 設定帳票は保存した会社情報と印刷先を表示し暗証文字を含まない()
    {
        using var db = new Db();
        var settings = new SystemSettings(db);
        Assert.True(settings.Initialize(Company, Start));
        Assert.True(settings.SaveParameters(Parameters with { Contact = new("Address", "", "", "", "1234567", "Country", "123") }));
        Assert.True(settings.SaveOperatingParameters(new(1, 6, 1, "Primary", "Ledger", "")));
        Assert.Equal("Primary", settings.ReadOperatingParameters()!.Queue3);
        var body = settings.PrintSettings();
        Assert.NotNull(body);
        Assert.Contains("住所1　Address", body);
        Assert.Contains("共通の印刷先　Primary", body);
        Assert.Contains("総勘定元帳の印刷先　Ledger", body);
        Assert.DoesNotContain("ABCD", body);
        Assert.DoesNotContain(settings.Read()!.S("Pass-Word"), body);
        Assert.Equal(body, Assert.Single(db.Spool()).Body);
    }

    [Fact]
    public void 初期設定は四つの固定長レコードを作成して上書きしない()
    {
        using var db = new Db();
        var settings = new SystemSettings(db);

        Assert.True(settings.Initialize(Company, Start));
        Assert.False(settings.Initialize(Company with { Name = "Other" }, Start.AddDays(1)));

        var records = db.Scan(SystemSettings.SystemFile);
        Assert.Equal(new[] { "00000001", "00000002", "00000003", "00000004" }, records.Select(r => r.Key));
        Assert.All(records, r => Assert.Equal(1024, r.Data.Length));
        var system = settings.Read()!;
        Assert.Equal("Example", system.St("Usera"));
        Assert.Equal(Start, SystemSettings.Date(system, "Run-Date"));
        Assert.False(settings.SetRunDate(Start.AddDays(1)));
    }

    [Theory]
    [InlineData(6, 6, true, "Y")]
    [InlineData(13, 13, false, "N")]
    [InlineData(99, 3, true, "Y")]
    public void 会計周期と在庫連携を設定する(int inputPeriod, int savedPeriod, bool stock, string stockLink)
    {
        using var db = new Db();
        var settings = new SystemSettings(db);
        Assert.True(settings.Initialize(Company with { Stock = stock }, Start));
        var before = settings.Read()!.B;
        Assert.False(settings.SaveParameters(Parameters with { PageLines = 28 }));
        Assert.Equal(before, settings.Read()!.B);

        Assert.True(settings.SaveParameters(Parameters with { Period = inputPeriod, PageLines = 29, SalesStockLink = true }));
        Assert.True(settings.SetRunDate(Start.AddDays(1)));
        var system = settings.Read()!;
        Assert.Equal(29, system.I("Page-Lines"));
        Assert.Equal(savedPeriod, system.I("Period"));
        Assert.Equal(stockLink, system.S("SL-Stock-Link"));
        Assert.Equal(Start, SystemSettings.Date(system, "Start-Date"));
        Assert.Equal(Start.AddDays(1), SystemSettings.Date(system, "Run-Date"));
    }

    [Fact]
    public void 勘定科目と既定勘定を固定長レコードで更新する()
    {
        using var db = new Db();
        var settings = new SystemSettings(db);
        Assert.True(settings.Initialize(Company, Start));
        var ledger = new GeneralLedger(db);
        var system = settings.Read()!;
        var header = new Account(new(3000, 0), "Header", 0, 'A', 1);
        var account = new Account(new(3100, 0), "Account", 1, ' ', 2);

        Assert.Equal(AccountError.MissingHeader, ledger.Register(system, account));
        Assert.Equal(AccountError.TradeCode, ledger.Register(system, header with { Code = new(1000, 0) }));
        Assert.Equal(AccountError.ReservedCode, ledger.Register(system, header with { Code = new(9999, 0) }));
        Assert.Equal(AccountError.None, ledger.Register(system, header));
        Assert.Equal(AccountError.None, ledger.Register(system, account));
        Assert.Equal(AccountError.Duplicate, ledger.Register(system, account));

        var amended = account with { Name = "Amended" };
        Assert.Equal(AccountError.None, ledger.Amend(system, amended));
        Assert.Equal(amended, ledger.Find(account.Code));
        var defaults = new DefaultAccount(1, 3100m, "01", "I");
        Assert.True(settings.AmendDefault(defaults));
        Assert.Equal(defaults, settings.DefaultAccounts()[0]);

        var stored = Layouts.Ledger.From(db.Read(GeneralLedger.LedgerFile, account.Code.Key)!);
        stored.SetN("balance", 1);
        Assert.True(db.Rewrite(GeneralLedger.LedgerFile, account.Code.Key, stored.B));
        Assert.Equal(AccountError.NonzeroBalance, ledger.Delete(account.Code));
        Assert.Equal(AccountError.None, ledger.Delete(header.Code));
        Assert.Null(ledger.Find(header.Code));
    }
}
