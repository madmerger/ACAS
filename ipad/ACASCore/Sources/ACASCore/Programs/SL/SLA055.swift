import Foundation

/// sales/sl055.cbl: Invoice Post Extract (請求書転記抽出)
enum SLA055 {
    static let progName = "SL055 (3.01.06)"

    final class WS {
        var pFlag = 0
        var invAmt: Int64 = 0
        var emergency = ""
        var vExists = 0
        var work2: Int64 = 0
        var work3: Int64 = 0
        var vatT: Int64 = 0, vatrT: Int64 = 0, carrT: Int64 = 0, discT: Int64 = 0
        var vatV: Int64 = 0, vatrV: Int64 = 0, carrV: Int64 = 0, discV: Int64 = 0
        /// FD レコード領域 (ファイルごとに 1 つ。読み込み失敗時は前の内容が残る)
        var value = Record(SLA070.valueLayout)
        var anal = Record(SLA070.analysisLayout)
        var valueFile: IndexedFile!, analFile: IndexedFile!
    }

    static func m9(_ v: Int64) -> Int64 { Cobol.truncate(v, digits: 9, signed: true) }
    static func m5(_ v: Int64) -> Int64 { Cobol.truncate(v, digits: 5, signed: true) }

    static func run(_ s: Session) throws {
        let c = s.console
        let w = WS()
        w.emergency = s.l10n.raw("sl055.emergency")
        w.valueFile = SLA070.valueFile(s)
        w.analFile = SLA070.analysisFile(s)
        if w.valueFile.open() != "00" {
            w.valueFile.close()
            w.valueFile.openOutput()
        }
        w.valueFile.close()
        if SLA.fileStatus(s, 15) != 1 {
            s.processFunc = 1; s.subFunction = 1
            _ = try s.call("sl070")
            if SLA.fileStatus(s, 15) != 1 {
                try SLA.maps99(s, 29)
                try SLA.maps99(s, 15)
                return
            }
        }
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("sl055.title"), at: 1201, color: 2)
        c.display(SLA.convertDate(s), at: 171, color: 2)
        c.display(s.t("sl055.working"), at: 1201, color: 2)
        let inv = SLA.invoiceFile(s)
        let invPath = s.ledgers + "invoice.dat"
        _ = inv.open(); _ = w.valueFile.open(); _ = w.analFile.open()
        // open extend open-item-file-2: ファイルが無いと declarative (use after error) が走り goback する。
        // 後続の「open output」には到達しない (レガシー実測)
        let oi2Path = s.ledgers + "openitm2.dat"
        if !s.store.exists(oi2Path) {
            c.display(s.t("sl055.sl121"), at: 23, 1)
            c.display("35", at: 23, 41)
            c.display(SLA.fileStatMsg(s, "35"), at: 23, 44)
            c.display(s.t("sl055.sl002"), at: 24, 1)
            _ = try c.accept(at: 24, 33, size: 1)
            return
        }
        func addValue(_ t: Int64, _ v: Int64) {
            for n in ["va-t-this", "va-t-year"] { w.value.setInt(n, Cobol.truncate(w.value.int(n) + t, digits: 5, signed: false)) }
            for n in ["va-v-this", "va-v-year"] { w.value.setInt(n, Cobol.truncate(w.value.int(n) + v, digits: 10, signed: true)) }
        }
        func rewriteInvoice(_ bytes: [UInt8]) {
            // rewrite invoice-record (134 バイト)
            _ = s.store.rewrite(invPath, key: Array(bytes[0..<10]), data: Array(bytes[0..<134]))
        }
        inv.startFirst()
        loop: while let rec = inv.readNext() {
            var ih = rec
            if ih.int("ih-test") != 0 {
                var il = Record(SLA.ilLayout, bytes: Array(ih.bytes[0..<80]))
                let upd = il.str("il-update")
                if upd == "z" || upd == "Z" { continue }
                if il.str("il-product").hasPrefix("/") { continue }
                setCode(w, "S" + Cobol.x(il.str("il-pa"), 2))
                readValueOrCreate(w)
                let net = il.str("il-type") != "3" ? il.int("il-net") : -il.int("il-net")
                addValue(1, net)
                if w.vExists == 0 { _ = w.valueFile.write(w.value) } else { _ = w.valueFile.rewrite(w.value) }
                if second(w) == " " { continue }
                setSecond(w, " ")
                guard let v = w.valueFile.read(key: Array(w.value.bytes[0..<3])) else { continue }
                w.value = v
                addValue(1, net)
                _ = w.valueFile.rewrite(w.value)
                il["il-update"] = "Z"
                var bytes = ih.bytes
                bytes.replaceSubrange(0..<80, with: il.bytes)
                rewriteInvoice(bytes)
                continue
            }
            // da020-Header-Analysis
            let analysed = ["z", "Z"].contains(ih.str("ih-update"))
            let applied = ["z", "Z"].contains(ih.str("ih-status"))
            let type = ih.int("ih-type")
            var skip = false
            if analysed && applied { continue }
            if type == 4 {
                skip = true
            } else if ih.str("ih-status") == "P" || ih.str("ih-status-l") != "L" {
                w.pFlag = 1
                skip = true
            }
            if skip {
                // da030-Skip-Invoice
                var key = Record(SLA.ihLayout)
                key.setInt("ih-invoice", Cobol.truncate(ih.int("ih-invoice") + 1, digits: 8, signed: false))
                key["ih-letter"] = " "
                key.setInt("ih-test", 0)
                if !inv.start(notLessThan: Array(key.bytes[0..<10])) { break loop }
                continue
            }
            extract(s, w, &ih, applied: applied, oi2Path)
            if analysed {
                rewriteInvoice(ih.bytes)
                continue
            }
            func signed(_ v: Int64) -> Int64 { type == 3 ? m9(-v) : v }
            w.work2 = signed(m9(ih.int("ih-c-vat") + ih.int("ih-vat") + ih.int("ih-e-vat")))
            if w.work2 != 0 && type != 1 { w.vatT = m5(w.vatT + 1); w.vatV = m9(w.vatV + w.work2) }
            if w.work2 != 0 && type == 1 { w.vatrT = m5(w.vatrT + 1); w.vatrV = m9(w.vatrV + w.work2) }
            w.work2 = signed(ih.int("ih-carriage"))
            if w.work2 != 0 { w.carrT = m5(w.carrT + 1); w.carrV = m9(w.carrV + w.work2) }
            w.work2 = signed(ih.int("ih-deduct-amt"))
            if w.work2 != 0 { w.discT = m5(w.discT + 1); w.discV = m9(w.discV + w.work2) }
            ih["ih-update"] = "Z"
            rewriteInvoice(ih.bytes)
        }
        // da040-Close-Files
        func special(_ group: String, _ t: Int64, _ v: Int64) {
            setCode(w, "S" + group)
            w.work3 = t; w.work2 = v
            readValueOrCreate(w)
            addValue(w.work3, w.work2)
            if w.vExists == 0 { _ = w.valueFile.write(w.value) } else { _ = w.valueFile.rewrite(w.value) }
            setSecond(w, " ")
            guard let r = w.valueFile.read(key: Array(w.value.bytes[0..<3])) else { return }
            w.value = r
            addValue(w.work3, w.work2)
            _ = w.valueFile.rewrite(w.value)
        }
        special("vo", w.vatT, w.vatV)
        special("vp", w.vatrT, w.vatrV)
        special("zc", w.carrT, w.carrV)
        special("zd", w.discT, w.discV)
        inv.close(); w.analFile.close(); w.valueFile.close()
        SLA.setFileStatus(s, 18, 1)
        if w.pFlag != 0 {
            c.display(s.t("sl055.sl122"), at: 23, 1)
            c.display(s.t("sl055.sl002"), at: 24, 1)
            _ = try c.accept(at: 24, 33, size: 1)
        }
    }

    // va-code = va-system + va-group (va-first, va-second)
    static func setCode(_ w: WS, _ code: String) { w.value["va-code"] = Cobol.x(code, 3) }
    static func second(_ w: WS) -> String { String(Array(w.value.str("va-code"))[2]) }
    static func setSecond(_ w: WS, _ ch: String) { w.value["va-code"] = String(w.value.str("va-code").prefix(2)) + ch }

    /// read value-file invalid key perform db000-Create, move zero to v-exists
    static func readValueOrCreate(_ w: WS) {
        w.vExists = 1
        if let r = w.valueFile.read(key: Array(w.value.bytes[0..<3])) {
            w.value = r
        } else {
            create(w)
            w.vExists = 0
        }
    }

    static func valueFromAnalysis(_ w: WS) {
        var v = Record(SLA070.valueLayout)
        v.bytes.replaceSubrange(0..<w.anal.bytes.count, with: w.anal.bytes)
        for n in ["va-t-this", "va-t-last", "va-t-year", "va-v-this", "va-v-last", "va-v-year"] { v.setInt(n, 0) }
        w.value = v
    }
    static func setPaCode(_ w: WS, _ code: String) {
        let a = Array(Cobol.x(code, 3))
        w.anal["pa-system"] = String(a[0]); w.anal["pa-first"] = String(a[1]); w.anal["pa-second"] = String(a[2])
    }

    // MARK: db000-Create section

    static func create(_ w: WS) {
        while true {
            setPaCode(w, w.value.str("va-code"))
            if let a = w.analFile.read(key: Array(w.anal.bytes[0..<3])) {
                w.anal = a
                break
            }
            // db010-Create-Anal
            setPaCode(w, w.value.str("va-code"))
            w.anal.setInt("pa-gl", 0)
            w.anal["pa-print"] = ""
            w.anal["pa-desc"] = w.emergency
            _ = w.analFile.write(w.anal)
            if w.anal.str("pa-second") != " " {
                w.anal["pa-second"] = " "
                _ = w.analFile.write(w.anal)
            }
        }
        valueFromAnalysis(w)
        if second(w) == " " { return }
        let save = w.value.str("va-code")
        setSecond(w, " ")
        setPaCode(w, w.value.str("va-code"))
        guard let a = w.analFile.read(key: Array(w.anal.bytes[0..<3])) else {
            setPaCode(w, save)
            return
        }
        w.anal = a
        valueFromAnalysis(w)
        _ = w.valueFile.write(w.value)
        setCode(w, save); setPaCode(w, save)
        guard let b = w.analFile.read(key: Array(w.anal.bytes[0..<3])) else { return }
        w.anal = b
        valueFromAnalysis(w)
    }

    // MARK: dd000-Extract section

    static func extract(_ s: Session, _ w: WS, _ ih: inout Record, applied: Bool, _ oi2Path: String) {
        if applied { return }
        var oi = Record(SLA.oiLayout)
        SLA.initialize(&oi)
        let type = ih.int("ih-type")
        oi.setInt("oi-p-c", ih.int("ih-p-c"))
        oi.setInt("oi-invoice", ih.int("ih-invoice"))
        oi["oi-customer"] = ih.str("ih-customer")
        oi.setInt("oi-date", ih.int("ih-date"))
        oi["oi-description"] = ih.str("ih-order")
        let sign: Int64 = type == 3 ? -1 : 1
        for n in ["net", "extra", "carriage", "vat", "c-vat", "e-vat", "discount"] { oi.setInt("oi-\(n)", sign * ih.int("ih-\(n)")) }
        oi.setInt("oi-paid", 0)
        oi.setInt("oi-deduct-amt", sign * ih.int("ih-deduct-amt"))
        oi.setInt("oi-deduct-vat", sign * ih.int("ih-deduct-vat"))
        oi.setInt("oi-deduct-days", ih.int("ih-deduct-days"))
        oi.setInt("oi-type", type)
        oi["oi-applied"] = " "; oi["oi-unapl"] = " "; oi["oi-hold-flag"] = " "
        oi.setInt("oi-cr", ih.int("ih-cr"))
        if type != 1 {
            w.invAmt = m9(ih.int("ih-net") + ih.int("ih-extra") + ih.int("ih-carriage") + ih.int("ih-discount") + ih.int("ih-vat")
                + ih.int("ih-c-vat") + ih.int("ih-e-vat") + ih.int("ih-deduct-amt") + ih.int("ih-deduct-vat"))
        }
        if type == 2 { SLA.addSys4(s, 2, w.invAmt) }
        if type == 3 { SLA.addSys4(s, 3, w.invAmt) }
        ih["ih-status"] = "Z"
        ih["ih-status-a"] = "A"
        s.store.appendRaw(oi2Path, oi.bytes)
    }
}
