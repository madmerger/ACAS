using System.Text;

namespace Acas.Core.Engine;

public enum FK { X, N9, C3, Comp, BChar, BShort, BLong }

public readonly record struct Fld(int Off, int Len, FK Kind, int Digits, int Dec, bool Signed);

/// <summary>レガシー copybook と同じバイト配置のレコード定義。</summary>
public sealed class Layout
{
    public readonly Dictionary<string, Fld> F = new(StringComparer.OrdinalIgnoreCase);
    public int Size { get; private set; }

    private Layout Add(string name, int len, FK kind, int digits = 0, int dec = 0, bool signed = false)
    {
        if (name.Length > 0) F[name] = new Fld(Size, len, kind, digits, dec, signed);
        Size += len;
        return this;
    }
    public Layout X(string name, int len) => Add(name, len, FK.X);
    public Layout Fill(int len) => Add("", len, FK.X);
    public Layout N9(string name, int digits, int dec = 0, bool signed = false) => Add(name, digits + dec, FK.N9, digits + dec, dec, signed);
    public Layout C3(string name, int digits, int dec = 0, bool signed = true) => Add(name, (digits + dec) / 2 + 1, FK.C3, digits + dec, dec, signed);
    public Layout Comp(string name, int digits, int dec = 0, bool signed = false)
    { int t = digits + dec; return Add(name, t <= 4 ? 2 : t <= 9 ? 4 : 8, FK.Comp, t, dec, signed); }
    public Layout BChar(string name, bool signed = true) => Add(name, 1, FK.BChar, 3, 0, signed);
    public Layout BShort(string name, bool signed = true) => Add(name, 2, FK.BShort, 5, 0, signed);
    public Layout BLong(string name, bool signed = true) => Add(name, 4, FK.BLong, 10, 0, signed);
    /// <summary>既存項目の再定義(別名)。</summary>
    public Layout Alias(string name, string of, int off = 0, int len = -1, FK kind = FK.X, int digits = 0, int dec = 0)
    { var f = F[of]; F[name] = new Fld(f.Off + off, len < 0 ? f.Len : len, kind, digits, dec, false); return this; }
    public Layout At(string name, int off, int len, FK kind = FK.X, int digits = 0, int dec = 0, bool signed = false)
    { F[name] = new Fld(off, len, kind, digits == 0 && kind == FK.N9 ? len : digits, dec, signed); return this; }
    public Layout Group(int times, Action<Layout, int> body) { for (int i = 1; i <= times; i++) body(this, i); return this; }
    public Rec New() { var r = new Rec(this, new byte[Size]); r.Init(); return r; }
    public Rec From(byte[] b) { var x = new byte[Size]; Array.Copy(b, x, Math.Min(b.Length, Size)); return new Rec(this, x); }
}

public sealed class Rec
{
    public readonly Layout L;
    public byte[] B;
    public Rec(Layout l, byte[] b) { L = l; B = b; }
    public Rec Clone() => new(L, (byte[])B.Clone());

    /// <summary>COBOL INITIALIZE 相当: 英数字=空白、数値=ゼロ。</summary>
    public void Init()
    {
        Array.Fill(B, (byte)0);
        foreach (var kv in L.F)
        {
            var f = kv.Value;
            if (f.Kind == FK.X) for (int i = 0; i < f.Len; i++) B[f.Off + i] = 0x20;
        }
        foreach (var kv in L.F) if (kv.Value.Kind != FK.X) SetN(kv.Key, 0);
    }

    public string S(string name)
    {
        var f = L.F[name];
        return Encoding.Latin1.GetString(B, f.Off, f.Len);
    }
    public string St(string name) => S(name).TrimEnd(' ', '\0');

    public void Set(string name, string v)
    {
        var f = L.F[name];
        if (f.Kind != FK.X) { SetN(name, Cob.ToNum(v)); return; }
        var bytes = Encoding.Latin1.GetBytes(v.PadRight(f.Len).Substring(0, f.Len));
        Array.Copy(bytes, 0, B, f.Off, f.Len);
    }

