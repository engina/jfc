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
    _ = isTrusted(prompt: true)
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }
}

struct FocusAttempt {
  let steps: [String]
  let elapsedMilliseconds: Double
}

final class AccessibilityFocuser {
  func focus(_ target: ResolvedTarget, strategy: ActivationStrategy) -> FocusAttempt {
    let started = DispatchTime.now().uptimeNanoseconds
    var steps: [String] = []

    if strategy == .ax || strategy == .both {
      let applicationElement = AXUIElementCreateApplication(target.pid)

      if let window = target.window {
        let mainError = AXUIElementSetAttributeValue(
          window,
          kAXMainAttribute as CFString,
          kCFBooleanTrue
        )
        steps.append("AX main=\(describe(mainError))")

        let raiseError = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        steps.append("AX raise=\(describe(raiseError))")
      } else {
        steps.append("AX window=unavailable")
      }

      let frontmostError = AXUIElementSetAttributeValue(
        applicationElement,
        kAXFrontmostAttribute as CFString,
        kCFBooleanTrue
      )
      steps.append("AX frontmost=\(describe(frontmostError))")

      if let window = target.window {
        let focusedError = AXUIElementSetAttributeValue(
          window,
          kAXFocusedAttribute as CFString,
          kCFBooleanTrue
        )
        steps.append("AX focused=\(describe(focusedError))")
      }
    }

    if strategy == .appkit || strategy == .both {
      if let application = NSRunningApplication(processIdentifier: target.pid) {
        let activated = application.activate(options: [])
        steps.append("AppKit activate=\(activated ? "accepted" : "rejected")")
      } else {
        steps.append("AppKit application=unavailable")
      }
    }

    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    return FocusAttempt(steps: steps, elapsedMilliseconds: elapsed)
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
