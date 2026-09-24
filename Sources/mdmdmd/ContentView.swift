import SwiftUI

struct ContentView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var prefs: Prefs
    @State private var columns: NavigationSplitViewVisibility = UserDefaults.standard.bool(forKey: "teleprompter") ? .detailOnly : .all
    @State private var selection: URL?

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                if workspace.current == nil {
                    ContentUnavailableView("No file open", systemImage: "doc.text", description: Text("Open a folder (⇧⌘O) or a file (⌘O)."))
                } else {
                    EditorView()
                }
                statusBar
            }
        }
        .onChange(of: prefs.teleprompter) { _, on in columns = on ? .detailOnly : .all }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(workspace.tree) { FileRow(node: $0, expanded: $workspace.expanded) }
        }
        .navigationTitle(workspace.root?.lastPathComponent ?? "mdmdmd")
        // Double-clicking the divider snaps back to the ideal width, so the
        // ideal tracks the widest visible row and the sidebar fits its content.
        .navigationSplitViewColumnWidth(min: 160, ideal: fittedWidth, max: 600)
        .onAppear { selection = workspace.current }
        .onChange(of: workspace.current) { _, url in selection = url }
        .onChange(of: selection) { _, url in
            if let url, url != workspace.current { workspace.openFile(url) }
        }
        .contextMenu { Button("Reload") { workspace.reloadTree() } }
    }

    /// Width of the widest visible row: indentation, disclosure chevron, icon, label, padding.
    private var fittedWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        func widest(_ nodes: [FileNode], depth: CGFloat) -> CGFloat {
            nodes.reduce(0) { best, node in
                let label = (node.name as NSString).size(withAttributes: [.font: font]).width
                var width = 80 + depth * 18 + label
                if node.isDirectory, workspace.expanded.contains(node.url) {
                    width = max(width, widest(node.children ?? [], depth: depth + 1))
                }
                return max(best, width)
            }
        }
        return min(600, max(180, ceil(widest(workspace.tree, depth: 0))))
    }

    private var statusBar: some View {
        let words = Styler.spokenWords(workspace.text)
        let seconds = Int(Double(words) / 150 * 60)
        return HStack(spacing: 12) {
            if let current = workspace.current {
                Text(current.lastPathComponent + (workspace.dirty ? " •" : ""))
            }
            Spacer()
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
