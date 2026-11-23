import Foundation

/// sales/sl900.cbl: Invoicing Menu / Invoicing Fixed Data
enum SLB900 {
    static let progName = "SL900 (3.01.09)"

    static func run(_ s: Session) throws {
        let c = s.console
        let wsDate = SLB.wsDate(s)
        s.delLink = s.caller
        s.caller = s.called
        if s.sys.int("next-invoice") == 0 { try fixedData(s, wsDate) }
        menuReturn: while true {
            let notInvoicing = s.sys.int("invoicer") == 9
            c.display(" ", at: 101, eraseEOS: true)
            c.display(progName, at: 101, color: 2)
            c.display(s.t("sl900.menu_title"), at: 134, color: 2)
            c.display(wsDate, at: 171, color: 2)
            c.display(s.t("sl900.select"), at: 501, color: 2)
            c.display(s.t("sl900.item_1"), at: 811, color: 2)
            if notInvoicing {
                c.display(s.t("sl900.item_2_details"), at: 911, color: 2)
            } else {
                c.display(s.t("sl900.item_2"), at: 911, color: 2)
                c.display(s.t("sl900.item_3"), at: 1011, color: 2)
                c.display(s.t("sl900.item_7"), at: 1411, color: 2)
                c.display(s.t("sl900.item_8"), at: 1511, color: 2)
            }
            c.display(s.t("sl900.item_4"), at: 1111, color: 2)
            c.display(s.t("sl900.item_5"), at: 1211, color: 2)
            c.display(s.t("sl900.item_6"), at: 1311, color: 2)
            c.display(s.t("sl900.item_9"), at: 1711, color: 2)
            while true {
                let reply = try SLB.acceptNum(s, at: 543, digits: 1, options: [.auto], color: 6)
                if reply == 9 {
                    s.sys.setInt("pass-value", 0)
                    s.called = s.caller
                    s.caller = s.delLink
                    return
                }
                if (reply == 3 || reply == 7 || reply == 8) && notInvoicing {
                    c.display(s.t("sl900.invalid_option"), at: 2015, color: 3, highlight: true)
                    continue
                }
                var called: String?
                switch reply {
                case 1:
                    try fixedData(s, wsDate)
                    continue menuReturn
                case 4: called = "sl920"
                case 5: called = "sl940"
                case 6: called = "sl200"
                case 7: called = "sl930"
                case 8: called = "sl950"
                case 2, 3: called = "sl910"
                default: break
                }
                if let name = called {
                    s.sys.setInt("pass-value", reply)
                    s.called = name
                    try s.call(name)
                }
                continue menuReturn
            }
        }
    }

    static func fixedData(_ s: Session, _ wsDate: String) throws {
        let c = s.console
        let gl = s.sys.int("level-1") == 1
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("sl900.fixed_title"), at: 131, color: 2)
        c.display(wsDate, at: 171, color: 2)
        c.display(s.t("sl900.next_invoice"), at: 511, color: 2)
        c.display(s.t("sl900.box8"), at: 545, color: 2)
        c.display(s.t("sl900.extra_desc"), at: 711, color: 2)
        c.display("]", at: 762, color: 2)
        c.display(s.t("sl900.extra_type"), at: 911, color: 2)
        c.display(s.t("sl900.extra_print"), at: 1011, color: 2)
        c.display(s.t("sl900.extra_rate"), at: 1111, color: 2)
        c.display(s.t("sl900.entry_level"), at: 1311, color: 2)
        c.display(s.t("sl900.box1"), at: 1345, color: 2)
        c.display(s.t("sl900.stock_link"), at: 1411, color: 2)
        c.display(s.t("sl900.stock_audit"), at: 1511, color: 2)
        if gl {
            c.display(s.t("sl900.extra_ac"), at: 1611, color: 2)
            c.display(s.t("sl900.box6"), at: 1645, color: 2)
            c.display(s.t("sl900.vat_ac"), at: 1711, color: 2)
            c.display(s.t("sl900.box6"), at: 1745, color: 2)
        }
        c.display(s.t("sl900.pf_retention"), at: 1911, color: 2)
        c.display(s.t("sl900.box3"), at: 1945, color: 2)
        c.display(s.t("sl900.ok_to_file"), at: 2111, color: 2)
        var nextInvoice = Cobol.truncate(s.sys.int("next-invoice"), digits: 8, signed: false)
        c.display(Cobol.z(nextInvoice, 8), at: 548, color: 3)
        c.display(s.sys.str("extra-desc"), at: 748, color: 2)
        c.display(s.sys.str("extra-type"), at: 948, color: 3)
        c.display(s.sys.str("extra-print"), at: 1048, color: 3)
        func discDisplay() -> String {
            let r = s.sys.int("extra-rate")
            return Cobol.z(r / 100, 2) + "." + Cobol.z(r % 100, 2)
        }
        var disc = discDisplay()
        c.display(disc, at: 1148, color: 3)
        c.display(Cobol.z(s.sys.int("invoicer"), 1), at: 1348, color: 3)
        c.display(s.sys.str("sl-stock-link"), at: 1437, color: 3)
        c.display(s.sys.str("sl-stock-audit"), at: 1537, color: 3)
        var extraAc = Cobol.truncate(s.sys.int("extra-charge-ac"), digits: 6, signed: false)
        c.display(Cobol.z(extraAc, 6), at: 1648, color: 3)
        var vatAc = Cobol.truncate(s.sys.int("vat-ac"), digits: 6, signed: false)
        c.display(Cobol.z(vatAc, 6), at: 1748, color: 3)
        var pfRet = Cobol.truncate(s.sys.int("pf-retention"), digits: 3, signed: false)
        c.display(Cobol.z(pfRet, 3), at: 1948, color: 3)

