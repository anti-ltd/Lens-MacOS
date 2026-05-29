#if APPSTAGE
import AppKit
import SwiftUI
import LensCore

// Dev tool: render one UI state into an on-screen window for appstage to
// screenshot, then keep running so the window can be captured. Mirrors Clonk's
// driver. Activated by `Lens --appstage <state>`.
//
// State is isolated via LENS_STATE_DIR (LensSettings.defaults switches to a
// throwaway suite), so a capture run never touches the user's presets. Prints
// the line appstage parses:
//
//   @@APPSTAGE_READY@@ {"window":<cgWindowID>,"w":W,"h":H,"slug":"<state>"}
@MainActor
enum AppStageCapture {
    /// The `<state>` passed via `--appstage`, or nil in normal runs.
    static var state: String? {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--appstage"), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    private static let editorStates: Set<String> = ["editor"]

    static func run(state: String) {
        NSApp.setActivationPolicy(.accessory)
        seed(for: state)

        let root: AnyView
        if editorStates.contains(state) {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            root = AnyView(DemoEditor())
        } else {
            NSApp.appearance = NSAppearance(named: .aqua)
            let tab: LensTab
            switch state {
            case "presets": tab = .presets
            case "output":  tab = .output
            case "about":   tab = .about
            default:        tab = .capture
            }
            root = AnyView(CapturePanel(tab: tab))
        }

        let host = NSHostingController(rootView: root)
        host.view.layoutSubtreeIfNeeded()

        let window = CaptureWindow(
            contentRect: NSRect(origin: .zero, size: host.view.fittingSize),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.contentViewController = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            host.view.layoutSubtreeIfNeeded()
            let fit = host.view.fittingSize
            if fit.width > 50, fit.height > 50 {
                window.setContentSize(fit)
                window.center()
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let f = window.frame
                print("@@APPSTAGE_READY@@ {\"window\":\(window.windowNumber),"
                      + "\"w\":\(Int(f.width)),\"h\":\(Int(f.height)),\"slug\":\"\(state)\"}")
                fflush(stdout)
            }
        }
    }

    /// Believable demo state so marketing shots look stocked and consistent.
    private static func seed(for state: String) {
        let s = LensSettings.shared
        s.presets = Preset.builtins
        s.activePresetID = s.presets.first { $0.name == "16:9" }?.id
        s.format = .png
        s.destination = .editor
        if state == "output" {
            if let idx = s.presets.firstIndex(where: { $0.id == s.activePresetID }) {
                s.presets[idx].backdrop = .marketing
            }
        }
    }
}

// Borderless windows can't become key by default; allow it so controls render
// in their active state.
private final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// The popover content as a self-contained rounded panel (no popover arrow).
private struct CapturePanel: View {
    let tab: LensTab
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LensTabContent(tab: tab)
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// A demo editor canvas with a synthetic image and a few annotations baked in.
private struct DemoEditor: View {
    @StateObject private var model: EditorModel = {
        let image = AppStageCapture.demoImage()
        let m = EditorModel(base: image, preset: Preset(name: "16:9", constraint: .ratio(w: 16, h: 9), backdrop: .marketing))
        m.commit(Annotation(kind: .rectangle, points: [CGPoint(x: 120, y: 100), CGPoint(x: 520, y: 360)],
                            color: RGBAColor(hex: "#FF3B30")!, lineWidth: 6))
        m.commit(Annotation(kind: .arrow, points: [CGPoint(x: 620, y: 520), CGPoint(x: 460, y: 360)],
                            color: RGBAColor(hex: "#FF9500")!, lineWidth: 8))
        return m
    }()

    var body: some View {
        EditorView(model: model, onClose: {})
            .frame(width: 900, height: 620)
    }
}

extension AppStageCapture {
    /// A synthetic gradient image to stand in for a real capture in shots.
    static func demoImage() -> CGImage {
        let w = 1000, h = 600
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.16, blue: 0.30, alpha: 1),
                   ending: NSColor(srgbRed: 0.20, green: 0.10, blue: 0.34, alpha: 1))?
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -45)
        img.unlockFocus()
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
#endif
