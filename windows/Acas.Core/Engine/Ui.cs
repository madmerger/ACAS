namespace Acas.Core.Engine;

/// <summary>画面 1 行分のレイアウト文字列を、2 桁以上の空白で区切られた文言単位に分けて表示する補助。
/// 括弧 [ ] { } の内側の空白では区切らない (入力欄の桁位置を保つため)。</summary>
public static class Ui
{
    public static void Paint(this Crt t, int row, string line, int fg = 2)
    {
        int i = 0, n = line.Length;
        while (i < n)
        {
            if (line[i] == ' ') { i++; continue; }
            int start = i, depth = 0, end = i;
            while (i < n)
            {
                char ch = line[i];
                if (ch is '[' or '{') depth++;
                else if (ch is ']' or '}') depth = Math.Max(0, depth - 1);
                if (ch != ' ') end = i;
                else if (depth == 0 && i + 1 < n && line[i + 1] == ' ') break;
                i++;
            }
            t.D(line.Substring(start, end - start + 1), row * 100 + start + 1, fg: fg);
        }
    }

    /// <summary>複数行をまとめて表示する。各要素は (行番号, 行レイアウト)。</summary>
    public static void Paint(this Crt t, params (int Row, string Line)[] lines)
    {
        foreach (var (r, l) in lines) t.Paint(r, l);
    }

    /// <summary>レガシー実測: 呼出先がファイルオープン等で異常終了したときに 23 行目へ出るエラー表示。</summary>
    public static async Task TError(Ctx c, string code, int pad = 0)
    {
        var t = c.Crt;
        t.D(code + " Error not in error.txt. Hit return to close", 2301, fg: 4);
        if (pad > 0) { t.V(new string(' ', pad - 49), 2350); t.V(" ", 2479); }
        await t.A(2380, 1);
        throw new StopRun { KeepScreen = true };
    }
}
