import Foundation
import OSLog

public enum JFCLog {
  public static let subsystem = "com.justfuckingclick.JFC"

  private static let lifecycleLogger = Logger(subsystem: subsystem, category: "lifecycle")
  private static let permissionLogger = Logger(subsystem: subsystem, category: "permissions")
  private static let eventTapLogger = Logger(subsystem: subsystem, category: "event-tap")
  private static let loginLogger = Logger(subsystem: subsystem, category: "start-at-login")

  public static func lifecycle(_ message: String) {
    lifecycleLogger.notice("\(message, privacy: .public)")
  }

  public static func permission(_ message: String) {
    permissionLogger.notice("\(message, privacy: .public)")
  }

  public static func permissionError(_ message: String) {
    permissionLogger.error("\(message, privacy: .public)")
  }

  public static func eventTap(_ message: String) {
    eventTapLogger.notice("\(message, privacy: .public)")
  }

  public static func eventTapError(_ message: String) {
    eventTapLogger.error("\(message, privacy: .public)")
  }

  public static func login(_ message: String) {
    loginLogger.notice("\(message, privacy: .public)")
  }

  public static func loginError(_ message: String) {
    loginLogger.error("\(message, privacy: .public)")
  }
}
