using System.Text;

namespace Acas.Core.Engine;

public enum Lang { En, Ja }

public enum K { Char, Enter, Esc, Tab, BackTab, Up, Down, Left, Right, Home, End, Backspace, Delete, PgUp, PgDn, F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12 }

public readonly record struct Key(K Kind, char Ch = '\0')
{
    public static Key Of(char c) => c switch
    {
        '\r' or '\n' => new Key(K.Enter),
        '\t' => new Key(K.Tab),
        '\x1b' => new Key(K.Esc),
        '\b' or '\x7f' => new Key(K.Backspace),
        _ => new Key(K.Char, c)
    };
}

/// <summary>キー入力待ち行列。プログラムは Read を await し、UI/テストが Post する。</summary>
public sealed class KeyQueue
{
    private readonly Queue<Key> _q = new();
    private TaskCompletionSource<Key>? _waiter;
    public bool Waiting => _waiter != null;
    public event Action? Idle;

    public Task<Key> Read()
    {
        if (_q.Count > 0) return Task.FromResult(_q.Dequeue());
        _waiter = new TaskCompletionSource<Key>();
        Idle?.Invoke();
        return _waiter.Task;
    }

    public void Post(Key k)
    {
        var w = _waiter;
        if (w != null) { _waiter = null; w.SetResult(k); }
        else _q.Enqueue(k);
    }
}

/// <summary>
/// レガシー 80x24 画面と同じ座標系を持つ画面モデル。
/// Visible は日本語(表示用)、Shadow はレガシー原文(同一性比較用)。
/// </summary>
public sealed class Crt
{
    public const int Rows = 24, Cols = 80;
    public readonly char[] Shadow = new char[Rows * Cols];
    public readonly char[] Visible = new char[Rows * Cols];   // '\0' = 全角文字の右半分
    public readonly byte[] Color = new byte[Rows * Cols];
    public int CurRow = 1, CurCol = 1;
    public bool CursorOn;
    public int FieldRow, FieldCol, FieldLen;                  // 入力中フィールド(強調表示用)
    public int Status;                                        // COB-CRT-STATUS 相当
    public Lang Lang = Lang.Ja;
    public readonly KeyQueue Keys = new();
    public event Action? Changed;
    public readonly SortedSet<string> Untranslated = new();
    public Action? Beep;

    public Crt() { Clear(); }

    public void Clear()
    {
        Array.Fill(Shadow, ' '); Array.Fill(Visible, ' '); Array.Fill(Color, (byte)7);
        Changed?.Invoke();
    }

    private static int Idx(int row, int col) => (row - 1) * Cols + (col - 1);

    public void EraseEos(int row, int col)
    {
        for (int i = Idx(row, col); i < Rows * Cols; i++) { Shadow[i] = ' '; Visible[i] = ' '; Color[i] = 7; }
    }

    public void EraseEol(int row, int col)
    {
        for (int i = Idx(row, col); i < row * Cols; i++) { Shadow[i] = ' '; Visible[i] = ' '; Color[i] = 7; }
    }

    private void Put(char[] buf, int row, int col, string s, int fg, bool wide)
    {
        int i = Idx(row, col), end = Rows * Cols;
        foreach (var ch in s)
        {
            if (i >= end) break;
            if (buf[i] == '\0' && i > 0) buf[i - 1] = ' ';
            buf[i] = ch; if (ReferenceEquals(buf, Visible)) Color[i] = (byte)fg;
            i++;
            if (wide && I18n.IsWide(ch) && i < end) { buf[i] = '\0'; Color[i] = (byte)fg; i++; }
        }
        if (i < end && buf[i] == '\0') buf[i] = ' ';
    }

    /// <summary>固定文言の表示 (DISPLAY literal AT llcc)。日本語モードでは対応表で翻訳する。</summary>
    public void D(string text, int pos, bool eos = false, bool eol = false, int fg = 2)
    {
        int row = pos / 100, col = pos % 100;
        if (pos > 9999) { row = pos / 1000; col = pos % 1000; }
        if (eos) EraseEos(row, col);
        if (eol) EraseEol(row, col);
        Put(Shadow, row, col, text, fg, false);
        string vis = text;
        if (Lang == Lang.Ja && text.Trim().Length > 0)
        {
            var t = I18n.T(text);
            if (t == null) { if (I18n.NeedsTranslation(text)) Untranslated.Add(text); }
            else vis = I18n.Fit(t, text.Length);
        }
        Put(Visible, row, col, vis, fg, true);
        Changed?.Invoke();
    }

    /// <summary>データ値の表示 (翻訳しない)。</summary>
    public void V(string text, int pos, bool eos = false, bool eol = false, int fg = 3)
    {
        int row = pos / 100, col = pos % 100;
        if (pos > 9999) { row = pos / 1000; col = pos % 1000; }
        if (eos) EraseEos(row, col);
        if (eol) EraseEol(row, col);
        Put(Shadow, row, col, text, fg, false);
        Put(Visible, row, col, text, fg, true);
        Changed?.Invoke();
    }

