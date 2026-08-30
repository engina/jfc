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

struct Display: Codable {
  let captureIndex: Int
  let displayID: UInt32
  let isMain: Bool
  let name: String
  let frame: Rectangle
  let visibleFrame: Rectangle
  let coreGraphicsBounds: Rectangle
  let backingScaleFactor: Double
  let pixelWidth: Int
  let pixelHeight: Int
}

struct DisplayDump: Codable {
  let capturedAt: String
  let displayCount: Int
  let screenCaptureAllowed: Bool
  let displays: [Display]
}

let screens = NSScreen.screens
let displays = screens.enumerated().compactMap { offset, screen -> Display? in
  let key = NSDeviceDescriptionKey("NSScreenNumber")
  guard let number = screen.deviceDescription[key] as? NSNumber else {
    return nil
  }

  let displayID = CGDirectDisplayID(number.uint32Value)
  return Display(
    captureIndex: offset + 1,
    displayID: displayID,
    isMain: displayID == CGMainDisplayID(),
    name: screen.localizedName,
    frame: Rectangle(screen.frame),
    visibleFrame: Rectangle(screen.visibleFrame),
    coreGraphicsBounds: Rectangle(CGDisplayBounds(displayID)),
    backingScaleFactor: screen.backingScaleFactor,
    pixelWidth: Int((screen.frame.width * screen.backingScaleFactor).rounded()),
    pixelHeight: Int((screen.frame.height * screen.backingScaleFactor).rounded())
  )
}

let dump = DisplayDump(
  capturedAt: ISO8601DateFormatter().string(from: Date()),
  displayCount: displays.count,
  screenCaptureAllowed: CGPreflightScreenCaptureAccess(),
  displays: displays
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let data = try encoder.encode(dump)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
