using System.Text.RegularExpressions;
namespace Acas.Core.Engine;

/// <summary>
/// COBOL SCREEN SECTION の画面定義 (固定文言 + 項目)。DISPLAY screen / ACCEPT screen を再現する。
/// 項目値は Rec (レコード項目名) または vars (作業項目) に束縛する。
/// </summary>
public sealed class Scr
{
    public sealed record Item(int Row, int Col, string? Lit, string Name, string Pic, bool Input);
    public readonly List<Item> Items = new();

    public Scr L(int row, int col, string lit) { Items.Add(new Item(row, col, lit, "", "", false)); return this; }
    public Scr F(int row, int col, string name, string pic, bool input = true) { Items.Add(new Item(row, col, null, name, pic, input)); return this; }

    private static (int len, int dec, bool num) Pic(string pic, Rec r, string name)
    {
        if (pic.Length == 0) return (r.L.F.TryGetValue(name, out var f) ? f.Len : 1, 0, false);
        string p = Regex.Replace(pic.ToLowerInvariant(), @"(.)\((\d+)\)", m => new string(m.Groups[1].Value[0], int.Parse(m.Groups[2].Value)));
        int dot = p.IndexOf('.');
        return (p.Length, dot < 0 ? 0 : p.Length - dot - 1, p[0] == '9');
    }

    private static string Get(Item it, Rec r, Dictionary<string, string> vars)
    {
        var (len, dec, num) = Pic(it.Pic, r, it.Name);
        if (vars.TryGetValue(it.Name, out var v)) return v.PadRight(len).Substring(0, len);
        if (!r.L.F.ContainsKey(it.Name)) return new string(' ', len);
        if (!num) return r.S(it.Name).Replace('\0', ' ').PadRight(len).Substring(0, len);
        decimal n = Math.Abs(r.N(it.Name));
        if (dec == 0) return Cob.P9(n, len);
        return Cob.P9(decimal.Truncate(n), len - dec - 1) + "." + Cob.P9(decimal.Truncate((n - decimal.Truncate(n)) * (decimal)Math.Pow(10, dec)), dec);
    }

    private static void Set(Item it, Rec r, Dictionary<string, string> vars, string s)
    {
        var (_, dec, num) = Pic(it.Pic, r, it.Name);
        if (vars.ContainsKey(it.Name)) { vars[it.Name] = s; return; }
        if (!r.L.F.ContainsKey(it.Name)) return;
        if (num) r.SetN(it.Name, Cob.Trunc(Cob.ToNum(s), dec)); else r.Set(it.Name, s);
    }

    /// <summary>DISPLAY screen-name。入力項目の空白は GnuCOBOL と同じくプロンプト文字 '_' で表示される。</summary>
    public void Display(Crt t, Rec r, Dictionary<string, string> vars)
    {
        foreach (var it in Items)
        {
            int pos = it.Row * 100 + it.Col;
            if (it.Lit != null) t.D(it.Lit, pos);
            else { var s = Get(it, r, vars); t.V(it.Input ? s.Replace(' ', '_') : s, pos, fg: 2); }
        }
    }

    /// <summary>ACCEPT screen-name WITH UPDATE。全項目を再表示し、Tab で項目移動、Enter/Esc で終了。</summary>
    public async Task Accept(Crt t, Rec r, Dictionary<string, string> vars)
    {
        Display(t, r, vars);
        var ins = Items.Where(i => i.Input).ToList();
        var fields = ins.Select(i => (i.Row * 100 + i.Col, Get(i, r, vars), Pic(i.Pic, r, i.Name).num)).ToList();
        var res = await t.Form(fields);
        for (int i = 0; i < ins.Count; i++) Set(ins[i], r, vars, res[i]);
    }
}
