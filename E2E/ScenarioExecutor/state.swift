import AppKit
import CoreGraphics
import Foundation

struct Rectangle: Codable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double

  init(_ rectangle: CGRect) {
    x = rectangle.origin.x
    y = rectangle.origin.y
    width = rectangle.size.width
    height = rectangle.size.height
  }
}

struct DisplayState: Codable {
  let index: Int
  let id: UInt32
  let bounds: Rectangle
}

struct WindowState: Codable {
  let zIndex: Int
  let number: Int
  let ownerName: String
  let bundleID: String?
  let pid: Int32
  let title: String
  let layer: Int
  let bounds: Rectangle
  let display: Int?
}

struct MachineState: Codable {
  let screenCaptureAllowed: Bool
  let frontmostBundleID: String?
  let displays: [DisplayState]
  let windows: [WindowState]
}

let displays: [DisplayState] = NSScreen.screens.enumerated().compactMap { offset, screen in
  let key = NSDeviceDescriptionKey("NSScreenNumber")
  guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
  let id = CGDirectDisplayID(number.uint32Value)
  return DisplayState(index: offset + 1, id: id, bounds: Rectangle(CGDisplayBounds(id)))
}

func displayIndex(containing rectangle: CGRect) -> Int? {
  let center = CGPoint(x: rectangle.midX, y: rectangle.midY)
  return displays.first { display in
    CGRect(
      x: display.bounds.x,
      y: display.bounds.y,
      width: display.bounds.width,
      height: display.bounds.height
    ).contains(center)
  }?.index
}

let rawWindows =
  CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
  as? [[String: Any]] ?? []
let windows: [WindowState] = rawWindows.enumerated().compactMap { offset, item in
  guard
    let ownerName = item[kCGWindowOwnerName as String] as? String,
    let pidNumber = item[kCGWindowOwnerPID as String] as? NSNumber,
    let number = item[kCGWindowNumber as String] as? NSNumber,
    let layer = item[kCGWindowLayer as String] as? NSNumber,
    let boundsDictionary = item[kCGWindowBounds as String] as? [String: Any],
    let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
  else { return nil }

  let pid = pid_t(pidNumber.int32Value)
  return WindowState(
    zIndex: offset,
    number: number.intValue,
    ownerName: ownerName,
    bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
    pid: pid,
    title: item[kCGWindowName as String] as? String ?? "",
    layer: layer.intValue,
    bounds: Rectangle(bounds),
    display: displayIndex(containing: bounds)
  )
}

let state = MachineState(
  screenCaptureAllowed: CGPreflightScreenCaptureAccess(),
  frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
  displays: displays,
  windows: windows
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
FileHandle.standardOutput.write(try encoder.encode(state))
FileHandle.standardOutput.write(Data("\n".utf8))
