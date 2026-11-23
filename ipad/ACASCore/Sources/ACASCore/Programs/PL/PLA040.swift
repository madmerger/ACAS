import Foundation

/// purchase/pl040.cbl: 仕入取引削除 (Invoice Data Deletion)
final class PLA040 {
    static let progName = "PL040 (3.01.01)"
    static func run(_ s: Session) throws { try PLA040(s).main() }

    let s: Session
    var c: Console { s.console }
    let purchase: IndexedFile, invoice: IndexedFile
    let delInv: PLA.SeqFile
    var purch = PLA.fdArea(PLA.purchLayout)
    var ih = Record(PLA.invHeaderLayout)
    var wsReply = " "
    var escapeCode = " "
    var wsDate = ""

    init(_ s: Session) {
        self.s = s
        purchase = PLA.purchaseFile(s); invoice = PLA.invoiceFile(s)
        delInv = PLA.SeqFile(s, path: s.ledgers + "delfolio.dat", recSize: 19)
    }

    func invKey(_ nos: Int64, _ item: Int64) -> [UInt8] { SJIS.encode(Cobol.z(nos, 8), size: 8) + [UInt8(truncatingIfNeeded: item)] }

    func main() throws {
        // program-start
        if PLA.fileStatus(s, 26) != 1 {
            try PLA.maps99(s, 17)
            try PLA.maps99(s, 15)
            return
        }
        c.display(" ", at: 101, eraseEOS: true)
        c.display(PLA040.progName, at: 101, color: 2)
        c.display(s.t("pl040.title"), at: 131, color: 2)
        wsDate = PLA.toDayDisplay(s)
        c.display(wsDate, at: 171, color: 2)
        _ = invoice.open(); _ = purchase.open()
        delInv.openExtend()
        while true {
            // done-open
            escapeCode = " "
            try invoiceDetails()
            if escapeCode == "Q" { break }
            c.display(" ", at: 16, 1, eraseEOS: true)
            // data-input
            c.display(s.t("pl040.further"), at: 1629, color: 2)
            wsReply = try c.accept(at: 1662, size: 1, color: 6).uppercased()
            c.display(" ", at: 1601, eraseEOS: true)
            if wsReply != "Y" { break }
        }
        purchase.close(); delInv.close(); invoice.close()
    }

    // MARK: invoice-details section

    func invoiceDetails() throws {
        c.display("****************************************", at: 441, color: 2, eraseEOL: true)
        c.display(s.t("pl040.box_date"), at: 541, color: 2, eraseEOL: true)
        c.display(s.t("pl040.box_order"), at: 641, color: 2, eraseEOL: true)
        c.display(s.t("pl040.box_folio"), at: 741, color: 2, eraseEOL: true)
        c.display("****************************************", at: 841, color: 2, eraseEOL: true)
        c.display(s.t("pl040.type_prompt"), at: 1001, color: 2)
        while true {
            // invoice-enter
            ih.setInt("ih-invoice", Int64(try c.accept(at: 750, size: 8, kind: .numeric, color: 3)) ?? 0)
            c.display(" ", at: 1640, eraseEOL: true)
            if ih.int("ih-invoice") == 0 {
                escapeCode = "Q"
                return
            }
            guard let r = invoice.read(key: invKey(ih.int("ih-invoice"), 0)) else {
                c.display(s.t("pl040.pl187"), at: 1640, color: 4)
                continue
            }
            ih = Record(PLA.invHeaderLayout, bytes: Array(r.bytes[0..<100]) + [UInt8](repeating: 0x20, count: 29))
            if ih.str("ih-status") == "z" {
                c.display(s.t("pl040.pl188"), at: 1601, color: 4)
                continue
            }
            break
        }
        wsDate = PLA.dateDisplay(s, ih.int("ih-date"))
        c.display(ih.str("ih-supplier"), at: 572, color: 3)
        purch.set("purch-key", ih.str("ih-supplier"))
        if let p = purchase.read(key: ih.str("ih-supplier")) { purch = p }
        c.display(PLA.shown(purch.raw("purch-name")), at: 401, color: 3)
        var a = 1
        let addr = Array(PLA.shown(purch.raw("purch-address")))
        let delim = s.sys.str("pl-delim").first ?? " "
        for l in [5, 6, 7] {
            c.display(PLA.unstring(addr, delim: delim, pointer: &a, size: 36), at: l, 1, color: 3)
        }
        var last = Cobol.x("", 36)
        if a >= 1 && a <= addr.count { last = Cobol.x(String(addr[(a - 1)..<min(addr.count, a - 1 + 36)]), 36) }
        c.display(last, at: 801, color: 3)
        c.display(wsDate, at: 548, color: 3)
        c.display(ih.str("ih-order"), at: 669, color: 3)
        c.display(ih.str("ih-ref"), at: 769, color: 3)
        c.display(String(ih.int("ih-type")), at: 1007, color: 3)
        c.display(s.t("pl040.to_be_deleted"), at: 1601, color: 2)
        wsReply = try c.accept(at: 1632, size: 1, initial: "N", options: [.update], color: 6).uppercased()
        if wsReply != "Y" { return }
        invoice.delete(key: invKey(ih.int("ih-invoice"), 0))
        // delete-details
        let n = Int(ih.int("ih-lines"))
        if n > 0 { for j in 1...n { invoice.delete(key: invKey(ih.int("ih-invoice"), Int64(j))) } }
        var d = Record(PLA.delInvLayout)
        d.setInt("del-inv-nos", ih.int("ih-invoice"))
        d.setInt("del-inv-dat", ih.int("ih-date"))
        d.set("del-inv-cus", ih.str("ih-supplier"))
        delInv.write(d.bytes)
    }
}
