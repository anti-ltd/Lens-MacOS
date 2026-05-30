import SwiftUI
import AppKit
import iUX_MacOS
import LensCore

/// Where captures go and how they look leaving the building: destination,
/// format/quality, save folder, filename template — plus the backdrop applied
/// to the active preset (the "beautiful backgrounds" pass).
struct OutputTab: View {
    @ObservedObject private var settings = LensSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: UX.cardSpacing) {
            CardSection("Destination") {
                Picker("", selection: $settings.destination) {
                    ForEach(CaptureDestination.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden()
                .padding(.vertical, 4)
                Divider()
                ToggleRow("Also copy to clipboard", isOn: $settings.alsoCopyToClipboard)
            }

            CardSection("Format") {
                Picker("", selection: $settings.format) {
                    ForEach(OutputFormat.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 4)
                if settings.format.isLossy {
                    Divider()
                    SliderRow.percent("Quality", value: $settings.quality)
                }
            }

            CardSection("Recording") {
                Picker("", selection: $settings.recordingSource) {
                    ForEach(RecordingSource.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 4)
                Divider()
                HStack {
                    Text("Frame rate").frame(width: 90, alignment: .leading)
                    Picker("", selection: $settings.recordingFPS) {
                        ForEach(RecordingFPS.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                .padding(.vertical, 6)
                Divider()
                HStack {
                    Text("Codec").frame(width: 90, alignment: .leading)
                    Picker("", selection: $settings.recordingCodec) {
                        ForEach(VideoCodec.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                .padding(.vertical, 6)
                Divider()
                ToggleRow("Record cursor", isOn: $settings.recordCursor)
                Divider()
                ToggleRow("System audio",
                          subtitle: "Record the sound your Mac plays",
                          isOn: $settings.recordSystemAudio)
                Divider()
                ToggleRow("Microphone",
                          subtitle: micAvailable ? "Mix your mic into the recording" : "Requires macOS 15 or later",
                          isOn: $settings.recordMicrophone)
                .disabled(!micAvailable)
            }

            CardSection("Studio frame") {
                Picker("", selection: $settings.studioPreset) {
                    ForEach(StudioPreset.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 4)
                Text("Applied by **Render Recording…** — backgrounds, rounded window, shadow & chrome.")
                    .font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 4)
                Divider()
                ToggleRow("Auto-zoom",
                          subtitle: "Cinematic camera that follows your clicks",
                          isOn: $settings.studioAutoZoom)
                if settings.studioAutoZoom {
                    Divider()
                    SliderRow("Zoom", value: $settings.studioZoom, in: 1.2...3.0, step: 0.1) {
                        String(format: "%.1f×", $0)
                    }
                    Divider()
                    ToggleRow("Punchy zoom", subtitle: "Snappy \"pop\" instead of a smooth ease",
                              isOn: $settings.studioPunchyZoom)
                }
                Divider()
                ToggleRow("Cinematic cursor",
                          subtitle: "Enlarged, smoothed cursor — turn off Record cursor to avoid doubling",
                          isOn: $settings.studioCursor)
                if settings.studioCursor {
                    Divider()
                    SliderRow("Cursor size", value: $settings.studioCursorSize, in: 1.0...3.0, step: 0.1) {
                        String(format: "%.1f×", $0)
                    }
                    Divider()
                    ToggleRow("Click ripples", isOn: $settings.studioClickRipples)
                    Divider()
                    SliderRow.percent("Spotlight", value: $settings.studioSpotlight)
                }
                Divider()
                ToggleRow("Keystroke overlay",
                          subtitle: "Show shortcuts (⌘C, ⌃⇧4…) as captions",
                          isOn: $settings.studioKeystrokes)
                Divider()
                ToggleRow("Webcam bubble",
                          subtitle: "Record the camera and overlay it as a PiP",
                          isOn: $settings.studioWebcam)
                if settings.studioWebcam {
                    Divider()
                    SliderRow.percent("Webcam size", value: $settings.studioWebcamSize)
                    Divider()
                    Picker("", selection: $settings.studioWebcamCorner) {
                        ForEach(WebcamStyle.Corner.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden().padding(.vertical, 4)
                }
            }

            CardSection("Save to") {
                HStack {
                    Text(abbreviatedPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…", action: chooseFolder)
                }
                .padding(.vertical, 6)
                Divider()
                TextFieldRow("Filename", prompt: "Lens {date} {time}", text: $settings.filenameTemplate)
                Text("Tokens: {name} {date} {time} {seq}")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }

            BackdropEditor(backdrop: backdropBinding)
        }
    }

    /// Microphone capture rides on ScreenCaptureKit's mic path, which is macOS 15+.
    private var micAvailable: Bool {
        if #available(macOS 15.0, *) { return true } else { return false }
    }

    private var abbreviatedPath: String {
        (settings.saveFolderPath as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (settings.saveFolderPath as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveFolderPath = url.path
        }
    }

    /// A binding that reads/writes the active preset's backdrop in place.
    private var backdropBinding: Binding<Backdrop> {
        Binding(
            get: { settings.activePreset.backdrop ?? .none },
            set: { newValue in
                guard let idx = settings.presets.firstIndex(where: { $0.id == settings.activePresetID }) else { return }
                settings.presets[idx].backdrop = newValue.isIdentity ? nil : newValue
            }
        )
    }
}

/// The backdrop controls for the active preset — fill, padding, corners, shadow.
private struct BackdropEditor: View {
    @Binding var backdrop: Backdrop

    enum FillKind: String, CaseIterable, Identifiable {
        case none, solid, gradient
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        CardSection("Backdrop (active preset)") {
            Picker("", selection: kindBinding) {
                ForEach(FillKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.vertical, 4)

            switch fillKind {
            case .none:
                EmptyView()
            case .solid:
                Divider()
                ColorPicker("Color", selection: solidColor)
                    .padding(.vertical, 6)
            case .gradient:
                Divider()
                HStack {
                    ColorPicker("From", selection: gradientFrom)
                    Spacer()
                    ColorPicker("To", selection: gradientTo)
                }
                .padding(.vertical, 6)
            }

            Divider()
            SliderRow("Padding", value: paddingBinding, in: 0...160, step: 4) { "\(Int($0))" }
            Divider()
            SliderRow("Corners", value: cornerBinding, in: 0...48, step: 1) { "\(Int($0))" }
            Divider()
            SliderRow.percent("Shadow", value: shadowBinding)
        }
    }

    // MARK: - Derived bindings

    private var fillKind: FillKind {
        switch backdrop.fill {
        case .transparent: return .none
        case .solid:       return .solid
        case .gradient:    return .gradient
        }
    }

    private var kindBinding: Binding<FillKind> {
        Binding(get: { fillKind }, set: { newKind in
            switch newKind {
            case .none:     backdrop.fill = .transparent
            case .solid:    backdrop.fill = .solid(.white)
            case .gradient: backdrop.fill = .gradient(from: RGBAColor(hex: "#5B8CFF")!, to: RGBAColor(hex: "#A855F7")!)
            }
        })
    }

    private var solidColor: Binding<Color> {
        Binding(get: {
            if case let .solid(c) = backdrop.fill { return c.color }
            return .white
        }, set: { backdrop.fill = .solid($0.rgba) })
    }

    private var gradientFrom: Binding<Color> {
        Binding(get: {
            if case let .gradient(f, _) = backdrop.fill { return f.color }
            return .blue
        }, set: { new in
            if case let .gradient(_, t) = backdrop.fill { backdrop.fill = .gradient(from: new.rgba, to: t) }
        })
    }

    private var gradientTo: Binding<Color> {
        Binding(get: {
            if case let .gradient(_, t) = backdrop.fill { return t.color }
            return .purple
        }, set: { new in
            if case let .gradient(f, _) = backdrop.fill { backdrop.fill = .gradient(from: f, to: new.rgba) }
        })
    }

    private var paddingBinding: Binding<Double> {
        Binding(get: { Double(backdrop.padding) }, set: { backdrop.padding = CGFloat($0) })
    }
    private var cornerBinding: Binding<Double> {
        Binding(get: { Double(backdrop.cornerRadius) }, set: { backdrop.cornerRadius = CGFloat($0) })
    }
    private var shadowBinding: Binding<Double> {
        Binding(get: { backdrop.shadowOpacity }, set: { backdrop.shadowOpacity = $0 })
    }
}

extension RGBAColor {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

extension Color {
    var rgba: RGBAColor {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return RGBAColor(r: Double(ns.redComponent), g: Double(ns.greenComponent),
                         b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
    }
}
