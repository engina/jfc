import AppKit
import Combine
import JFCCore
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
  static let loginItemIdentifier = "io.e10n.jfc.login-item"

  enum OperationalState: Equatable {
    case running
    case stopped
    case needsPermission
    case failed
  }

  @Published private(set) var accessibilityGranted: Bool
  @Published private(set) var operationalState: OperationalState = .stopped
  @Published private(set) var launchAtLoginStatus: SMAppService.Status
  @Published private(set) var errorMessage: String?

  private enum DefaultsKey {
    static let enabled = "JFCEnabled"
  }

  private let defaults: UserDefaults
  private let clickAgent = ClickAgentClient()
  private var refreshTask: Task<Void, Never>?
  private var shouldBeEnabled: Bool
  private var requestNumber: UInt64 = 0

  private static var loginItemService: SMAppService {
    SMAppService.loginItem(identifier: loginItemIdentifier)
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    if defaults.object(forKey: DefaultsKey.enabled) == nil {
      defaults.set(true, forKey: DefaultsKey.enabled)
    }

    shouldBeEnabled = defaults.bool(forKey: DefaultsKey.enabled)
    accessibilityGranted = false
    launchAtLoginStatus = Self.loginItemService.status
    JFCLog.login("Initial SAL status: \(describe(launchAtLoginStatus))")

    reconcileClickAgent()
    refreshTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        self?.refreshAccessibility()
      }
    }
  }

  var isRunning: Bool {
    operationalState == .running
  }

  var startsAtLogin: Bool {
    launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
  }

  var loginItemNeedsApproval: Bool {
    launchAtLoginStatus == .requiresApproval
  }

  func refresh() {
    launchAtLoginStatus = Self.loginItemService.status
    refreshAccessibility()
  }

  private func refreshAccessibility() {
    performRequest { [clickAgent] completion in
      clickAgent.status(completion: completion)
    } completion: { [weak self] status in
      guard let self else { return }
      if shouldBeEnabled && status.accessibilityGranted && !status.running
        && status.errorMessage == nil
      {
        reconcileClickAgent()
      } else {
        apply(status)
      }
    }
  }

  func requestAccessibility() {
    errorMessage = nil
    AccessibilityPermission.openSystemSettings()
  }

  func start() {
    JFCLog.lifecycle("Start requested")
    errorMessage = nil
    shouldBeEnabled = true
    defaults.set(true, forKey: DefaultsKey.enabled)

    reconcileClickAgent()
  }

  func stop() {
    JFCLog.lifecycle("Stop requested")
    errorMessage = nil
    shouldBeEnabled = false
    defaults.set(false, forKey: DefaultsKey.enabled)
    reconcileClickAgent()
  }

  func setStartsAtLogin(_ enabled: Bool) {
    JFCLog.login("SAL \(enabled ? "enable" : "disable") requested")
    errorMessage = nil
    let service = Self.loginItemService

    do {
      if enabled {
        switch service.status {
        case .enabled:
          JFCLog.login("SAL already enabled")
          break
        case .requiresApproval:
          JFCLog.login("SAL requires approval; opening Login Items settings")
          SMAppService.openSystemSettingsLoginItems()
        case .notRegistered, .notFound:
          try service.register()
        @unknown default:
          try service.register()
        }
      } else if service.status != .notRegistered {
        try service.unregister()
      }
    } catch {
      let nsError = error as NSError
      JFCLog.loginError(
        "SAL update failed: domain=\(nsError.domain) code=\(nsError.code)"
      )
      errorMessage = "Couldn’t update Start at Login: \(error.localizedDescription)"
    }

    launchAtLoginStatus = service.status
    JFCLog.login("SAL status: \(describe(launchAtLoginStatus))")
    if launchAtLoginStatus == .requiresApproval {
      errorMessage = "Start at Login needs your approval in System Settings."
    }
  }

  func openLoginItemsSettings() {
    JFCLog.login("Opening Login Items settings")
    SMAppService.openSystemSettingsLoginItems()
  }

  func clearError() {
    errorMessage = nil
  }

  func shutDown() {
    refreshTask?.cancel()
    refreshTask = nil
    clickAgent.invalidate()
  }

  private func describe(_ status: SMAppService.Status) -> String {
    switch status {
    case .notRegistered: "not registered"
    case .enabled: "enabled"
    case .requiresApproval: "requires approval"
    case .notFound: "not found"
    @unknown default: "unknown"
    }
  }

  private func reconcileClickAgent() {
    performRequest { [clickAgent, shouldBeEnabled] completion in
      clickAgent.setEnabled(shouldBeEnabled, completion: completion)
    } completion: { [weak self] status in
      self?.apply(status)
    }
  }

  private func performRequest(
    _ operation: (@escaping ClickAgentClient.Completion) -> Void,
    completion: @escaping (ClickAgentStatus) -> Void
  ) {
    requestNumber &+= 1
    let requestNumber = requestNumber
    operation { [weak self] result in
      guard let self, requestNumber == self.requestNumber else { return }
      switch result {
      case .success(let status):
        completion(status)
      case .failure(let error):
        self.operationalState = .failed
        self.errorMessage = error.localizedDescription
      }
    }
  }

  private func apply(_ status: ClickAgentStatus) {
    let wasGranted = accessibilityGranted
    accessibilityGranted = status.accessibilityGranted

    if accessibilityGranted != wasGranted {
      JFCLog.permission(
        "Accessibility status changed: \(accessibilityGranted ? "granted" : "revoked")"
      )
    }

    if let agentError = status.errorMessage {
      operationalState = .failed
      errorMessage = agentError
    } else if !accessibilityGranted {
      operationalState = .needsPermission
      errorMessage = nil
    } else if shouldBeEnabled && status.running {
      operationalState = .running
      errorMessage = nil
    } else if shouldBeEnabled {
      operationalState = .failed
      errorMessage = "The JFC click agent isn’t running."
    } else {
      operationalState = .stopped
      errorMessage = nil
    }
  }
}
