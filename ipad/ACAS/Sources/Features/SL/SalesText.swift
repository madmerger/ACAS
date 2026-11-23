import Foundation

func slText(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "SL")
}
