import Foundation

enum Launch {
    static let freePeriod = false
    static let arguments = ProcessInfo.processInfo.arguments
    #if DEBUG
    static let testing = arguments.contains("-ui-testing")
    #else
    static let testing = false
    #endif
    static var isFree: Bool { freePeriod && !testing }
    static var usageDate: Date {
        if testing, let text = ProcessInfo.processInfo.environment["SCORE_TEST_DATE"],
           let date = ISO8601DateFormatter().date(from: text) { return date }
        return Date()
    }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    static func has(_ flag: String) -> Bool { testing && arguments.contains(flag) }
    static func value(_ flag: String) -> String? {
        guard testing, let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
