using System.Text;

namespace Acas.Core.Engine;

/// <summary>プログラム終了 (STOP RUN) を表す。</summary>
public sealed class StopRun : Exception { public bool KeepScreen; }
/// <summary>レガシーのランタイム異常終了 (画面はそのまま残る)。</summary>
public sealed class Halt : Exception { public Halt(string why) : base(why) { } }

/// <summary>実行コンテキスト: 画面、ローカルDB、日時、帳票スプール。</summary>
public sealed class Ctx
{
    public readonly Crt Crt = new();
    public readonly Db Db;
    public Func<DateTime> Now = () => DateTime.Now;
    public Func<int, Task> Sleep = _ => Task.CompletedTask;
    public const string L = "ledgers/acas/", I = "ledgers/irs/";
    public Rec Sys = Layouts.System.New();
    public bool BackupNoise;
    public readonly List<(string Name, List<string> Lines)> Reports = new(), EnglishReports = new();

    public Ctx(Db db) { Db = db; }

    public const string SysFile = L + "system.dat";
    public bool LoadSys()
    {
        var b = Db.Read(SysFile, "00000001");
        if (b == null) return false;
        Sys = Layouts.System.From(b);
        return true;
    }
    public void SaveSys() => Db.Put(SysFile, "00000001", Sys.B);

    /// <summary>帳票を開く。Close でスプール(DB)へ保存する。</summary>
    public Report OpenReport(string name = "prt-1") => new(this, name);

    // 日付 (maps04 相当)
    public string Today() => Now().ToString("dd/MM/yyyy");
    public string Time() => Now().ToString("HH:mm:ss");
}

public sealed class Report
{
    private readonly Ctx _c; public readonly string Name;
    public readonly List<string> Lines = new(), English = new();
    public Report(Ctx c, string name) { _c = c; Name = name; }
    /// <summary>1行出力。parts は (文字列, 固定文言か) の並び。固定文言は日本語へ翻訳し桁位置を保つ。</summary>
    public void Write(params object[] parts)
    {
        var en = new StringBuilder(); var ja = new StringBuilder();
        foreach (var p in parts)
        {
            if (p is Lit l) { en.Append(l.Text); var t = I18n.T(l.Text); if (t == null && I18n.NeedsTranslation(l.Text)) _c.Crt.Untranslated.Add(l.Text); ja.Append(I18n.Fit(t ?? l.Text, l.Text.Length)); }
            else { en.Append(p); ja.Append(p); }
        }
        English.Add(en.ToString().TrimEnd()); Lines.Add(ja.ToString().TrimEnd());
    }
    private bool _first = true;
    /// <summary>WRITE ... AFTER n: n 回改行してから 1 行出力する。</summary>
    public void After(int n, params object[] parts)
    {
        for (int i = _first ? 0 : 1; i < n; i++) { English.Add(""); Lines.Add(""); }
        _first = false;
        Write(parts);
    }
    public void Page() { English.Add("\f"); Lines.Add("\f"); }
    public void Close()
    {
        _c.EnglishReports.Add((Name, English));
        _c.Reports.Add((Name, Lines));
        _c.Db.AddSpool(Name, string.Join("\n", Lines) + "\n");
    }
}

/// <summary>帳票上の固定文言 (翻訳対象)。</summary>
public sealed record Lit(string Text);
