import AppKit
import CoreGraphics
import Foundation

public struct EventTapConfiguration {
  public var observeOnly: Bool
  public var settleMilliseconds: UInt32
  public var verbose: Bool
  public var loggingEnabled: Bool
  public var traceOutputPath: String?

  public init(
    observeOnly: Bool = false,
    settleMilliseconds: UInt32 = 0,
    verbose: Bool = false,
    loggingEnabled: Bool = false,
    traceOutputPath: String? = nil
  ) {
    self.observeOnly = observeOnly
    self.settleMilliseconds = settleMilliseconds
    self.verbose = verbose
    self.loggingEnabled = loggingEnabled
    self.traceOutputPath = traceOutputPath
  }
}

public enum EventTapStartError: Error, CustomStringConvertible, LocalizedError {
  case creationFailed
  case runLoopSourceFailed
  case traceOutputFailed(String)

  public var description: String {
    switch self {
    case .creationFailed:
      "CGEvent tap creation failed. Grant Accessibility, then restart JFC."
    case .runLoopSourceFailed:
      "Could not create a run-loop source for the event tap."
    case .traceOutputFailed(let reason):
      "Could not create forensic trace: \(reason)"
    }
  }

  public var errorDescription: String? {
    description
  }
}

public final class EventTap {
  private let configuration: EventTapConfiguration
  private let resolver = WindowResolver()
  private let focuser = AccessibilityFocuser()
  private var tap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var sourceRunLoop: CFRunLoop?
  private var clickNumber: UInt64 = 0
  private var eventSequence: UInt64 = 0
  private var forensicTrace: ForensicTrace?

  public var isRunning: Bool {
    tap != nil
  }

  public init(configuration: EventTapConfiguration = EventTapConfiguration()) {
    self.configuration = configuration
  }

  public func start() throws {
    guard tap == nil else { return }

    if let path = configuration.traceOutputPath {
      do {
        forensicTrace = try ForensicTrace(path: path, configuration: configuration)
      } catch {
        throw EventTapStartError.traceOutputFailed(String(describing: error))
      }
    }

    let mask =
      (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
      | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
    let tapOptions: CGEventTapOptions = configuration.observeOnly ? .listenOnly : .defaultTap

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
      JFCLog.eventTapError("Event tap creation failed")
      throw EventTapStartError.creationFailed
    }

    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
      CFMachPortInvalidate(tap)
      JFCLog.eventTapError("Event tap run-loop source creation failed")
      throw EventTapStartError.runLoopSourceFailed
    }

    let runLoop = CFRunLoopGetCurrent()
    self.tap = tap
    runLoopSource = source
    sourceRunLoop = runLoop
    CFRunLoopAddSource(runLoop, source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    JFCLog.eventTap("Event tap started")
    forensicTrace?.recordTapStarted()
  }

  public func stop() {
    guard let tap else { return }

    CGEvent.tapEnable(tap: tap, enable: false)
    if let runLoopSource, let sourceRunLoop {
      CFRunLoopRemoveSource(sourceRunLoop, runLoopSource, .commonModes)
    }
    CFMachPortInvalidate(tap)
    self.tap = nil
    runLoopSource = nil
    sourceRunLoop = nil
    JFCLog.eventTap("Event tap stopped")
    forensicTrace?.recordTapStopped()
    forensicTrace = nil
  }

