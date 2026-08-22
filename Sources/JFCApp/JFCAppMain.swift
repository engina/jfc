import AppKit

@main
enum JFCAppMain {
  @MainActor
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    let launchedAtLogin = ProcessInfo.processInfo.arguments.contains("--launch-at-login")
    application.setActivationPolicy(launchedAtLogin ? .accessory : .regular)
    application.run()
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var model: AppState?
  private var controlWindowController: ControlWindowController?
  private var installedMainMenu = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    let model = AppState()
    self.model = model
    controlWindowController = ControlWindowController(model: model) { [weak self] in
      self?.hideApplicationPresence()
    }

    if !ProcessInfo.processInfo.arguments.contains("--launch-at-login") {
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
    model?.refresh()
    showControlWindow()
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    model?.shutDown()
  }

  private func showControlWindow() {
    installMainMenuIfNeeded()
    NSApplication.shared.setActivationPolicy(.regular)
    controlWindowController?.show(forceToFront: true)
    DispatchQueue.main.async { [weak self] in
      NSApplication.shared.activate()
      self?.controlWindowController?.show(forceToFront: true)
    }
  }

  private func hideApplicationPresence() {
    NSApplication.shared.setActivationPolicy(.accessory)
  }

  private func installMainMenuIfNeeded() {
    guard !installedMainMenu else { return }
    installedMainMenu = true
    AppMenu.install()
  }
}
