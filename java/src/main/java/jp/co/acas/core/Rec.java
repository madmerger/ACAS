package jp.co.acas.core;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** レガシーとバイト互換の固定長レコード。項目名（COBOL 名、大文字小文字無視）でアクセスする。添字は 1 始まり。 */
public final class Rec {
    public final Layout layout;
    private byte[] data;

    Rec(Layout layout, byte[] data) { this.layout = layout; this.data = data; }

    public byte[] bytes() { return data; }
    public byte[] copyBytes() { return data.clone(); }
    public void load(byte[] src) {
        int n = Math.min(src.length, data.length);
        System.arraycopy(src, 0, data, 0, n);
        if (n < data.length) Arrays.fill(data, n, data.length, (byte) ' ');
    }
    public Rec copy() { return new Rec(layout, data.clone()); }

    /** COBOL の INITIALIZE 相当: 英数字=空白、数字=ゼロ。 */
    public void initialize() { init(layout.root, 0); }
    private void init(Layout.Field f, int delta) {
        for (int i = 0; i < f.occurs; i++) {
            int d = delta + i * (f.occurs > 1 ? f.size : 0);
            if (f.kind == Layout.Kind.GROUP) { for (Layout.Field c : f.children) if (c.redefines == null) init(c, d); }
            else if (f.kind == Layout.Kind.ALPHA || f.kind == Layout.Kind.EDITED) Arrays.fill(data, f.offset + d, f.offset + d + f.size, (byte) ' ');
            else putNum(f, f.offset + d, BigDecimal.ZERO);
        }
    }

    public int offset(String name, int... idx) {
        Layout.Field f = layout.field(name);
        return off(f, idx);
    }
    private int off(Layout.Field f, int... idx) {
        int o = f.offset;
        if (idx.length > f.strides.length) throw new IllegalArgumentException("添字が多すぎます: " + f.name);
        for (int i = 0; i < idx.length; i++) o += (idx[i] - 1) * f.strides[i];
        return o;
    }
    public int size(String name) { return layout.field(name).size; }

    /** 項目の生バイト列を文字列として取得（集団項目も可）。 */
    public String str(String name, int... idx) {
        Layout.Field f = layout.field(name);
        return new String(data, off(f, idx), f.size, StandardCharsets.ISO_8859_1);
    }
    public String trim(String name, int... idx) { return str(name, idx).stripTrailing(); }
    public byte[] raw(String name, int... idx) {
        Layout.Field f = layout.field(name); int o = off(f, idx);
        return Arrays.copyOfRange(data, o, o + f.size);
    }
    public void setRaw(String name, byte[] v, int... idx) {
        Layout.Field f = layout.field(name); int o = off(f, idx);
        System.arraycopy(v, 0, data, o, Math.min(v.length, f.size));
    }
    /** MOVE 英数字: 左詰め・空白埋め・切り捨て。数字項目へは setNum を使うこと。 */
    public void set(String name, String v, int... idx) {
        Layout.Field f = layout.field(name); int o = off(f, idx);
        if (f.kind != Layout.Kind.GROUP && f.kind != Layout.Kind.ALPHA && f.kind != Layout.Kind.EDITED) {
            putNum(f, o, Num.parse(v)); return;
        }
        byte[] b = v.getBytes(StandardCharsets.ISO_8859_1);
        int n = Math.min(b.length, f.size);
        System.arraycopy(b, 0, data, o, n);
        Arrays.fill(data, o + n, o + f.size, (byte) ' ');
    }
    public BigDecimal num(String name, int... idx) {
        Layout.Field f = layout.field(name);
        return getNum(f, off(f, idx));
    }
    public int intv(String name, int... idx) { return num(name, idx).intValue(); }
    public long longv(String name, int... idx) { return num(name, idx).longValue(); }
    /** MOVE 数値: 小数部は切り捨て、整数部の上位桁あふれは切り捨て（COBOL 既定動作）。 */
    public void setNum(String name, BigDecimal v, int... idx) {
        Layout.Field f = layout.field(name); putNum(f, off(f, idx), v);
    }
    public void setNum(String name, long v, int... idx) { setNum(name, BigDecimal.valueOf(v), idx); }
    /** COMPUTE ... ROUNDED 相当（四捨五入）。 */
    public void setRounded(String name, BigDecimal v, int... idx) {
        Layout.Field f = layout.field(name);
        putNum(f, off(f, idx), v.setScale(f.scale, RoundingMode.HALF_UP));
    }
    public void add(String name, BigDecimal v, int... idx) { setNum(name, num(name, idx).add(v), idx); }
    public void sub(String name, BigDecimal v, int... idx) { setNum(name, num(name, idx).subtract(v), idx); }

