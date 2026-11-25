import AppKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// A node that shows a file: PDFs, images, text, office documents, audio and video are drawn
/// with Quick Look, on the same page surface a written node uses.
struct FileNodeView: View {
    let node: NodeModel
    let space: SpaceModel

    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var node = node
        let url = node.file.map { store.fileURL(for: $0, in: space) }
        let available = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        VStack(alignment: .leading, spacing: 14) {
            header(title: $node.title, url: available ? url : nil)
            LinkChips(space: space, anchor: Anchor(nodeID: node.id, blockID: nil))
            Group {
                if let url, available {
                    QuickLookPreview(url: url)
                } else {
                    missing
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.embedFill(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardStroke(scheme), lineWidth: 1).allowsHitTesting(false))
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .pageSurface()
    }

    private func header(title: Binding<String>, url: URL?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: node.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                TextField(L("Untitled", "제목 없음"), text: title)
                    .textFieldStyle(.plain)
                    .font(.doc(22, .bold))
                if let file = node.file {
                    Text(file.originalName + "  ·  " + file.summary + "  ·  "
                         + L("added ", "추가 ") + formatDate(file.addedAt, date: .abbreviated, time: .omitted))
                        .font(.app(11.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            if let url {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label(L("Open", "열기"), systemImage: "arrow.up.forward.app").font(.app(11.5, .medium))
                }
                .buttonStyle(SoftButtonStyle())
                .help(L("Open in the default app", "기본 앱으로 열기"))
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Label(L("Show", "위치"), systemImage: "folder").font(.app(11.5, .medium))
                }
                .buttonStyle(SoftButtonStyle())
                .help(L("Show in Finder", "Finder에서 보기"))
            }
            AddLinkButton(space: space, anchor: Anchor(nodeID: node.id, blockID: nil), labeled: true)
        }
    }

    private var missing: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.folder").font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(L("This file is no longer in the Space's folder.", "이 파일이 Space 폴더에 더 이상 없어요."))
                .font(.app(13, .medium))
            Text(L("Delete this node and add the file again.", "이 노드를 삭제하고 파일을 다시 추가해 주세요."))
                .font(.app(12)).foregroundStyle(.secondary)
        }
    }
}

/// Quick Look's own preview view, hosted in SwiftUI.
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) != url as NSURL { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}

/// Adding files to a Space: from the open panel, or dropped on the window.
@MainActor
enum FileImporter {
    static func pick(into space: SpaceModel, store: Store, ui: AppUI) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = L("Add", "추가")
        panel.message = L("Files are copied into this Space, so the originals can be moved or deleted.",
                          "파일은 이 Space 안에 복사돼요. 원본은 옮기거나 지워도 됩니다.")
        guard panel.runModal() == .OK else { return }
        add(panel.urls, to: space, store: store, ui: ui)
    }

    static func add(_ urls: [URL], to space: SpaceModel, store: Store, ui: AppUI) {
        var added = 0
        var failure: String?
        withAnimation(Motion.spring) {
            for url in urls {
                do {
                    try store.importFile(at: url, into: space)
                    added += 1
                } catch {
                    failure = url.lastPathComponent
                }
            }
        }
        if let failure, added == 0 {
            ui.flash(L("Couldn't add “\(failure)”", "“\(failure)”을(를) 추가할 수 없어요"), symbol: "exclamationmark.triangle.fill")
        } else if added > 0 {
            ui.flash(added == 1 ? L("File added", "파일을 추가했어요") : L("\(added) files added", "파일 \(added)개를 추가했어요"), symbol: "paperclip.circle.fill")
        }
    }

    /// Pulls file URLs out of a drop and adds them.
    static func handleDrop(_ providers: [NSItemProvider], into space: SpaceModel, store: Store, ui: AppUI) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { add([url], to: space, store: store, ui: ui) }
            }
        }
        return true
    }
}
