import Foundation

/// sales/sl940.cbl: Invoicing Data Deletion (請求書削除)
enum SLB940 {
    static let progName = "SL940 (3.01.04)"

    /// UNSTRING src DELIMITED BY delim INTO target(size) POINTER p (delim nil = 区切りなし)
    static func unstring(_ src: [Character], _ delim: Character?, size: Int, pointer p: inout Int) -> String? {
        if p < 1 || p > src.count { return nil }
        var i = p - 1
        var out: [Character] = []
        while i < src.count {
            if let d = delim, src[i] == d { i += 1; p = i + 1; return Cobol.x(String(out), size) }
            out.append(src[i]); i += 1
        }
        p = src.count + 1
        return Cobol.x(String(out), size)
    }

    static func run(_ s: Session) throws {
        let c = s.console
        // program-start
        if SLB.fileStatus(s, 16) != 1 {
            try SLB.maps99(s, 17)
            try SLB.maps99(s, 15)
            return
        }
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("sl940.title"), at: 131, color: 2)
        c.display(SLB.wsDate(s), at: 171, color: 2)

        let inv = SLB.invoiceFile(s)
        let salesFile = SLB.salesFile(s)
        let delivery = SLB.deliveryFile(s)
        inv.open(); salesFile.open(); delivery.open()
        let dnos = s.ledgers + "delinvno.dat"
        if !s.store.exists(dnos) { s.store.writeRaw(dnos, []) }

        var sih = Record(SLB.sihLayout)
        sih.setInt("sih-invoice", 0)
        var sales = Record(SLB.salesLayout)
        var deliv = Record(SLB.deliveryLayout)
        var addressLine = Cobol.x("", 36)
        let delim = Character(Cobol.x(s.sys.str("sl-delim"), 1))

        func invoiceDetails() throws -> Bool {
            let stars = String(repeating: "*", count: 40)
            c.display(stars, at: 441, color: 2, eraseEOL: true)
            c.display(s.t("sl940.box_date"), at: 541, color: 2, eraseEOL: true)
            c.display(s.t("sl940.box_ac"), at: 641, color: 2, eraseEOL: true)
            c.display(s.t("sl940.box_invoice"), at: 741, color: 2, eraseEOL: true)
            c.display(stars, at: 841, color: 2, eraseEOL: true)
            c.display(s.t("sl940.type_line"), at: 1001, color: 2)
            while true {
                sih.setInt("sih-invoice", try SLB.acceptNum(s, at: 751, digits: 8, initial: sih.int("sih-invoice"), color: 3))
                c.display(" ", at: 1601, eraseEOL: true)
                if sih.int("sih-invoice") == 0 { return false }
                sih["sih-letter"] = " "
                c.display(s.t("sl940.give_letter"), at: 1601, color: 2)
                sih["sih-letter"] = try c.accept(at: 759, size: 1, initial: " ", options: [.update], color: 6)
                c.display(" ", at: 1601, eraseEOL: true)
                var key = Record(SLB.invoiceLayout)
                key.setInt("invoice-nos", sih.int("sih-invoice"))
                key["invoice-let"] = sih.str("sih-letter")
                key.setInt("item-nos", 0)
                guard let rec = inv.read(key: inv.key(of: key)) else {
                    c.display(s.t("sl940.sl194"), at: 1640, color: 4)
                    continue
                }
                sih = SLB.sih(from: rec)
                if sih.str("sih-status") == "z" {
                    c.display(s.t("sl940.sl195"), at: 1601, color: 4, eraseEOL: true)
                    continue
                }
                break
            }
            let wsDate = SLB.convBin(s, sih.int("sih-date")).wsDate
            c.display(sih.str("sih-customer"), at: 653, color: 3)
            if let r = salesFile.read(key: sih.raw("sih-customer")) { sales = r }
            else { sales.setRaw("sales-key", sih.raw("sih-customer")) }
            var addressA: String
            if sales.int("delivery-tag") != 0 {
                deliv["deliv-key"] = "D" + sales.str("sales-key")
                if let d = delivery.read(key: deliv.raw("deliv-key")) {
                    deliv = d
                    addressA = deliv.str("deliv-address")
                } else {
                    sales.setInt("delivery-tag", 0)
                    addressA = sales.str("sales-addr1") + sales.str("sales-addr2")
                }
            } else {
                addressA = sales.str("sales-addr1") + sales.str("sales-addr2")
            }
            if sales.int("delivery-tag") == 0 { c.display(sales.str("sales-name"), at: 401, color: 3) }
            else { c.display(deliv.str("deliv-name"), at: 401, color: 3) }
            let src = Array(Cobol.x(addressA, 96))
            var a = 1
            for (i, pos) in [501, 601, 701, 801].enumerated() {
                if i > 0 { addressLine = Cobol.x("", 36) }
                if let t = unstring(src, i < 3 ? delim : nil, size: 36, pointer: &a) { addressLine = t }
                c.display(addressLine, at: pos, color: 3)
            }
            addressLine = Cobol.x("", 36)
            c.display(wsDate, at: 550, color: 3)
            c.display(sih.str("sih-order"), at: 769, color: 3)
            c.display(String(sih.int("sih-type")), at: 1007, color: 3)
            c.display(s.t("sl940.to_be_deleted"), at: 1601, color: 2)
            let reply = try c.accept(at: 1632, size: 1, initial: "N", options: [.update], color: 6).uppercased()
            if reply != "Y" { return true }
            var key = Record(SLB.invoiceLayout)
            key.setInt("invoice-nos", sih.int("sih-invoice"))
            key["invoice-let"] = sih.str("sih-letter")
            key.setInt("item-nos", 0)
            inv.delete(key: inv.key(of: key))
            // delete-details
            var j: Int64 = 0
            for _ in 0..<max(0, Int(sih.int("sih-lines"))) {
                j += 1
                key.setInt("item-nos", j)
                inv.delete(key: inv.key(of: key))
            }
            var b = Array(Cobol.z(sih.int("sih-invoice"), 8).utf8)
            let d = UInt32(truncatingIfNeeded: sih.int("sih-date"))
            b += [UInt8(d & 0xFF), UInt8((d >> 8) & 0xFF), UInt8((d >> 16) & 0xFF), UInt8(d >> 24)]
            b += sih.raw("sih-customer")
            s.store.appendRaw(dnos, b)
            return true
        }

        while true {
            if !(try invoiceDetails()) { break }
            c.display(" ", at: 1601, eraseEOS: true)
            c.display(s.t("sl940.delete_further"), at: 1629, color: 2)
            let reply = try c.accept(at: 1662, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
            c.display(" ", at: 1601, eraseEOL: true)
            if reply != "Y" { break }
        }
        salesFile.close(); delivery.close(); inv.close()
    }
}
