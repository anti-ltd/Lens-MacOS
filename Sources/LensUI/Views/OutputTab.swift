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
