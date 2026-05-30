import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LensCore

/// Drives the multi-clip Studio project window: a list of recording clips that
/// play back-to-back, saved as a `.lensproj`, exported to one video.
@available(macOS 14.0, *)
@MainActor
final class StudioProjectModel: ObservableObject {
    @Published var project: StudioProject
    @Published var projectURL: URL?
    @Published var exportProgress: Double?
    @Published var status: String?

    init(project: StudioProject = StudioProject(), url: URL? = nil) {
        self.project = project
        self.projectURL = url
    }

    func addRecording() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose recording session folders to add"
        panel.directoryURL = URL(fileURLWithPath: (LensSettings.shared.saveFolderPath as NSString).expandingTildeInPath)
            .appendingPathComponent("Lens Recordings", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
            let doc = StudioDocument.load(from: folder) ?? StudioEditorModel.defaultDocument()
            project.clips.append(StudioClip(name: folder.lastPathComponent, sessionPath: folder.path, document: doc))
        }
    }

    func remove(at offsets: IndexSet) { project.clips.remove(atOffsets: offsets) }
    func move(from: IndexSet, to: Int) { project.clips.move(fromOffsets: from, toOffset: to) }

    func setEnabled(_ id: UUID, _ on: Bool) {
        guard let i = project.clips.firstIndex(where: { $0.id == id }) else { return }
        project.clips[i].enabled = on
    }

    func editClip(_ clip: StudioClip) {
        StudioEditorWindowController.open(folder: clip.sessionURL)
    }

    func saveProject() {
        if let url = projectURL {
            try? project.save(to: url)
            status = "Saved \(url.lastPathComponent)"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: StudioProject.fileExtension) ?? .json]
        panel.nameFieldStringValue = "\(project.name).\(StudioProject.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? project.save(to: url)
        projectURL = url
        status = "Saved \(url.lastPathComponent)"
    }

    func export() {
        guard !project.enabledClips.isEmpty else { status = "Add at least one clip"; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(project.name).mp4"
        guard panel.runModal() == .OK, let out = panel.url else { return }
        exportProgress = 0
        let project = project
        Task {
            do {
                _ = try await ProjectRenderer.render(project, to: out) { p in
                    Task { @MainActor in self.exportProgress = p }
                }
                exportProgress = nil
                status = "Exported \(out.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } catch {
                exportProgress = nil
                status = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
