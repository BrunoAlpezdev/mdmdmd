import SwiftUI

struct ContentView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var prefs: Prefs
    @State private var columns: NavigationSplitViewVisibility = UserDefaults.standard.bool(forKey: "teleprompter") ? .detailOnly : .all

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
        List(workspace.tree, children: \.children, selection: $workspace.current) { node in
            Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                .lineLimit(1)
        }
        .navigationTitle(workspace.root?.lastPathComponent ?? "mdmdmd")
        .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        .onChange(of: workspace.current) { _, url in
            if let url, !(workspace.tree.contains { $0.url == url && $0.isDirectory }) {
                workspace.openFile(url)
            }
        }
        .contextMenu { Button("Reload") { workspace.reloadTree() } }
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
