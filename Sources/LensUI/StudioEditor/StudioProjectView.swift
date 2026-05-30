import SwiftUI
import AppKit
import iUX_MacOS
import LensCore

/// The standalone multi-clip project window: a reorderable list of recording
/// clips that play in sequence, with project save + one-click export.
@available(macOS 14.0, *)
struct StudioProjectView: View {
    @ObservedObject var model: StudioProjectModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.project.clips.isEmpty { empty } else { clipList }
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var header: some View {
        HStack {
            TextField("Project name", text: $model.project.name).textFieldStyle(.roundedBorder).frame(width: 220)
            Spacer()
            Button { model.addRecording() } label: { Label("Add Recording", systemImage: "plus") }
        }
        .padding(10)
    }

    private var clipList: some View {
        List {
            ForEach(model.project.clips) { clip in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(get: { clip.enabled }, set: { model.setEnabled(clip.id, $0) }))
                        .labelsHidden().toggleStyle(.checkbox)
                    Image(systemName: "film").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(clip.name).lineLimit(1)
                        Text(clip.sessionPath).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("Edit") { model.editClip(clip) }.buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
            .onMove { model.move(from: $0, to: $1) }
            .onDelete { model.remove(at: $0) }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 38)).foregroundStyle(.tertiary)
            Text("No clips yet").font(.headline)
            Text("Add recordings to build a video. They play back-to-back in this order — drag to reorder.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Crossfade").foregroundStyle(.secondary)
                Slider(value: $model.project.transition, in: 0...1.5).frame(width: 160)
                Text(model.project.transition < 0.01 ? "Off" : String(format: "%.2fs", model.project.transition))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let p = model.exportProgress { ProgressView(value: p).progressViewStyle(.linear) }
            HStack {
                Button("Save Project", action: model.saveProject)
                if let s = model.status { Text(s).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Export Video") { model.export() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.project.enabledClips.isEmpty || model.exportProgress != nil)
            }
        }
        .padding(10)
    }
}
