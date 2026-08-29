import Foundation

struct DiagnosticOptions {
  var promptForPermissions = true
  var clickLimit: UInt64?
  var outputPath: String?

  static let usage = """
    jfc-input-diagnostic — compare physical and synthetic macOS left clicks

    Usage:
      jfc-input-diagnostic [options]

    Options:
      --clicks <count>            Exit after this many complete session-level clicks
      --output <path>             Write JSON Lines to this file instead of standard output
      --no-permission-prompt      Do not open the Input Monitoring permission prompt
      -h, --help                  Show this help

    Output is JSON Lines. The executable observes only leftMouseDown and
    leftMouseUp. Device identity, raw HID reports, pointer coordinates, and
    source process identifiers may be present in the output.
    """

  static func parse(_ arguments: [String]) throws -> DiagnosticOptions {
    var options = DiagnosticOptions()
    var index = 0

    while index < arguments.count {
      switch arguments[index] {
      case "--clicks":
        index += 1
        guard index < arguments.count,
          let count = UInt64(arguments[index]),
          count > 0
        else {
          throw DiagnosticOptionError("--clicks requires a positive integer")
        }
        options.clickLimit = count

      case "--no-permission-prompt":
        options.promptForPermissions = false

      case "--output":
        index += 1
        guard index < arguments.count, !arguments[index].isEmpty else {
          throw DiagnosticOptionError("--output requires a file path")
        }
        options.outputPath = arguments[index]

      case "-h", "--help":
        throw DiagnosticHelpRequested()

      default:
        throw DiagnosticOptionError("unknown option: \(arguments[index])")
      }

      index += 1
    }

    return options
  }
}

struct DiagnosticOptionError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}

struct DiagnosticHelpRequested: Error {}
