import SwiftUI
import iUX_MacOS
import LensCore

/// The everyday surface: trigger any capture mode right now, set the hotkeys,
/// and tune capture behaviour (cursor, window shadow, sound, confirmation).
struct CaptureTab: View {
    @ObservedObject private var settings = LensSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: UX.cardSpacing) {
            CardSection("Capture now") {
                HStack(spacing: 10) {
                    ForEach(CaptureMode.allCases) { mode in
                        CircleButton(systemImage: mode.symbol, size: 42) {
                            NSApp.keyWindow?.close()
                            CaptureController.shared.perform(mode)
                        }
                        .help(mode.title)
                    }
                }
                .padding(.vertical, 6)
            }

            CardSection("Hotkeys") {
                ForEach(Array(CaptureMode.allCases.enumerated()), id: \.element) { index, mode in
                    if index > 0 { Divider() }
                    HStack {
                        Label(mode.title, systemImage: mode.symbol)
                        Spacer()
                        ShortcutRecorderView(mode: mode)
                            .fixedSize()
                    }
                    .padding(.vertical, 6)
                }
            }

            CardSection("Behaviour") {
                ToggleRow("Capture cursor",
                          subtitle: "Include the pointer in screenshots",
                          isOn: $settings.captureCursor)
                Divider()
                ToggleRow("Window shadow",
                          subtitle: "Keep the drop shadow on window captures",
                          isOn: $settings.windowShadow)
                Divider()
                ToggleRow("Shutter sound", isOn: $settings.playSound)
                Divider()
                ToggleRow("Show confirmation",
                          subtitle: "Flash a thumbnail after capture",
                          isOn: $settings.showThumbnail)
            }
        }
    }
}
