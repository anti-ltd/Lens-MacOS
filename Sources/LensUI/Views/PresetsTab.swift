import SwiftUI
import iUX_MacOS
import LensCore

/// The "repeatable" half: pick the active preset (its ratio/pixel lock applies
/// to every capture), and build your own — docs, social, ads — in one place.
struct PresetsTab: View {
    @ObservedObject private var settings = LensSettings.shared

    @State private var newName = ""
    @State private var kind = NewKind.ratio
    @State private var aWidth = "16"
    @State private var aHeight = "9"

    enum NewKind: String, CaseIterable, Identifiable {
        case free, ratio, pixels
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UX.cardSpacing) {
            CardSection("Active preset") {
                ChipGroup(
                    settings.presets,
                    title: { $0.name },
                    isSelected: { $0.id == settings.activePresetID },
                    size: .small,
                    select: { settings.activePresetID = $0.id }
                )
                .padding(.vertical, 6)

                Divider()
                HStack {
                    Label(settings.activePreset.constraint.label, systemImage: "aspectratio")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !isBuiltin(settings.activePreset) {
                        Button(role: .destructive) { deleteActive() } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete this preset")
                    }
                }
                .padding(.vertical, 6)
            }

            CardSection("New preset") {
                TextFieldRow(prompt: "Preset name", text: $newName)
                Divider()
                Picker("", selection: $kind) {
                    ForEach(NewKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 6)

                if kind != .free {
                    HStack(spacing: 6) {
                        TextField(kind == .ratio ? "W" : "px W", text: $aWidth)
                            .frame(width: 64)
                        Text(kind == .ratio ? ":" : "×").foregroundStyle(.secondary)
                        TextField(kind == .ratio ? "H" : "px H", text: $aHeight)
                            .frame(width: 64)
                        Spacer()
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(.vertical, 4)
                }

                Divider()
                HStack {
                    Spacer()
                    Button("Add Preset", action: addPreset)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func isBuiltin(_ p: Preset) -> Bool {
        Preset.builtins.contains { $0.name == p.name }
    }

    private func addPreset() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let constraint: FrameConstraint
        switch kind {
        case .free:
            constraint = .free
        case .ratio:
            constraint = .ratio(w: Double(aWidth) ?? 16, h: Double(aHeight) ?? 9)
        case .pixels:
            constraint = .pixels(w: Int(aWidth) ?? 1920, h: Int(aHeight) ?? 1080)
        }
        let preset = Preset(name: name, constraint: constraint)
        settings.presets.append(preset)
        settings.activePresetID = preset.id
        newName = ""
    }

    private func deleteActive() {
        let id = settings.activePresetID
        settings.presets.removeAll { $0.id == id }
        settings.activePresetID = settings.presets.first?.id
    }
}
