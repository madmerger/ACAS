using System.Globalization;
using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>共通サブルーチン (maps04 日付変換ほか) と画面ヘッダ部品。</summary>
public static class Common
{
    /// <summary>maps04: dd/mm/yyyy → 通算日。不正なら 0。区切り . , - は / とみなす。</summary>
    public static int Maps04(string date)
    {
        var a = date.PadRight(10).Substring(0, 10).Replace('.', '/').Replace(',', '/').Replace('-', '/');
        if (a.Count(ch => ch == '/') != 2) return 0;
        string dd = a.Substring(0, 2), mm = a.Substring(3, 2), cc = a.Substring(6, 2), yy = a.Substring(8, 2);
        if (!IsNum(dd) || !IsNum(mm) || !IsNum(cc)) return 0;
        int d = int.Parse(dd), m = int.Parse(mm);
        if (d < 1 || d > 31 || m < 1 || m > 12 || !IsNum(yy.Replace(' ', '0'))) return 0;
        // 年下 2 桁の空白は (文字コード - '0') = -16 として桁計算される (レガシー実測 CALC-259: "01/01/24  " → 2224 年)
        int y = int.Parse(cc) * 100 + (yy[0] - '0') * 10 + (yy[1] - '0');
        if (y < 1601 || d > DateTime.DaysInMonth(y, m)) return 0;
        return Launcher.DateToBin(new DateTime(y, m, d));
    }
    public static bool IsNum(string s) => s.Length > 0 && s.All(ch => ch >= '0' && ch <= '9');

    /// <summary>UK 形式 (dd/mm/yyyy) ⇔ システム日付書式の相互変換。</summary>
    public static string ToForm(Ctx c, string uk)
    {
        int f = c.Sys.I("Date-Form");
        if (f == 2) return uk.Substring(3, 2) + "/" + uk.Substring(0, 2) + uk.Substring(5);
        if (f == 3) return uk.Substring(6, 4) + "/" + uk.Substring(3, 2) + "/" + uk.Substring(0, 2);
        return uk;
    }
    public static string FromForm(Ctx c, string s)
    {
        s = s.PadRight(10);
        int f = c.Sys.I("Date-Form");
        if (f == 2) return s.Substring(3, 2) + "/" + s.Substring(0, 2) + s.Substring(5);
        if (f == 3) return s.Substring(8, 2) + "/" + s.Substring(5, 2) + "/" + s.Substring(0, 4);
        return s;
    }

    /// <summary>メニュー画面共通ヘッダ (社名・日付・プログラム名・タイトル・時刻・著作権行)。</summary>
    public static void MenuHead(Ctx c, string toDay, string prog, string title, int titlePos)
    {
        var t = c.Crt;
        t.D(" ", 0101, eos: true);
        t.V(c.Sys.S("Maps-Ser-xx"), 2474);
        t.V(Cob.P9(c.Sys.N("Maps-Ser-nn"), 4), 2476);
        t.D("Copyright (c) 1976-", 2401, fg: 3);
        t.V(c.Now().ToString("yyyy"), 2420);
        t.D(" Applewood Computers", 2424, fg: 3);
        t.V(c.Sys.S("Usera"), 0101);
        t.V(ToForm(c, toDay), 0171);
        t.V(prog, 0301, fg: 2);
        t.D(title, titlePos);
        t.D("at ", 0355); t.V(c.Time(), 0358, fg: 2);
        t.D("on ", 0367);
        var n = c.Now();
        t.V(ToForm(c, n.ToString("dd/MM/yyyy")).Substring(0, 6) + n.ToString("yy"), 0370, fg: 2);
    }

    /// <summary>プログラム共通ヘッダ: "Client -" 形式 (gl000 等)。</summary>
    public static void ClientHead(Ctx c, string prog, string title, int titlePos, int timePos = 0370)
    {
        var t = c.Crt;
        t.D("Client -", 0101, eos: true);
        t.V(c.Sys.S("Usera"), 0110);
        t.V(prog, 0301, fg: 2);
        t.D(title, titlePos);
        t.V(c.Sys.S("Maps-Ser-xx"), 2474, fg: 2);
        t.V(Cob.P9(c.Sys.N("Maps-Ser-nn"), 4), 2476, fg: 2);
        t.D("at ", timePos); t.V(c.Time(), timePos + 3, fg: 2);
    }

    /// <summary>xx000 Start of Day: 処理日入力。toDay(UK) を更新し Run-Date を設定する。</summary>
    public static async Task<string> StartOfDay(Ctx c, string prog, string title, int titlePos, string errMsg)
    {
        var t = c.Crt;
        string u = c.Now().ToString("dd/MM/yyyy");
        ClientHead(c, prog, title, titlePos);
        while (true)
        {
            int f = c.Sys.I("Date-Form");
            if (f < 1 || f > 3) { c.Sys.SetN("Date-Form", 1); f = 1; }
            u = ToForm(c, u);
            t.D(f == 1 ? "Enter todays date as dd/mm/yyyy - [          ]" : f == 2 ? "Enter todays date as mm/dd/yyyy - [          ]" : "Enter todays date as yyyy/mm/dd - [          ]", 0812);
            t.V(u, 0847);
            u = FromForm(c, await t.A(0847, 10, init: u));
            int bin = Maps04(u);
            if (bin == 0) { t.D(errMsg, 0860, fg: 4); continue; }
            t.D(" ", 0860, eol: true);
            c.Sys.SetN("Run-Date", bin);
            return u;
        }
    }
}
