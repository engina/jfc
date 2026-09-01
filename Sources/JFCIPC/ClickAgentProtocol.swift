import Foundation

public let jfcClickAgentBundleIdentifier = "io.e10n.jfc.click-agent"

public func jfcClickAgentPortName(token: String) -> CFString {
  "io.e10n.jfc.click-agent.\(token)" as CFString
}

public enum ClickAgentCommand: String, Codable, Sendable {
  case setEnabled
  case shutdown
  case status
}

public struct ClickAgentRequest: Codable, Sendable {
  public let id: String
  public let command: ClickAgentCommand
  public let enabled: Bool?
  public let ownerProcessIdentifier: Int32

  public init(
    id: String = UUID().uuidString,
    command: ClickAgentCommand,
    enabled: Bool? = nil,
    ownerProcessIdentifier: Int32
  ) {
    self.id = id
    self.command = command
    self.enabled = enabled
    self.ownerProcessIdentifier = ownerProcessIdentifier
  }
}

public struct ClickAgentResponse: Codable, Sendable {
  public let id: String
  public let accessibilityGranted: Bool
  public let running: Bool
  public let errorMessage: String?

  public init(
    id: String,
    accessibilityGranted: Bool,
    running: Bool,
    errorMessage: String?
  ) {
    self.id = id
    self.accessibilityGranted = accessibilityGranted
    self.running = running
    self.errorMessage = errorMessage
  }
}
