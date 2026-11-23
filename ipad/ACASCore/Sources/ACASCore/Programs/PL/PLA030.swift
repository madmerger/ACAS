import Foundation

/// purchase/pl030.cbl: 仕入取引修正 (Invoice Data Amend)
final class PLA030 {
    static let progName = "PL030 (3.01.01)"
    static func run(_ s: Session) throws { try PLA030(s).main() }

    /// cr-note 節から init01 節の main 段落への GO TO
    struct RestartMain: Error {}

    let s: Session
    var c: Console { s.console }
    let purchase: IndexedFile, invoice: IndexedFile
    let analysis: PLA.CheckedFile
    var purch = PLA.fdArea(PLA.purchLayout)
    var anal = PLA.fdArea(PLA.analLayout)
    /// invoice-file のレコード領域
    var invArea = [UInt8](repeating: 0, count: 129)
    var ih = Record(PLA.invHeaderLayout)
    var lines: [Record] = []
    var wsReply = " "
    var z = 0
    var wsDate = ""
    var vatCode: Int64 = 0
    var i = 0, j = 0
    var lin = 0
    var escapeCode = " "
    var newScreen = 0
    var wsNet: Int64 = 0, wsVat: Int64 = 0
    var amtOk6: Int64 = 0, amtOk7: Int64 = 0
    var wsDayes: Int64 = 0
    var crt: Int { c.crtStatus }

    init(_ s: Session) {
        self.s = s
        purchase = PLA.purchaseFile(s); invoice = PLA.invoiceFile(s)
        analysis = PLA.analysisFile(s)
        lines = (0...41).map { _ in Record(PLA.wsLineLayout) }
    }

    func e9(_ v: Int64) -> String { PLA.ed("z(6)9.99", v, int: 7) }
    func e8(_ v: Int64) -> String { PLA.ed("z(5)9.99", v, int: 6) }
    func ensure(_ n: Int) { while lines.count < n + 2 { lines.append(Record(PLA.wsLineLayout)) } }
    func invKey(_ nos: Int64, _ item: Int64) -> [UInt8] { SJIS.encode(Cobol.z(nos, 8), size: 8) + [UInt8(truncatingIfNeeded: item)] }
    /// WS の invoice-line (75 バイト) への集団 MOVE
    func lineFromArea() -> Record {
        Record(PLA.wsLineLayout, bytes: Array(invArea[0..<75]) + [UInt8](repeating: 0x20, count: 54))
    }

