import AppKit
import CoreGraphics
import Foundation

final class CGEventMonitor: @unchecked Sendable {
  private enum Stage: String, CaseIterable {
    case hid
    case session
    case annotatedSession

    var location: CGEventTapLocation {
      switch self {
      case .hid: .cghidEventTap
      case .session: .cgSessionEventTap
      case .annotatedSession: .cgAnnotatedSessionEventTap
      }
    }
  }

  private final class TapContext {
    unowned let owner: CGEventMonitor
    let stage: Stage

    init(owner: CGEventMonitor, stage: Stage) {
      self.owner = owner
      self.stage = stage
    }
  }

  private struct TapHandle {
    let port: CFMachPort
    let source: CFRunLoopSource
    let context: TapContext
  }

  private struct PendingEvent: @unchecked Sendable {
    let event: CGEvent
    let type: CGEventType
    let stage: Stage
    let sequence: UInt64
  }

  private var handles: [TapHandle] = []
  private var stageSequences: [Stage: UInt64] = [:]
  private var completedSessionClicks: UInt64 = 0
  private let clickLimit: UInt64?
  private let completion: () -> Void

  init(clickLimit: UInt64?, completion: @escaping () -> Void) {
    self.clickLimit = clickLimit
    self.completion = completion
  }

  static func accessGranted() -> Bool {
    CGPreflightListenEventAccess()
  }

  static func requestAccess() -> Bool {
    CGRequestListenEventAccess()
  }

