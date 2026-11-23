import Foundation

func stockText(_ key: String) -> String {
    NSLocalizedString("stock." + key, tableName: "ST", comment: "")
}
