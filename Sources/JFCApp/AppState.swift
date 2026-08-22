import AppKit
import Combine
import JFCCore
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
  static let loginItemIdentifier = "com.justfuckingclick.JFC.LoginItem"

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
  private let eventTap = EventTap()
  private var refreshTask: Task<Void, Never>?
  private var shouldBeEnabled: Bool

  private static var loginItemService: SMAppService {
    SMAppService.loginItem(identifier: loginItemIdentifier)
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    if defaults.object(forKey: DefaultsKey.enabled) == nil {
      defaults.set(true, forKey: DefaultsKey.enabled)
    }

    shouldBeEnabled = defaults.bool(forKey: DefaultsKey.enabled)
    accessibilityGranted = AccessibilityPermission.isTrusted(prompt: false)
    launchAtLoginStatus = Self.loginItemService.status

    reconcileEventTap()
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
    let wasGranted = accessibilityGranted
    accessibilityGranted = AccessibilityPermission.isTrusted(prompt: false)

    if accessibilityGranted != wasGranted || (shouldBeEnabled && !eventTap.isRunning) {
      reconcileEventTap()
    } else if !accessibilityGranted && eventTap.isRunning {
      reconcileEventTap()
    }
  }

  func requestAccessibility() {
    errorMessage = nil
    AccessibilityPermission.openSystemSettings()
  }

  func start() {
    errorMessage = nil
    shouldBeEnabled = true
    defaults.set(true, forKey: DefaultsKey.enabled)

    guard accessibilityGranted else {
      operationalState = .needsPermission
      requestAccessibility()
      return
    }

    reconcileEventTap()
  }

  func stop() {
    errorMessage = nil
    shouldBeEnabled = false
    defaults.set(false, forKey: DefaultsKey.enabled)
    eventTap.stop()
    operationalState = .stopped
  }

  func setStartsAtLogin(_ enabled: Bool) {
    errorMessage = nil
    let service = Self.loginItemService

    do {
      if enabled {
        switch service.status {
        case .enabled:
          break
        case .requiresApproval:
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
      errorMessage = "Couldn’t update Start at Login: \(error.localizedDescription)"
    }

    launchAtLoginStatus = service.status
    if launchAtLoginStatus == .requiresApproval {
      errorMessage = "Start at Login needs your approval in System Settings."
    }
  }

  func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  func clearError() {
    errorMessage = nil
  }

  func shutDown() {
    refreshTask?.cancel()
    refreshTask = nil
    eventTap.stop()
  }

  private func reconcileEventTap() {
    guard accessibilityGranted else {
      eventTap.stop()
      operationalState = .needsPermission
      return
    }

    guard shouldBeEnabled else {
      eventTap.stop()
      operationalState = .stopped
      return
    }

    guard !eventTap.isRunning else {
      operationalState = .running
      return
    }

    do {
      try eventTap.start()
      operationalState = .running
      errorMessage = nil
    } catch {
      operationalState = .failed
      errorMessage = error.localizedDescription
    }
  }
}
