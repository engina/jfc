import AppKit
import JFCCore

private enum LaunchContext {
  static let loginEnvironmentKey = "JFC_LAUNCHED_AT_LOGIN"

  static var isLoginLaunch: Bool {
    ProcessInfo.processInfo.arguments.contains("--launch-at-login")
      || ProcessInfo.processInfo.environment[loginEnvironmentKey] == "1"
  }
}

@main
enum JFCAppMain {
  @MainActor
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(LaunchContext.isLoginLaunch ? .accessory : .regular)
    application.run()
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var model: AppState?
  private var controlWindowController: ControlWindowController?
  private var installedMainMenu = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    JFCLog.lifecycle(
      LaunchContext.isLoginLaunch
        ? "Application launched at login" : "Application launched deliberately"
    )
    let model = AppState()
    self.model = model
    controlWindowController = ControlWindowController(model: model) { [weak self] in
      self?.hideApplicationPresence()
    }

    if !LaunchContext.isLoginLaunch {
      showControlWindow()
    }
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    model?.refresh()
    if controlWindowController?.window?.isVisible == true {
      controlWindowController?.show()
    }
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    JFCLog.lifecycle("Application reopened deliberately")
    model?.refresh()
    showControlWindow()
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    JFCLog.lifecycle("Application terminating")
    model?.shutDown()
  }

  private func showControlWindow() {
    JFCLog.lifecycle("Showing control window")
    installMainMenuIfNeeded()
    NSApplication.shared.setActivationPolicy(.regular)
    controlWindowController?.show(forceToFront: true)
    DispatchQueue.main.async { [weak self] in
      NSApplication.shared.activate()
      self?.controlWindowController?.show(forceToFront: true)
    }
  }

  private func hideApplicationPresence() {
    JFCLog.lifecycle("Control window closed; continuing in background")
    NSApplication.shared.setActivationPolicy(.accessory)
  }

  private func installMainMenuIfNeeded() {
    guard !installedMainMenu else { return }
    installedMainMenu = true
    AppMenu.install()
  }
}
