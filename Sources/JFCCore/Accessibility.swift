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

struct FocusStep {
  let phase: String
  let operation: String
  let result: String
  let startedUptimeNanoseconds: UInt64
  let finishedUptimeNanoseconds: UInt64

  var elapsedMilliseconds: Double {
    Double(finishedUptimeNanoseconds - startedUptimeNanoseconds) / 1_000_000
  }

  var logDescription: String {
    "\(operation)=\(result)"
  }
}

struct FocusAttempt {
  let steps: [FocusStep]
  let elapsedMilliseconds: Double
}

typealias FocusStepObserver = (FocusStep) -> Void

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

  func focusWindow(
    _ target: ResolvedTarget,
    afterStep: FocusStepObserver? = nil
  ) -> FocusAttempt {
    let started = DispatchTime.now().uptimeNanoseconds
    var steps: [FocusStep] = []

    appendWindowFocusSteps(
      target.window,
      phase: "activeApplicationWindow",
      afterStep: afterStep,
      to: &steps
    )

    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    return FocusAttempt(steps: steps, elapsedMilliseconds: elapsed)
  }

  func focus(
    _ target: ResolvedTarget,
    afterStep: FocusStepObserver? = nil
  ) -> FocusAttempt {
    let started = DispatchTime.now().uptimeNanoseconds
    var steps: [FocusStep] = []

    let applicationElement = AXUIElementCreateApplication(target.pid)
    AXUIElementSetMessagingTimeout(applicationElement, 0.1)

    appendWindowFocusSteps(
      target.window,
      includeFocused: false,
      phase: "beforeApplicationActivation",
      afterStep: afterStep,
      to: &steps
    )

    if let application = NSRunningApplication(processIdentifier: target.pid) {
      let stepStarted = DispatchTime.now().uptimeNanoseconds
      let activated = application.activate(options: [])
      append(
        FocusStep(
          phase: "applicationActivation",
          operation: "AppKit activate",
          result: activated ? "success" : "failure",
          startedUptimeNanoseconds: stepStarted,
          finishedUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        ),
        afterStep: afterStep,
        to: &steps
      )
    } else {
      let now = DispatchTime.now().uptimeNanoseconds
      append(
        FocusStep(
          phase: "applicationActivation",
          operation: "AppKit application",
          result: "unavailable",
          startedUptimeNanoseconds: now,
          finishedUptimeNanoseconds: now
        ),
        afterStep: afterStep,
        to: &steps
      )
    }

    appendWindowFocusSteps(
      target.window,
      includeFocused: false,
      phase: "afterApplicationActivation",
      afterStep: afterStep,
      to: &steps
    )
    appendFocusedStep(
      target.window,
      phase: "afterApplicationActivation",
      afterStep: afterStep,
      to: &steps
    )

    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    return FocusAttempt(steps: steps, elapsedMilliseconds: elapsed)
  }

  private func appendWindowFocusSteps(
    _ window: AXUIElement?,
    includeFocused: Bool = true,
    phase: String,
    afterStep: FocusStepObserver?,
    to steps: inout [FocusStep]
  ) {
    guard let window else {
      let now = DispatchTime.now().uptimeNanoseconds
      append(
        FocusStep(
          phase: phase,
          operation: "AX window",
          result: "unavailable",
          startedUptimeNanoseconds: now,
          finishedUptimeNanoseconds: now
        ),
        afterStep: afterStep,
        to: &steps
      )
      return
    }

    let mainStarted = DispatchTime.now().uptimeNanoseconds
    let mainError = AXUIElementSetAttributeValue(
      window,
      kAXMainAttribute as CFString,
      kCFBooleanTrue
    )
    append(
      FocusStep(
        phase: phase,
        operation: "AX main",
        result: describe(mainError),
        startedUptimeNanoseconds: mainStarted,
        finishedUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
      ),
      afterStep: afterStep,
      to: &steps
    )

    let raiseStarted = DispatchTime.now().uptimeNanoseconds
    let raiseError = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    append(
      FocusStep(
        phase: phase,
        operation: "AX raise",
        result: describe(raiseError),
        startedUptimeNanoseconds: raiseStarted,
        finishedUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
      ),
      afterStep: afterStep,
      to: &steps
    )

    if includeFocused {
      appendFocusedStep(
        window,
        phase: phase,
        afterStep: afterStep,
        to: &steps
      )
    }
  }

  private func appendFocusedStep(
    _ window: AXUIElement?,
    phase: String,
    afterStep: FocusStepObserver?,
    to steps: inout [FocusStep]
  ) {
    guard let window else { return }

    let focusedStarted = DispatchTime.now().uptimeNanoseconds
    let focusedError = AXUIElementSetAttributeValue(
      window,
      kAXFocusedAttribute as CFString,
      kCFBooleanTrue
    )
    append(
      FocusStep(
        phase: phase,
        operation: "AX focused",
        result: describe(focusedError),
        startedUptimeNanoseconds: focusedStarted,
        finishedUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
      ),
      afterStep: afterStep,
      to: &steps
    )
  }

  private func append(
    _ step: FocusStep,
    afterStep: FocusStepObserver?,
    to steps: inout [FocusStep]
  ) {
    steps.append(step)
    afterStep?(step)
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
