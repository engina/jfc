import ApplicationServices
import CoreGraphics
import Foundation

@main
enum JFCMain {
  static func main() {
    let options: CLIOptions
    do {
      options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
    } catch is CLIHelpRequested {
      print(CLIOptions.usage)
      return
    } catch {
      FileHandle.standardError.write(Data("error: \(error)\n\n\(CLIOptions.usage)\n".utf8))
      Foundation.exit(2)
    }

    let accessibilityGranted = AccessibilityPermission.isTrusted(
      prompt: options.promptForPermissions
    )
    var inputMonitoringGranted = CGPreflightListenEventAccess()
    if !inputMonitoringGranted && options.promptForPermissions {
      inputMonitoringGranted = CGRequestListenEventAccess()
    }

    Log.block([
      "jfc first-click experiment",
      "mode: \(options.observeOnly ? "observe only" : "same-event pass-through")",
      "activation: \(options.activationStrategy.rawValue)",
      "settle: \(options.settleMilliseconds) ms",
      "Accessibility: \(accessibilityGranted ? "granted" : "NOT GRANTED")",
      "Input Monitoring: \(inputMonitoringGranted ? "granted" : "NOT GRANTED")",
    ])

    guard accessibilityGranted else {
      permissionInstructions()
      Foundation.exit(1)
    }

    let eventTap = EventTap(options: options)
    do {
      try eventTap.start()
    } catch {
      FileHandle.standardError.write(Data("error: \(error)\n".utf8))
      permissionInstructions()
      Foundation.exit(1)
    }

    Log.line("Listening for leftMouseDown/leftMouseUp. Press Control-C to stop.\n")
    eventTap.run()
  }

  private static func permissionInstructions() {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path
    Log.block([
      "Permissions are required:",
      "1. Open System Settings > Privacy & Security > Accessibility.",
      "2. Enable or add this executable: \(executable)",
      "3. If macOS asks, also enable it under Input Monitoring.",
      "4. Quit and restart jfc after changing either permission.",
      "",
      "Tip: run `swift build`, then grant the stable .build/debug/jfc executable.",
    ])
  }
}