    public decimal N(string name)
    {
        var f = L.F[name];
        long raw;
        switch (f.Kind)
        {
            case FK.N9:
                {
                    raw = 0; bool neg = false;
                    for (int i = 0; i < f.Len; i++)
                    {
                        int c = B[f.Off + i];
                        if (i == f.Len - 1 && f.Signed && c >= 0x70) { neg = true; c -= 0x40; }
                        int d = c - 0x30; if (d < 0 || d > 9) d = 0;
                        raw = raw * 10 + d;
                    }
                    if (neg) raw = -raw;
                    break;
                }
            case FK.C3:
                {
                    raw = 0;
                    for (int i = 0; i < f.Len; i++)
                    {
                        int b = B[f.Off + i];
                        raw = raw * 10 + (b >> 4);
                        if (i < f.Len - 1) raw = raw * 10 + (b & 15);
                        else if ((b & 15) == 0x0D) raw = -raw;
                    }
                    break;
                }
            case FK.Comp:
                {
                    raw = f.Signed && (B[f.Off] & 0x80) != 0 ? -1 : 0;
                    for (int i = 0; i < f.Len; i++) raw = (raw << 8) | B[f.Off + i];
                    break;
                }
            case FK.BChar: raw = f.Signed ? (sbyte)B[f.Off] : B[f.Off]; break;
            case FK.BShort: raw = f.Signed ? BitConverter.ToInt16(B, f.Off) : BitConverter.ToUInt16(B, f.Off); break;
            case FK.BLong: raw = f.Signed ? BitConverter.ToInt32(B, f.Off) : BitConverter.ToUInt32(B, f.Off); break;
            default: return Cob.ToNum(S(name));
        }
        decimal v = raw;
        for (int i = 0; i < f.Dec; i++) v /= 10m;
        return v;
    }
    public int I(string name) => (int)N(name);

    /// <summary>COBOL MOVE 相当: 小数部・上位桁は切り捨て、符号なし項目は絶対値。</summary>
    public void SetN(string name, decimal v)
    {
        var f = L.F[name];
        if (f.Kind == FK.X) { Set(name, v.ToString()); return; }
        decimal scaled = v;
        for (int i = 0; i < f.Dec; i++) scaled *= 10m;
        long raw = (long)decimal.Truncate(scaled);
        bool neg = raw < 0;
        if (!f.Signed && neg) { raw = -raw; neg = false; }
        long abs = Math.Abs(raw);
        if (f.Kind is FK.N9 or FK.C3 or FK.Comp)
        {
            long mod = 1; for (int i = 0; i < f.Digits; i++) mod *= 10;
            abs %= mod;
        }
        switch (f.Kind)
        {
            case FK.N9:
                for (int i = f.Len - 1; i >= 0; i--) { B[f.Off + i] = (byte)(0x30 + abs % 10); abs /= 10; }
                if (f.Signed && neg) B[f.Off + f.Len - 1] += 0x40;
                break;
            case FK.C3:
                {
                    int nib = f.Signed ? (neg ? 0x0D : 0x0C) : 0x0F;
                    for (int i = f.Len - 1; i >= 0; i--)
                    {
                        int lo;
                        if (i == f.Len - 1) lo = nib; else { lo = (int)(abs % 10); abs /= 10; }
                        int hi = (int)(abs % 10); abs /= 10;
                        B[f.Off + i] = (byte)((hi << 4) | lo);
                    }
                    break;
                }
            case FK.Comp:
                {
                    long x = neg ? -abs : abs;
                    for (int i = f.Len - 1; i >= 0; i--) { B[f.Off + i] = (byte)(x & 0xFF); x >>= 8; }
                    break;
                }
            case FK.BChar: B[f.Off] = (byte)(neg ? -abs : abs); break;
            case FK.BShort: BitConverter.GetBytes((short)(neg ? -abs : abs)).CopyTo(B, f.Off); break;
            case FK.BLong: BitConverter.GetBytes((int)(neg ? -abs : abs)).CopyTo(B, f.Off); break;
        }
    }
}

/// <summary>COBOL の数値・編集規則の補助関数。</summary>
public static class Cob
{
    /// <summary>英数字→数値の MOVE (空白無視、小数点対応)。</summary>
    public static decimal ToNum(string s)
    {
        var sb = new StringBuilder(); bool neg = false, dot = false;
        foreach (var c in s)
        {
            if (char.IsDigit(c)) sb.Append(c);
            else if (c == '.' && !dot) { sb.Append('.'); dot = true; }
            else if (c == '-') neg = true;
        }
        if (sb.Length == 0 || sb.ToString() == ".") return 0;
        var v = decimal.Parse(sb.ToString(), System.Globalization.CultureInfo.InvariantCulture);
        return neg ? -v : v;
    }
    public static int ToInt(string s) => (int)decimal.Truncate(ToNum(s));
    public static decimal Trunc(decimal v, int dec) { decimal m = 1; for (int i = 0; i < dec; i++) m *= 10; return decimal.Truncate(v * m) / m; }
    public static decimal Round(decimal v, int dec) => Math.Round(v, dec, MidpointRounding.AwayFromZero);
    /// <summary>PIC 9(n) 表示 (ゼロ埋め、上位切り捨て)。</summary>
    public static string P9(decimal v, int digits)
    {
        var s = ((long)Math.Abs(decimal.Truncate(v))).ToString().PadLeft(digits, '0');
        return s.Substring(s.Length - digits);
    }
    /// <summary>編集 PICTURE (9 Z * , . - + CR DB B 0 / 通貨記号)。例: Edit(v, "ZZZ,ZZ9.99-")。</summary>
    public static string Edit(decimal v, string pic) => PicEdit.Format(v, pic);
}
