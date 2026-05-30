import SwiftUI
import AppKit
import iUX_MacOS
import LensCore

/// Options + live preview for grouping the selected captures into a single
/// collage image. "Create" hands the composed `CGImage` back to the gallery,
/// which opens it in the editor for any final touches.
struct CollageOptionsView: View {
    let images: [CGImage]
    let onDone: (CGImage?) -> Void

    @State private var autoColumns = true
    @State private var columns = 2
    @State private var spacing = 16.0
    @State private var padding = 24.0
    @State private var cornerRadius = 10.0
    @State private var fill = FillKind.gradient
    @State private var solid = Color(red: 0.05, green: 0.07, blue: 0.15)
    @State private var gradFrom = Color(red: 0.36, green: 0.55, blue: 1.0)
    @State private var gradTo = Color(red: 0.66, green: 0.33, blue: 0.97)

    enum FillKind: String, CaseIterable, Identifiable {
        case none, solid, gradient
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        HStack(spacing: 0) {
            controls.frame(width: 300)
            Divider()
            preview.frame(minWidth: 360)
        }
        .frame(width: 720, height: 520)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: UX.cardSpacing) {
            Text("Make Collage").font(.title3.weight(.semibold))
            Text("\(images.count) images").foregroundStyle(.secondary).font(.callout)

            CardSection("Layout") {
                ToggleRow("Auto columns", isOn: $autoColumns)
                if !autoColumns {
                    Divider()
                    Stepper("Columns: \(columns)", value: $columns, in: 1...8)
                        .padding(.vertical, 6)
                }
                Divider()
                SliderRow("Spacing", value: $spacing, in: 0...60, step: 2) { "\(Int($0))" }
                Divider()
                SliderRow("Padding", value: $padding, in: 0...80, step: 2) { "\(Int($0))" }
                Divider()
                SliderRow("Corners", value: $cornerRadius, in: 0...40, step: 1) { "\(Int($0))" }
            }

            CardSection("Background") {
                Picker("", selection: $fill) {
                    ForEach(FillKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().padding(.vertical, 4)
                switch fill {
                case .none: EmptyView()
                case .solid:
                    ColorPicker("Color", selection: $solid).padding(.vertical, 4)
                case .gradient:
                    HStack { ColorPicker("From", selection: $gradFrom); Spacer(); ColorPicker("To", selection: $gradTo) }
                        .padding(.vertical, 4)
                }
            }

            Spacer()
            HStack {
                Button("Cancel") { onDone(nil) }
                Spacer()
                Button("Create") { onDone(compose()) }
                    .buttonStyle(.borderedProminent)
                    .disabled(images.count < 2)
            }
        }
        .padding(16)
    }

    private var preview: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let cg = compose() {
                Image(nsImage: NSImage(cgImage: cg, size: .zero))
                    .resizable().aspectRatio(contentMode: .fit)
                    .padding(20)
                    .shadow(radius: 8)
            }
        }
    }

    private func options() -> CollageComposer.Options {
        CollageComposer.Options(
            columns: autoColumns ? 0 : columns,
            spacing: CGFloat(spacing),
            padding: CGFloat(padding),
            maxTile: 480,
            background: backgroundFill,
            cornerRadius: CGFloat(cornerRadius)
        )
    }

    private var backgroundFill: Backdrop.Fill {
        switch fill {
        case .none: return .transparent
        case .solid: return .solid(solid.rgba)
        case .gradient: return .gradient(from: gradFrom.rgba, to: gradTo.rgba)
        }
    }

    private func compose() -> CGImage? {
        CollageComposer.make(images, options: options())
    }
}
