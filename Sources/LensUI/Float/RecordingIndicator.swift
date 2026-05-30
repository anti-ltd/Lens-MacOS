import AppKit
import SwiftUI

/// A small floating "recording" pill — a pulsing red dot, an elapsed timer, and
/// a stop button — shown while a screen recording is in progress.
@MainActor
enum RecordingIndicator {
    private static var panel: NSPanel?

    static func show(started: Date, onStop: @escaping () -> Void) {
        hide()
        let hud = RecordingHUD(started: started, onStop: onStop)
        let host = NSHostingView(rootView: hud)
        let size = NSSize(width: 150, height: 40)
        host.frame = NSRect(origin: .zero, size: size)

        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 12)

        let p = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = host
        p.orderFrontRegardless()
        panel = p
    }

    static func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct RecordingHUD: View {
    let started: Date
    let onStop: () -> Void
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            TimelineView(.periodic(from: started, by: 1)) { ctx in
                Text(elapsed(to: ctx.date)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Button(action: onStop) {
                Image(systemName: "stop.fill").foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Stop recording")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.8), in: Capsule())
        .onAppear { pulse = true }
    }

    private func elapsed(to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(started)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
