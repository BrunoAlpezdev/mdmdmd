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

    /// Never wraps: as the window narrows the sliders go first, then the file
    /// name, and the reading time stays.
    private var statusBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { fileName; Spacer(); knobs; stats }
            HStack(spacing: 12) { fileName; Spacer(); stats }
            HStack(spacing: 12) { Spacer(); stats }
        }
        .lineLimit(1)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var fileName: some View {
        Text((workspace.current?.lastPathComponent ?? "") + (workspace.dirty ? " •" : ""))
            .truncationMode(.middle)
    }

    private var knobs: some View {
        HStack(spacing: 12) {
            knob("arrow.up.and.down.text.horizontal", $prefs.topMargin, 0...200, "Top margin")
            knob("arrow.left.and.right.text.vertical", $prefs.columnWidth, 480...2400, "Column width")
        }
        .fixedSize()
    }

    private var stats: some View {
        let words = Styler.spokenWords(workspace.text)
        let seconds = Int(Double(words) / 150 * 60)
        return HStack(spacing: 10) {
            Text("\(words) spoken words · \(seconds / 60):\(String(format: "%02d", seconds % 60)) at 150 wpm")
            quickControls
        }
        .fixedSize()
    }

    /// The View menu items people reach for mid-recording, one click away.
    private var quickControls: some View {
        HStack(spacing: 8) {
            Button { prefs.hiddenFromCapture.toggle() } label: {
                Image(systemName: prefs.hiddenFromCapture ? "eye.slash" : "eye")
            }
            .help(prefs.hiddenFromCapture ? "Hidden from screen capture" : "Visible in screen capture")

            Button { prefs.teleprompter.toggle() } label: {
                Image(systemName: prefs.teleprompter ? "pin.fill" : "pin")
            }
            .help("Teleprompter mode (⇧⌘T)")

            Menu {
                Picker("Theme", selection: $prefs.themeName) {
                    ForEach(Theme.all, id: \.name) { Text($0.name).tag($0.name) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "paintpalette")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Theme: \(prefs.themeName)")
        }
        .buttonStyle(.plain)
        .menuStyle(.button)
        .imageScale(.medium)
    }

    private func knob(_ icon: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ help: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Slider(value: value, in: range).frame(width: 100)
            Text("\(Int(value.wrappedValue))").monospacedDigit().frame(width: 32, alignment: .trailing)
        }
        .controlSize(.mini)
        .help(help)
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
