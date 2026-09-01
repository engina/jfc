import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

/// Explicit, CLI-only diagnostics. This intentionally contains private UI and
/// event metadata and must never be connected to product Unified Logging.
final class ForensicTrace: @unchecked Sendable {
  private let lock = NSLock()
  private let output: FileHandle
  private let startedUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
  private let formatter = ISO8601DateFormatter()

  init(path: String, configuration: EventTapConfiguration) throws {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if !FileManager.default.fileExists(atPath: url.path) {
      guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
        throw ForensicTraceError.cannotOpen(url.path)
      }
    }
    output = try FileHandle(forWritingTo: url)
    try output.truncate(atOffset: 0)

    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    write([
      "record": "traceStart",
      "schemaVersion": 1,
      "warning":
        "Contains private window titles, controls, application metadata, cursor positions, and serialized click events. Full diagnostics may perturb event timing.",
      "outputPath": url.path,
      "process": processDescription(ProcessInfo.processInfo.processIdentifier),
      "executable": URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path,
      "arguments": CommandLine.arguments,
      "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
      "eventTap": [
        "location": "cgSessionEventTap",
        "placement": "headInsertEventTap",
        "mode": configuration.observeOnly ? "listenOnly" : "defaultTap",
        "events": ["leftMouseDown", "leftMouseUp"],
      ],
      "configuration": [
        "observeOnly": configuration.observeOnly,
        "settleMilliseconds": configuration.settleMilliseconds,
        "verbose": configuration.verbose,
      ],
      "machTimebase": [
        "numerator": timebase.numer,
        "denominator": timebase.denom,
      ],
      "displays": displayDescription(),
    ])
  }

  deinit {
    try? output.close()
  }

  func recordTapStarted() {
    write(["record": "eventTapState", "state": "started"])
  }

  func recordTapStopped() {
    write(["record": "eventTapState", "state": "stopped"])
  }

  func recordTapDisabled(reason: String) {
    write([
      "record": "eventTapState",
      "state": "disabledAndReenabled",
      "reason": reason,
    ])
  }

  func recordIncomingEvent(
    _ event: CGEvent,
    type: CGEventType,
    sequence: UInt64,
    clickNumber: UInt64,
    callbackUptimeNanoseconds: UInt64
  ) {
    var record: [String: Any] = baseRecord("incomingCGEvent")
    record.merge([
      "sequence": sequence,
      "clickNumber": clickNumber,
      "direction": type == .leftMouseDown ? "down" : "up",
      "type": type.rawValue,
      "callbackUptimeNanoseconds": callbackUptimeNanoseconds,
      "eventTimestamp": event.timestamp,
      "location": point(event.location),
      "unflippedLocation": point(event.unflippedLocation),
      "flags": event.flags.rawValue,
      "flagsHex": hex(event.flags.rawValue),
      "integerFields": integerFields(event),
      "doubleFields": [
        "mouseEventPressure": finite(event.getDoubleValueField(.mouseEventPressure))
      ],
      "pressedMouseButtons": NSEvent.pressedMouseButtons,
    ]) { _, new in new }

    if let data = event.data as Data? {
      record["serializedEventLength"] = data.count
      record["serializedEventHex"] = dataHex(data)
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
    write(record)
  }

  func recordResolutionFailure(clickNumber: UInt64, reason: String) {
    write([
      "record": "decision",
      "clickNumber": clickNumber,
      "decision": "resolutionFailurePassThrough",
      "reason": reason,
    ])
  }

  func recordDecision(
    clickNumber: UInt64,
    decision: String,
    reason: String? = nil,
    target: ResolvedTarget? = nil
  ) {
    var record: [String: Any] = [
      "record": "decision",
      "clickNumber": clickNumber,
      "decision": decision,
      "frontmostApplication": applicationDescription(
        NSWorkspace.shared.frontmostApplication
      ),
    ]
    if let reason {
      record["reason"] = reason
    }
    if let target {
      record["target"] = targetDescription(target)
    }
    write(record)
  }

  func recordFocusAttempt(clickNumber: UInt64, attempt: FocusAttempt) {
    write([
      "record": "focusAttempt",
      "clickNumber": clickNumber,
      "elapsedMilliseconds": attempt.elapsedMilliseconds,
      "steps": attempt.steps.map { step in
        [
          "phase": step.phase,
          "operation": step.operation,
          "result": step.result,
          "startedUptimeNanoseconds": step.startedUptimeNanoseconds,
          "finishedUptimeNanoseconds": step.finishedUptimeNanoseconds,
          "elapsedMilliseconds": step.elapsedMilliseconds,
        ] as [String: Any]
      },
    ])
  }

  func recordFocusCheckpoint(
    clickNumber: UInt64,
    step: FocusStep,
    target: ResolvedTarget
  ) {
    write([
      "record": "focusCheckpoint",
      "clickNumber": clickNumber,
      "step": [
        "phase": step.phase,
        "operation": step.operation,
        "result": step.result,
        "startedUptimeNanoseconds": step.startedUptimeNanoseconds,
        "finishedUptimeNanoseconds": step.finishedUptimeNanoseconds,
        "elapsedMilliseconds": step.elapsedMilliseconds,
      ],
      "frontmostApplication": applicationDescription(
        NSWorkspace.shared.frontmostApplication
      ),
      "target": targetDescription(target),
      "windows": windowListDescription(),
    ])
  }

  func recordForwarding(
    sequence: UInt64,
    clickNumber: UInt64,
    focusMilliseconds: Double?,
    totalMilliseconds: Double,
    settleMilliseconds: UInt32
  ) {
    var record: [String: Any] = [
      "record": "eventDisposition",
      "sequence": sequence,
      "clickNumber": clickNumber,
      "direction": "down",
      "disposition": "returnSameIncomingCGEvent",
      "totalMilliseconds": totalMilliseconds,
      "settleMilliseconds": settleMilliseconds,
    ]
    if let focusMilliseconds {
      record["focusMilliseconds"] = focusMilliseconds
    }
    write(record)
  }

  func recordMouseUpPassThrough(
    sequence: UInt64,
    clickNumber: UInt64,
    callbackMilliseconds: Double
  ) {
    write([
      "record": "eventDisposition",
      "sequence": sequence,
      "clickNumber": clickNumber,
      "direction": "up",
      "disposition": "returnSameIncomingCGEvent",
      "totalMilliseconds": callbackMilliseconds,
    ])
  }

  func recordState(
    phase: String,
    clickNumber: UInt64,
    target: ResolvedTarget,
    includeAccessibility: Bool = true,
    fullAccessibility: Bool = false,
    scheduledDelayMilliseconds: Int? = nil,
    scheduledAtUptimeNanoseconds: UInt64? = nil
  ) {
    let captureStarted = DispatchTime.now().uptimeNanoseconds
    var record: [String: Any] = baseRecord("systemState")
    record.merge([
      "phase": phase,
      "clickNumber": clickNumber,
      "frontmostApplication": applicationDescription(
        NSWorkspace.shared.frontmostApplication
      ),
      "target": targetDescription(target),
      "windows": windowListDescription(),
    ]) { _, new in new }

    if let scheduledDelayMilliseconds, let scheduledAtUptimeNanoseconds {
      record["scheduledDelayMilliseconds"] = scheduledDelayMilliseconds
      record["actualStartDelayMilliseconds"] =
        Double(captureStarted - scheduledAtUptimeNanoseconds) / 1_000_000
    }

    if includeAccessibility {
      record["targetApplicationState"] = targetApplicationState(target)
      record["targetWindowState"] = accessibilityState(
        target.window,
        attributes: lightweightWindowAttributes
      )
      record["targetElementState"] = accessibilityState(
        target.element,
        attributes: lightweightElementAttributes
      )
    }

    if fullAccessibility {
      record["fullAccessibility"] = [
        "application": fullAccessibilityDescription(
          AXUIElementCreateApplication(target.pid)
        ),
        "window": fullAccessibilityDescription(target.window),
        "element": fullAccessibilityDescription(target.element),
      ]
      record["displays"] = displayDescription()
    }
    write(record)
  }

  func schedulePostReturnStates(clickNumber: UInt64, target: ResolvedTarget) {
    let context = PostReturnContext(
      trace: self,
      clickNumber: clickNumber,
      target: target,
      scheduledAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
    )
    for delay in [0, 1, 5, 10, 20, 50, 100, 250] {
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
        context.trace.recordState(
          phase: "postReturn+\(delay)ms",
          clickNumber: context.clickNumber,
          target: context.target,
          fullAccessibility: delay == 250,
          scheduledDelayMilliseconds: delay,
          scheduledAtUptimeNanoseconds: context.scheduledAtUptimeNanoseconds
        )
      }
    }
  }

  private var lightweightWindowAttributes: [CFString] {
    [
      kAXRoleAttribute as CFString,
      kAXSubroleAttribute as CFString,
      kAXTitleAttribute as CFString,
      kAXPositionAttribute as CFString,
      kAXSizeAttribute as CFString,
      kAXMainAttribute as CFString,
      kAXFocusedAttribute as CFString,
      kAXMinimizedAttribute as CFString,
      kAXEnabledAttribute as CFString,
    ]
  }

  private var lightweightElementAttributes: [CFString] {
    [
      kAXRoleAttribute as CFString,
      kAXSubroleAttribute as CFString,
      kAXTitleAttribute as CFString,
      kAXDescriptionAttribute as CFString,
      kAXIdentifierAttribute as CFString,
      kAXValueAttribute as CFString,
      kAXEnabledAttribute as CFString,
      kAXFocusedAttribute as CFString,
      kAXPositionAttribute as CFString,
      kAXSizeAttribute as CFString,
    ]
  }

  private func write(_ object: [String: Any]) {
    var enriched = object
    if enriched["wallTime"] == nil {
      enriched["wallTime"] = formatter.string(from: Date())
    }
    if enriched["traceUptimeNanoseconds"] == nil {
      enriched["traceUptimeNanoseconds"] =
        DispatchTime.now().uptimeNanoseconds - startedUptimeNanoseconds
    }

    lock.lock()
    defer { lock.unlock() }
    do {
      let data = try JSONSerialization.data(
        withJSONObject: enriched,
        options: [.sortedKeys, .withoutEscapingSlashes]
      )
      output.write(data)
      output.write(Data([0x0A]))
    } catch {
      let message = "error: could not encode forensic record: \(error)\n"
      FileHandle.standardError.write(Data(message.utf8))
    }
  }

  private func baseRecord(_ name: String) -> [String: Any] {
    [
      "record": name,
      "wallTime": formatter.string(from: Date()),
      "traceUptimeNanoseconds":
        DispatchTime.now().uptimeNanoseconds - startedUptimeNanoseconds,
    ]
  }

  private func targetDescription(_ target: ResolvedTarget) -> [String: Any] {
    var result: [String: Any] = [
      "pid": target.pid,
      "applicationName": target.applicationName,
      "windowTitle": target.windowTitle,
      "elementRole": target.elementRole,
      "shouldBypass": target.shouldBypass,
    ]
    if let bundleIdentifier = target.bundleIdentifier {
      result["bundleIdentifier"] = bundleIdentifier
    }
    if let subrole = target.elementSubrole {
      result["elementSubrole"] = subrole
    }
    if let reason = target.bypassReason {
      result["bypassReason"] = reason
    }
    return result
  }

  private func targetApplicationState(_ target: ResolvedTarget) -> [String: Any] {
    let application = NSRunningApplication(processIdentifier: target.pid)
    let axApplication = AXUIElementCreateApplication(target.pid)
    AXUIElementSetMessagingTimeout(axApplication, 0.1)
    return [
      "runningApplication": applicationDescription(application),
      "accessibility": accessibilityState(
        axApplication,
        attributes: [
          kAXRoleAttribute as CFString,
          kAXTitleAttribute as CFString,
          kAXFrontmostAttribute as CFString,
          kAXFocusedWindowAttribute as CFString,
          kAXMainWindowAttribute as CFString,
          kAXHiddenAttribute as CFString,
        ]
      ),
    ]
  }

  private func applicationDescription(_ application: NSRunningApplication?) -> [String: Any] {
    guard let application else { return ["available": false] }
    var result: [String: Any] = [
      "available": true,
      "pid": application.processIdentifier,
      "localizedName": application.localizedName ?? NSNull(),
      "bundleIdentifier": application.bundleIdentifier ?? NSNull(),
      "bundleURL": application.bundleURL?.path ?? NSNull(),
      "executableURL": application.executableURL?.path ?? NSNull(),
      "isActive": application.isActive,
      "isHidden": application.isHidden,
      "isTerminated": application.isTerminated,
      "activationPolicy": application.activationPolicy.rawValue,
    ]
    if let launchDate = application.launchDate {
      result["launchDate"] = formatter.string(from: launchDate)
    }
    return result
  }

  private func processDescription(_ pid: pid_t) -> [String: Any] {
    applicationDescription(NSRunningApplication(processIdentifier: pid))
  }

  private func accessibilityState(
    _ element: AXUIElement?,
    attributes: [CFString]
  ) -> [String: Any] {
    guard let element else { return ["available": false] }
    AXUIElementSetMessagingTimeout(element, 0.1)
    var pid: pid_t = 0
    let pidError = AXUIElementGetPid(element, &pid)
    var values: [String: Any] = [:]
    for attribute in attributes {
      values[attribute as String] = attributeDescription(element, attribute: attribute)
    }
    return [
      "available": true,
      "pid": pid,
      "pidResult": axErrorDescription(pidError),
      "attributes": values,
    ]
  }

  private func fullAccessibilityDescription(_ element: AXUIElement?) -> [String: Any] {
    guard let element else { return ["available": false] }
    AXUIElementSetMessagingTimeout(element, 0.1)

    var result = accessibilityState(element, attributes: [])
    var attributeNames: CFArray?
    let attributesError = AXUIElementCopyAttributeNames(element, &attributeNames)
    let attributes = (attributeNames as? [String] ?? []).sorted()
    result["attributeNamesResult"] = axErrorDescription(attributesError)
    result["attributeCount"] = attributes.count
    result["attributes"] = Dictionary(
      uniqueKeysWithValues: attributes.map { name in
        (name, attributeDescription(element, attribute: name as CFString))
      })

    var actionNames: CFArray?
    let actionsError = AXUIElementCopyActionNames(element, &actionNames)
    result["actionNamesResult"] = axErrorDescription(actionsError)
    result["actions"] = (actionNames as? [String] ?? []).sorted()

    var parameterizedNames: CFArray?
    let parameterizedError = AXUIElementCopyParameterizedAttributeNames(
      element,
      &parameterizedNames
    )
    result["parameterizedAttributeNamesResult"] = axErrorDescription(parameterizedError)
    result["parameterizedAttributes"] = (parameterizedNames as? [String] ?? []).sorted()
    return result
  }

  private func attributeDescription(
    _ element: AXUIElement,
    attribute: CFString
  ) -> [String: Any] {
    var settable = DarwinBoolean(false)
    let settableError = AXUIElementIsAttributeSettable(element, attribute, &settable)
    var value: CFTypeRef?
    let valueError = AXUIElementCopyAttributeValue(element, attribute, &value)
    var result: [String: Any] = [
      "copyResult": axErrorDescription(valueError),
      "settableResult": axErrorDescription(settableError),
      "settable": settable.boolValue,
    ]
    if valueError == .success, let value {
      result["value"] = accessibilityValue(value, depth: 0)
      result["cfTypeID"] = CFGetTypeID(value)
    }
    return result
  }

  private func accessibilityValue(_ value: CFTypeRef, depth: Int) -> Any {
    if depth >= 3 {
      return ["truncated": true, "description": String(describing: value)]
    }

    let typeID = CFGetTypeID(value)
    if typeID == AXUIElementGetTypeID() {
      return accessibilityElementReference(value as! AXUIElement, includeAttributes: depth == 0)
    }
    if typeID == AXValueGetTypeID() {
      return axValueDescription(value as! AXValue)
    }
    if typeID == CFArrayGetTypeID(), let values = value as? [Any] {
      let limit = min(values.count, 256)
      return [
        "count": values.count,
        "truncated": values.count > limit,
        "values": values.prefix(limit).map {
          accessibilityValue($0 as CFTypeRef, depth: depth + 1)
        },
      ]
    }
    if typeID == CFDictionaryGetTypeID(), let dictionary = value as? [AnyHashable: Any] {
      return Dictionary(
        uniqueKeysWithValues: dictionary.map { key, item in
          (String(describing: key), accessibilityValue(item as CFTypeRef, depth: depth + 1))
        })
    }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number }
    if let url = value as? URL { return url.absoluteString }
    if let attributed = value as? NSAttributedString { return attributed.string }
    return [
      "cfTypeID": typeID,
      "description": String(describing: value),
    ]
  }

  private func accessibilityElementReference(
    _ element: AXUIElement,
    includeAttributes: Bool
  ) -> [String: Any] {
    AXUIElementSetMessagingTimeout(element, 0.1)
    var pid: pid_t = 0
    let pidError = AXUIElementGetPid(element, &pid)
    var result: [String: Any] = [
      "type": "AXUIElement",
      "pid": pid,
      "pidResult": axErrorDescription(pidError),
      "description": String(describing: element),
    ]
    guard includeAttributes else { return result }
    for attribute in [
      kAXRoleAttribute as CFString,
      kAXSubroleAttribute as CFString,
      kAXTitleAttribute as CFString,
      kAXIdentifierAttribute as CFString,
    ] {
      var value: CFTypeRef?
      if AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
        let value
      {
        result[attribute as String] = accessibilityValue(value, depth: 2)
      }
    }
    return result
  }

  private func axValueDescription(_ value: AXValue) -> [String: Any] {
    switch AXValueGetType(value) {
    case .cgPoint:
      var point = CGPoint.zero
      AXValueGetValue(value, .cgPoint, &point)
      return ["type": "CGPoint", "value": self.point(point)]
    case .cgSize:
      var size = CGSize.zero
      AXValueGetValue(value, .cgSize, &size)
      return ["type": "CGSize", "value": ["width": size.width, "height": size.height]]
    case .cgRect:
      var rect = CGRect.zero
      AXValueGetValue(value, .cgRect, &rect)
      return ["type": "CGRect", "value": rectangle(rect)]
    case .cfRange:
      var range = CFRange()
      AXValueGetValue(value, .cfRange, &range)
      return ["type": "CFRange", "value": ["location": range.location, "length": range.length]]
    case .axError:
      var error = AXError.success
      AXValueGetValue(value, .axError, &error)
      return ["type": "AXError", "value": axErrorDescription(error)]
    case .illegal:
      return ["type": "illegal"]
    @unknown default:
      return ["type": "unknown", "description": String(describing: value)]
    }
  }

  private func windowListDescription() -> [[String: Any]] {
    guard
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else { return [] }

    return windows.enumerated().map { index, window in
      var result = Dictionary(
        uniqueKeysWithValues: window.map { key, value in
          (key, jsonValue(value, depth: 0))
        })
      result["zIndex"] = index
      return result
    }
  }

  private func displayDescription() -> [[String: Any]] {
    NSScreen.screens.enumerated().map { index, screen in
      let displayID =
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
        .uint32Value ?? 0
      var result: [String: Any] = [
        "screenIndex": index,
        "displayID": displayID,
        "isMain": screen == NSScreen.main,
        "frame": rectangle(screen.frame),
        "visibleFrame": rectangle(screen.visibleFrame),
        "backingScaleFactor": screen.backingScaleFactor,
        "localizedName": screen.localizedName,
        "rotationDegrees": CGDisplayRotation(displayID),
        "pixelWidth": CGDisplayPixelsWide(displayID),
        "pixelHeight": CGDisplayPixelsHigh(displayID),
        "bounds": rectangle(CGDisplayBounds(displayID)),
      ]
      if let mode = CGDisplayCopyDisplayMode(displayID) {
        result["mode"] = [
          "width": mode.width,
          "height": mode.height,
          "pixelWidth": mode.pixelWidth,
          "pixelHeight": mode.pixelHeight,
          "refreshRate": mode.refreshRate,
          "ioFlags": mode.ioFlags,
        ]
      }
      return result
    }
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

  private func point(_ point: CGPoint) -> [String: Any] {
    ["x": finite(point.x), "y": finite(point.y)]
  }

  private func rectangle(_ rectangle: CGRect) -> [String: Any] {
    [
      "x": finite(rectangle.origin.x),
      "y": finite(rectangle.origin.y),
      "width": finite(rectangle.width),
      "height": finite(rectangle.height),
    ]
  }

  private func jsonValue(_ value: Any, depth: Int) -> Any {
    if depth >= 4 { return String(describing: value) }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number }
    if let dictionary = value as? [String: Any] {
      return Dictionary(
        uniqueKeysWithValues: dictionary.map {
          ($0.key, jsonValue($0.value, depth: depth + 1))
        })
    }
    if let dictionary = value as? NSDictionary {
      return Dictionary(
        uniqueKeysWithValues: dictionary.map { key, item in
          (String(describing: key), jsonValue(item, depth: depth + 1))
        })
    }
    if let array = value as? [Any] {
      return array.map { jsonValue($0, depth: depth + 1) }
    }
    return String(describing: value)
  }

  private func axErrorDescription(_ error: AXError) -> String {
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

  private func finite(_ value: Double) -> Any {
    value.isFinite ? value : String(describing: value)
  }

  private func hex<T: FixedWidthInteger>(_ value: T) -> String {
    "0x" + String(UInt64(truncatingIfNeeded: value), radix: 16)
  }

  private func dataHex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }
}

private final class PostReturnContext: @unchecked Sendable {
  let trace: ForensicTrace
  let clickNumber: UInt64
  let target: ResolvedTarget
  let scheduledAtUptimeNanoseconds: UInt64

  init(
    trace: ForensicTrace,
    clickNumber: UInt64,
    target: ResolvedTarget,
    scheduledAtUptimeNanoseconds: UInt64
  ) {
    self.trace = trace
    self.clickNumber = clickNumber
    self.target = target
    self.scheduledAtUptimeNanoseconds = scheduledAtUptimeNanoseconds
  }
}

private enum ForensicTraceError: Error, CustomStringConvertible {
  case cannotOpen(String)

  var description: String {
    switch self {
    case .cannotOpen(let path):
      "could not open \(path)"
    }
  }
}
