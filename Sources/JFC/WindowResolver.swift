import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct ResolvedTarget {
  let pid: pid_t
  let applicationName: String
  let bundleIdentifier: String?
  let window: AXUIElement?
  let windowTitle: String
  let elementRole: String
  let elementSubrole: String?
  let shouldBypass: Bool
  let bypassReason: String?
}

struct ResolutionFailure: Error, CustomStringConvertible {
  let description: String
}

final class WindowResolver {
  private let systemWideElement = AXUIElementCreateSystemWide()

  init() {
    // Keep a hung or nonresponsive AX provider from stalling the global input
    // stream long enough for WindowServer to disable this event tap.
    AXUIElementSetMessagingTimeout(systemWideElement, 0.1)
  }

  func resolve(at point: CGPoint) -> Result<ResolvedTarget, ResolutionFailure> {
    var rawElement: AXUIElement?
    let hitTestError = AXUIElementCopyElementAtPosition(
      systemWideElement,
      Float(point.x),
      Float(point.y),
      &rawElement
    )

    guard hitTestError == .success, let element = rawElement else {
      return .failure(
        ResolutionFailure(description: "AX hit-test failed: \(hitTestError.rawValue)")
      )
    }

    var pid: pid_t = 0
    let pidError = AXUIElementGetPid(element, &pid)
    guard pidError == .success, pid > 0 else {
      return .failure(
        ResolutionFailure(description: "could not obtain target pid: \(pidError.rawValue)")
      )
    }

    let role = stringAttribute(element, kAXRoleAttribute as CFString) ?? "unknown"
    let subrole = stringAttribute(element, kAXSubroleAttribute as CFString)
    let window =
      elementAttribute(element, kAXWindowAttribute as CFString)
      ?? (role == (kAXWindowRole as String) ? element : nil)
    let windowTitle =
      window.flatMap {
        stringAttribute($0, kAXTitleAttribute as CFString)
      } ?? "<untitled>"

    let runningApplication = NSRunningApplication(processIdentifier: pid)
    let applicationName =
      runningApplication?.localizedName
      ?? fallbackOwnerName(at: point, pid: pid)
      ?? "pid \(pid)"

    let bypassReason = safetyBypassReason(
      elementRole: role,
      elementSubrole: subrole,
      hasWindow: window != nil,
      runningApplication: runningApplication
    )

    return .success(
      ResolvedTarget(
        pid: pid,
        applicationName: applicationName,
        bundleIdentifier: runningApplication?.bundleIdentifier,
        window: window,
        windowTitle: windowTitle,
        elementRole: role,
        elementSubrole: subrole,
        shouldBypass: bypassReason != nil,
        bypassReason: bypassReason
      )
    )
  }

  private func safetyBypassReason(
    elementRole: String,
    elementSubrole: String?,
    hasWindow: Bool,
    runningApplication: NSRunningApplication?
  ) -> String? {
    guard hasWindow else {
      return "no containing AX window (desktop, menu bar, Dock, or unsupported UI)"
    }

    if runningApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
      return "target is jfc itself"
    }

    if runningApplication?.activationPolicy == .prohibited {
      return "target application cannot be activated"
    }

    let excludedRoles = [
      kAXWindowRole as String,
      kAXGrowAreaRole as String,
    ]
    if excludedRoles.contains(elementRole) {
      return "window drag/resize surface (\(elementRole))"
    }

    let excludedSubroles = [
      kAXCloseButtonSubrole as String,
      kAXMinimizeButtonSubrole as String,
      kAXZoomButtonSubrole as String,
      kAXFullScreenButtonSubrole as String,
    ]
    if let elementSubrole, excludedSubroles.contains(elementSubrole) {
      return "window-management control (\(elementSubrole))"
    }

    return nil
  }

  private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
      return nil
    }
    return value as? String
  }

  private func elementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
      let value,
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else {
      return nil
    }
    return (value as! AXUIElement)
  }

  private func fallbackOwnerName(at point: CGPoint, pid: pid_t) -> String? {
    guard
      let rawWindows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return nil
    }

    for window in rawWindows {
      guard let ownerPID = window[kCGWindowOwnerPID as String] as? NSNumber,
        ownerPID.int32Value == pid,
        let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
        bounds.contains(point)
      else {
        continue
      }
      return window[kCGWindowOwnerName as String] as? String
    }

    return nil
  }
}
