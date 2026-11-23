import Foundation

/// purchase/pl020.cbl: 仕入取引入力 (Invoice Data Entry)
final class PLA020 {
    static let progName = "PL020 (3.01.08)"
    static func run(_ s: Session) throws { try PLA020(s).main() }

    let s: Session
    var c: Console { s.console }
    let purchase: IndexedFile, invoice: IndexedFile
    let analysis: PLA.CheckedFile
    let delInv: PLA.SeqFile
    var purch = PLA.fdArea(PLA.purchLayout)
    var anal = PLA.fdArea(PLA.analLayout)
    var ih = Record(PLA.invHeaderLayout)
    var lines: [Record] = []
    var wsReply = " "
    var z = 0
    var delExists = false
    var wsDate = ""
    var vatCode: Int64 = 0
    var i = 0, j = 0
    var lin = 0, cole = 0
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
        delInv = PLA.SeqFile(s, path: s.ledgers + "delfolio.dat", recSize: 19)
    }

    func e9(_ v: Int64) -> String { PLA.ed("z(6)9.99", v, int: 7) }
    func e8(_ v: Int64) -> String { PLA.ed("z(5)9.99", v, int: 6) }
    func newLine() -> Record { Record(PLA.wsLineLayout) }
    /// invoice-line (i) (1 起点)。添字が範囲外でも落とさない。
    func ensure(_ n: Int) { while lines.count < n + 1 { lines.append(newLine()) } }

    func main() throws {
        wsDate = PLA.toDayDisplay(s)
        try programStart()
        main: while true {
            ih = Record(PLA.invHeaderLayout)
            try invoiceDetails()
            if z != 0 || escapeCode == "Q" { break }
            lin = 16; cole = 1
            c.display(" ", at: lin, cole, eraseEOS: true)
            // data-input
            lines = (0...41).map { _ in newLine() }
            for f in ["ih-deduct-days", "ih-deduct-amt", "ih-discount", "ih-p-c", "ih-net", "ih-vat"] { ih.setInt(f, 0) }
            i = 0
            try invLevel1()
            if crt == 2005 { continue main }
            if i != 1 { try endTotals() }
            while true {
                // more-data
                c.display(s.t("pl020.further"), at: 24, 29, color: 2)
                c.crtStatus = 0
                wsReply = try c.accept(at: 24, 60, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                c.display(" ", at: 24, 1, eraseEOL: true)
                if wsReply == "Y" { continue main }
                if wsReply == "N" { break main }
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
            for k in 1...i {
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

    func writeError(_ status: String, key: String, line1: Int, line2: Int, acceptCol: Int) throws {
        c.display(s.t("pl020.pl180"), at: line1, 1, color: 4, eraseEOL: true)
        c.display(status, at: line1, 36, color: 3)
        c.display(PLA.fileStatMsg(s, status), at: line1, 39, color: 3)
        c.display(key, at: line1, 64, color: 3)
        c.display(s.t("pl020.pl006"), at: line2, 1, color: 3)
        wsReply = try c.accept(at: line2, acceptCol, size: 1)
        c.display(" ", at: line1, 1, eraseEOL: true)
        c.display(" ", at: line2, 1, eraseEOL: true)
    }

    func writeDetails() throws {
        j += 1
        ensure(j)
        lines[j].setInt("il-invoice", ih.int("ih-invoice"))
        lines[j].setInt("il-line", Int64(j))
        lines[j].set("il-type", String(ih.int("ih-type")))
        if invoice.write(Record(PLA.invHeaderLayout, bytes: lines[j].bytes)) != "00" {
            try writeError(invoice.status, key: lines[j].str("invoice-key"), line1: 20, line2: 21, acceptCol: 30)
        }
    }

    // MARK: inv-level-1 section

    func invLevel1() throws {
        c.display(String(repeating: "-", count: 80), at: 1101, color: 2)
        c.display(s.t("pl020.level_1"), at: 1201, color: 2)
        c.display(s.t("pl020.line"), at: 1216, color: 2)
        c.display("[          ]", at: 1236, color: 2)
        c.display("[          ]", at: 1254, color: 2)
        c.display("[          ]", at: 1267, color: 2)
        c.display(s.t("pl020.code"), at: 1405, color: 2)
        c.display(s.t("pl020.columns"), at: 1436, color: 2)
        while true {
            lin = 16
            while lin <= 23 {
                i += 1
                c.display("(", at: lin, 1, color: 2, eraseEOL: true)
                c.display(Cobol.z(i % 100, 2), at: lin, 2, color: 2)
                c.display(") [  ]", at: lin, 4, color: 2)
                c.display("[          ] [ ]   {         } (", at: lin, 36, color: 2)
                c.display(")", at: lin, 78, color: 2)
                lin += 1
            }
            i = abs(i - (23 - 16))
            j = 1
            c.display(Cobol.z(i % 100, 2), at: 1223, color: 3)
            c.crtStatus = 0
            try getData1()
            if crt == 2005 { return }
            if newScreen == 1 { continue }
            ensure(i)
            if !lines[i].raw("il-description").allSatisfy({ $0 == 0x20 }) && i != 40 { continue }
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
                if i > 1 && lines[i].str("il-pa") == "  " { lines[i].set("il-pa", lines[i - 1].str("il-pa")) }
                var wsPa = lines[i].str("il-pa")
                c.display(wsPa, at: lin, 7, color: 3)
                wsPa = try c.accept(at: lin, 7, size: 2, initial: wsPa, options: [.update], color: 3)
                lines[i].set("il-pa", wsPa)
                anal.set("pa-group", wsPa)
                lines[i].set("il-description", "")
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
                anal.set("pa-system", "P")
                switch analysis.read(key: Array(anal.bytes[0..<3])) {
                case .invalidKey:
                    c.display(s.t("pl020.pl186"), at: lin, 11, color: 4)
                    continue code
                case .ok(let r): anal = r
                case .notOpen: break
                }
                c.display(PLA.shown(anal.raw("pa-desc")), at: lin, 11, color: 3)
                lines[i].setRaw("il-description", anal.raw("pa-desc"))
                // get-net
                amtOk7 = try PLA.acceptMoney(s, at: lin, 37, digits: 7, value: 0)
                if amtOk7 == 0 { continue code }
                lines[i].setInt("il-net", amtOk7); wsNet = amtOk7
                // get-vat-code
                repeat {
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

    // MARK: end-totals section

    func endTotals() throws {
        totals: while true {
            c.crtStatus = 0
            try totalScreen()
            if crt == 2005 { return }
            lin = 15
            c.display(" ", at: lin, 1, eraseEOS: true)
            c.display("*********************", at: 1660, color: 2)
            for l in [17, 18, 19] {
                c.display("*", at: l, 60, color: 2)
                c.display("*", at: l, 80, color: 2)
            }
            c.display("*********************", at: 2060, color: 2)
            c.display(s.t("pl020.ok_to_store"), at: 1761, color: 2)
            c.display(s.t("pl020.yn"), at: 1968, color: 2)
            while true {
                wsReply = try c.accept(at: 1977, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                if crt == 2005 { return }
                if wsReply == "N" { continue totals }
                if wsReply == "Y" { break totals }
            }
        }
        ih.set("ih-status", "P")
        i = abs(i - 1)
        ih.setInt("ih-lines", Int64(i))
        if invoice.write(ih) != "00" {
            try writeError(invoice.status, key: ih.str("invoice-key"), line1: 23, line2: 24, acceptCol: 30)
        }
        j = 0
        for _ in 0..<i { try writeDetails() }
        if !delExists {
            s.sys.setInt("next-folio", s.sys.int("next-folio") + 1)
        }
        // del-exists の場合の delete del-inv-nos-file record は順編成ファイルに対しては何も行わない
        lin = 11
        s.sys.setInt("p-flag-i", 1)
        c.display(" ", at: lin, 1, eraseEOS: true)
    }

    // MARK: total-screen section

    func totalScreen() throws {
        while true {
            c.display(" ", at: 11, 1, eraseEOS: true)
            c.display(String(repeating: "-", count: 80), at: 1101, color: 2)
            c.display(s.t("pl020.level_1"), at: 1201, color: 2)
            c.display(s.t("pl020.t_net_vat"), at: 1225, color: 2)
            c.display(s.t("pl020.t_gross_days"), at: 1254, color: 2)
            c.display(s.t("pl020.sub_totals"), at: 1404, color: 2)
            c.display("{          }   {         }", at: 1425, color: 2)
            c.display("{          }     [  ]", at: 1454, color: 2)
            c.display(s.t("pl020.prompt_disc"), at: 1704, color: 2)
            c.display("[          ]", at: 1725, color: 2)
            c.display("{          }     [  ]", at: 1754, color: 2)
            c.display(s.t("pl020.shipping"), at: 1904, color: 2)
            c.display("[          ]   [         ]", at: 1925, color: 2)
            c.display("{          }", at: 1954, color: 2)
            c.display("------------   -----------", at: 2225, color: 2)
            c.display("------------", at: 2254, color: 2)
            c.display(s.t("pl020.itemised"), at: 2304, color: 2)
            c.display("{          }   {         }", at: 2325, color: 2)
            c.display("{          }", at: 2354, color: 2)
            c.display(e9(ih.int("ih-net")), at: 1426, color: 3)
            c.display(e8(ih.int("ih-vat")), at: 1441, color: 3)
            c.display(e9(ih.int("ih-net") + ih.int("ih-vat")), at: 1455, color: 3)
            // get-days
            ih.setInt("ih-days", 0); ih.setInt("ih-carriage", 0)
            if ih.int("ih-type") == 2 { ih.setInt("ih-days", purch.int("purch-credit")) }
            wsDayes = abs(ih.int("ih-days")) % 100
            c.display(Cobol.z(wsDayes, 2), at: 1472, color: 3)
            if ih.int("ih-type") == 2 {
                wsDayes = Int64(try c.accept(at: 1472, size: 2, kind: .numeric, initial: Cobol.z(wsDayes, 2), options: [.update], color: 3)) ?? 0
                ih.setInt("ih-days", wsDayes)
                // get-extra
                repeat {
                    for f in ["ih-extra", "ih-e-vat", "ih-deduct-amt", "ih-deduct-vat", "ih-deduct-days"] { ih.setInt(f, 0) }
                    amtOk7 = try PLA.acceptMoney(s, at: 17, 26, digits: 7, value: ih.int("ih-deduct-amt"))
                } while amtOk7 >= 100000
                ih.setInt("ih-deduct-amt", amtOk7 % 100000)
                if ih.int("ih-deduct-amt") != 0 {
                    c.display(e9(amtOk7), at: 1755, color: 3)
                    c.display(Cobol.z(wsDayes, 2), at: 1772, color: 3)
                    wsDayes = Int64(try c.accept(at: 1772, size: 2, kind: .numeric, initial: Cobol.z(wsDayes, 2), options: [.update], color: 3)) ?? 0
                    ih.setInt("ih-deduct-days", wsDayes)
                }
            }
            // get-carriage
            amtOk7 = try PLA.acceptMoney(s, at: 19, 26, digits: 7, value: 0)
            ih.setInt("ih-carriage", amtOk7)
            amtOk6 = Calc.vat(net: ih.int("ih-carriage"), rate: s.sys.int("vat-rate-1"))
            amtOk6 = try PLA.acceptMoney(s, at: 19, 41, digits: 6, value: amtOk6)
            ih.setInt("ih-c-vat", amtOk6)
            c.display(e9(ih.int("ih-carriage") + ih.int("ih-c-vat")), at: 1955, color: 3)
            c.display(e9(ih.int("ih-net") + ih.int("ih-carriage")), at: 2326, color: 3)
            c.display(e8(ih.int("ih-vat") + ih.int("ih-c-vat")), at: 2341, color: 3)
            c.display(e9(ih.int("ih-net") + ih.int("ih-carriage") + ih.int("ih-vat") + ih.int("ih-c-vat")), at: 2355, color: 3)
            c.display(s.t("pl020.ok"), at: 2374, color: 2)
            wsReply = try c.accept(at: 2379, size: 1, color: 3).uppercased()
            if wsReply == "Y" { return }
        }
    }

    // MARK: invoice-details section

    func invoiceDetails() throws {
        details: while true {
            c.display(" ", at: 101, eraseEOS: true)
            c.display(PLA020.progName, at: 101, color: 2)
            c.display(s.t("pl020.title"), at: 132, color: 2)
            wsDate = PLA.toDayDisplay(s)
            c.display(wsDate, at: 171, color: 2)
            c.display("****************************************", at: 441, color: 2)
            c.display(s.t("pl020.box_date"), at: 541, color: 2)
            c.display(s.t("pl020.box_order"), at: 641, color: 2)
            c.display(s.t("pl020.box_folio"), at: 741, color: 2)
            c.display("****************************************", at: 841, color: 2)
            c.display(s.t("pl020.f1_new"), at: 911, color: 2)
            c.display(s.t("pl020.type_prompt"), at: 1001, color: 2)
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
            supplier: while true {
                // supplier-input
                c.crtStatus = 0
                ih.set("ih-supplier", try c.accept(at: 572, size: 7, color: 3).uppercased())
                if ih.str("ih-supplier") == "CREATE9" {
                    c.display(s.t("pl020.creating_invoice_file"), at: 2301, color: 2)
                    invoice.close()
                    invoice.openOutput()
                    invoice.close()
                    PLA.setFileStatus(s, 26, 1)
                    _ = invoice.open()
                }
                // supplier-test
                if ih.str("ih-supplier") == "NEW    " || crt == 1001 {
                    // new-supplier
                    purchase.close(); invoice.close(); analysis.close()
                    try s.call("pl025")
                    try programStart()
                    continue details
                }
                if Cobol.rtrim(ih.str("ih-supplier")).isEmpty {
                    escapeCode = "Q"
                    return
                }
                purch.set("purch-key", ih.str("ih-supplier"))
                guard let p = purchase.read(key: ih.str("ih-supplier")) else {
                    try PLA.maps99(s, 21)
                    continue supplier
                }
                purch = p
                break
            }
            c.display("                       ", at: 911)
            c.display(" ", at: 23, 1, eraseEOL: true)
            if delExists {
                getADeletedInvoice()
            } else {
                if s.sys.int("next-folio") == 0 { s.sys.setInt("next-folio", 1) }
                ih.setInt("ih-invoice", s.sys.int("next-folio"))
            }
            c.display(Cobol.z(ih.int("ih-invoice"), 8), at: 750, color: 3)
            c.display(purch.str("purch-name"), at: 301, color: 3)
            z = 1
            let addr = Array(purch.str("purch-address"))
            let delim = s.sys.str("pl-delim").first ?? " "
            for l in [4, 5, 6, 7] {
                c.display(PLA.unstring(addr, delim: delim, pointer: &z, size: 36), at: l, 1, color: 3)
            }
            // 区切り無しの UNSTRING: ポインタ位置から 36 桁
            var last = Cobol.x("", 36)
            if z >= 1 && z <= addr.count {
                last = Cobol.x(String(addr[(z - 1)..<min(addr.count, z - 1 + 36)]), 36)
                z = min(addr.count, z - 1 + 36) + 1
            }
            c.display(last, at: 801, color: 3)
            ih.set("ih-order", try c.accept(at: 669, size: 10, color: 3))
            ih.set("ih-ref", try c.accept(at: 769, size: 10, color: 3))
            while true {
                // type-input
                ih.setInt("ih-type", Int64(try c.accept(at: 1007, size: 1, kind: .numeric, color: 3)) ?? 0)
                if ih.int("ih-type") == 0 { continue details }
                if ih.int("ih-type") <= 3 { break }
            }
            c.display(" ", at: 1001, eraseEOL: true)
            c.display(">>> ", at: 1031, color: 2)
            c.display(s.t("pl020.type_\(ih.int("ih-type"))"), at: 1035, color: 2)
            ih.setInt("ih-cr", 0)
            if ih.int("ih-type") == 3 {
                try crNote()
                if escapeCode == "Q" { continue details }
            }
            z = 0
            return
        }
    }

    // MARK: get-a-deleted-invoice section

    func getADeletedInvoice() {
        if delExists {
            while let r = delInv.read() {
                let nos = Int64(String(decoding: r[0..<8], as: UTF8.self)) ?? 0
                if nos == 0 { continue }
                ih.setInt("ih-invoice", nos)
                c.display(s.t("pl020.using_deleted"), at: 345, color: 2)
                return
            }
            delInv.close()
            delInv.openOutput()
            c.display("                             ", at: 345)
        }
        // レガシーどおり next-folio ではなく next-invoice を使う
        ih.setInt("ih-invoice", s.sys.int("next-invoice"))
        delExists = false
    }

    // MARK: cr-note section

    func crNote() throws {
        func clear() { for l in 12...16 { c.display(" ", at: l, 1, eraseEOL: true) } }
        clear()
        input: while true {
            c.display(s.t("pl020.invoice_to_credit"), at: 1201, color: 2)
            let cr = Int64(try c.accept(at: 1222, size: 8, kind: .numeric, initial: "00000000", options: [.update], color: 3)) ?? 0
            if crt == 2005 { escapeCode = "Q"; return }
            ih.setInt("ih-cr", cr)
            if cr == 0 { clear(); return }
            if cr == 99999999 { escapeCode = "Q"; return }
            escapeCode = " "
            if let r = invoice.read(key: SJIS.encode(Cobol.z(cr, 8), size: 8) + [0]) {
                c.display(" ", at: 23, 1, eraseEOL: true)
                if r.int("ih-type") != 2 {
                    c.display(s.t("pl020.pl184"), at: 23, 1, color: 4)
                    continue input
                }
                if r.str("ih-supplier") != purch.str("purch-key") {
                    c.display(s.t("pl020.pl187"), at: 23, 1, color: 4)
                    continue input
                }
                clear()
                return
            }
            c.display(s.t("pl020.pl181"), at: 23, 1, color: 4)
            while true {
                // check-inv-no-ok
                c.display(s.t("pl020.use_this_invoice"), at: 1401, color: 2)
                c.display(s.t("pl020.use_this_note1"), at: 1501, color: 2)
                c.display(s.t("pl020.use_this_note2"), at: 1601, color: 2)
                wsReply = try c.accept(at: 1439, size: 1, initial: "N", options: [.update], color: 6).uppercased()
                if wsReply == "Y" { clear(); return }
                if wsReply == "N" { clear(); continue input }
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
        if PLA.fileStatus(s, 26) != 1 {
            c.display(s.t("pl020.creating_invoice_file") + " ", at: 23, 1, color: 2)
            invoice.openOutput()
            invoice.close()
            PLA.setFileStatus(s, 26, 1)
        }
        _ = invoice.open()
        if !delInv.openInput() {
            delExists = false
            return
        }
        delInv.close()
        _ = delInv.openInput()
        delExists = true
    }
}
