namespace Acas.Core.Engine;

/// <summary>レガシー copybook に対応するレコード定義。</summary>
public static partial class Layouts
{
    /// <summary>copybooks/wssystem.cob (system.dat レコード1, 1024 バイト)。</summary>
    public static readonly Layout System = BuildSystem();

    /// <summary>general/fdledger.cob (ledger.dat, 126 バイト, キー = nos+pc)。</summary>
    public static readonly Layout Ledger = new Layout()
        .N9("nos", 6).N9("pc", 2).N9("type", 1).X("place", 1).N9("level", 1).Fill(5).X("name", 24)
        .C3("balance", 8, 2).C3("last", 8, 2).C3("q1", 8, 2).C3("q2", 8, 2).C3("q3", 8, 2).C3("q4", 8, 2).Fill(50);

    /// <summary>copybooks/wsdflt.cob (system.dat レコード2): 既定勘定 33 件。</summary>
    public static readonly Layout Default = BuildDefault();
    private static Layout BuildDefault()
    {
        var l = new Layout();
        for (int i = 1; i <= 33; i++) l.Comp("acs" + i, 4, 2);
        for (int i = 1; i <= 33; i++) l.X("code" + i, 2);
        for (int i = 1; i <= 33; i++) l.X("vat" + i, 1);
        l.Fill(1024 - l.Size);
        return l;
    }

    /// <summary>copybooks/fdbatch.cob (96 バイト)。キー = ledger + batch-nos。</summary>
    public static readonly Layout Batch = new Layout()
        .N9("ledger", 1).N9("batch-nos", 5).N9("items", 2).N9("batch-status", 1).N9("cleared-status", 1).N9("bcycle", 2)
        .BLong("entered").BLong("proofed").BLong("posted").BLong("stored")
        .C3("input-gross", 9, 2, false).C3("input-vat", 9, 2, false).C3("actual-gross", 9, 2, false).C3("actual-vat", 9, 2, false)
        .X("description", 24).N9("bdefault", 2).X("convention", 2).N9("batch-def-ac", 6).N9("batch-def-pc", 2)
        .X("batch-def-code", 2).X("batch-def-vat", 1).N9("batch-start", 5);

    /// <summary>copybooks/fdpost.cob (98 バイト, 相対編成)。</summary>
    public static readonly Layout Posting = new Layout()
        .N9("batch", 5).N9("post-number", 5).X("post-code", 2).X("post-date", 8).N9("post-dr", 6).N9("dr-pc", 2)
        .N9("post-cr", 6).N9("cr-pc", 2).N9("post-amount", 8, 2, true).X("post-legend", 32).N9("vat-ac", 6).N9("vat-pc", 2)
        .X("post-vat-side", 2).N9("vat-amount", 8, 2, true);

