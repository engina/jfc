import Foundation

enum JSONLines {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var output = FileHandle.standardOutput

  static func setOutput(path: String) throws {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    if !FileManager.default.fileExists(atPath: url.path) {
      guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
        throw JSONLinesError.cannotOpenOutput(url.path)
      }
    }
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: 0)
    output = handle
  }

  static func write(_ object: [String: Any]) {
    lock.lock()
    defer { lock.unlock() }
    do {
      let data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
      )
      output.write(data)
      output.write(Data([0x0A]))
    } catch {
      let message = "error: could not encode diagnostic record: \(error)\n"
      FileHandle.standardError.write(Data(message.utf8))
    }
  }

  static func error(_ message: String) {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  }

  static func hex<T: FixedWidthInteger>(_ value: T) -> String {
    "0x" + String(UInt64(truncatingIfNeeded: value), radix: 16)
  }

  static func dataHex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }

  static func finite(_ value: Double) -> Any {
    value.isFinite ? value : String(describing: value)
  }
}

enum JSONLinesError: Error, CustomStringConvertible {
  case cannotOpenOutput(String)

  var description: String {
    switch self {
    case .cannotOpenOutput(let path):
      "could not open diagnostic output: \(path)"
    }
  }
}
