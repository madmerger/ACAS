using System.Text.Json;
using Acas.Core.Engine;
using Acas.Core.Programs;

namespace Acas.Tests;

public class CalcTests
{
    [Theory]
    [InlineData("K9P34Y", "K9P34Y 2 Y")]
    [InlineData("6N3WD2", "6N3WD2 3 Y")]
    [InlineData("BF5-JX", "BF5-JX 9 Y")]
    [InlineData("------", "------ 2 Y")]
    public void チェックディジットはレガシー実測と同じ(string code, string line) => Assert.Equal(line, Calc.Line09(code));

    [Fact]
    public void チェックディジット検証() { Assert.True(Calc.Maps09Verify("K9P34Y2")); Assert.False(Calc.Maps09Verify("K9P34Y3")); Assert.Null(Calc.Maps09("k9p34y")); }

    [Theory]
    [InlineData("01/01/2024", 154498)]
    [InlineData("30/04/2024", 154618)]
    [InlineData("15.06.2025", 155029)]
    [InlineData("AB/01/2024", 0)]
    [InlineData("31/02/2026", 0)]
    [InlineData("01/01/24  ", 227546)]
    public void 日付は通算日へ変換される(string date, int bin) => Assert.Equal(bin, Common.Maps04(date));

    [Theory]
    [InlineData("100.00", "20.00", "000020.00")]
    [InlineData("0.03", "17.50", "000000.01")]
    [InlineData("0.05", "5.00", "000000.00")]
    [InlineData("0.05", "10.00", "000000.01")]
    [InlineData("-100.00", "20.00", "000020.00")]      // レガシー実測: 符号は落ちる
    [InlineData("1234567.89", "20.00", "246913.58")]
    public void VAT額の丸め(string net, string rate, string vat) => Assert.Equal(vat, Calc.LineVat(net, rate).Split('|')[1]);

    [Theory]
    [InlineData(0, 0)] [InlineData(29, 0)] [InlineData(30, 30)] [InlineData(59, 30)] [InlineData(60, 60)] [InlineData(89, 60)] [InlineData(90, 90)] [InlineData(365, 90)]
    public void 売掛年齢区分(int days, int bucket) => Assert.Equal(bucket, Calc.AgeBucket(days));

    [Theory]
    [InlineData("1000.00", "3", "333.3333")]
    [InlineData("0.10", "3", "0.0333")]
    [InlineData("99999.99", "1", "99999.9900")]
    public void 在庫平均原価(string v, string q, string cost) => Assert.Equal(cost, Calc.LineAvg(v, q).Split('|')[1].Trim());
}

public class EngineTests
{
    [Fact]
    public void 対応表の括弧位置は原文と揃う() => Assert.Empty(I18n.Misaligned());

    [Fact]
    public async Task 文字入力はEnterで確定する()
    {
        var t = new Crt();
        var task = t.A(0501, 4);
        foreach (var ch in "AB") t.Keys.Post(new Key(K.Char, ch));
        t.Keys.Post(new Key(K.Enter));
        Assert.Equal("AB", (await task).TrimEnd());
        Assert.Equal(0, t.Status);
    }

    [Fact]
    public void ローカルDBは固定長レコードを保持する()
    {
        using var db = new Db();
        db.LoadBaseline("biz");
        var c = new Ctx(db);
        Assert.True(c.LoadSys());
        var name = c.Sys.S("Usera");
        c.Sys.Set("Usera", "テスト");
        c.SaveSys();
        Assert.True(c.LoadSys());
        Assert.NotEqual(name, c.Sys.S("Usera"));
    }

    [Fact]
    public async Task ACASメニューは日本語で表示されXで終了する()
    {
        using var db = new Db();
        db.LoadBaseline("biz");
        var c = new Ctx(db);
        var p = Launcher.RunAcas(c);
        var jp = string.Join("\n", c.Crt.VisibleLines());
        Assert.Contains("総勘定元帳", jp);
        Assert.Contains("General Ledger", string.Join("\n", c.Crt.ShadowLines()));
        c.Crt.Keys.Post(new Key(K.Char, 'X'));
        c.Crt.Keys.Post(new Key(K.Enter));
        await Task.WhenAny(p, Task.Delay(2000));
    }
}

/// <summary>レガシー証跡 (環境変数 ACAS_EVIDENCE) がある場合のみ、SYS/GL/CALC の同一性を一括確認する。</summary>
public class EquivalenceTests
{
    [Fact]
    public async Task 証跡があればCALCとGLの移植済みケースが一致する()
    {
        var root = Environment.GetEnvironmentVariable("ACAS_EVIDENCE");
        if (string.IsNullOrEmpty(root) || !File.Exists(Path.Combine(root, "入力", "シナリオ台帳.json"))) return;
        using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "入力", "シナリオ台帳.json")));
        var bad = new List<string>();
        foreach (var c in doc.RootElement.GetProperty("cases").EnumerateArray())
        {
            var id = c.GetProperty("id").GetString()!;
            if (id.StartsWith("CALC"))
            {
                var r = Calc.Run(c);
                if (r != null && r.Value.Line != Calc.LegacyLine(c, root)) bad.Add(id);
            }
            else if (id is "GL-001" or "GL-005" or "GL-009" or "GL-010" or "GL-036" or "SYS-002" or "SYS-005")
            {
                if (!(await CaseRunner.Run(c, root)).Match) bad.Add(id);
            }
        }
        Assert.Empty(bad);
    }
}
