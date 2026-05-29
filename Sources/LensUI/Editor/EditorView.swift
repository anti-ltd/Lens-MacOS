import SwiftUI
import AppKit
import iUX_MacOS
import LensCore

/// The annotation editor. A fit-to-window canvas over the capture, a tool rail,
/// and export actions. Annotations are dragged directly on the image; the live
/// draft is drawn as a lightweight overlay, then baked into the preview on
/// release (so it always matches what's exported).
struct EditorView: View {
    @ObservedObject var model: EditorModel
    var onClose: () -> Void

    @State private var draftStart: CGPoint?
    @State private var draftCurrent: CGPoint?
    @State private var draftPoints: [CGPoint] = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Annotation.Kind.allCases) { kind in
                    Button { model.tool = kind } label: {
                        Image(systemName: kind.symbol)
                            .frame(width: 26, height: 22)
                            .background(model.tool == kind ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                                       in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(model.tool == kind ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    }
                    .buttonStyle(.plain)
                    .help(kind.title)
                }
            }

            HStack(spacing: 12) {
                ColorPicker("", selection: $model.color).labelsHidden().frame(width: 44)
                HStack(spacing: 4) {
                    Image(systemName: "lineweight").foregroundStyle(.secondary)
                    Slider(value: $model.lineWidth, in: 1...24).frame(width: 90)
                }
                if model.tool == .text {
                    TextField("Label", text: $model.textDraft).frame(width: 120).textFieldStyle(.roundedBorder)
                }
                Picker("", selection: $model.backdropChoice) {
                    ForEach(EditorModel.BackdropChoice.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 150)

                Spacer()

                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .keyboardShortcut("z", modifiers: .command).help("Undo")
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .keyboardShortcut("z", modifiers: [.command, .shift]).help("Redo")
                Button { model.clear() } label: { Image(systemName: "trash") }.help("Clear all")

                Divider().frame(height: 18)

                Button { runOCR() } label: { Image(systemName: "text.viewfinder") }.help("Copy text (OCR)")
                Button { copy() } label: { Image(systemName: "doc.on.clipboard") }
                    .keyboardShortcut("c", modifiers: [.command, .shift]).help("Copy")
                Button { pin() } label: { Image(systemName: "pin") }.help("Pin")
                Button("Save", action: save).keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let fit = fitRect(in: geo.size)
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                Image(nsImage: model.preview)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)
                    .shadow(radius: 6)
                draftOverlay
            }
            .contentShape(Rectangle())
            .gesture(drag(fit: fit))
        }
    }

    @ViewBuilder private var draftOverlay: some View {
        if let s = draftStart, let c = draftCurrent {
            let col = model.color
            switch model.tool {
            case .rectangle, .highlight, .pixelate, .blur, .spotlight, .redact:
                Path { $0.addRect(CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                                          width: abs(c.x - s.x), height: abs(c.y - s.y))) }
                    .stroke(col, lineWidth: 2)
            case .ellipse:
                Path { $0.addEllipse(in: CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                                                 width: abs(c.x - s.x), height: abs(c.y - s.y))) }
                    .stroke(col, lineWidth: 2)
            case .arrow, .line:
                Path { $0.move(to: s); $0.addLine(to: c) }.stroke(col, lineWidth: CGFloat(model.lineWidth))
            case .freehand:
                Path { p in
                    guard let first = draftPoints.first else { return }
                    p.move(to: first); draftPoints.dropFirst().forEach { p.addLine(to: $0) }
                }.stroke(col, lineWidth: CGFloat(model.lineWidth))
            case .text, .counter:
                EmptyView()
            }
        }
    }

    private func drag(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if draftStart == nil { draftStart = value.startLocation; draftPoints = [value.startLocation] }
                draftCurrent = value.location
                if model.tool == .freehand { draftPoints.append(value.location) }
            }
            .onEnded { value in
                defer { draftStart = nil; draftCurrent = nil; draftPoints = [] }
                let startPx = pixel(from: value.startLocation, fit: fit)
                let endPx = pixel(from: value.location, fit: fit)
                switch model.tool {
                case .text:
                    guard !model.textDraft.isEmpty else { return }
                    model.commit(model.makeAnnotation(kind: .text, points: [startPx]))
                case .counter:
                    model.commit(model.makeAnnotation(kind: .counter, points: [startPx]))
                case .freehand:
                    let pts = draftPoints.map { pixel(from: $0, fit: fit) }
                    guard pts.count >= 2 else { return }
                    model.commit(model.makeAnnotation(kind: .freehand, points: pts))
                default:
                    guard hypot(endPx.x - startPx.x, endPx.y - startPx.y) >= 3 else { return }
                    model.commit(model.makeAnnotation(kind: model.tool, points: [startPx, endPx]))
                }
            }
    }

    // MARK: - Geometry

    private func fitRect(in size: CGSize) -> CGRect {
        let pw = model.pixelSize.width, ph = model.pixelSize.height
        guard pw > 0, ph > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = min(size.width / pw, size.height / ph)
        let w = pw * scale, h = ph * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func pixel(from viewPoint: CGPoint, fit: CGRect) -> CGPoint {
        let sx = model.pixelSize.width / max(fit.width, 1)
        let sy = model.pixelSize.height / max(fit.height, 1)
        let x = (viewPoint.x - fit.minX) * sx
        let y = (viewPoint.y - fit.minY) * sy
        return CGPoint(x: min(max(x, 0), model.pixelSize.width),
                       y: min(max(y, 0), model.pixelSize.height))
    }

    // MARK: - Export actions

    private func save() {
        let image = model.finalImage()
        let s = LensSettings.shared
        do {
            let url = try OutputWriter.write(image, toFolder: s.saveFolderPath,
                                             format: s.format, quality: s.quality,
                                             template: s.filenameTemplate)
            CaptureFeedback.toast("Saved \(url.lastPathComponent)")
            onClose()
        } catch {
            NSSound.beep()
        }
    }

    private func copy() {
        OutputWriter.copyToClipboard(model.finalImage())
        CaptureFeedback.toast("Copied to clipboard")
    }

    private func pin() {
        PinWindowController.pin(model.finalImage())
        onClose()
    }

    private func runOCR() {
        if let text = try? TextRecognizer.recognizeText(in: model.base), !text.isEmpty {
            OutputWriter.copyToClipboard(text: text)
            CaptureFeedback.toast("Copied recognised text")
        } else {
            CaptureFeedback.toast("No text found")
        }
    }
}
