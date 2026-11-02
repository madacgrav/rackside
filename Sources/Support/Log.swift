import OSLog

/// One logger per subsystem area. There was previously no logging at all.
enum Log {
    private static let subsystem = "com.madacgrav.trainme"
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let archive = Logger(subsystem: subsystem, category: "archive")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let sync = Logger(subsystem: subsystem, category: "sync")
}
