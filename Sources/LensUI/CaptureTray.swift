import AppKit
import LensCore

/// The rapid-capture collection. With destination set to **Add to Tray**, every
/// capture lands here instead of opening an editor; the gallery then manages,
/// edits, exports, or collages the whole batch at once.
@MainActor
final class CaptureTray: ObservableObject {
    static let shared = CaptureTray()
    private init() {}

    struct Item: Identifiable {
        let id = UUID()
        let image: CGImage
        let date: Date
        let preset: Preset
    }

    @Published private(set) var items: [Item] = []

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    func add(_ image: CGImage, preset: Preset) {
        items.append(Item(image: image, date: Date(), preset: preset))
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items.removeAll()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func images(for ids: [UUID]) -> [CGImage] {
        // Preserve tray order for the given selection.
        items.filter { ids.contains($0.id) }.map(\.image)
    }

    var allImages: [CGImage] { items.map(\.image) }
}
