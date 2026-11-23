import Foundation

public struct BusinessContext {
    public let store: FileStore
    public let timeZone: TimeZone
    public let now: () -> Date

    public init(store: FileStore, timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.timeZone = timeZone
        self.now = now
    }

    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
