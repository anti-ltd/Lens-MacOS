import AppKit
import SwiftUI
import LensCore

/// State for one editor session. Annotations are baked into a `preview` image
/// (in base-image pixel space, no backdrop) for WYSIWYG editing; the backdrop
/// and frame constraint are applied only on export, so canvas coordinates map
/// 1:1 to capture pixels.
@MainActor
final class EditorModel: ObservableObject {
    enum BackdropChoice: String, CaseIterable, Identifiable {
        case none, clean, marketing, preset
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "None"
            case .clean: return "Clean"
            case .marketing: return "Marketing"
            case .preset: return "Preset"
            }
        }
    }

    let base: CGImage
    let preset: Preset

    @Published var annotations: [Annotation] = []
    @Published var tool: Annotation.Kind = .arrow
    @Published var color: Color = .red
    @Published var lineWidth: Double = 4
    @Published var textDraft: String = "Label"
    @Published var backdropChoice: BackdropChoice
    @Published private(set) var preview: NSImage

    private var counter = 1
    private var redoStack: [[Annotation]] = []

    init(base: CGImage, preset: Preset) {
        self.base = base
        self.preset = preset
        self.backdropChoice = (preset.backdrop != nil) ? .preset : .none
        self.preview = NSImage(cgImage: base, size: NSSize(width: base.width, height: base.height))
    }

    var pixelSize: CGSize { CGSize(width: base.width, height: base.height) }

    var nextCounter: Int { counter }

    // MARK: - Mutations

    func commit(_ annotation: Annotation) {
        redoStack.removeAll()
        annotations.append(annotation)
        if annotation.kind == .counter { counter += 1 }
        rebuild()
    }

    func undo() {
        guard let last = annotations.popLast() else { return }
        redoStack.append([last])
        if last.kind == .counter { counter = max(1, counter - 1) }
        rebuild()
    }

    func redo() {
        guard let restored = redoStack.popLast() else { return }
        annotations.append(contentsOf: restored)
        rebuild()
    }

    func clear() {
        guard !annotations.isEmpty else { return }
        annotations.removeAll()
        counter = 1
        redoStack.removeAll()
        rebuild()
    }

    func makeAnnotation(kind: Annotation.Kind, points: [CGPoint]) -> Annotation {
        Annotation(
            kind: kind,
            points: points,
            color: color.rgba,
            lineWidth: CGFloat(lineWidth),
            text: kind == .text ? textDraft : "",
            number: kind == .counter ? counter : 1
        )
    }

    private func rebuild() {
        let rendered = annotations.isEmpty ? base : Compositor.render(annotations: annotations, on: base)
        preview = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
    }

    // MARK: - Export

    private var resolvedBackdrop: Backdrop {
        switch backdropChoice {
        case .none: return .none
        case .clean: return .clean
        case .marketing: return .marketing
        case .preset: return preset.backdrop ?? .none
        }
    }

    /// The export-ready image: annotations baked, frame constraint applied,
    /// backdrop wrapped.
    func finalImage() -> CGImage {
        Compositor.compose(
            base: base,
            annotations: annotations,
            constraint: preset.constraint,
            backdrop: resolvedBackdrop
        )
    }
}
