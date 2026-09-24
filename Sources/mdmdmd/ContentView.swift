import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var workspace: Workspace
    @State private var selection: URL?

    var body: some View {
        List(selection: $selection) {
            ForEach(workspace.tree) { FileRow(node: $0, expanded: $workspace.expanded) }
        }
        .listStyle(.sidebar)
        .onAppear { selection = workspace.current }
        .onChange(of: workspace.current) { _, url in selection = url }
        .onChange(of: selection) { _, url in
            if let url, url != workspace.current { workspace.openFile(url) }
        }
        .contextMenu { Button("Reload") { workspace.reloadTree() } }
    }
}

struct DetailView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        VStack(spacing: 0) {
            if workspace.current == nil {
                ContentUnavailableView("No file open", systemImage: "doc.text", description: Text("Open a folder (⇧⌘O) or a file (⌘O)."))
            } else {
                EditorView()
            }
            statusBar
        }
    }

    private var statusBar: some View {
        let words = Styler.spokenWords(workspace.text)
        let seconds = Int(Double(words) / 150 * 60)
        return HStack(spacing: 12) {
            if let current = workspace.current {
                Text(current.lastPathComponent + (workspace.dirty ? " •" : ""))
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                Slider(value: $prefs.topMargin, in: 0...200).frame(width: 110)
                Text("\(Int(prefs.topMargin))").monospacedDigit().frame(width: 26, alignment: .trailing)
            }
            .controlSize(.mini)
            .help("Top margin")
            Text("\(words) spoken words · \(seconds / 60):\(String(format: "%02d", seconds % 60)) at 150 wpm")
            if prefs.hiddenFromCapture {
                Label("Hidden from capture", systemImage: "eye.slash").labelStyle(.titleAndIcon)
            }
            if prefs.teleprompter {
                Label("Teleprompter", systemImage: "pin.fill")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

private struct FileRow: View {
    let node: FileNode
    @Binding var expanded: Set<URL>

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded.contains(node.url) },
                set: { open in if open { expanded.insert(node.url) } else { expanded.remove(node.url) } }
            )) {
                ForEach(children) { FileRow(node: $0, expanded: $expanded) }
            } label: {
                Label(node.name, systemImage: "folder").lineLimit(1)
            }
        } else {
            Label(node.name, systemImage: "doc.text").lineLimit(1).tag(node.url)
        }
    }
}
