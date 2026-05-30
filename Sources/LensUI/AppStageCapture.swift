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
        if state == "studio" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            root = AnyView(StudioShowcase())
        } else if editorStates.contains(state) {
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

// The Studio output: a believable app capture run through the cinematic
// compositor (window chrome, gradient backdrop, a title layer + logo bug).
private struct StudioShowcase: View {
    var body: some View {
        Image(nsImage: NSImage(cgImage: AppStageCapture.studioFrame(),
                               size: NSSize(width: 1, height: 1)))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 980)
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

    /// A mock app window (sidebar + content) to stand in for a recorded screen.
    static func demoScreen() -> CGImage {
        let w: CGFloat = 1280, h: CGFloat = 800
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSColor(srgbRed: 0.10, green: 0.11, blue: 0.15, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        // Sidebar.
        NSColor(srgbRed: 0.14, green: 0.15, blue: 0.20, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 260, height: h).fill()
        for i in 0..<7 {
            NSColor(white: 1, alpha: i == 2 ? 0.16 : 0.06).setFill()
            NSBezierPath(roundedRect: NSRect(x: 18, y: h - 90 - CGFloat(i) * 64, width: 224, height: 44),
                         xRadius: 8, yRadius: 8).fill()
        }
        // Content cards.
        let accents = [NSColor(srgbRed: 0.36, green: 0.55, blue: 1, alpha: 1),
                       NSColor(srgbRed: 0.66, green: 0.33, blue: 0.97, alpha: 1),
                       NSColor(srgbRed: 0.16, green: 0.78, blue: 0.5, alpha: 1)]
        for r in 0..<3 {
            for c in 0..<3 {
                let x = 300 + CGFloat(c) * 320, y = h - 140 - CGFloat(r) * 210
                NSColor(white: 1, alpha: 0.05).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y - 160, width: 290, height: 170), xRadius: 12, yRadius: 12).fill()
                accents[(r + c) % 3].withAlphaComponent(0.9).setFill()
                NSBezierPath(roundedRect: NSRect(x: x + 16, y: y - 40, width: 60, height: 24), xRadius: 6, yRadius: 6).fill()
            }
        }
        img.unlockFocus()
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    /// One composed Studio frame: a mock screen framed with window chrome over a
    /// gradient, with the cinematic cursor + a click ripple and the logo bug —
    /// the actual output of the Studio renderer.
    static func studioFrame() -> CGImage {
        let screen = demoScreen()
        let size = CGSize(width: screen.width, height: screen.height)
        // Synthetic events: cursor parked on a card with a click, so the cursor
        // cinema (enlarged cursor + ripple) reads as a real recording moment.
        let cx = Double(size.width) * 0.46, cy = Double(size.height) * 0.42
        var events = RecordingEvents(fps: 30, scale: 1, pixelSize: size,
                                     regionGlobalPoints: CGRect(origin: .zero, size: size), duration: 1)
        events.cursors = [.init(t: 0, x: cx, y: cy), .init(t: 1, x: cx, y: cy)]
        events.clicks = [.init(t: 0.0, x: cx, y: cy, button: 0)]

        let comp = StudioComposer(
            style: StudioPreset.window.style,
            camera: CameraStyle(enabled: false),
            cursor: CursorStyle(enabled: true, size: 2.2, clickRipples: true),
            watermark: "github.com/anti-ltd/Lens-MacOS",
            events: events,
            sourcePixelSize: size)
        let out = comp.transform(CIImage(cgImage: screen), 0.16)
        return CIContext().createCGImage(out, from: CGRect(origin: .zero, size: comp.canvasSize))!
    }
}
#endif
