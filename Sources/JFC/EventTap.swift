import AppKit
import CoreGraphics
import Foundation

enum EventTapStartError: Error, CustomStringConvertible {
  case creationFailed
  case runLoopSourceFailed

  var description: String {
    switch self {
    case .creationFailed:
      "CGEvent tap creation failed. Grant Accessibility and Input Monitoring, then restart jfc."
    case .runLoopSourceFailed:
      "Could not create a run-loop source for the event tap."
    }
  }
}

final class EventTap {
  private let options: CLIOptions
  private let resolver = WindowResolver()
  private let focuser = AccessibilityFocuser()
  private var tap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var clickNumber: UInt64 = 0

  init(options: CLIOptions) {
    self.options = options
  }

  func start() throws {
    let mask =
      (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
      | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
    let tapOptions: CGEventTapOptions = options.observeOnly ? .listenOnly : .defaultTap

    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo else {
        return Unmanaged.passUnretained(event)
      }
      let owner = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
      return owner.handle(type: type, event: event)
    }

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: tapOptions,
        eventsOfInterest: mask,
        callback: callback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw EventTapStartError.creationFailed
    }

    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
      throw EventTapStartError.runLoopSourceFailed
    }

    self.tap = tap
    self.runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  func run() -> Never {
    CFRunLoopRun()
    fatalError("event-tap run loop unexpectedly stopped")
  }

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      Log.line(
        "EVENT TAP DISABLED (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabling"
      )
      if let tap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    if type == .leftMouseUp {
      if options.verbose {
        Log.line("mouseUp: passed through unchanged")
      }
      return Unmanaged.passUnretained(event)
    }

    guard type == .leftMouseDown else {
      return Unmanaged.passUnretained(event)
    }

    clickNumber += 1
    let started = DispatchTime.now().uptimeNanoseconds
    let point = event.location
    let clickState = event.getIntegerValueField(.mouseEventClickState)
    let activeApplication = NSWorkspace.shared.frontmostApplication

    switch resolver.resolve(at: point) {
    case .failure(let error):
      if options.verbose {
        Log.block([
          "CLICK #\(clickNumber)",
          "cursor: \(format(point))",
          "resolver: \(error)",
          "forwarding original click unchanged",
        ])
      }
      return Unmanaged.passUnretained(event)

    case .success(let target):
      let targetIsActive = activeApplication?.processIdentifier == target.pid
      if targetIsActive || target.shouldBypass {
        if options.verbose {
          let reason =
            targetIsActive
            ? "target application is already active"
            : (target.bypassReason ?? "safety policy")
          Log.block(
            clickLog(
              target: target,
              activeApplication: activeApplication,
              point: point,
              clickState: clickState
            ) + [
              "action: bypass (\(reason))",
              "forwarding original click unchanged",
            ])
        }
        return Unmanaged.passUnretained(event)
      }

      var lines = clickLog(
        target: target,
        activeApplication: activeApplication,
        point: point,
        clickState: clickState
      )

      if options.observeOnly {
        lines.append("observe-only: would activate \(target.applicationName)")
        lines.append("forwarding original click unchanged")
        Log.block(lines)
        return Unmanaged.passUnretained(event)
      }

      lines.append(
        "activating \(target.applicationName) via \(options.activationStrategy.rawValue)...")
      let focusAttempt = focuser.focus(target, strategy: options.activationStrategy)
      lines.append(contentsOf: focusAttempt.steps.map { "  \($0)" })

      if options.settleMilliseconds > 0 {
        Thread.sleep(
          forTimeInterval: Double(options.settleMilliseconds) / 1_000.0
        )
        lines.append("held original event for \(options.settleMilliseconds) ms")
      }

      let totalElapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
      lines.append(
        String(
          format: "forwarding SAME CGEvent (focus %.2f ms, total %.2f ms)",
          focusAttempt.elapsedMilliseconds,
          totalElapsed
        )
      )
      Log.block(lines)
      return Unmanaged.passUnretained(event)
    }
  }

  private func clickLog(
    target: ResolvedTarget,
    activeApplication: NSRunningApplication?,
    point: CGPoint,
    clickState: Int64
  ) -> [String] {
    var element = target.elementRole
    if let subrole = target.elementSubrole {
      element += " / \(subrole)"
    }

    return [
      "CLICK #\(clickNumber) (clickState=\(clickState))",
      "cursor: \(format(point))",
      "target app: \(target.applicationName) [pid \(target.pid)]",
      "target window: \(target.windowTitle)",
      "target element: \(element)",
      "currently active app: \(activeApplication?.localizedName ?? "<unknown>")",
    ]
  }

  private func format(_ point: CGPoint) -> String {
    String(format: "%.1f,%.1f", point.x, point.y)
  }
}

enum Log {
  static func line(_ message: String) {
    write(message + "\n")
  }

  static func block(_ lines: [String]) {
    write(lines.joined(separator: "\n") + "\n\n")
  }

  private static func write(_ message: String) {
    guard let data = message.data(using: .utf8) else { return }
    FileHandle.standardOutput.write(data)
  }
}
