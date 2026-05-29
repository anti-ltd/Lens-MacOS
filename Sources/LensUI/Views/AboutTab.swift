import SwiftUI
import AppKit
import iUX_MacOS
import LensCore

/// App identity, screen-recording permission status, and quit.
struct AboutTab: View {
    @State private var hasPermission = CaptureController.hasScreenRecordingPermission()
    @State private var hasAccessibility = CaptureController.hasAccessibilityPermission()

    var body: some View {
        VStack(alignment: .leading, spacing: UX.cardSpacing) {
            CardSection {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lens").font(.title2.weight(.bold))
                        Text(versionString).font(.caption).foregroundStyle(.secondary)
                        Text("Precise, repeatable screenshots.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            CardSection("Permissions") {
                permissionRow(
                    title: "Screen Recording",
                    detail: "Required to capture any pixels.",
                    granted: hasPermission,
                    action: { CaptureController.openScreenRecordingSettings() }
                )
                Divider()
                permissionRow(
                    title: "Accessibility",
                    detail: "Required for global hotkeys and scrolling capture.",
                    granted: hasAccessibility,
                    action: { CaptureController.requestAccessibilityPermission() }
                )
            }

            CardSection {
                HStack {
                    Spacer()
                    Button("Quit Lens") { NSApp.terminate(nil) }
                    Spacer()
                }
                .padding(.vertical, 6)
            }
        }
        .onAppear {
            hasPermission = CaptureController.hasScreenRecordingPermission()
            hasAccessibility = CaptureController.hasAccessibilityPermission()
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: granted ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .foregroundStyle(granted ? .green : .orange)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Grant", action: action) }
        }
        .padding(.vertical, 6)
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }
}
