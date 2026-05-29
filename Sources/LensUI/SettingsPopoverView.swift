import SwiftUI
import iUX_MacOS
import LensCore

/// The tabs Lens exposes in its settings popover (and the pop-out window's
/// sidebar — same enum drives both, per iUX's `SettingsTab`).
enum LensTab: String, SettingsTab {
    case capture, presets, output, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: return "Capture"
        case .presets: return "Presets"
        case .output:  return "Output"
        case .about:   return "About"
        }
    }

    var icon: String {
        switch self {
        case .capture: return "camera.viewfinder"
        case .presets: return "aspectratio"
        case .output:  return "square.and.arrow.down"
        case .about:   return "info.circle"
        }
    }
}

/// The menu-bar popover root: a segmented tab bar with a pop-out button, over
/// the per-tab content. The pop-out button opens the standalone settings window.
public struct SettingsPopoverView: View {
    public static let windowID = "lens-settings"
    @State private var tab: LensTab = .capture

    public init() {}

    public var body: some View {
        SettingsPopover(selection: $tab, width: 360, popOutWindowID: Self.windowID) { t in
            LensTabContent(tab: t)
        }
    }
}

/// Per-tab body, shared by the popover and the pop-out window.
struct LensTabContent: View {
    let tab: LensTab

    var body: some View {
        switch tab {
        case .capture: CaptureTab()
        case .presets: PresetsTab()
        case .output:  OutputTab()
        case .about:   AboutTab()
        }
    }
}
