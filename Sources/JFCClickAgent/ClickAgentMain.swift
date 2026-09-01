import AppKit
import JFCCore
import JFCIPC

@main
enum ClickAgentMain {
  @MainActor
  static func main() {
    guard let launchOptions = ClickAgentLaunchOptions(arguments: ProcessInfo.processInfo.arguments)
    else {
      JFCLog.lifecycle("Click agent launched without valid owner information")
      return
    }

    let application = NSApplication.shared
    let delegate = ClickAgentAppDelegate(launchOptions: launchOptions)
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
  }
}

private struct ClickAgentLaunchOptions {
  let ownerProcessIdentifier: pid_t
  let token: String

  init?(arguments: [String]) {
    guard
      let ownerValue = Self.value(after: "--owner-pid", in: arguments),
      let ownerProcessIdentifier = pid_t(ownerValue),
      ownerProcessIdentifier > 0,
      let token = Self.value(after: "--ipc-token", in: arguments),
      UUID(uuidString: token) != nil
    else { return nil }

    self.ownerProcessIdentifier = ownerProcessIdentifier
    self.token = token
  }

  private static func value(after option: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: option) else { return nil }
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex else { return nil }
    return arguments[valueIndex]
  }
}

@MainActor
private final class ClickAgentAppDelegate: NSObject, NSApplicationDelegate {
  private let launchOptions: ClickAgentLaunchOptions
  private let service: ClickAgentService
  private var server: ClickAgentMessageServer?
  private var ownerMonitor: Timer?

  init(launchOptions: ClickAgentLaunchOptions) {
    self.launchOptions = launchOptions
    service = ClickAgentService(
      ownerProcessIdentifier: launchOptions.ownerProcessIdentifier
    )
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      server = try ClickAgentMessageServer(
        token: launchOptions.token,
        service: service
      )
    } catch {
      let nsError = error as NSError
      JFCLog.lifecycle(
        "Click agent IPC setup failed: domain=\(nsError.domain) code=\(nsError.code)"
      )
      NSApplication.shared.terminate(nil)
      return
    }

    service.onShutdownRequested = {
      DispatchQueue.main.async {
        NSApplication.shared.terminate(nil)
      }
    }
    ownerMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
      [weak self] timer in
      guard let self else {
        timer.invalidate()
        return
      }
      Task { @MainActor in
        self.checkOwner()
      }
    }
    JFCLog.lifecycle("Click agent application launched")
  }

  func applicationWillTerminate(_ notification: Notification) {
    ownerMonitor?.invalidate()
    ownerMonitor = nil
    service.stop()
    server?.invalidate()
    server = nil
    JFCLog.lifecycle("Click agent application terminating")
  }

  private func checkOwner() {
    guard kill(launchOptions.ownerProcessIdentifier, 0) != 0, errno == ESRCH else {
      return
    }
    JFCLog.lifecycle("Click agent owner exited")
    NSApplication.shared.terminate(nil)
  }
}

@MainActor
private final class ClickAgentService {
  private let ownerProcessIdentifier: pid_t
  private let eventTap = EventTap(
    configuration: EventTapConfiguration(
      ignoredBundleIdentifiers: ["io.e10n.jfc"]
    )
  )
  var onShutdownRequested: (() -> Void)?

  init(ownerProcessIdentifier: pid_t) {
    self.ownerProcessIdentifier = ownerProcessIdentifier
  }

  func handle(_ request: ClickAgentRequest) -> ClickAgentResponse {
    let trusted = AccessibilityPermission.isTrusted(prompt: false)
    guard request.ownerProcessIdentifier == ownerProcessIdentifier else {
      return ClickAgentResponse(
        id: request.id,
        accessibilityGranted: trusted,
        running: eventTap.isRunning,
        errorMessage: "The click-agent request owner is invalid."
      )
    }

    switch request.command {
    case .setEnabled:
      guard request.enabled == true else {
        eventTap.stop()
        return response(to: request, trusted: trusted)
      }
      guard trusted else {
        eventTap.stop()
        return response(to: request, trusted: false)
      }
      guard !eventTap.isRunning else {
        return response(to: request, trusted: true)
      }

      do {
        try eventTap.start()
        return response(to: request, trusted: true)
      } catch {
        return response(
          to: request,
          trusted: true,
          errorMessage: error.localizedDescription
        )
      }

    case .status:
      return response(to: request, trusted: trusted)

    case .shutdown:
      eventTap.stop()
      onShutdownRequested?()
      return response(to: request, trusted: trusted)
    }
  }

  func stop() {
    eventTap.stop()
  }

  private func response(
    to request: ClickAgentRequest,
    trusted: Bool,
    errorMessage: String? = nil
  ) -> ClickAgentResponse {
    ClickAgentResponse(
      id: request.id,
      accessibilityGranted: trusted,
      running: eventTap.isRunning,
      errorMessage: errorMessage
    )
  }
}

@MainActor
private final class ClickAgentMessageServer {
  private var port: CFMessagePort?

  init(token: String, service: ClickAgentService) throws {
    var context = CFMessagePortContext(
      version: 0,
      info: Unmanaged.passUnretained(service).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )
    var shouldFreeInfo = DarwinBoolean(false)
    guard
      let port = CFMessagePortCreateLocal(
        nil,
        jfcClickAgentPortName(token: token),
        clickAgentMessageCallback,
        &context,
        &shouldFreeInfo
      )
    else {
      throw ClickAgentMessageServerError.couldNotCreatePort
    }

    self.port = port
    CFMessagePortSetDispatchQueue(port, DispatchQueue.main)
  }

  func invalidate() {
    if let port {
      CFMessagePortInvalidate(port)
      self.port = nil
    }
  }
}

private enum ClickAgentMessageServerError: Error {
  case couldNotCreatePort
}

private let clickAgentMessageCallback: CFMessagePortCallBack = {
  _, _, requestData, context in
  guard let requestData, let context else { return nil }
  let service = Unmanaged<ClickAgentService>.fromOpaque(context).takeUnretainedValue()

  do {
    let request = try JSONDecoder().decode(ClickAgentRequest.self, from: requestData as Data)
    let response = MainActor.assumeIsolated {
      service.handle(request)
    }
    let responseData = try JSONEncoder().encode(response)
    return Unmanaged.passRetained(responseData as CFData)
  } catch {
    return nil
  }
}
