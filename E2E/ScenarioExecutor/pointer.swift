import CoreGraphics
import Foundation

struct Point: Codable {
  let x: Double
  let y: Double
}

struct Result: Codable {
  let target: Point
  let actual: Point
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
  exit(2)
}

guard CommandLine.arguments.count == 3 else {
  fail("usage: pointer.swift <x> <y>")
}
guard
  let x = Double(CommandLine.arguments[1]),
  let y = Double(CommandLine.arguments[2]),
  x.isFinite,
  y.isFinite
else {
  fail("pointer coordinates must be finite numbers")
}

let target = CGPoint(x: x, y: y)
var displayCount: UInt32 = 0
guard CGGetDisplaysWithPoint(target, 0, nil, &displayCount) == .success, displayCount > 0 else {
  fail("pointer target is outside every active display")
}
guard CGWarpMouseCursorPosition(target) == .success else {
  fail("could not position pointer")
}

usleep(50_000)
guard let event = CGEvent(source: nil) else {
  fail("could not read pointer position")
}
let actual = event.location
let tolerance = 0.75
guard abs(actual.x - target.x) <= tolerance, abs(actual.y - target.y) <= tolerance else {
  fail("pointer position mismatch: target=\(target), actual=\(actual)")
}

let result = Result(
  target: Point(x: target.x, y: target.y),
  actual: Point(x: actual.x, y: actual.y)
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
FileHandle.standardOutput.write(try encoder.encode(result))
FileHandle.standardOutput.write(Data("\n".utf8))
