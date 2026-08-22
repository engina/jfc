import AppKit

@main
enum JFCLoginItemMain {
  @MainActor
  static func main() {
    let application = NSApplication.shared
    let delegate = LoginItemDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.prohibited)
    application.run()
  }
}

@MainActor
final class LoginItemDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let mainApplicationURL = mainApplicationURL() else {
      NSApplication.shared.terminate(nil)
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.arguments = ["--launch-at-login"]

    NSWorkspace.shared.openApplication(
      at: mainApplicationURL,
      configuration: configuration
    ) { _, error in
      if let error {
        NSLog("JFC login item could not launch the main app: %@", error.localizedDescription)
      }
      DispatchQueue.main.async {
        NSApplication.shared.terminate(nil)
      }
    }
  }

  private func mainApplicationURL() -> URL? {
    var candidate = Bundle.main.bundleURL.deletingLastPathComponent()

    while candidate.path != "/" {
      if candidate.pathExtension == "app" {
        return candidate
      }
      candidate.deleteLastPathComponent()
    }

    return nil
  }
}
