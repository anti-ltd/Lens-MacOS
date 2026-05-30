import SwiftUI
import AppKit
import LensCore

/// The rapid-capture gallery: a grid of every tray item with multi-select, plus
/// bulk actions — edit, export, clear, and "Make Collage". Empty when nothing's
/// been collected yet.
struct GalleryView: View {
    @ObservedObject private var tray = CaptureTray.shared
    @State private var selection: Set<UUID> = []
    @State private var showingCollage = false

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if tray.isEmpty {
                empty
            } else {
                grid
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .sheet(isPresented: $showingCollage) {
            CollageOptionsView(images: targetImages) { result in
                showingCollage = false
                guard let result else { return }
                EditorWindowController.present(
                    capture: .init(image: result, preset: LensSettings.shared.activePreset))
            }
        }
    }

    // MARK: - Bars

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("\(tray.count) capture\(tray.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            if !selection.isEmpty {
                Text("· \(selection.count) selected").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Select All") { selection = Set(tray.items.map(\.id)) }
                .disabled(tray.isEmpty)
            Button("Edit") { editSelected() }
                .disabled(selection.count != 1)
            Button("Export") { exportTarget() }
                .disabled(tray.isEmpty)
            Button(role: .destructive) { deleteSelected() } label: { Text("Delete") }
                .disabled(selection.isEmpty)
            Button("Make Collage") { showingCollage = true }
                .buttonStyle(.borderedProminent)
                .disabled(targetImages.count < 2)
            Menu {
                Button("Clear Tray", role: .destructive) { tray.clear(); selection = [] }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(12)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(tray.items) { item in
                    cell(item)
                }
            }
            .padding(16)
        }
    }

    private func cell(_ item: CaptureTray.Item) -> some View {
        let selected = selection.contains(item.id)
        return Image(nsImage: NSImage(cgImage: item.image, size: .zero))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(Color(nsColor: .underPageBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, .tint)
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggle(item.id) }
            .contextMenu {
                Button("Edit") { editOne(item) }
                Button("Remove", role: .destructive) { tray.remove(item.id); selection.remove(item.id) }
            }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("No captures yet").font(.headline)
            Text("Set the destination to **Add to Tray** in Output, then capture away — they'll collect here.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// The selection if any, otherwise the whole tray (so "Make Collage"/"Export"
    /// act on everything when nothing's picked).
    private var targetImages: [CGImage] {
        selection.isEmpty ? tray.allImages : tray.images(for: Array(selection))
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func editSelected() {
        guard let id = selection.first, let item = tray.items.first(where: { $0.id == id }) else { return }
        editOne(item)
    }

    private func editOne(_ item: CaptureTray.Item) {
        EditorWindowController.present(capture: .init(image: item.image, preset: item.preset))
    }

    private func deleteSelected() {
        for id in selection { tray.remove(id) }
        selection = []
    }

    private func exportTarget() {
        let s = LensSettings.shared
        var saved = 0
        for image in targetImages {
            if (try? OutputWriter.write(image, toFolder: s.saveFolderPath, format: s.format,
                                        quality: s.quality, template: s.filenameTemplate)) != nil {
                saved += 1
            }
        }
        CaptureFeedback.toast("Exported \(saved) image\(saved == 1 ? "" : "s")")
    }
}
