import SwiftUI

struct ControlView: View {
  @ObservedObject var model: AppState
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      header

      if model.accessibilityGranted {
        controls
      } else {
        onboarding
      }
    }
    .padding(30)
    .frame(width: 520)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    HStack(spacing: 14) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .scaledToFit()
        .frame(width: 52, height: 52)

      Text("JFC")
        .font(.system(size: 25, weight: .bold, design: .rounded))

      Spacer()

      Link(destination: URL(string: "https://github.com/engina/jfc")!) {
        githubMark
          .frame(width: 19, height: 19)
          .padding(6)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .opacity(0.58)
      .help("View JFC on GitHub")
      .accessibilityLabel("View JFC on GitHub")
    }
  }

  @ViewBuilder
  private var githubMark: some View {
    if let image = githubMarkImage {
      Image(nsImage: image)
        .resizable()
        .scaledToFit()
    } else {
      Image(systemName: "link")
        .resizable()
        .scaledToFit()
    }
  }

  private var githubMarkImage: NSImage? {
    let color = colorScheme == .dark ? "White" : "Black"
    guard
      let url = Bundle.main.url(
        forResource: "GitHub-Invertocat-\(color)",
        withExtension: "pdf"
      )
    else { return nil }
    return NSImage(contentsOf: url)
  }

  private var onboarding: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 7) {
        Text("Allow JFC to focus the window you click")
          .font(.title3.weight(.semibold))
        Text(
          "macOS requires Accessibility permission before JFC can activate the window beneath your pointer."
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      permissionExplanation

      if let errorMessage = model.errorMessage {
        errorBanner(errorMessage)
      }

      HStack {
        Spacer()

        Button("Open System Settings") {
          model.requestAccessibility()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }

      HStack(spacing: 7) {
        ProgressView()
          .controlSize(.small)
        Text("JFC will continue automatically when permission is granted.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var permissionExplanation: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 11) {
        Image(systemName: "hand.raised.fill")
          .foregroundStyle(.tint)
          .frame(width: 20)
        VStack(alignment: .leading, spacing: 3) {
          Text("Accessibility")
            .fontWeight(.medium)
          Text("Used only to identify and focus the window beneath a left click.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      HStack(alignment: .top, spacing: 11) {
        Image(systemName: "keyboard.badge.ellipsis")
          .foregroundStyle(.secondary)
          .frame(width: 20)
        VStack(alignment: .leading, spacing: 3) {
          Text("No Input Monitoring")
            .fontWeight(.medium)
          Text("JFC does not monitor keyboard input and does not request that permission.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(16)
    .background {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(spacing: 0) {
        settingsRow(
          icon: model.isRunning ? "checkmark.circle.fill" : "pause.circle.fill",
          iconColor: model.isRunning ? .green : .secondary,
          title: "JFC",
          detail: statusDetail
        ) {
          HStack(spacing: 10) {
            Text(statusTitle)
              .fontWeight(.medium)
              .foregroundStyle(model.isRunning ? .green : .secondary)

            Button {
              if model.isRunning {
                model.stop()
              } else {
                model.start()
              }
            } label: {
              Image(systemName: model.isRunning ? "stop.circle" : "play.circle")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 18, height: 18)
                .padding(4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(0.72)
            .help(model.isRunning ? "Stop JFC" : "Start JFC")
            .accessibilityLabel(model.isRunning ? "Stop JFC" : "Start JFC")
          }
        }

        Divider().padding(.leading, 43)

        settingsRow(
          icon: "hand.raised.fill",
          iconColor: .green,
          title: "Accessibility",
          detail: "Permission granted"
        ) {
          Image(systemName: "checkmark")
            .fontWeight(.semibold)
            .foregroundStyle(.green)
            .accessibilityLabel("Granted")
        }

        Divider().padding(.leading, 43)

        settingsRow(
          icon: "power",
          iconColor: .accentColor,
          title: "Start at Login",
          detail: loginItemDetail
        ) {
          Toggle(
            "Start at Login",
            isOn: Binding(
              get: { model.startsAtLogin },
              set: { model.setStartsAtLogin($0) }
            )
          )
          .labelsHidden()
        }
      }
      .background {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor))
      }

      if model.loginItemNeedsApproval {
        HStack {
          Label("Approve JFC under Allow in the Background.", systemImage: "exclamationmark.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Open Settings") {
            model.openLoginItemsSettings()
          }
        }
      }

      if let errorMessage = model.errorMessage {
        errorBanner(errorMessage)
      }
    }
  }

  private var statusTitle: String {
    switch model.operationalState {
    case .running: "Running"
    case .stopped: "Stopped"
    case .needsPermission: "Needs permission"
    case .failed: "Couldn’t start"
    }
  }

  private var statusDetail: String {
    switch model.operationalState {
    case .running: "First clicks pass through"
    case .stopped: "Click-through is disabled"
    case .needsPermission: "Accessibility permission is required"
    case .failed: "JFC encountered an error"
    }
  }

  private var loginItemDetail: String {
    switch model.launchAtLoginStatus {
    case .enabled: "Enabled"
    case .requiresApproval: "Waiting for approval"
    case .notRegistered: "Disabled"
    case .notFound: "Unavailable in this build"
    @unknown default: "Unknown"
    }
  }

  private func settingsRow<Trailing: View>(
    icon: String,
    iconColor: Color,
    title: String,
    detail: String,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(iconColor)
        .frame(width: 22)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .fontWeight(.medium)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
      trailing()
    }
    .padding(.horizontal, 15)
    .frame(minHeight: 62)
  }

  private func errorBanner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(message)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      Button {
        model.clearError()
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss")
    }
    .padding(12)
    .background {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(Color.orange.opacity(0.12))
    }
  }
}
