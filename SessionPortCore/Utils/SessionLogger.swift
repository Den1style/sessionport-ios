import OSLog

/// Structured logging via OSLog (per build guide). Replaces `print()`:
/// zero-cost at .debug in Release, readable in Console.app, and supports
/// privacy redaction so secrets never leak into crash reports.
enum SessionLogger {
    private static let subsystem = "com.lusine.sessionport"

    static let storage  = Logger(subsystem: subsystem, category: "storage")
    static let transfer = Logger(subsystem: subsystem, category: "transfer")
    static let oauth    = Logger(subsystem: subsystem, category: "oauth")
    static let sync     = Logger(subsystem: subsystem, category: "sync")
}
