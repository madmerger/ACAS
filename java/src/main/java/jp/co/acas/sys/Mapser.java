package jp.co.acas.sys;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;

import java.time.LocalDate;
import java.util.Arrays;

/** ACAS.cbl の mapser / level-setup セクション: システムファイルの初期作成（会社名と利用領域）。 */
public class Mapser extends Program {
    private Rec sys;

    @Override
    public void run(Object... args) {
        clearScreen();
        display(1, 1, Acas.PROG_NAME);
        display(1, 22, "ACAS System Setup Routine - Level 1");
        CobFile f = SystemFile.file(ctx);
        if (!f.open(CobFile.Mode.OUTPUT).equals("00")) {
            display(11, 1, "Problem with opening system file. Hit return to clear", 4);
            accept(11, 54, 1);
            stopRun();
        }
        sys = SystemFile.shared(ctx);
        sys.initialize();
        zeroFillers(sys.layout.root);
        sys.setNum("system-record-version-prime", 1);
        sys.setNum("system-record-version-secondary", 1);
        sys.setNum("date-form", 1);
        String reply;
        do {
            display(11, 1, "Enter the Company Name :- [");
            display(11, 60, "]");
            sys.set("usera", acceptUpdate(11, 28, 32, sys.str("usera")));
            display(13, 1, "Please verify that name is correct (Y/N) :- [ ]");
            reply = acceptUpdate(13, 46, 1, "Y", 0);
        } while (!reply.equalsIgnoreCase("Y"));
        sys.set("user-code", Maps01.name(ctx, sys.str("usera")));
        sys.set("pass-word", Maps01.password(ctx, "pass"));
        sys.set("sl-own-nos", "N");
        LocalDate today = ctx.today();
        ctx.shared.put("to-day", Maps04.toDate(Maps04.toBin(today)));
        sys.setNum("run-date", Maps04.toBin(today));
        levelSetup(reply);
        sys.setNum("op-system", 1);
        sys.setNum("sales-range", 1);
        sys.setNum("purchase-range", 2);
        sys.setNum("next-batch", 1);
        sys.setNum("sl-dunning", 1);
        sys.setNum("sl-charges", 1);
        sys.setNum("invoicer", 2);
        sys.setNum("sl-credit", 30);
        sys.set("sl-delim", "\\");
        f.rrn = 1;
        f.write(sys);
        f.rrn = 2;
        f.write(padded(Layout.of("copybooks/wsdflt.cob", "Default-Record").newRec().bytes()));
        byte[] spaces = new byte[sys.layout.size];
        Arrays.fill(spaces, (byte) ' ');
        f.rrn = 3;
        f.write(spaces);
        f.rrn = 4;
        f.write(padded(Layout.of("copybooks/wssys4.cob", "System-Record-4").newRec().bytes()));
        f.close();
    }

    /** INITIALIZE は FILLER を初期化しないため、レガシーでは未使用域が LOW-VALUES のまま書き出される。 */
    private void zeroFillers(Layout.Field f) {
        if (f.redefines != null) return;
        if (f.kind == Layout.Kind.GROUP) { for (Layout.Field c : f.children) zeroFillers(c); return; }
        if ("filler".equals(f.name)) Arrays.fill(sys.bytes(), f.offset, f.offset + f.size * f.occurs, (byte) 0);
    }

    private byte[] padded(byte[] rec) {
        byte[] out = new byte[sys.layout.size];
        Arrays.fill(out, (byte) ' ');
        System.arraycopy(rec, 0, out, 0, Math.min(rec.length, out.length));
        return out;
    }

    private void levelSetup(String reply) {
        while (true) {
            sys.set("maps-ser-xx", "mp");
            sys.setNum("maps-ser-nn", 9999);
            display(19, 1, "Using General  Ledger (Y/N) ? :- [ ]");
            display(20, 1, "Using Purchase Ledger (Y/N) ? :- [ ]");
            display(21, 1, "Using Sales    Ledger (Y/N) ? :- [ ]");
            display(19, 41, "Using Invoicing       (Y/N) ? :- [ ]");
            display(20, 41, "Using Stock Control   (Y/N) ? :- [ ]");
            display(21, 41, "Using Order Entry     (Y/N) ? :- [ ]");
            int[][] at = {{19, 35}, {20, 35}, {21, 35}, {19, 75}, {20, 75}, {21, 75}};
            String[] fields = {"level-1", "level-2", "level-3", "full-invoicing", "level-4", "level-5"};
            for (int i = 0; i < 6; i++) {
                String r = acceptUpdate(at[i][0], at[i][1], 1, reply, 0);
                // レガシーは先頭 4 項目のみ応答を大文字化して保持する
                reply = i < 4 ? upper(r) : r;
                sys.setNum(fields[i], r.equalsIgnoreCase("Y") ? 1 : 0);
            }
            display(23, 1, "Please confirm (Y/N) :- [ ] ");
            StringBuilder o = new StringBuilder();
            boolean gl = sys.intv("level-1") == 1, bl = sys.intv("level-2") == 1, sl = sys.intv("level-3") == 1;
            if (gl) o.append("General ");
            if (bl && gl) o.append("/ ");
            if (bl) o.append("Purchase ");
            if (sl && (gl || bl)) o.append("/ ");
            if (sl) o.append("Sales ");
            if (sl && sys.intv("full-invoicing") == 1) o.append("/ Invoicing");
            if (sys.intv("level-4") == 1) o.append("/ Stock ");
            if (sys.intv("level-5") == 1) o.append("/ Order Entry");
            String list = (o + " ".repeat(60)).substring(0, 60);
            ctx.term.display(24, 1, list, 2);
            reply = upper(accept(23, 26, 1));
            if (reply.equals("Y")) return;
        }
    }
}
