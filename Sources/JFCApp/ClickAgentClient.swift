import AppKit
import JFCIPC

struct ClickAgentStatus: Equatable {
  let accessibilityGranted: Bool
  let running: Bool
  let errorMessage: String?
}

@MainActor
final class ClickAgentClient {
  typealias Completion = @MainActor @Sendable (Result<ClickAgentStatus, Error>) -> Void

  private let token = UUID().uuidString
  private var launchRequested = false
  private var invalidated = false

  func setEnabled(_ enabled: Bool, completion: @escaping Completion) {
    perform(command: .setEnabled, enabled: enabled, completion: completion)
  }

  func status(completion: @escaping Completion) {
    perform(command: .status, completion: completion)
  }

  func invalidate() {
    guard !invalidated else { return }
    let request = makeRequest(command: .shutdown)
    _ = try? send(request)
    invalidated = true
  }

  private func perform(
    command: ClickAgentCommand,
    enabled: Bool? = nil,
    completion: @escaping Completion
  ) {
    guard !invalidated else {
      completion(.failure(ClickAgentClientError.cancelled))
      return
    }

    let request = makeRequest(command: command, enabled: enabled)
    let deadline = Date().addingTimeInterval(5)
    launchHelperIfNeeded(completion: completion)
    attempt(request, until: deadline, completion: completion)
  }

  private func attempt(
    _ request: ClickAgentRequest,
    until deadline: Date,
    completion: @escaping Completion
  ) {
    guard !invalidated else {
      completion(.failure(ClickAgentClientError.cancelled))
      return
    }

    do {
      let response = try send(request)
      guard response.id == request.id else {
        throw ClickAgentClientError.invalidResponse
      }
      completion(
        .success(
          ClickAgentStatus(
            accessibilityGranted: response.accessibilityGranted,
            running: response.running,
            errorMessage: response.errorMessage
          )
        )
      )
    } catch ClickAgentClientError.agentUnavailable where Date() < deadline {
      launchHelperIfNeeded(completion: completion)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        self?.attempt(request, until: deadline, completion: completion)
      }
    } catch {
      completion(.failure(error))
    }
  }

  private func send(_ request: ClickAgentRequest) throws -> ClickAgentResponse {
    guard
      let port = CFMessagePortCreateRemote(
        nil,
        jfcClickAgentPortName(token: token)
      )
    else {
      launchRequested = false
      throw ClickAgentClientError.agentUnavailable
    }

    let requestData = try JSONEncoder().encode(request)
    var responseData: Unmanaged<CFData>?
    let result = CFMessagePortSendRequest(
      port,
      0,
      requestData as CFData,
      0.25,
      0.25,
      CFRunLoopMode.defaultMode.rawValue,
      &responseData
    )
    guard result == kCFMessagePortSuccess, let responseData else {
      if result == kCFMessagePortIsInvalid || result == kCFMessagePortTransportError {
        launchRequested = false
      }
      throw ClickAgentClientError.agentUnavailable
    }
    return try JSONDecoder().decode(
      ClickAgentResponse.self,
      from: responseData.takeRetainedValue() as Data
    )
  }

  private func launchHelperIfNeeded(completion: @escaping Completion) {
    guard !launchRequested else { return }
    guard let helperURL = clickAgentApplicationURL else {
      completion(.failure(ClickAgentClientError.helperNotFound))
      return
    }

    launchRequested = true
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.arguments = [
      "--owner-pid", String(ProcessInfo.processInfo.processIdentifier),
      "--ipc-token", token,
    ]
    NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) {
      [weak self] _, error in
      guard let error else { return }
      DispatchQueue.main.async {
        self?.launchRequested = false
        completion(.failure(error))
      }
    }
  }

  private var clickAgentApplicationURL: URL? {
    let url = Bundle.main.bundleURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Helpers", isDirectory: true)
      .appendingPathComponent("JFC Click Agent.app", isDirectory: true)
    return Bundle(url: url) == nil ? nil : url
  }

  private func makeRequest(
    command: ClickAgentCommand,
    enabled: Bool? = nil
  ) -> ClickAgentRequest {
    ClickAgentRequest(
      command: command,
      enabled: enabled,
      ownerProcessIdentifier: ProcessInfo.processInfo.processIdentifier
    )
  }
}

private enum ClickAgentClientError: LocalizedError {
  case agentUnavailable
  case cancelled
  case helperNotFound
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .agentUnavailable:
      "The JFC click agent is not available."
    case .cancelled:
      "The JFC click-agent request was cancelled."
    case .helperNotFound:
      "The JFC click-agent application is missing."
    case .invalidResponse:
      "The JFC click agent returned an invalid response."
    }
  }
}