    private static Layout BuildSystem()
    {
        var l = new Layout();
        l.BChar("Version-Prime").BChar("Version-Secondary");
        for (int i = 1; i <= 5; i++) l.Comp("Vat-Rate-" + i, 2, 2);
        l.BChar("Cyclea").BChar("Period").BChar("Page-Lines", false)
         .BLong("Next-Invoice").BLong("Run-Date").BLong("Start-Date").BLong("End-Date")
         .X("Usera", 32).X("User-Code", 32).X("Address-1", 24).X("Address-2", 24).X("Address-3", 24).X("Address-4", 24)
         .X("Post-Code", 12).X("Country", 24).X("Print-Spool-Name", 48);
        for (int i = 1; i <= 32; i++) l.N9("File-Status-" + i, 1);
        l.N9("Pass-Value", 1);
        for (int i = 1; i <= 6; i++) l.N9("Level-" + i, 1);
        l.X("Pass-Word", 4).N9("Host", 1).N9("Op-System", 1).N9("Current-Quarter", 1)
         .N9("File-System-Used", 1).N9("File-Duplicates-In-Use", 1).X("Maps-Ser-xx", 2).BShort("Maps-Ser-nn")
         .N9("Date-Form", 1).N9("Data-Capture-Used", 1).X("RDBMS-DB-Name", 12).X("RDBMS-User", 12).X("RDBMS-Passwd", 12)
         .X("VAT-Reg-Number", 11).Fill(8);
        // General-Ledger-Block
        l.X("P-C", 1).X("P-C-Grouped", 1).X("P-C-Level", 1).X("Comps", 1).X("Comps-Active", 1).X("M-V", 1).X("Arch", 1)
         .X("Trans-Print", 1).X("Trans-Printed", 1).N9("Header-Level", 1).N9("Sales-Range", 1).N9("Purchase-Range", 1)
         .X("Vat", 1).X("Batch-Id", 1).X("Ledger-2nd-Index", 1).X("Irs-Instead", 1)
         .BShort("Ledger-Sec").BShort("Updates").BShort("Postings").BShort("Next-Batch")
         .BLong("Extra-Charge-Ac").BLong("Vat-Ac").X("Print-Spool-Name2", 48);
        // Purchase-Ledger-Block
        l.BLong("Next-Folio").BLong("BL-Pay-Ac").BLong("P-Creditors").BLong("BL-Purch-Ac").BLong("BL-End-Cycle-Date")
         .BShort("BL-Next-Batch").BChar("Age-To-Pay").X("Purchase-Ledger", 1).X("PL-Delim", 1).N9("Entry-Level", 1)
         .N9("P-Flag-A", 1).N9("P-Flag-I", 1).N9("P-Flag-P", 1).X("PL-Stock-Link", 1).X("Print-Spool-Name3", 48).Fill(10);
        // Sales-Ledger-Block
        l.X("Sales-Ledger", 1).X("SL-Delim", 1).X("Oi-3-Flag", 1).X("Cust-Flag", 1).X("Oi-5-Flag", 1).X("S-Flag-Oi-3", 1)
         .N9("Full-Invoicing", 1).N9("S-Flag-A", 1).N9("S-Flag-I", 1).N9("S-Flag-P", 1).N9("SL-Dunning", 1).N9("SL-Charges", 1)
         .X("Sl-Own-Nos", 1).N9("SL-Stats-Run", 1).N9("Sl-Day-Book", 1).N9("Invoicer", 1).X("Extra-Desc", 14).X("Extra-Type", 1)
         .X("Extra-Print", 1).X("SL-Stock-Link", 1).X("SL-Stock-Audit", 1)
         .Comp("SL-Late-Per", 2, 2).Comp("SL-Disc", 2, 2).Comp("Extra-Rate", 2, 2)
         .BChar("SL-Days-1").BChar("SL-Days-2").BChar("SL-Days-3").BChar("SL-Credit").Fill(2)
         .BShort("SL-Min").BShort("SL-Max").BShort("PF-Retention").BShort("First-Sl-Batch")
         .BLong("First-Sl-Inv").BLong("SL-Limit").BLong("SL-Pay-Ac").BLong("S-Debtors").BLong("SL-Sales-Ac").BLong("S-End-Cycle-Date")
         .X("SL-Comp-Head-Pick", 1).X("SL-Comp-Head-Inv", 1).X("SL-Comp-Head-Stat", 1).X("SL-Comp-Head-Lets", 1).X("SL-VAT-Printed", 1).Fill(45);
        // Stock-Control-Block
        l.X("Stk-Abrev-Ref", 6).N9("Stk-Debug", 1).N9("Stk-Manu-Used", 1).N9("Stk-OE-Used", 1).N9("Stk-Audit-Used", 1).N9("Stk-Mov-Audit", 1)
         .X("Stk-Period-Cur", 1).X("Stk-Period-dat", 1).Fill(1).X("Stock-Control", 1).N9("Stk-Averaging", 1).N9("Stk-Activity-Rep-Run", 1).Fill(1)
         .BChar("Stk-Page-Lines", false).BChar("Stk-Audit-No", false).Fill(68);
        l.Fill(128); // Order-Entry-Block
        // IRS-Entry-Block
        l.X("Client", 24).X("fn-1", 9).X("fn-2", 10).X("fn-3", 8).X("fn-4", 8).X("fn-5", 12).X("System-Ops", 1)
         .N9("Next-Post", 5).N9("vat1", 2, 2).N9("vat2", 2, 2).N9("vat3", 2, 2).N9("IRS-Pass-Value", 1).N9("save-sequ", 1)
         .X("system-work-group", 18).X("PL-App-Created", 1).N9("PL-Approp-AC", 5).N9("1st-Time-Flag", 1).Fill(12);
        if (l.Size < 1024) l.Fill(1024 - l.Size);
        return l;
    }
}
