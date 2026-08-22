import AppKit
import SwiftUI

@MainActor
final class ControlWindowController: NSWindowController, NSWindowDelegate {
  private let onClose: () -> Void

  init(model: AppState, onClose: @escaping () -> Void) {
    self.onClose = onClose
    let contentView = ControlView(model: model)
    let hostingController = NSHostingController(rootView: contentView)
    let window = NSWindow(contentViewController: hostingController)

    window.title = "JFC"
    window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace]
    window.setContentSize(NSSize(width: 520, height: 430))
    window.standardWindowButton(.zoomButton)?.isHidden = true

    super.init(window: window)
    window.delegate = self

    if !window.setFrameUsingName("JFCControlWindow") {
      window.center()
    }
    window.setFrameAutosaveName("JFCControlWindow")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func show(forceToFront: Bool = false) {
    guard let window else { return }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    // Don’t let the secondary GitHub link become the initial focused control.
    window.makeFirstResponder(nil)
    if forceToFront {
      window.orderFrontRegardless()
    }
  }

  func windowWillClose(_ notification: Notification) {
    onClose()
  }
}
