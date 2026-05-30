import SwiftUI
import AppKit
import iUX_MacOS
import LensCore

/// The Studio editor: live preview + transport on the left, all the per-recording
/// controls on the right, export at the bottom. Every control binds straight into
/// the `StudioDocument`, so edits re-render the preview live.
@available(macOS 14.0, *)
struct StudioEditorView: View {
    @ObservedObject var model: StudioEditorModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                preview
                Divider()
                transport
            }
            Divider()
            controls.frame(width: 320)
        }
        .frame(minWidth: 900, minHeight: 560)
        .task { await model.load() }
    }

    // MARK: - Preview + transport

    private var preview: some View {
        ZStack {
            Color.black
            if let img = model.previewImage {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(16)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 22)
            }
            .buttonStyle(.borderless)
            Text(timecode(model.currentTime)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Slider(value: Binding(get: { model.currentTime }, set: { model.seek(to: $0) }), in: 0...max(model.duration, 0.01))
            Text(timecode(model.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(10)
    }

    // MARK: - Controls

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UX.cardSpacing) {
                CardSection("Look") {
                    Picker("", selection: presetBinding) {
                        ForEach(StudioPreset.allCases) { Text($0.label).tag($0 as StudioPreset?) }
                        Text("Custom").tag(StudioPreset?.none)
                    }
                    .labelsHidden().padding(.vertical, 4)
                    Divider()
                    Picker("Chrome", selection: $model.doc.scene.chrome) {
                        ForEach(SceneStyle.Chrome.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Aspect", selection: $model.doc.scene.aspect) {
                        ForEach(SceneStyle.Aspect.allCases) { Text($0.label).tag($0) }
                    }
                    SliderRow("Padding", value: cg(\.scene.insetFraction), in: 0...0.2, step: 0.01) { String(format: "%.0f%%", $0 * 100) }
                    SliderRow("Corners", value: cg(\.scene.cornerRadius), in: 0...40, step: 1) { "\(Int($0))" }
                    SliderRow.percent("Shadow", value: dbl(\.scene.shadowOpacity))
                    SliderRow("3D tilt", value: cg(\.scene.tilt), in: 0...0.15, step: 0.01) { String(format: "%.0f%%", $0 * 100) }
                }

                CardSection("Auto-zoom") {
                    ToggleRow("Enabled", isOn: $model.doc.camera.enabled)
                    if model.doc.camera.enabled {
                        SliderRow("Amount", value: cg(\.camera.zoom), in: 1.2...3.0, step: 0.1) { String(format: "%.1f×", $0) }
                        SliderRow("Smoothing", value: dbl(\.camera.smoothing), in: 0.1...0.8, step: 0.05) { String(format: "%.2fs", $0) }
                        Picker("Easing", selection: $model.doc.camera.easing) {
                            ForEach(CameraStyle.Easing.allCases) { Text($0.label).tag($0) }
                        }
                    }
                }

                CardSection("Cursor") {
                    ToggleRow("Cinematic cursor", isOn: $model.doc.cursor.enabled)
                    if model.doc.cursor.enabled {
                        SliderRow("Size", value: cg(\.cursor.size), in: 1.0...3.0, step: 0.1) { String(format: "%.1f×", $0) }
                        ToggleRow("Click ripples", isOn: $model.doc.cursor.clickRipples)
                        SliderRow.percent("Spotlight", value: dbl(\.cursor.spotlight))
                    }
                }

                CardSection("Overlays") {
                    ToggleRow("Keystrokes", isOn: $model.doc.keystrokes.enabled)
                    Divider()
                    ToggleRow("Webcam bubble", isOn: $model.doc.webcam.enabled)
                    if model.doc.webcam.enabled {
                        SliderRow.percent("Webcam size", value: cg(\.webcam.sizeFraction))
                        Picker("Corner", selection: $model.doc.webcam.corner) {
                            ForEach(WebcamStyle.Corner.allCases) { Text($0.label).tag($0) }
                        }
                    }
                }

                if model.duration > 0.2 {
                    CardSection("Trim") {
                        let step = min(0.05, model.duration / 20)
                        SliderRow("Start", value: Binding(get: { model.doc.trimStart },
                                                          set: { model.doc.trimStart = min($0, (model.doc.trimEnd ?? model.duration) - 0.1) }),
                                  in: 0...model.duration, step: step) { timecode($0) }
                        SliderRow("End", value: Binding(get: { model.doc.trimEnd ?? model.duration },
                                                        set: { model.doc.trimEnd = max($0, model.doc.trimStart + 0.1) }),
                                  in: 0...model.duration, step: step) { timecode($0) }
                    }
                }

                CardSection("Layers") {
                    HStack {
                        Button { model.addTextLayer() } label: { Label("Text", systemImage: "textformat") }
                        Button { model.addImageLayer() } label: { Label("Image", systemImage: "photo") }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    ForEach($model.doc.layers) { $layer in
                        Divider()
                        layerRow($layer)
                    }
                }

                CardSection("Audio") {
                    if let music = model.doc.music {
                        HStack {
                            Image(systemName: "music.note").foregroundStyle(.secondary)
                            Text(URL(fileURLWithPath: music.path).lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Remove") { model.doc.music = nil }.buttonStyle(.borderless)
                        }
                        .padding(.vertical, 6)
                        SliderRow.percent("Music volume", value: Binding(
                            get: { model.doc.music?.volume ?? 0.5 }, set: { model.doc.music?.volume = $0 }))
                        ToggleRow("Duck under recording audio", isOn: Binding(
                            get: { model.doc.music?.duck ?? true }, set: { model.doc.music?.duck = $0 }))
                    } else {
                        Button { model.chooseMusic() } label: { Label("Add Music…", systemImage: "music.note") }
                            .padding(.vertical, 6)
                    }
                    Divider()
                    ToggleRow("Remove silent gaps",
                              subtitle: "Collapse long idle stretches on export",
                              isOn: $model.doc.removeSilence)
                }

                CardSection("Titles & branding") {
                    HStack {
                        Text("Logo bug").frame(width: 80, alignment: .leading)
                        TextField("e.g. yourapp.com", text: $model.doc.watermark).textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 4)
                    Divider()
                    titleCard("Intro", binding: Binding(get: { model.doc.intro }, set: { model.doc.intro = $0 }))
                    Divider()
                    titleCard("Outro", binding: Binding(get: { model.doc.outro }, set: { model.doc.outro = $0 }))
                }

                Divider()
                exportBar
            }
            .padding(14)
        }
    }

    private var exportBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let p = model.exportProgress {
                ProgressView(value: p).progressViewStyle(.linear)
            }
            HStack {
                Button("Save", action: model.save)
                Spacer()
                Button("GIF") { model.exportGIF() }
                Button("Export") { model.export() }.buttonStyle(.borderedProminent)
            }
            if let s = model.status {
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func layerRow(_ layer: Binding<StudioLayer>) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                if layer.wrappedValue.isText {
                    TextField("Text", text: textBinding(layer)).textFieldStyle(.roundedBorder)
                    ColorPicker("Color", selection: Binding(
                        get: { layer.wrappedValue.color.color }, set: { layer.wrappedValue.color = $0.rgba }))
                }
                SliderRow("Size", value: layer.scale, in: 0.03...0.6, step: 0.01) { String(format: "%.0f%%", $0 * 100) }
                SliderRow("X", value: layer.x, in: 0...1, step: 0.01) { String(format: "%.0f%%", $0 * 100) }
                SliderRow("Y", value: layer.y, in: 0...1, step: 0.01) { String(format: "%.0f%%", $0 * 100) }
                SliderRow.percent("Opacity", value: layer.opacity)
                SliderRow("Fade in", value: layer.fadeIn, in: 0...2, step: 0.05) { String(format: "%.2fs", $0) }
                SliderRow("Fade out", value: layer.fadeOut, in: 0...2, step: 0.05) { String(format: "%.2fs", $0) }
                let moveOn = Binding(
                    get: { layer.wrappedValue.endX != nil || layer.wrappedValue.endY != nil },
                    set: { on in
                        layer.wrappedValue.endX = on ? layer.wrappedValue.x : nil
                        layer.wrappedValue.endY = on ? layer.wrappedValue.y : nil
                    })
                ToggleRow("Move", isOn: moveOn)
                if moveOn.wrappedValue {
                    SliderRow("End X", value: Binding(get: { layer.wrappedValue.endX ?? layer.wrappedValue.x },
                                                     set: { layer.wrappedValue.endX = $0 }), in: 0...1, step: 0.01) { String(format: "%.0f%%", $0 * 100) }
                    SliderRow("End Y", value: Binding(get: { layer.wrappedValue.endY ?? layer.wrappedValue.y },
                                                     set: { layer.wrappedValue.endY = $0 }), in: 0...1, step: 0.01) { String(format: "%.0f%%", $0 * 100) }
                }
                if model.duration > 0.2 {
                    SliderRow("Start", value: layer.start, in: 0...model.duration, step: 0.1) { timecode($0) }
                    SliderRow("Length", value: layer.duration, in: 0...model.duration, step: 0.1) {
                        $0 <= 0 ? "Full" : String(format: "%.1fs", $0)
                    }
                }
                Button(role: .destructive) { model.removeLayer(layer.wrappedValue.id) } label: { Text("Remove") }
                    .buttonStyle(.borderless)
            }
            .padding(.leading, 6)
        } label: {
            Label(layer.wrappedValue.summary, systemImage: layer.wrappedValue.isText ? "textformat" : "photo")
                .lineLimit(1)
        }
    }

    private func textBinding(_ layer: Binding<StudioLayer>) -> Binding<String> {
        Binding(get: {
            if case let .text(s) = layer.wrappedValue.kind { return s }
            return ""
        }, set: { layer.wrappedValue.kind = .text($0) })
    }

    @ViewBuilder
    private func titleCard(_ name: String, binding: Binding<TitleCard?>) -> some View {
        let on = Binding(get: { binding.wrappedValue != nil },
                         set: { binding.wrappedValue = $0 ? TitleCard(title: name) : nil })
        ToggleRow(name, isOn: on)
        if let card = binding.wrappedValue {
            TextField("Title", text: Binding(get: { card.title }, set: { binding.wrappedValue?.title = $0 }))
                .textFieldStyle(.roundedBorder)
            TextField("Subtitle", text: Binding(get: { card.subtitle }, set: { binding.wrappedValue?.subtitle = $0 }))
                .textFieldStyle(.roundedBorder)
            SliderRow("Length", value: Binding(get: { card.duration }, set: { binding.wrappedValue?.duration = $0 }),
                      in: 0.5...5.0, step: 0.1) { String(format: "%.1fs", $0) }
        }
    }

    // MARK: - Binding helpers

    /// Binding into a `Double` field of the document.
    private func dbl(_ kp: WritableKeyPath<StudioDocument, Double>) -> Binding<Double> {
        Binding(get: { model.doc[keyPath: kp] }, set: { model.doc[keyPath: kp] = $0 })
    }
    /// Binding into a `CGFloat` field of the document, surfaced as `Double`.
    private func cg(_ kp: WritableKeyPath<StudioDocument, CGFloat>) -> Binding<Double> {
        Binding(get: { Double(model.doc[keyPath: kp]) }, set: { model.doc[keyPath: kp] = CGFloat($0) })
    }

    private var presetBinding: Binding<StudioPreset?> {
        Binding(get: { StudioPreset.allCases.first { $0.style == model.doc.scene } },
                set: { if let p = $0 { model.doc.scene = p.style } })
    }

    private func timecode(_ t: Double) -> String {
        let s = max(0, t)
        return String(format: "%d:%02d.%02d", Int(s) / 60, Int(s) % 60, Int((s.truncatingRemainder(dividingBy: 1)) * 100))
    }
}