  func start() throws {
    let mask =
      (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
      | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)

    for stage in Stage.allCases {
      let context = TapContext(owner: self, stage: stage)
      let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()
        return context.owner.handle(type: type, event: event, stage: context.stage)
      }
      guard
        let port = CGEvent.tapCreate(
          tap: stage.location,
          place: .headInsertEventTap,
          options: .listenOnly,
          eventsOfInterest: mask,
          callback: callback,
          userInfo: Unmanaged.passUnretained(context).toOpaque()
        )
      else {
        JSONLines.error("could not create \(stage.rawValue) CGEvent tap")
        continue
      }
      guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
        CFMachPortInvalidate(port)
        JSONLines.error("could not create \(stage.rawValue) event-tap run-loop source")
        continue
      }
      handles.append(TapHandle(port: port, source: source, context: context))
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
      CGEvent.tapEnable(tap: port, enable: true)
    }

    guard !handles.isEmpty else {
      throw CGEventMonitorError.noEventTaps
    }
  }

  func stop() {
    for handle in handles {
      CGEvent.tapEnable(tap: handle.port, enable: false)
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), handle.source, .commonModes)
      CFMachPortInvalidate(handle.port)
    }
    handles.removeAll()
  }

  private func handle(
    type: CGEventType,
    event: CGEvent,
    stage: Stage
  ) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let handle = handles.first(where: { $0.context.stage == stage }) {
        CGEvent.tapEnable(tap: handle.port, enable: true)
      }
      JSONLines.write([
        "record": "cgEventTapDisabled",
        "stage": stage.rawValue,
        "reason": type == .tapDisabledByTimeout ? "timeout" : "userInput",
      ])
      return Unmanaged.passUnretained(event)
    }

    guard type == .leftMouseDown || type == .leftMouseUp else {
      return Unmanaged.passUnretained(event)
    }

    stageSequences[stage, default: 0] += 1
    let pending = PendingEvent(
      event: event.copy()!,
      type: type,
      stage: stage,
      sequence: stageSequences[stage, default: 0]
    )
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      JSONLines.write(
        eventDescription(
          pending.event,
          type: pending.type,
          stage: pending.stage,
          sequence: pending.sequence
        ))
    }

    if stage == .session, type == .leftMouseUp, let clickLimit {
      completedSessionClicks += 1
      if completedSessionClicks >= clickLimit {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [completion] in
          completion()
        }
      }
    }
    return Unmanaged.passUnretained(event)
  }

  private func eventDescription(
    _ event: CGEvent,
    type: CGEventType,
    stage: Stage,
    sequence: UInt64
  ) -> [String: Any] {
    var record: [String: Any] = [
      "record": "cgEvent",
      "stage": stage.rawValue,
      "sequence": sequence,
      "direction": type == .leftMouseDown ? "down" : "up",
      "type": type.rawValue,
      "callbackMachAbsolute": MonotonicClock.now(),
      "eventTimestamp": event.timestamp,
      "location": point(event.location),
      "unflippedLocation": point(event.unflippedLocation),
      "flags": event.flags.rawValue,
      "flagsHex": JSONLines.hex(event.flags.rawValue),
      "integerFields": integerFields(event),
      "doubleFields": doubleFields(event),
      "pressedMouseButtons": NSEvent.pressedMouseButtons,
    ]

    if let data = event.data as Data? {
      record["serializedEventLength"] = data.count
      record["serializedEventHex"] = JSONLines.dataHex(data)
    }
    if let nsEvent = NSEvent(cgEvent: event) {
      record["nsEvent"] = nsEventDescription(nsEvent)
    }
    if let source = CGEventSource(event: event) {
      record["source"] = [
        "stateID": source.sourceStateID.rawValue,
        "userData": source.userData,
        "pixelsPerLine": source.pixelsPerLine,
      ]
    }
    return record
  }

  private func integerFields(_ event: CGEvent) -> [String: Int64] {
    let fields: [(String, CGEventField)] = [
      ("mouseEventNumber", .mouseEventNumber),
      ("mouseEventClickState", .mouseEventClickState),
      ("mouseEventButtonNumber", .mouseEventButtonNumber),
      ("mouseEventDeltaX", .mouseEventDeltaX),
      ("mouseEventDeltaY", .mouseEventDeltaY),
      ("mouseEventInstantMouser", .mouseEventInstantMouser),
      ("mouseEventSubtype", .mouseEventSubtype),
      ("eventTargetProcessSerialNumber", .eventTargetProcessSerialNumber),
      ("eventTargetUnixProcessID", .eventTargetUnixProcessID),
      ("eventSourceUnixProcessID", .eventSourceUnixProcessID),
      ("eventSourceUserData", .eventSourceUserData),
      ("eventSourceUserID", .eventSourceUserID),
      ("eventSourceGroupID", .eventSourceGroupID),
      ("eventSourceStateID", .eventSourceStateID),
      ("mouseEventWindowUnderMousePointer", .mouseEventWindowUnderMousePointer),
      (
        "mouseEventWindowUnderMousePointerThatCanHandleThisEvent",
        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent
      ),
      ("eventUnacceleratedPointerMovementX", .eventUnacceleratedPointerMovementX),
      ("eventUnacceleratedPointerMovementY", .eventUnacceleratedPointerMovementY),
    ]
    return Dictionary(
      uniqueKeysWithValues: fields.map {
        ($0.0, event.getIntegerValueField($0.1))
      })
  }

  private func doubleFields(_ event: CGEvent) -> [String: Double] {
    [
      "mouseEventPressure": event.getDoubleValueField(.mouseEventPressure)
    ]
  }

  private func nsEventDescription(_ event: NSEvent) -> [String: Any] {
    [
      "type": event.type.rawValue,
      "subtype": event.subtype.rawValue,
      "modifierFlags": event.modifierFlags.rawValue,
      "timestamp": event.timestamp,
      "windowNumber": event.windowNumber,
      "locationInWindow": point(event.locationInWindow),
      "clickCount": event.clickCount,
      "buttonNumber": event.buttonNumber,
      "eventNumber": event.eventNumber,
      "pressure": event.pressure,
      "associatedEventsMask": event.associatedEventsMask.rawValue,
    ]
  }

  private func point(_ point: CGPoint) -> [String: Double] {
    ["x": point.x, "y": point.y]
  }
}

enum CGEventMonitorError: Error, CustomStringConvertible {
  case noEventTaps

  var description: String {
    switch self {
    case .noEventTaps:
      "could not create any Core Graphics event tap; grant Input Monitoring and restart"
    }
  }
}
