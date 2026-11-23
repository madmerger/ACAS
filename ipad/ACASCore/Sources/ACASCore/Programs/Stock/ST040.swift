import Foundation

/// stock/st040.cbl: Stock Activity Reset (期間・年度累計のクリア)
enum ST040 {
    static let progName = "ST040 (3.01.06)"

    static func run(_ s: Session) throws {
        let c = s.console
        let convDate = ST.convDate(s)
        // aa010-Questions
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("st040.title"), at: 131, color: 2)
        c.display(convDate, at: 171, color: 2)
        c.display(s.t("st040.can_clear"), at: 410, color: 2)
        let cur = s.sys.str("stk-period-cur")
        c.display(s.t(cur == "Q" ? "st040.quarter" : (cur == "W" ? "st040.week" : "st040.month")), at: 427, color: 2)
        c.display(s.t("st040.totals"), at: 434, color: 2)
        c.display(s.t("st040.clear_year"), at: 610, color: 2)
        // aa020-Accept-Loop
        var replyPeriod = "N", replyYear = "N"
        while true {
            replyPeriod = "N"; replyYear = "N"
            replyPeriod = try c.accept(at: 444, size: 1, initial: replyPeriod, options: [.update], color: 6).uppercased()
            if replyPeriod != "Y" && replyPeriod != "N" {
                c.display(s.t("st040.st402"), at: 23, 1, color: 4, highlight: true)
                continue
            }
            replyYear = try c.accept(at: 659, size: 1, initial: replyYear, options: [.update], color: 6).uppercased()
            if replyYear != "Y" && replyYear != "N" {
                c.display(s.t("st040.st402"), at: 23, 1, color: 4, highlight: true)
                continue
            }
            break
        }
        c.display(" ", at: 23, 1, eraseEOL: true)
        let clearPeriod = replyPeriod == "Y", clearYear = replyYear == "Y"
        if !clearYear && !clearPeriod { return }
        if clearPeriod { c.display(s.t("st040.will_clear_period"), at: 801, color: 3, highlight: true) }
        if clearYear { c.display(s.t("st040.will_clear_year"), at: 901, color: 3, highlight: true) }
        // aa030-U-Sure
        while true {
            if s.sys.int("stk-activity-rep-run") == 0 {
                c.display(s.t("st040.no_audit"), at: 23, 1, color: 6, highlight: true)
                try ST.maps99(s, 45)
                return
            }
            c.display(s.t("st040.sure"), at: 1210, color: 2, highlight: true)
            let reply = try c.accept(at: 1265, size: 1, initial: "N", options: [.update], color: 6).uppercased()
            if reply != "N" && reply != "Y" {
                c.display(s.t("st040.st402"), at: 23, 1, color: 4, highlight: true)
                continue
            }
            if reply == "N" { return }
            break
        }
        c.display(" ", at: 23, 1, eraseEOL: true)
        let f = ST.stockFile(s)
        if f.open() != "00" {
            c.display(s.t("st040.st401"), at: 23, 1, color: 4, highlight: true)
            c.display(f.status, at: 23, 28, color: 2, highlight: true)
            try ST.maps99(s, 45)
            return
        }
        c.display(s.t("st040.updating"), at: 1210, color: 2, highlight: true, eraseEOL: true)
        // ba000-Clear-Totals
        while var rec = f.readNext() {
            if clearPeriod { for n in ST.monthlyTotals { rec.setInt(n, 0) } }
            if clearYear { for m in 1...12 { for k in ST.historyKinds { rec.setInt(k + "\(m)", 0) } } }
            if f.rewrite(rec) != "00" {
                c.display(s.t("st.st000"), at: 23, 1, color: 4, highlight: true)
                c.display(f.status, at: 23, 38, color: 2, highlight: true)
                try ST.maps99(s, 45)
                break
            }
        }
        f.close()
    }
}
