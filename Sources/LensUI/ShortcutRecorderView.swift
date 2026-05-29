import SwiftUI
import AppKit
import LensCore

/// A compact hotkey recorder bound to one `CaptureMode`. Click it, press a
/// modifier+key combo, and it persists into `LensSettings.hotkeys`. Escape
/// unbinds. Adapted from FileMaster's recorder, parametrised per mode.
struct ShortcutRecorderView: NSViewRepresentable {
    let mode: CaptureMode
    @ObservedObject private var settings = LensSettings.shared

    func makeNSView(context: Context) -> RecorderNSView { RecorderNSView(mode: mode) }
    func updateNSView(_ nsView: RecorderNSView, context: Context) { nsView.refresh() }

    final class RecorderNSView: NSView {
        private let mode: CaptureMode
        private var isRecording = false

        init(mode: CaptureMode) {
            self.mode = mode
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 5
            layer?.borderWidth = 1.5
            updateStyle()
        }

        required init?(coder: NSCoder) { fatalError() }

        override var intrinsicContentSize: NSSize { NSSize(width: 104, height: 22) }
        override var acceptsFirstResponder: Bool { true }

        func refresh() { updateStyle(); needsDisplay = true }

        private func updateStyle() {
            if isRecording {
                layer?.borderColor = NSColor.controlAccentColor.cgColor
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            } else {
                layer?.borderColor = NSColor.separatorColor.cgColor
                layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            let binding = LensSettings.shared.binding(for: mode)
            let label: String
            let color: NSColor
            if isRecording {
                label = "Type shortcut…"; color = .secondaryLabelColor
            } else if binding.isSet {
                label = binding.display; color = .labelColor
            } else {
                label = "Click to set"; color = .placeholderTextColor
            }
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: color,
                .paragraphStyle: para,
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let sz = str.size()
            str.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            isRecording = true
            updateStyle(); needsDisplay = true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { super.keyDown(with: event); return }
            let keyCode = event.keyCode
            if keyCode == 53 { // Escape = unbind
                LensSettings.shared.setBinding(.unbound, for: mode)
                stopRecording(); return
            }
            if keyCode == 36 || keyCode == 48 { stopRecording(); return } // Enter/Tab = cancel
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !mods.isEmpty else { return } // require a modifier
            LensSettings.shared.setBinding(
                HotkeyBinding(keyCode: Int(keyCode), modifiers: Int(mods.rawValue)),
                for: mode
            )
            stopRecording()
        }

        override func resignFirstResponder() -> Bool {
            if isRecording { stopRecording() }
            return super.resignFirstResponder()
        }

        private func stopRecording() {
            isRecording = false
            updateStyle(); needsDisplay = true
        }
    }
}
