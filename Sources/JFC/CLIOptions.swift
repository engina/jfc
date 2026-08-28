import Foundation
import JFCCore

struct CLIOptions {
  var observeOnly = false
  var promptForPermissions = true
  var settleMilliseconds: UInt32 = 0
  var verbose = false

  var eventTapConfiguration: EventTapConfiguration {
    EventTapConfiguration(
      observeOnly: observeOnly,
      settleMilliseconds: settleMilliseconds,
      verbose: verbose,
      loggingEnabled: true
    )
  }

  static let usage = """
    jfc — first-click focus experiment for macOS

    Usage:
      jfc [options]

    Options:
      --settle-ms <0...100>       Hold the original mouse-down briefly after focus
                                  (default: 0; no event is synthesized)
      --observe                   Resolve and log clicks without changing focus
      --no-permission-prompt      Check permissions without opening macOS prompts
      --verbose                   Log passed-through mouse-up and skipped clicks
      -h, --help                  Show this help

    Start with the defaults. If the first click only focuses Chrome, compare:

      jfc --settle-ms 10
      jfc --settle-ms 20
    """

  static func parse(_ arguments: [String]) throws -> CLIOptions {
    var options = CLIOptions()
    var index = 0

    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--settle-ms":
        index += 1
        guard index < arguments.count,
          let milliseconds = UInt32(arguments[index]),
          milliseconds <= 100
        else {
          throw CLIError("--settle-ms requires an integer from 0 through 100")
        }
        options.settleMilliseconds = milliseconds

      case "--observe":
        options.observeOnly = true

      case "--no-permission-prompt":
        options.promptForPermissions = false

      case "--verbose":
        options.verbose = true

      case "-h", "--help":
        throw CLIHelpRequested()

      default:
        throw CLIError("unknown option: \(argument)")
      }

      index += 1
    }

    return options
  }
}

struct CLIError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}

struct CLIHelpRequested: Error {}
