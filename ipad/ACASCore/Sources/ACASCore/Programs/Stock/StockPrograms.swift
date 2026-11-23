import Foundation

/// 在庫管理 (stock, st000-st060) のプログラム登録
public enum StockPrograms {
    public static func register(_ s: Session) {
        s.programs["stock"] = Stock.run
        s.programs["st000"] = ST000.run
        s.programs["st010"] = ST010.run
        s.programs["st020"] = ST020.run
        s.programs["st030"] = ST030.run
        s.programs["st040"] = ST040.run
        s.programs["st050"] = ST050.run
    }
}
