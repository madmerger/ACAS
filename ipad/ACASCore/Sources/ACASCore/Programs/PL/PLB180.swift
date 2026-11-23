import Foundation

/// pl180.cbl: 請求処理メニュー / 請求固定データ (Invoicing Menu / Invoicing Fixed Data)
enum PLB180 {
    static let progName = "PL180 (3.00.02)"

    static func run(_ s: Session) throws {
        let c = s.console
        s.delLink = s.caller
        s.caller = s.called
        if s.sys.int("next-folio") == 0 { try fixedData(s) }
        menu: while true {
            c.display(" ", at: 101, eraseEOS: true)
            c.display(progName, at: 101, color: 2)
            c.display(s.t("pl180.menu_title"), at: 134, color: 2)
            c.display(s.toDay, at: 171, color: 2)
            c.display(s.t("pl180.select"), at: 501, color: 2)
            c.display(s.t("pl180.opt1"), at: 811, color: 2)
            c.display(s.t("pl180.opt2"), at: 1011, color: 2)
            c.display(s.t("pl180.opt3"), at: 1211, color: 2)
            c.display(s.t("pl180.opt4"), at: 1411, color: 2)
            c.display(s.t("pl180.opt5"), at: 1611, color: 2)
            c.display(s.t("pl180.opt9"), at: 2011, color: 2)
            let reply = try PLB.acceptNum(s, at: 543, digits: 1, options: [.auto], color: 6)
            if reply == 9 { break menu }
            if reply == 1 { try fixedData(s) }
            let called: String? = reply == 2 ? "pl020" : reply == 3 ? "pl030" : reply == 4 ? "pl040" : reply == 5 ? "pl050" : nil
            if let called {
                s.called = called
                try s.call(called)
            }
        }
        s.called = s.caller
        s.caller = s.delLink
    }

    static func fixedData(_ s: Session) throws {
        let c = s.console
        let gl = s.sys.int("level-1") == 1
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("pl180.fixed_title"), at: 131, color: 2)
        c.display(s.toDay, at: 171, color: 2)
        c.display(s.t("pl180.next_folio"), at: 511, color: 2)
        c.display("- [        ]", at: 545, color: 2)
        if gl {
            c.display(s.t("pl180.vat_account"), at: 711, color: 2)
            c.display("- [      ]", at: 745, color: 2)
        }
        c.display(s.t("pl180.details_ok"), at: 1011, color: 2)
        dataEntry: while true {
            var folio = Cobol.truncate(s.sys.int("next-folio"), digits: 8, signed: false)
            c.display(Cobol.z(folio, 8), at: 548, color: 3)
            folio = try PLB.acceptNum(s, at: 548, digits: 8, initial: folio, color: 3)
            s.sys.setInt("next-folio", folio)
            if s.sys.int("next-folio") == 0 { continue }
            if gl {
                var vat = Cobol.truncate(s.sys.int("vat-ac"), digits: 6, signed: false)
                c.display(Cobol.z(vat, 6), at: 748, color: 3)
                vat = try PLB.acceptNum(s, at: 748, digits: 6, initial: vat, color: 3)
                s.sys.setInt("vat-ac", vat)
            }
            while true {
                let r = try c.accept(at: 1048, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                if r == "N" { continue dataEntry }
                if r == "Y" { return }
            }
        }
    }
}
