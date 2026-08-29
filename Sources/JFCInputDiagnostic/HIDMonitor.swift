import CoreFoundation
import Foundation
import IOKit.hid
import IOKit.hidsystem

final class HIDMonitor: @unchecked Sendable {
  private struct RawReport {
    let senderKey: UInt
    let timestamp: UInt64
    let result: IOReturn
    let type: IOHIDReportType
    let reportID: UInt32
    let bytes: Data
  }

  private struct ValueSnapshot: @unchecked Sendable {
    let timestamp: UInt64
    let integerValue: CFIndex
    let length: CFIndex
    let bytes: Data
    let physicalValue: Double
    let calibratedValue: Double
    let element: IOHIDElement
  }

  private let manager: IOHIDManager
  private var nextDeviceNumber = 1
  private var deviceNumbers: [UInt: Int] = [:]
  private var recentReports: [RawReport] = []
  private var recentValues: [UInt: [UInt64: [IOHIDElementCookie: ValueSnapshot]]] = [:]
  private var recentValueTimestamps: [UInt: [UInt64]] = [:]

  init() {
    manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  }

  static func accessDescription() -> String {
    switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
    case kIOHIDAccessTypeGranted:
      "granted"
    case kIOHIDAccessTypeDenied:
      "denied"
    default:
      "unknown"
    }
  }

  static func requestAccess() -> Bool {
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
  }

  func start() throws {
    let deviceMatches: [[String: Any]] = [
      [
        kIOHIDDeviceUsagePageKey: Int(kHIDPage_GenericDesktop),
        kIOHIDDeviceUsageKey: Int(kHIDUsage_GD_Mouse),
      ],
      [
        kIOHIDDeviceUsagePageKey: Int(kHIDPage_GenericDesktop),
        kIOHIDDeviceUsageKey: Int(kHIDUsage_GD_Pointer),
      ],
      [
        kIOHIDDeviceUsagePageKey: Int(kHIDPage_Digitizer),
        kIOHIDDeviceUsageKey: Int(kHIDUsage_Dig_TouchPad),
      ],
    ]
    IOHIDManagerSetDeviceMatchingMultiple(manager, deviceMatches as CFArray)
    IOHIDManagerSetInputValueMatching(manager, nil)

    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterDeviceMatchingCallback(
      manager,
      { context, result, _, device in
        guard let context else { return }
        let owner = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
        owner.deviceMatched(device, result: result)
      },
      context
    )
    IOHIDManagerRegisterDeviceRemovalCallback(
      manager,
      { context, result, _, device in
        guard let context else { return }
        let owner = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
        owner.deviceRemoved(device, result: result)
      },
      context
    )
    IOHIDManagerRegisterInputReportWithTimeStampCallback(
      manager,
      { context, result, sender, type, reportID, report, reportLength, timestamp in
        guard let context, let sender else { return }
        let owner = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
        owner.reportReceived(
          sender: sender,
          result: result,
          type: type,
          reportID: reportID,
          report: report,
          reportLength: reportLength,
          timestamp: timestamp
        )
      },
      context
    )
    IOHIDManagerRegisterInputValueCallback(
      manager,
      { context, result, _, value in
        guard let context else { return }
        let owner = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
        owner.valueReceived(value, result: result)
      },
      context
    )

    IOHIDManagerScheduleWithRunLoop(
      manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else {
      throw HIDMonitorError.openFailed(result)
    }
  }

  func stop() {
    IOHIDManagerUnscheduleFromRunLoop(
      manager,
      CFRunLoopGetCurrent(),
      CFRunLoopMode.commonModes.rawValue
    )
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  }

  private func deviceMatched(_ device: IOHIDDevice, result: IOReturn) {
    let key = deviceKey(device)
    if deviceNumbers[key] == nil {
      deviceNumbers[key] = nextDeviceNumber
      nextDeviceNumber += 1
    }

    var record: [String: Any] = [
      "record": "hidDeviceMatched",
      "callbackMachAbsolute": MonotonicClock.now(),
      "device": deviceNumber(key),
      "result": result,
      "resultHex": JSONLines.hex(result),
      "properties": deviceProperties(device),
    ]

    if let elements = IOHIDDeviceCopyMatchingElements(
      device,
      nil,
      IOOptionBits(kIOHIDOptionsTypeNone)
    ) as? [IOHIDElement] {
      record["elements"] = elements.map(elementDescription)
    }

    JSONLines.write(record)
  }

  private func deviceRemoved(_ device: IOHIDDevice, result: IOReturn) {
    let key = deviceKey(device)
    JSONLines.write([
      "record": "hidDeviceRemoved",
      "callbackMachAbsolute": MonotonicClock.now(),
      "device": deviceNumber(key),
      "result": result,
      "resultHex": JSONLines.hex(result),
    ])
    recentValues[key] = nil
    recentValueTimestamps[key] = nil
  }

  private func reportReceived(
    sender: UnsafeMutableRawPointer,
    result: IOReturn,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex,
    timestamp: UInt64
  ) {
    recentReports.append(
      RawReport(
        senderKey: UInt(bitPattern: sender),
        timestamp: timestamp,
        result: result,
        type: type,
        reportID: reportID,
        bytes: Data(bytes: report, count: max(0, reportLength))
      ))
    if recentReports.count > 128 {
      recentReports.removeFirst()
    }
  }

  private func remember(_ value: ValueSnapshot, deviceKey: UInt) {
    if recentValues[deviceKey, default: [:]][value.timestamp] == nil {
      recentValueTimestamps[deviceKey, default: []].append(value.timestamp)
    }
    recentValues[deviceKey, default: [:]][value.timestamp, default: [:]][
      IOHIDElementGetCookie(value.element)
    ] = value

    while recentValueTimestamps[deviceKey, default: []].count > 64 {
      let expiredTimestamp = recentValueTimestamps[deviceKey]!.removeFirst()
      recentValues[deviceKey]?[expiredTimestamp] = nil
    }
  }

  private func valueReceived(_ value: IOHIDValue, result: IOReturn) {
    let element = IOHIDValueGetElement(value)
    let device = IOHIDElementGetDevice(element)
    let key = deviceKey(device)
    let timestamp = IOHIDValueGetTimeStamp(value)
    let length = IOHIDValueGetLength(value)
    let snapshot = ValueSnapshot(
      timestamp: timestamp,
      integerValue: IOHIDValueGetIntegerValue(value),
      length: length,
      bytes: Data(bytes: IOHIDValueGetBytePtr(value), count: max(0, length)),
      physicalValue: IOHIDValueGetScaledValue(
        value,
        IOHIDValueScaleType(kIOHIDValueScaleTypePhysical)
      ),
      calibratedValue: IOHIDValueGetScaledValue(
        value,
        IOHIDValueScaleType(kIOHIDValueScaleTypeCalibrated)
      ),
      element: element
    )
    remember(snapshot, deviceKey: key)

    let isPrimaryButton =
      IOHIDElementGetUsagePage(element) == kHIDPage_Button
      && IOHIDElementGetUsage(element) == 1
    guard isPrimaryButton else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(5)) { [weak self] in
      self?.writeClick(
        deviceKey: key,
        result: result,
        primaryButton: snapshot
      )
    }
  }

  private func writeClick(
    deviceKey key: UInt,
    result: IOReturn,
    primaryButton: ValueSnapshot
  ) {
    let timestamp = primaryButton.timestamp
    let values =
      recentValues[key]?[timestamp]?.values
      .sorted {
        IOHIDElementGetCookie($0.element) < IOHIDElementGetCookie($1.element)
      } ?? []

    let exactReports = recentReports.filter { $0.timestamp == timestamp }
    let selectedReports: [RawReport]
    let reportMatch: String
    if exactReports.isEmpty,
      let nearest = recentReports.min(by: {
        absoluteDifference($0.timestamp, timestamp) < absoluteDifference($1.timestamp, timestamp)
      })
    {
      selectedReports = [nearest]
      reportMatch = "nearest"
    } else {
      selectedReports = exactReports
      reportMatch = "exactTimestamp"
    }

    JSONLines.write([
      "record": "hidPrimaryButton",
      "callbackMachAbsolute": MonotonicClock.now(),
      "device": deviceNumber(key),
      "direction": primaryButton.integerValue == 0 ? "up" : "down",
      "result": result,
      "resultHex": JSONLines.hex(result),
      "timestampMachAbsolute": timestamp,
      "timestampNanoseconds": MonotonicClock.nanoseconds(timestamp),
      "primaryButton": valueDescription(primaryButton),
      "sameTimestampValues": values.map(valueDescription),
      "rawReportMatch": reportMatch,
      "rawReports": selectedReports.map {
        reportDescription($0, clickTimestamp: timestamp, deviceKey: key)
      },
    ])
  }

  private func reportDescription(
    _ report: RawReport,
    clickTimestamp: UInt64,
    deviceKey: UInt
  ) -> [String: Any] {
    [
      "timestampMachAbsolute": report.timestamp,
      "timestampNanoseconds": MonotonicClock.nanoseconds(report.timestamp),
      "timestampDifference": signedDifference(report.timestamp, clickTimestamp),
      "result": report.result,
      "resultHex": JSONLines.hex(report.result),
      "reportType": report.type.rawValue,
      "reportID": report.reportID,
      "length": report.bytes.count,
      "bytesHex": JSONLines.dataHex(report.bytes),
      "senderMatchesDevice": report.senderKey == deviceKey,
    ]
  }

  private func valueDescription(_ value: ValueSnapshot) -> [String: Any] {
    [
      "timestampMachAbsolute": value.timestamp,
      "timestampNanoseconds": MonotonicClock.nanoseconds(value.timestamp),
      "integer": value.integerValue,
      "length": value.length,
      "bytesHex": JSONLines.dataHex(value.bytes),
      "scaledPhysical": JSONLines.finite(value.physicalValue),
      "scaledCalibrated": JSONLines.finite(value.calibratedValue),
      "element": elementDescription(value.element),
    ]
  }

  private func deviceProperties(_ device: IOHIDDevice) -> [String: Any] {
    let keys = [
      kIOHIDTransportKey,
      kIOHIDVendorIDKey,
      kIOHIDProductIDKey,
      kIOHIDVersionNumberKey,
      kIOHIDManufacturerKey,
      kIOHIDProductKey,
      kIOHIDSerialNumberKey,
      kIOHIDCountryCodeKey,
      kIOHIDLocationIDKey,
      kIOHIDDeviceUsagePairsKey,
      kIOHIDDeviceUsageKey,
      kIOHIDDeviceUsagePageKey,
      kIOHIDPrimaryUsageKey,
      kIOHIDPrimaryUsagePageKey,
      kIOHIDMaxInputReportSizeKey,
      kIOHIDMaxOutputReportSizeKey,
      kIOHIDMaxFeatureReportSizeKey,
      kIOHIDReportIntervalKey,
      kIOHIDReportDescriptorKey,
      kIOHIDBuiltInKey,
      kIOHIDPhysicalDeviceUniqueIDKey,
      kIOHIDVendorIDSourceKey,
      kIOHIDUniqueIDKey,
    ]

    var result: [String: Any] = [:]
    for key in keys {
      if let value = IOHIDDeviceGetProperty(device, key as CFString) {
        result[key] = jsonValue(value)
      }
    }
    return result
  }

  private func elementDescription(_ element: IOHIDElement) -> [String: Any] {
    var result: [String: Any] = [
      "cookie": IOHIDElementGetCookie(element),
      "type": IOHIDElementGetType(element).rawValue,
      "collectionType": IOHIDElementGetCollectionType(element).rawValue,
      "usagePage": IOHIDElementGetUsagePage(element),
      "usage": IOHIDElementGetUsage(element),
      "isVirtual": IOHIDElementIsVirtual(element),
      "isRelative": IOHIDElementIsRelative(element),
      "isWrapping": IOHIDElementIsWrapping(element),
      "isArray": IOHIDElementIsArray(element),
      "isNonLinear": IOHIDElementIsNonLinear(element),
      "hasPreferredState": IOHIDElementHasPreferredState(element),
      "hasNullState": IOHIDElementHasNullState(element),
      "reportID": IOHIDElementGetReportID(element),
      "reportSizeBits": IOHIDElementGetReportSize(element),
      "reportCount": IOHIDElementGetReportCount(element),
      "unit": IOHIDElementGetUnit(element),
      "unitExponent": IOHIDElementGetUnitExponent(element),
      "logicalMin": IOHIDElementGetLogicalMin(element),
      "logicalMax": IOHIDElementGetLogicalMax(element),
      "physicalMin": IOHIDElementGetPhysicalMin(element),
      "physicalMax": IOHIDElementGetPhysicalMax(element),
    ]
    result["name"] = IOHIDElementGetName(element) as String
    if let parent = IOHIDElementGetParent(element) {
      result["parentCookie"] = IOHIDElementGetCookie(parent)
    }
    return result
  }

  private func jsonValue(_ value: CFTypeRef) -> Any {
    if CFGetTypeID(value) == CFDataGetTypeID() {
      return [
        "encoding": "hex",
        "value": JSONLines.dataHex(value as! Data),
      ]
    }
    if CFGetTypeID(value) == CFArrayGetTypeID() {
      return (value as! [Any]).map { jsonValue($0 as CFTypeRef) }
    }
    if CFGetTypeID(value) == CFDictionaryGetTypeID() {
      let dictionary = value as! [AnyHashable: Any]
      return Dictionary(
        uniqueKeysWithValues: dictionary.map {
          (String(describing: $0.key), jsonValue($0.value as CFTypeRef))
        })
    }
    if CFGetTypeID(value) == CFBooleanGetTypeID() {
      return CFBooleanGetValue((value as! CFBoolean))
    }
    if CFGetTypeID(value) == CFStringGetTypeID() || CFGetTypeID(value) == CFNumberGetTypeID() {
      return value
    }
    return String(describing: value)
  }

  private func deviceKey(_ device: IOHIDDevice) -> UInt {
    UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
  }

  private func deviceNumber(_ key: UInt) -> Int {
    if let number = deviceNumbers[key] { return number }
    let number = nextDeviceNumber
    deviceNumbers[key] = number
    nextDeviceNumber += 1
    return number
  }

  private func absoluteDifference(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    lhs >= rhs ? lhs - rhs : rhs - lhs
  }

  private func signedDifference(_ lhs: UInt64, _ rhs: UInt64) -> String {
    lhs >= rhs ? String(lhs - rhs) : "-\(rhs - lhs)"
  }
}

enum HIDMonitorError: Error, CustomStringConvertible {
  case openFailed(IOReturn)

  var description: String {
    switch self {
    case .openFailed(let result):
      "IOHIDManagerOpen failed with \(result) (\(JSONLines.hex(result)))"
    }
  }
}