        dataEntry: while true {
            nextInvoice = try SLB.acceptNum(s, at: 548, digits: 8, initial: nextInvoice, color: 3)
            s.sys.setInt("next-invoice", nextInvoice)
            if nextInvoice == 0 { continue }
            s.sys["extra-desc"] = try c.accept(at: 748, size: 14, initial: s.sys.str("extra-desc"), options: [.update], color: 2)
            if s.sys.str("extra-desc").trimmingCharacters(in: .whitespaces).isEmpty {
                s.sys["extra-type"] = " "; s.sys["extra-print"] = " "
                s.sys.setInt("extra-rate", 0)
            } else {
                repeat {
                    s.sys["extra-type"] = try c.accept(at: 948, size: 1, initial: s.sys.str("extra-type"), options: [.update], color: 3).uppercased()
                } while s.sys.str("extra-type") != "C" && s.sys.str("extra-type") != "D"
                repeat {
                    s.sys["extra-print"] = try c.accept(at: 1048, size: 1, initial: s.sys.str("extra-print"), options: [.update], color: 3).uppercased()
                } while s.sys.str("extra-print") != "Y" && s.sys.str("extra-print") != "N"
                disc = try c.accept(at: 1148, size: 5, initial: disc, options: [.update], color: 3)
                let a = Array(Cobol.x(disc, 5))
                func dig(_ ch: Character) -> Int64 { Int64(ch.wholeNumberValue ?? 0) }
                s.sys.setInt("extra-rate", dig(a[0]) * 1000 + dig(a[1]) * 100 + dig(a[3]) * 10 + dig(a[4]))
            }
            // entry-x
            repeat {
                s.sys.setInt("invoicer", try SLB.acceptNum(s, at: 1348, digits: 1, initial: s.sys.int("invoicer"), color: 3))
            } while s.sys.int("invoicer") != 1 && s.sys.int("invoicer") != 2
            repeat {
                s.sys["sl-stock-link"] = try c.accept(at: 1437, size: 1, initial: s.sys.str("sl-stock-link"), options: [.update], color: 3).uppercased()
            } while s.sys.str("sl-stock-link") != "Y" && s.sys.str("sl-stock-link") != "N"
            if s.sys.str("sl-stock-link") == "N" {
                s.sys["sl-stock-audit"] = "N"
            } else {
                s.sys["sl-stock-audit"] = "Y"
                repeat {
                    s.sys["sl-stock-audit"] = try c.accept(at: 1537, size: 1, initial: s.sys.str("sl-stock-audit"), options: [.update], color: 3).uppercased()
                } while s.sys.str("sl-stock-audit") != "Y" && s.sys.str("sl-stock-audit") != "N"
            }
            if gl {
                extraAc = try SLB.acceptNum(s, at: 1648, digits: 6, initial: extraAc, color: 3)
                s.sys.setInt("extra-charge-ac", extraAc)
                vatAc = try SLB.acceptNum(s, at: 1748, digits: 6, initial: vatAc, color: 3)
                s.sys.setInt("vat-ac", vatAc)
            }
            while true {
                pfRet = try SLB.acceptNum(s, at: 1948, digits: 3, initial: pfRet, color: 3)
                s.sys.setInt("pf-retention", pfRet)
                let reply = try c.accept(at: 2148, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                if reply == "N" { continue dataEntry }
                if reply == "Y" { return }
            }
        }
    }
}