  public func run() -> Never {
    CFRunLoopRun()
    JFCLog.eventTapError("Event-tap run loop stopped unexpectedly")
    fatalError("event-tap run loop unexpectedly stopped")
  }

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
      JFCLog.eventTapError("Event tap disabled by \(reason); re-enabling")
      if configuration.loggingEnabled {
        Log.line(
          "EVENT TAP DISABLED (\(reason)); re-enabling"
        )
      }
      if let tap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      forensicTrace?.recordTapDisabled(reason: reason)
      return Unmanaged.passUnretained(event)
    }

    guard type == .leftMouseDown || type == .leftMouseUp else {
      return Unmanaged.passUnretained(event)
    }

    let callbackStarted = DispatchTime.now().uptimeNanoseconds
    eventSequence += 1
    forensicTrace?.recordIncomingEvent(
      event,
      type: type,
      sequence: eventSequence,
      clickNumber: clickNumber + (type == .leftMouseDown ? 1 : 0),
      callbackUptimeNanoseconds: callbackStarted
    )

    if type == .leftMouseUp {
      if configuration.verbose && configuration.loggingEnabled {
        Log.line("mouseUp: passed through unchanged")
      }
      forensicTrace?.recordMouseUpPassThrough(
        sequence: eventSequence,
        clickNumber: clickNumber,
        callbackMilliseconds: elapsedMilliseconds(since: callbackStarted)
      )
      return Unmanaged.passUnretained(event)
    }

    clickNumber += 1
    let started = callbackStarted
    let point = event.location
    let clickState = event.getIntegerValueField(.mouseEventClickState)
    let activeApplication = NSWorkspace.shared.frontmostApplication

    switch resolver.resolve(at: point) {
    case .failure(let error):
      forensicTrace?.recordResolutionFailure(
        clickNumber: clickNumber,
        reason: error.description
      )
      forensicTrace?.recordForwarding(
        sequence: eventSequence,
        clickNumber: clickNumber,
        focusMilliseconds: nil,
        totalMilliseconds: elapsedMilliseconds(since: started),
        settleMilliseconds: 0
      )
      if configuration.verbose && configuration.loggingEnabled {
        Log.block([
          "CLICK #\(clickNumber)",
          "cursor: \(format(point))",
          "resolver: \(error)",
          "forwarding original click unchanged",
        ])
      }
      return Unmanaged.passUnretained(event)

    case .success(let target):
      forensicTrace?.recordState(
        phase: "resolvedBeforeDecision",
        clickNumber: clickNumber,
        target: target,
        includeAccessibility: false
      )
      if target.shouldBypass {
        forensicTrace?.recordDecision(
          clickNumber: clickNumber,
          decision: "safetyBypass",
          reason: target.bypassReason,
          target: target
        )
        if configuration.verbose && configuration.loggingEnabled {
          Log.block(
            clickLog(
              target: target,
              activeApplication: activeApplication,
              point: point,
              clickState: clickState
            ) + [
              "action: bypass (\(target.bypassReason ?? "safety policy"))",
              "forwarding original click unchanged",
            ])
        }
        recordPassThroughTrace(target: target, started: started)
        return Unmanaged.passUnretained(event)
      }

      var lines = clickLog(
        target: target,
        activeApplication: activeApplication,
        point: point,
        clickState: clickState
      )

      let targetApplicationIsActive = activeApplication?.processIdentifier == target.pid
      if targetApplicationIsActive {
        switch focuser.windowFocusState(target) {
        case .focused:
          forensicTrace?.recordDecision(
            clickNumber: clickNumber,
            decision: "alreadyFocusedPassThrough",
            target: target
          )
          if configuration.verbose && configuration.loggingEnabled {
            lines.append("action: bypass (target window is already focused)")
            lines.append("forwarding original click unchanged")
            Log.block(lines)
          }
          recordPassThroughTrace(target: target, started: started)
          return Unmanaged.passUnretained(event)

        case .unavailable(let reason):
          forensicTrace?.recordDecision(
            clickNumber: clickNumber,
            decision: "focusStateUnavailablePassThrough",
            reason: reason,
            target: target
          )
          if configuration.verbose && configuration.loggingEnabled {
            lines.append("action: bypass (\(reason))")
            lines.append("forwarding original click unchanged")
            Log.block(lines)
          }
          recordPassThroughTrace(target: target, started: started)
          return Unmanaged.passUnretained(event)

        case .unfocused:
          if configuration.observeOnly {
            forensicTrace?.recordDecision(
              clickNumber: self.clickNumber,
              decision: "observeOnlyWouldFocusWindow",
              target: target
            )
            lines.append("observe-only: would focus another window in the active application")
            lines.append("forwarding original click unchanged")
            if configuration.loggingEnabled {
              Log.block(lines)
            }
            recordPassThroughTrace(target: target, started: started)
            return Unmanaged.passUnretained(event)
          }

          lines.append(
            "focusing another window in the active application via AX..."
          )
          forensicTrace?.recordDecision(
            clickNumber: clickNumber,
            decision: "focusWindowInActiveApplication",
            target: target
          )
          let focusAttempt = focuser.focusWindow(target) { [forensicTrace] step in
            forensicTrace?.recordFocusCheckpoint(
              clickNumber: self.clickNumber,
              step: step,
              target: target
            )
          }
          forensicTrace?.recordFocusAttempt(
            clickNumber: clickNumber,
            attempt: focusAttempt
          )
          forensicTrace?.recordState(
            phase: "afterFocusBeforeReturn",
            clickNumber: clickNumber,
            target: target,
            includeAccessibility: false
          )
          lines.append(contentsOf: focusAttempt.steps.map { "  \($0.logDescription)" })
          appendForwardingLog(
            to: &lines,
            focusAttempt: focusAttempt,
            started: started
          )
          if configuration.loggingEnabled {
            Log.block(lines)
          }
          recordFocusedForwardingTrace(
            target: target,
            attempt: focusAttempt,
            started: started
          )
          return Unmanaged.passUnretained(event)
        }
      }

      if configuration.observeOnly {
        forensicTrace?.recordDecision(
          clickNumber: self.clickNumber,
          decision: "observeOnlyWouldActivateApplication",
          target: target
        )
        lines.append("observe-only: would activate \(target.applicationName)")
        lines.append("forwarding original click unchanged")
        if configuration.loggingEnabled {
          Log.block(lines)
        }
        recordPassThroughTrace(target: target, started: started)
        return Unmanaged.passUnretained(event)
      }

      lines.append("activating \(target.applicationName) via AX window focus + AppKit...")
      forensicTrace?.recordDecision(
        clickNumber: clickNumber,
        decision: "activateApplicationAndFocusWindow",
        target: target
      )
      let focusAttempt = focuser.focus(target) { [forensicTrace] step in
        forensicTrace?.recordFocusCheckpoint(
          clickNumber: self.clickNumber,
          step: step,
          target: target
        )
      }
      forensicTrace?.recordFocusAttempt(
        clickNumber: clickNumber,
        attempt: focusAttempt
      )
      forensicTrace?.recordState(
        phase: "afterFocusBeforeReturn",
        clickNumber: clickNumber,
        target: target,
        includeAccessibility: false
      )
      lines.append(contentsOf: focusAttempt.steps.map { "  \($0.logDescription)" })

      appendForwardingLog(
        to: &lines,
        focusAttempt: focusAttempt,
        started: started
      )
      if configuration.loggingEnabled {
        Log.block(lines)
      }
      recordFocusedForwardingTrace(
        target: target,
        attempt: focusAttempt,
        started: started
      )
      return Unmanaged.passUnretained(event)
    }
  }

  private func appendForwardingLog(
    to lines: inout [String],
    focusAttempt: FocusAttempt,
    started: UInt64
  ) {
    if configuration.settleMilliseconds > 0 {
      Thread.sleep(
        forTimeInterval: Double(configuration.settleMilliseconds) / 1_000.0
      )
      lines.append("held original event for \(configuration.settleMilliseconds) ms")
    }

    let totalElapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    lines.append(
      String(
        format: "forwarding SAME CGEvent (focus %.2f ms, total %.2f ms)",
        focusAttempt.elapsedMilliseconds,
        totalElapsed
      )
    )
  }

  private func recordPassThroughTrace(target: ResolvedTarget, started: UInt64) {
    guard let forensicTrace else { return }
    forensicTrace.recordForwarding(
      sequence: eventSequence,
      clickNumber: clickNumber,
      focusMilliseconds: nil,
      totalMilliseconds: elapsedMilliseconds(since: started),
      settleMilliseconds: 0
    )
    forensicTrace.schedulePostReturnStates(clickNumber: clickNumber, target: target)
  }

  private func recordFocusedForwardingTrace(
    target: ResolvedTarget,
    attempt: FocusAttempt,
    started: UInt64
  ) {
    guard let forensicTrace else { return }
    forensicTrace.recordForwarding(
      sequence: eventSequence,
      clickNumber: clickNumber,
      focusMilliseconds: attempt.elapsedMilliseconds,
      totalMilliseconds: elapsedMilliseconds(since: started),
      settleMilliseconds: configuration.settleMilliseconds
    )
    forensicTrace.schedulePostReturnStates(clickNumber: clickNumber, target: target)
  }

  private func elapsedMilliseconds(since started: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
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

public enum Log {
  public static func line(_ message: String) {
    write(message + "\n")
  }

  public static func block(_ lines: [String]) {
    write(lines.joined(separator: "\n") + "\n\n")
  }

  private static func write(_ message: String) {
    guard let data = message.data(using: .utf8) else { return }
    FileHandle.standardOutput.write(data)
  }
}