    private BigDecimal getNum(Layout.Field f, int o) {
        switch (f.kind) {
            case DISPLAY_NUM: {
                long val = 0; boolean neg = false;
                for (int i = 0; i < f.size; i++) {
                    int b = data[o + i] & 0xff;
                    if (i == f.size - 1 && b >= 0x70 && b <= 0x79) { neg = true; b -= 0x40; }
                    int d = b - '0';
                    if (d < 0 || d > 9) d = 0;
                    val = val * 10 + d;
                }
                return BigDecimal.valueOf(neg ? -val : val, f.scale);
            }
            case COMP3: {
                long val = 0;
                for (int i = 0; i < f.size; i++) {
                    int b = data[o + i] & 0xff;
                    val = val * 10 + (b >> 4);
                    if (i < f.size - 1) val = val * 10 + (b & 15);
                }
                int s = data[o + f.size - 1] & 15;
                return BigDecimal.valueOf(s == 0x0d || s == 0x0b ? -val : val, f.scale);
            }
            case COMP: {
                byte[] b = Arrays.copyOfRange(data, o, o + f.size);
                BigInteger bi = f.signed ? new BigInteger(b) : new BigInteger(1, b);
                return new BigDecimal(bi, f.scale);
            }
            case NATIVE_BIN: {
                byte[] b = new byte[f.size];
                for (int i = 0; i < f.size; i++) b[i] = data[o + f.size - 1 - i];
                return new BigDecimal(f.signed ? new BigInteger(b) : new BigInteger(1, b));
            }
            default:
                return Num.parse(new String(data, o, f.size, StandardCharsets.ISO_8859_1));
        }
    }

    private void putNum(Layout.Field f, int o, BigDecimal v) {
        if (f.kind == Layout.Kind.ALPHA || f.kind == Layout.Kind.GROUP || f.kind == Layout.Kind.EDITED) {
            set(f.name, v.toPlainString()); return;
        }
        BigInteger unscaled = v.setScale(f.scale, RoundingMode.DOWN).unscaledValue();
        boolean neg = unscaled.signum() < 0;
        if (f.kind == Layout.Kind.NATIVE_BIN || f.kind == Layout.Kind.COMP) {
            if (f.kind == Layout.Kind.COMP) unscaled = unscaled.remainder(BigInteger.TEN.pow(f.digits));
            if (!f.signed && f.kind == Layout.Kind.COMP) unscaled = unscaled.abs();
            byte[] be = new byte[f.size];
            byte[] src = unscaled.toByteArray();
            byte fill = (byte) (unscaled.signum() < 0 ? 0xff : 0);
            Arrays.fill(be, fill);
            for (int i = 0; i < Math.min(src.length, be.length); i++) be[be.length - 1 - i] = src[src.length - 1 - i];
            if (f.kind == Layout.Kind.COMP) System.arraycopy(be, 0, data, o, f.size);
            else for (int i = 0; i < f.size; i++) data[o + i] = be[f.size - 1 - i];
            return;
        }
        String digits = unscaled.abs().toString();
        if (digits.length() > f.digits) digits = digits.substring(digits.length() - f.digits);
        digits = "0".repeat(f.digits - digits.length()) + digits;
        if (f.kind == Layout.Kind.DISPLAY_NUM) {
            for (int i = 0; i < f.size; i++) data[o + i] = (byte) digits.charAt(i);
            if (f.signed && neg) data[o + f.size - 1] += 0x40;
        } else { // COMP3
            String d = (f.digits % 2 == 0 ? "0" : "") + digits;
            int sign = !f.signed ? 0x0f : neg ? 0x0d : 0x0c;
            for (int i = 0; i < f.size; i++) {
                int hi = d.charAt(i * 2) - '0';
                int lo = i == f.size - 1 ? sign : d.charAt(i * 2 + 1) - '0';
                data[o + i] = (byte) (hi << 4 | lo);
            }
        }
    }
}
