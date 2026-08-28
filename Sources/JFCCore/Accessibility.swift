import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum AccessibilityPermission {
  public static func isTrusted(prompt: Bool) -> Bool {
    if !prompt {
      return AXIsProcessTrustedWithOptions(nil)
    }

    // The imported C symbol is mutable and therefore rejected by Swift 6's
    // strict concurrency checking. This is the symbol's documented value.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  public static func openSystemSettings() {
    JFCLog.permission("Opening Accessibility settings")
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    else {
      JFCLog.permissionError("Could not construct Accessibility settings URL")
      return
    }
    NSWorkspace.shared.open(url)
  }
}

struct FocusAttempt {
  let steps: [String]
  let elapsedMilliseconds: Double
}

enum WindowFocusState {
  case focused
  case unfocused
  case unavailable(String)
}

final class AccessibilityFocuser {
  func windowFocusState(_ target: ResolvedTarget) -> WindowFocusState {
    guard let targetWindow = target.window else {
      return .unavailable("target window unavailable")
    }

    let applicationElement = AXUIElementCreateApplication(target.pid)
    AXUIElementSetMessagingTimeout(applicationElement, 0.1)

    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      applicationElement,
      kAXFocusedWindowAttribute as CFString,
      &value
    )
    guard error == .success else {
      return .unavailable("AX focused-window lookup=\(describe(error))")
    }
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
      return .unavailable("AX focused-window lookup=invalid value")
    }

    let focusedWindow = value as! AXUIElement
    return CFEqual(targetWindow, focusedWindow) ? .focused : .unfocused
  }

  func focusWindow(_ target: ResolvedTarget) -> FocusAttempt {
    let started = DispatchTime.now().uptimeNanoseconds
    var steps: [String] = []

    appendWindowFocusSteps(target.window, to: &steps)

    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    return FocusAttempt(steps: steps, elapsedMilliseconds: elapsed)
  }

  func focus(_ target: ResolvedTarget) -> FocusAttempt {
    let started = DispatchTime.now().uptimeNanoseconds
    var steps: [String] = []

    let applicationElement = AXUIElementCreateApplication(target.pid)
    AXUIElementSetMessagingTimeout(applicationElement, 0.1)

    appendWindowFocusSteps(target.window, includeFocused: false, to: &steps)

    if let application = NSRunningApplication(processIdentifier: target.pid) {
      let activated = application.activate(options: [])
      steps.append("AppKit activate=\(activated ? "success" : "failure")")
    } else {
      steps.append("AppKit application=unavailable")
    }

    appendFocusedStep(target.window, to: &steps)

    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    return FocusAttempt(steps: steps, elapsedMilliseconds: elapsed)
  }

  private func appendWindowFocusSteps(
    _ window: AXUIElement?,
    includeFocused: Bool = true,
    to steps: inout [String]
  ) {
    guard let window else {
      steps.append("AX window=unavailable")
      return
    }

    let mainError = AXUIElementSetAttributeValue(
      window,
      kAXMainAttribute as CFString,
      kCFBooleanTrue
    )
    steps.append("AX main=\(describe(mainError))")

    let raiseError = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    steps.append("AX raise=\(describe(raiseError))")

    if includeFocused {
      appendFocusedStep(window, to: &steps)
    }
  }

  private func appendFocusedStep(_ window: AXUIElement?, to steps: inout [String]) {
    guard let window else { return }

    let focusedError = AXUIElementSetAttributeValue(
      window,
      kAXFocusedAttribute as CFString,
      kCFBooleanTrue
    )
    steps.append("AX focused=\(describe(focusedError))")
  }

  private func describe(_ error: AXError) -> String {
    switch error {
    case .success: "success"
    case .failure: "failure"
    case .illegalArgument: "illegalArgument"
    case .invalidUIElement: "invalidUIElement"
    case .invalidUIElementObserver: "invalidUIElementObserver"
    case .cannotComplete: "cannotComplete"
    case .attributeUnsupported: "attributeUnsupported"
    case .actionUnsupported: "actionUnsupported"
    case .notificationUnsupported: "notificationUnsupported"
    case .notImplemented: "notImplemented"
    case .notificationAlreadyRegistered: "notificationAlreadyRegistered"
    case .notificationNotRegistered: "notificationNotRegistered"
    case .apiDisabled: "apiDisabled"
    case .noValue: "noValue"
    case .parameterizedAttributeUnsupported: "parameterizedAttributeUnsupported"
    case .notEnoughPrecision: "notEnoughPrecision"
    @unknown default: "unknown(\(error.rawValue))"
    }
  }
}