    func main() throws {
        try programStart()
        main: while true {
            do {
                lines = (0...41).map { _ in Record(PLA.wsLineLayout) }
                try invoiceDetails()
                if crt == 2005 || z != 0 || escapeCode == "Q" { break }
                lin = 16
                c.display(" ", at: lin, 1, eraseEOS: true)
                // data-input
                for f in ["ih-p-c", "ih-net", "ih-vat"] { ih.setInt(f, 0) }
                i = 0
                try invLevel1()
                if crt == 2005 { continue main }
                if i != 1 { try endTotals() }
                while true {
                    // more-data
                    c.display(s.t("pl030.further"), at: 1629, color: 2)
                    wsReply = try c.accept(at: 1661, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                    c.display(" ", at: 1601, eraseEOL: true)
                    if wsReply == "Y" { continue main }
                    if wsReply == "N" { break main }
                }
            } catch is RestartMain {
                continue main
            }
        }
        // menu-exit
        s.sys.setInt("pass-value", 0)
        purchase.close(); analysis.close(); invoice.close()
    }

    // MARK: running-totals section

    func runningTotals() {
        var net: Int64 = 0, vat: Int64 = 0
        if i >= 1 {
            ensure(i)
            for k in 1...i where lines[k].str("il-type") != "D" {
                net = Cobol.truncate(net + lines[k].int("il-net"), digits: 9)
                vat = Cobol.truncate(vat + lines[k].int("il-vat"), digits: 9)
            }
        }
        ih.setInt("ih-net", net); ih.setInt("ih-vat", vat)
        c.display(e9(net), at: 1237, color: 3)
        c.display(e9(vat), at: 1255, color: 3)
        c.display(e9(net + vat), at: 1268, color: 3)
    }

    // MARK: write-details section

    func writeError(_ key: String, status: String, invKey: String) throws {
        c.display(s.t(key), at: 2001, color: 4, eraseEOL: true)
        c.display(status, at: 2036, color: 3)
        c.display(PLA.fileStatMsg(s, status), at: 2039, color: 3)
        c.display(invKey, at: 2064, color: 3)
        c.display(s.t("pl030.pl006"), at: 2101, color: 3)
        wsReply = try c.accept(at: 2130, size: 1)
        c.display(" ", at: 2001, eraseEOL: true)
        c.display(" ", at: 2101, eraseEOL: true)
    }

    func writeDetails() throws {
        j += 1
        ensure(j)
        lines[j].setInt("il-invoice", ih.int("ih-invoice"))
        lines[j].setInt("il-line", Int64(j))
        lines[j].set("il-type", String(ih.int("ih-type")))
        invArea = lines[j].bytes
        let rec = Record(PLA.invHeaderLayout, bytes: invArea)
        var st = invoice.rewrite(rec)
        if st != "00" { st = invoice.write(rec) }
        if st != "00" { try writeError("pl030.pl180", status: st, invKey: rec.str("invoice-key")) }
    }

    // MARK: read-details section

    func readDetails() {
        j = 0
        let n = Int(ih.int("ih-lines"))
        if n <= 0 { return }
        for _ in 0..<n {
            j += 1
            ensure(j)
            if let r = invoice.read(key: invKey(ih.int("ih-invoice"), Int64(j))) { invArea = r.bytes }
            else { for (k, b) in invKey(ih.int("ih-invoice"), Int64(j)).enumerated() { invArea[k] = b } }
            lines[j] = lineFromArea()
        }
    }

    // MARK: inv-level-1 section

    func displayOutline1() {
        i += 1
        c.display(" ", at: lin, 1, eraseEOL: true)
        c.display("(", at: lin, 1, color: 2)
        c.display(Cobol.z(i % 100, 2), at: lin, 2, color: 3)
        c.display(") [  ]", at: lin, 4, color: 2)
        c.display("[          ] [ ]   {         } (", at: lin, 36, color: 2)
        c.display(")", at: lin, 78, color: 2)
    }

    func invLevel1() throws {
        c.display(String(repeating: "-", count: 80), at: 1101, color: 2)
        c.display(s.t("pl030.level_1"), at: 1201, color: 2)
        c.display(s.t("pl030.line"), at: 1216, color: 2)
        c.display("<          >", at: 1236, color: 2)
        c.display("<          >", at: 1254, color: 2)
        c.display("<          >", at: 1267, color: 2)
        c.display(s.t("pl030.code"), at: 1406, color: 2)
        c.display(s.t("pl030.columns"), at: 1436, color: 2)
        while true {
            lin = 16
            while lin <= 23 { displayOutline1(); lin += 1 }
            i = abs(i - (23 - 16))
            j = 1
            c.display(Cobol.z(i % 100, 2), at: 1223, color: 3)
            try getData1()
            if crt == 2005 { return }
            if newScreen == 1 { continue }
            ensure(i)
            if !lines[i].raw("il-description").allSatisfy({ $0 == 0x20 }) && i != 40 && escapeCode != "Q" { continue }
            return
        }
    }

    // MARK: get-data-1 section

    func getData1() throws {
        data1: while true {
            lin = j + 15
            if lin > 23 {
                i = abs(i - 1)
                newScreen = 1
                return
            }
            newScreen = 0
            code: while true {
                // get-code
                ensure(i)
                var wsPa = lines[i].str("il-pa")
                c.display(wsPa, at: lin, 7, color: 3)
                wsPa = try c.accept(at: lin, 7, size: 2, initial: wsPa, options: [.update], color: 3)
                if wsPa == "  " { return }
                if crt == 2005 { return }
                if wsPa == "<<" && i == 1 { continue code }
                if wsPa == "<<" {
                    lin -= 1
                    if lin > 15 {
                        i -= 1
                        j -= 1
                        continue code
                    }
                    i = abs(i - 8)
                    continue data1
                }
                if wsPa == "**" {
                    clearDownLine()
                    i = abs(i - 1)
                    displayOutline1()
                    continue code
                }
                lines[i].set("il-pa", wsPa)
                anal.set("pa-group", wsPa)
                anal.set("pa-system", "P")
                switch analysis.read(key: Array(anal.bytes[0..<3])) {
                case .invalidKey:
                    c.display(s.t("pl030.pa_not_exist"), at: lin, 11, color: 4)
                    continue code
                case .ok(let r): anal = r
                case .notOpen: break
                }
                c.display(PLA.shown(anal.raw("pa-desc")), at: lin, 11, color: 3)
                lines[i].setRaw("il-description", anal.raw("pa-desc"))
                // get-net
                amtOk7 = try PLA.acceptMoney(s, at: lin, 37, digits: 7, value: abs(lines[i].int("il-net")))
                if amtOk7 == 0 { continue code }
                lines[i].setInt("il-net", amtOk7); wsNet = amtOk7
                // get-vat-code
                repeat {
                    vatCode = lines[i].int("il-vat-code")
                    c.display(String(vatCode), at: lin, 50, color: 3)
                    vatCode = Int64(try c.accept(at: lin, 50, size: 1, kind: .numeric, initial: String(vatCode), options: [.update], color: 3)) ?? 0
                } while vatCode > 3
                lines[i].setInt("il-vat-code", vatCode)
                if vatCode == 0 {
                    amtOk6 = 0
                } else {
                    amtOk6 = Calc.vat(net: wsNet, rate: s.sys.int("vat-rate-\(vatCode)"))
                }
                // get-vat-rate
                amtOk6 = try PLA.acceptMoney(s, at: lin, 56, digits: 6, value: amtOk6)
                lines[i].setInt("il-vat", amtOk6); wsVat = amtOk6
                c.display(e9(wsVat + wsNet), at: lin, 68, color: 3)
                runningTotals()
                j += 1
                i += 1
                continue data1
            }
        }
    }

    func clearDownLine() {
        ensure(41)
        if i >= 1 && i <= 39 {
            for k in i...39 {
                lines[k] = lines[k + 1]
                lines[k].setInt("il-line", Int64(k))
            }
        }
        z = 0
        if Int64(i) <= ih.int("ih-lines") {
            let key = invKey(ih.int("ih-invoice"), ih.int("ih-lines"))
            for (k, b) in key.enumerated() { invArea[k] = b }
            invoice.delete(key: key)
            ih.setInt("ih-lines", ih.int("ih-lines") - 1)
        }
    }

    // MARK: end-totals section

    func endTotals() throws {
        totals: while true {
            try totalScreen()
            lin = 15
            c.display(" ", at: lin, 1, eraseEOS: true)
            c.display("*********************", at: 1660, color: 2)
            for l in [17, 18, 19] {
                c.display("*", at: l, 60, color: 2)
                c.display("*", at: l, 80, color: 2)
            }
            c.display("*********************", at: 2060, color: 2)
            c.display(s.t("pl030.ok_to_store"), at: 1761, color: 2)
            c.display(s.t("pl030.yn"), at: 1968, color: 2)
            while true {
                wsReply = try c.accept(at: 1977, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                if wsReply == "N" { continue totals }
                if wsReply == "Y" { break totals }
            }
        }
        ih.set("ih-status", "P")
        i = abs(i - 1)
        ih.setInt("ih-lines", Int64(i))
        invArea = Array(ih.bytes[0..<100]) + [UInt8](repeating: 0x20, count: 29)
        let rec = Record(PLA.invHeaderLayout, bytes: invArea)
        if invoice.rewrite(rec) != "00" { try writeError("pl030.pl186", status: invoice.status, invKey: rec.str("invoice-key")) }
        j = 0
        for _ in 0..<i { try writeDetails() }
        lin = 11
        s.sys.setInt("p-flag-i", 1)
        c.display(" ", at: lin, 1, eraseEOS: true)
    }

    // MARK: total-screen section

    func totalScreen() throws {
        c.display(" ", at: 11, 1, eraseEOS: true)
        c.display(String(repeating: "-", count: 80), at: 1101, color: 2)
        c.display(s.t("pl030.level_1"), at: 1201, color: 2)
        c.display(s.t("pl030.t_net_vat"), at: 1325, color: 2)
        c.display(s.t("pl030.t_gross_days"), at: 1354, color: 2)
        c.display(s.t("pl030.sub_totals"), at: 1504, color: 2)
        c.display("{          }   {         }", at: 1525, color: 2)
        c.display("{          }     [  ]", at: 1554, color: 2)
        c.display(s.t("pl030.prompt_disc"), at: 1704, color: 2)
        c.display("[          ]", at: 1725, color: 2)
        c.display("{          }     [  ]", at: 1754, color: 2)
        c.display(s.t("pl030.shipping"), at: 1904, color: 2)
        c.display("[          ]   [         ]", at: 1925, color: 2)
        c.display("{          }", at: 1954, color: 2)
        c.display("------------   -----------", at: 2225, color: 2)
        c.display("------------", at: 2254, color: 2)
        c.display(s.t("pl030.itemised"), at: 2304, color: 2)
        c.display("{          }   {         }", at: 2325, color: 2)
        c.display("{          }", at: 2354, color: 2)
        c.display(e9(ih.int("ih-net")), at: 1526, color: 3)
        c.display(e8(ih.int("ih-vat")), at: 1541, color: 3)
        c.display(e9(ih.int("ih-net") + ih.int("ih-vat")), at: 1555, color: 3)
        // get-days
        wsDayes = abs(ih.int("ih-days")) % 100
        c.display(Cobol.z(wsDayes, 2), at: 1572, color: 3)
        if ih.int("ih-type") != 2 {
            ih.setInt("ih-days", 0)
        } else {
            wsDayes = Int64(try c.accept(at: 1572, size: 2, kind: .numeric, initial: Cobol.z(wsDayes, 2), options: [.update], color: 3)) ?? 0
            ih.setInt("ih-days", wsDayes)
            // get-extra
            repeat {
                amtOk7 = try PLA.acceptMoney(s, at: 17, 26, digits: 7, value: ih.int("ih-deduct-amt"))
            } while amtOk7 >= 100000
            ih.setInt("ih-deduct-amt", amtOk7 % 100000)
            if ih.int("ih-deduct-amt") == 0 {
                ih.setInt("ih-deduct-vat", 0); ih.setInt("ih-deduct-days", 0)
            } else {
                c.display(e9(amtOk7), at: 1755, color: 3)
                // ws-days (日付編集域の 2 桁英数字) を作業域に流用している
                var wsDays = Cobol.z(abs(ih.int("ih-deduct-days")) % 100, 2)
                c.display(wsDays, at: 1772, color: 3)
                wsDays = try c.accept(at: 1772, size: 2, initial: wsDays, options: [.update], color: 3)
                ih.setInt("ih-deduct-days", wsDays.unicodeScalars.reduce(Int64(0)) { $0 * 10 + Int64($1.value & 0x0F) })
            }
        }
        // get-carriage
        amtOk7 = try PLA.acceptMoney(s, at: 19, 26, digits: 7, value: abs(ih.int("ih-carriage")))
        ih.setInt("ih-carriage", amtOk7)
        amtOk6 = Calc.vat(net: ih.int("ih-carriage"), rate: s.sys.int("vat-rate-1"))
        amtOk6 = try PLA.acceptMoney(s, at: 19, 41, digits: 6, value: amtOk6)
        ih.setInt("ih-c-vat", amtOk6)
        c.display(e9(ih.int("ih-carriage") + ih.int("ih-c-vat")), at: 1955, color: 3)
        c.display(e9(ih.int("ih-net") + ih.int("ih-carriage")), at: 2326, color: 3)
        c.display(e8(ih.int("ih-vat") + ih.int("ih-c-vat")), at: 2341, color: 3)
        c.display(e9(ih.int("ih-net") + ih.int("ih-carriage") + ih.int("ih-vat") + ih.int("ih-c-vat")), at: 2355, color: 3)
        c.display(s.t("pl030.ok"), at: 2374, color: 2)
        wsReply = try c.accept(at: 2379, size: 1, color: 6).uppercased()
    }

    // MARK: invoice-details section

    func mainDisplayEnd() { c.display(s.t("pl030.type_prompt"), at: 1001, color: 2) }

    func invoiceDetails() throws {
        c.display(" ", at: 101, eraseEOS: true)
        c.display(PLA030.progName, at: 101, color: 2)
        c.display(s.t("pl030.title"), at: 133, color: 2)
        wsDate = PLA.toDayDisplay(s)
        c.display(wsDate, at: 171, color: 2)
        c.display("****************************************", at: 441, color: 2)
        c.display(s.t("pl030.box_date"), at: 541, color: 2)
        c.display(s.t("pl030.box_order"), at: 641, color: 2)
        c.display(s.t("pl030.box_folio"), at: 741, color: 2)
        c.display("****************************************", at: 841, color: 2)
        mainDisplayEnd()
        while true {
            // invoice-enter
            ih.setInt("ih-invoice", 0)
            c.display("00000000", at: 750, color: 3)
            ih.setInt("ih-invoice", Int64(try c.accept(at: 750, size: 8, kind: .numeric, initial: "00000000", options: [.update], color: 3)) ?? 0)
            if ih.int("ih-invoice") == 0 || crt == 2005 {
                z = 1
                return
            }
            let key = invKey(ih.int("ih-invoice"), 0)
            guard let r = invoice.read(key: key) else {
                for (k, b) in key.enumerated() { invArea[k] = b }
                c.display(s.t("pl030.pl187"), at: 1640, color: 2)
                continue
            }
            invArea = r.bytes
            ih = Record(PLA.invHeaderLayout, bytes: Array(invArea[0..<100]) + [UInt8](repeating: 0x20, count: 29))
            c.display(" ", at: 1640, eraseEOL: true)
            if ih.str("ih-status").uppercased() == "Z" {
                c.display(s.t("pl030.pl188"), at: 1601, color: 2, eraseEOL: true)
                continue
            }
            break
        }
        c.display(" ", at: 1601, eraseEOL: true)
        wsDate = PLA.dateDisplay(s, ih.int("ih-date"))
        readDetails()
        // date-input
        while true {
            c.display(wsDate, at: 548, color: 3)
            wsDate = try c.accept(at: 548, size: 10, initial: wsDate, options: [.update], color: 3)
            if crt == 2005 || Cobol.rtrim(wsDate).isEmpty {
                z = 1
                return
            }
            let v = PLA.validateDate(s, wsDate)
            wsDate = v.uk
            if v.bin == 0 { continue }
            ih.setInt("ih-date", Int64(v.bin))
            break
        }
        while true {
            // supplier-input
            c.display(ih.str("ih-supplier"), at: 572, color: 3)
            ih.set("ih-supplier", try c.accept(at: 572, size: 7, initial: ih.str("ih-supplier"), options: [.update], color: 3).uppercased())
            if crt == 2005 || Cobol.rtrim(ih.str("ih-supplier")).isEmpty {
                escapeCode = "Q"
                return
            }
            purch.set("purch-key", ih.str("ih-supplier"))
            if let p = purchase.read(key: ih.str("ih-supplier")) { purch = p; break }
        }
        c.display(purch.str("purch-name"), at: 301, color: 3)
        z = 1
        let addr = Array(purch.str("purch-address"))
        let delim = s.sys.str("pl-delim").first ?? " "
        for l in [4, 5, 6, 7] {
            c.display(PLA.unstring(addr, delim: delim, pointer: &z, size: 36), at: l, 1, color: 3)
        }
        var last = Cobol.x("", 36)
        if z >= 1 && z <= addr.count {
            last = Cobol.x(String(addr[(z - 1)..<min(addr.count, z - 1 + 36)]), 36)
            z = min(addr.count, z - 1 + 36) + 1
        }
        z %= 100
        c.display(last, at: 801, color: 3)
        // order-input / ref-input
        c.display(ih.str("ih-order"), at: 669, color: 3)
        ih.set("ih-order", try c.accept(at: 669, size: 10, initial: ih.str("ih-order"), options: [.update], color: 3))
        c.display(ih.str("ih-ref"), at: 769, color: 3)
        ih.set("ih-ref", try c.accept(at: 769, size: 10, initial: ih.str("ih-ref"), options: [.update], color: 3))
        while true {
            // type-input
            let t = String(ih.int("ih-type"))
            c.display(t, at: 1007, color: 3)
            ih.setInt("ih-type", Int64(try c.accept(at: 1007, size: 1, kind: .numeric, initial: t, options: [.update], color: 3)) ?? 0)
            if ih.int("ih-type") == 0 { return }
            if ih.int("ih-type") > 3 { continue }
            if ih.int("ih-type") == 3 {
                try crNote()
                if escapeCode == "Q" {
                    mainDisplayEnd()
                    continue
                }
            }
            z = 0
            return
        }
    }

    // MARK: cr-note section

    func crNote() throws {
        func mainDisplay() { for l in 12...16 { c.display(" ", at: l, 1, eraseEOL: true) } }
        mainDisplay()
        input: while true {
            c.display(s.t("pl030.invoice_to_credit"), at: 1201, color: 2)
            let shown = Cobol.z(abs(ih.int("ih-cr")) % 100_000_000, 8)
            c.display(shown, at: 1222, color: 3)
            let cr = Int64(try c.accept(at: 1222, size: 8, kind: .numeric, initial: shown, options: [.update], color: 3)) ?? 0
            ih.setInt("ih-cr", cr)
            if cr == 0 { mainDisplay(); return }
            if cr == 99999999 { escapeCode = "Q"; return }
            escapeCode = " "
            let key = invKey(cr, 0)
            if let r = invoice.read(key: key) {
                invArea = r.bytes
                c.display(" ", at: 1301, eraseEOL: true)
                if r.int("ih-type") != 2 {
                    c.display(s.t("pl030.pl184"), at: 1301, color: 2)
                    continue input
                }
                if r.str("ih-supplier") != purch.str("purch-key") {
                    c.display(s.t("pl030.pl190"), at: 1301, color: 2)
                    continue input
                }
                mainDisplay()
                return
            }
            for (k, b) in key.enumerated() { invArea[k] = b }
            c.display(s.t("pl030.pl189"), at: 1332, color: 2)
            while true {
                // check-inv-no-ok
                c.display(s.t("pl030.use_this_invoice"), at: 1401, color: 2)
                c.display(s.t("pl030.use_this_note1"), at: 1501, color: 2)
                c.display(s.t("pl030.use_this_note2"), at: 1601, color: 2)
                wsReply = try c.accept(at: 1439, size: 1, initial: "N", options: [.update], color: 6).uppercased()
                if wsReply == "Y" { mainDisplay(); return }
                // "go to main" は init01 節の main 段落へ飛ぶ (レガシーの動作)
                if wsReply == "N" { throw RestartMain() }
            }
        }
    }

    // MARK: program-start section

    func programStart() throws {
        c.display(" ", at: 101, eraseEOS: true)
        if PLA.fileStatus(s, 15) != 1 {
            try PLA.maps99(s, 29)
            try PLA.maps99(s, 15)
        }
        _ = purchase.open(); analysis.open()
        _ = invoice.open()
    }
}