    public void Erase(int pos, bool eos = false, bool eol = true)
    {
        int row = pos / 100, col = pos % 100;
        if (eos) EraseEos(row, col); else EraseEol(row, col);
        Changed?.Invoke();
    }

    /// <summary>
    /// ACCEPT field AT llcc。GnuCOBOL の項目入力(上書き、Enter/Esc/ファンクションキー終了、AUTO)を再現する。
    /// update=false の場合は空白で開始する。
    /// </summary>
    public async Task<string> A(int pos, int len, string? init = null, bool auto = false, bool secure = false, bool upper = false, bool numeric = false)
    {
        int row = pos / 100, col = pos % 100;
        var buf = (init ?? "").PadRight(len).Substring(0, len).ToCharArray();
        if (len > Cols - col + 1) len = Cols - col + 1;
        int cur = 0;
        void Show()
        {
            var s = secure ? new string('*', len).Substring(0, len) : new string(buf, 0, len);
            if (secure) s = new string(buf, 0, len).TrimEnd().Length == 0 ? new string(' ', len) : new string('*', new string(buf, 0, len).TrimEnd().Length).PadRight(len);
            Put(Shadow, row, col, s, 6, false); Put(Visible, row, col, s, 6, false);
            CurRow = row; CurCol = col + Math.Min(cur, len - 1); CursorOn = true;
            FieldRow = row; FieldCol = col; FieldLen = len;
            Changed?.Invoke();
        }
        Show();
        while (true)
        {
            var k = await Keys.Read();
            switch (k.Kind)
            {
                case K.Char:
                    {
                        char ch = upper ? char.ToUpperInvariant(k.Ch) : k.Ch;
                        if (ch < ' ' || ch > '~') { Beep?.Invoke(); break; }
                        if (numeric && !(char.IsDigit(ch) || ch is '.' or '-' or '+' or ' ' or ',')) { Beep?.Invoke(); break; }
                        if (cur >= len) cur = len - 1;
                        buf[cur] = ch;
                        if (cur < len - 1) cur++;
                        else if (auto) { Show(); Status = 0; goto done; }
                        Show();
                        break;
                    }
                case K.Backspace:
                    if (cur > 0)
                    {
                        cur--;
                        for (int i = cur; i < len - 1; i++) buf[i] = buf[i + 1];
                        buf[len - 1] = ' ';
                        Show();
                    }
                    break;
                case K.Delete:
                    for (int i = cur; i < len - 1; i++) buf[i] = buf[i + 1];
                    buf[len - 1] = ' ';
                    Show();
                    break;
                case K.Left: if (cur > 0) cur--; Show(); break;
                case K.Right: if (cur < len - 1) cur++; Show(); break;
                case K.Home: cur = 0; Show(); break;
                case K.End: cur = Math.Max(0, new string(buf, 0, len).TrimEnd().Length - 1); Show(); break;
                case K.Enter: Status = 0; goto done;
                case K.Esc: Status = 2005; goto done;
                case K.Tab: Status = 2007; goto done;
                case K.BackTab: Status = 2008; goto done;
                case K.Up: Status = 2003; goto done;
                case K.Down: Status = 2004; goto done;
                case K.PgUp: Status = 2001; goto done;
                case K.PgDn: Status = 2002; goto done;
                default:
                    if (k.Kind >= K.F1 && k.Kind <= K.F12) { Status = 1001 + (k.Kind - K.F1); goto done; }
                    break;
            }
        }
    done:
        CursorOn = false; FieldLen = 0;
        Changed?.Invoke();
        return new string(buf, 0, len);
    }

    /// <summary>数値項目の ACCEPT (UPDATE)。現在値をゼロ詰めで表示し、入力結果を数値化して返す。</summary>
    public async Task<decimal> AN(int pos, int digits, decimal cur = 0, bool update = true, bool auto = false)
    {
        var s = await A(pos, digits, update ? Cob.P9(cur, digits) : null, auto: auto);
        return Cob.Trunc(Cob.ToNum(s), 0) % (decimal)Math.Pow(10, digits);
    }

    public string[] ShadowLines()
    {
        var r = new string[Rows];
        for (int i = 0; i < Rows; i++) r[i] = new string(Shadow, i * Cols, Cols);
        return r;
    }

    public string[] VisibleLines()
    {
        var r = new string[Rows];
        for (int i = 0; i < Rows; i++)
        {
            var sb = new StringBuilder();
            for (int c = 0; c < Cols; c++) { var ch = Visible[i * Cols + c]; if (ch != ' ') sb.Append(ch); }
            r[i] = sb.ToString();
        }
        return r;
    }
}
