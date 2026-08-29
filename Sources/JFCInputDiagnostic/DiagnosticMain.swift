import CoreFoundation
import Foundation

@main
enum DiagnosticMain {
  static func main() {
    let options: DiagnosticOptions
    do {
      options = try DiagnosticOptions.parse(Array(CommandLine.arguments.dropFirst()))
    } catch is DiagnosticHelpRequested {
      print(DiagnosticOptions.usage)
      return
    } catch {
      FileHandle.standardError.write(Data("error: \(error)\n\n\(DiagnosticOptions.usage)\n".utf8))
      Foundation.exit(2)
    }

    if let outputPath = options.outputPath {
      do {
        try JSONLines.setOutput(path: outputPath)
      } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        Foundation.exit(2)
      }
    }

    let hidAccessBefore = HIDMonitor.accessDescription()
    let cgAccessBefore = CGEventMonitor.accessGranted()
    var permissionRequestAccepted: [String: Bool] = [:]
    if options.promptForPermissions {
      if hidAccessBefore != "granted" {
        permissionRequestAccepted["ioHIDListen"] = HIDMonitor.requestAccess()
      }
      if !cgAccessBefore {
        permissionRequestAccepted["cgListenEvent"] = CGEventMonitor.requestAccess()
      }
    }

    JSONLines.write([
      "record": "diagnosticStarted",
      "pid": ProcessInfo.processInfo.processIdentifier,
      "executable": URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path,
      "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
      "ioHIDListenAccess": hidAccessBefore,
      "cgListenEventAccess": cgAccessBefore,
      "permissionRequestAccepted": permissionRequestAccepted,
      "scope": "leftMouseDown and leftMouseUp only",
      "warning": "output may contain device identity, raw HID data, coordinates, and process IDs",
    ])

    let hidMonitor = HIDMonitor()
    do {
      try hidMonitor.start()
    } catch {
      JSONLines.error(String(describing: error))
    }

    var cgMonitor: CGEventMonitor!
    cgMonitor = CGEventMonitor(clickLimit: options.clickLimit) {
      cgMonitor.stop()
      hidMonitor.stop()
      CFRunLoopStop(CFRunLoopGetMain())
    }
    do {
      try cgMonitor.start()
    } catch {
      JSONLines.error(String(describing: error))
      hidMonitor.stop()
      permissionInstructions()
      Foundation.exit(1)
    }

    JSONLines.write([
      "record": "diagnosticReady",
      "message": "Click the primary mouse/trackpad button; press Control-C to stop",
    ])
    CFRunLoopRun()
  }

  private static func permissionInstructions() {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path
    FileHandle.standardError.write(
      Data(
        """

        Input Monitoring is required by this diagnostic executable only:
        1. Open System Settings > Privacy & Security > Input Monitoring.
        2. Enable or add: \(executable)
        3. Quit and restart the diagnostic.

        JFC itself still requires Accessibility only.

        """.utf8
      )
    )
  }
}
