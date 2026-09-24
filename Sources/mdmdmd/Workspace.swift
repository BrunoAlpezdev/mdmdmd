import AppKit
import Combine

struct FileNode: Identifiable, Hashable {
    let url: URL
    var children: [FileNode]?
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isDirectory: Bool { children != nil }
}

/// The opened folder, the current file, and the text being edited.
@MainActor
final class Workspace: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var tree: [FileNode] = []
    @Published var current: URL?
    @Published private(set) var text = ""
    @Published private(set) var dirty = false
    /// Folders open in the sidebar. Drives the tree and the fit-to-content width.
    @Published var expanded: Set<URL> = []

    private var watcher: DispatchSourceFileSystemObject?
    private var autosave: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    /// A folder the sidebar always shows, whatever file gets opened. Nil means
    /// the sidebar follows the opened file's folder.
    @Published var defaultRoot: URL? = UserDefaults.standard.string(forKey: "defaultRoot").map { URL(fileURLWithPath: $0) } {
        didSet {
            defaults.set(defaultRoot?.path, forKey: "defaultRoot")
            if let defaultRoot { openFolder(defaultRoot) }
        }
    }

    init() {
        if let path = (defaults.string(forKey: "defaultRoot") ?? defaults.string(forKey: "root")) { openFolder(URL(fileURLWithPath: path)) }
        if let path = defaults.string(forKey: "current") { openFile(URL(fileURLWithPath: path)) }
    }

    func openFolder(_ url: URL) {
        root = url
        expanded = []
        defaults.set(url.path, forKey: "root")
        reloadTree()
    }

    func reloadTree() {
        tree = root.map(Self.scan) ?? []
    }

    /// Width of the widest visible sidebar row: indentation, chevron, icon, label, padding.
    var fittedSidebarWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        func widest(_ nodes: [FileNode], depth: CGFloat) -> CGFloat {
            nodes.reduce(0) { best, node in
                let label = (node.name as NSString).size(withAttributes: [.font: font]).width
                var width = 80 + depth * 18 + label
                if node.isDirectory, expanded.contains(node.url) {
                    width = max(width, widest(node.children ?? [], depth: depth + 1))
                }
                return max(best, width)
            }
        }
        return min(600, max(180, ceil(widest(tree, depth: 0))))
    }

    /// `relocate` is true only for files the user explicitly opened from
    /// outside (Finder, `open`, the Open dialog). Session restore and sidebar
    /// clicks never move anything.
    func openFile(_ url: URL, relocate: Bool = false) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let url = relocate ? (defaultRoot.map { moveIntoDefaultFolder(url, root: $0) } ?? url) : url
        if defaultRoot == nil, root == nil || !url.path.hasPrefix(root!.path) { openFolder(url.deletingLastPathComponent()) }
        autosave?.cancel()
        current = url
        // Reveal the file: expand every folder between the root and it.
        var parent = url.deletingLastPathComponent()
        while let root, parent.path.hasPrefix(root.path), parent.path != root.path {
            expanded.insert(parent)
            parent = parent.deletingLastPathComponent()
        }
        defaults.set(url.path, forKey: "current")
        text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        dirty = false
        watch(url)
    }

    /// A file opened from outside the pinned folder moves into it, so every
    /// script ends up in one place. A name clash gets a numeric suffix.
    private func moveIntoDefaultFolder(_ url: URL, root: URL) -> URL {
        guard !url.path.hasPrefix(root.path + "/") else { return url }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            defaultRoot = nil  // the pinned folder is gone; stop pinning rather than failing every open
            return url
        }
        var target = root.appendingPathComponent(url.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = root.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(n).\(url.pathExtension)")
            n += 1
        }
        do {
            try fm.moveItem(at: url, to: target)
            reloadTree()
            return target
        } catch {
            NSAlert(error: error).runModal()
            return url
        }
    }

    /// Opens whatever Finder or `open` handed us: a folder or a file.
    func open(_ url: URL) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        isDir.boolValue ? openFolder(url) : openFile(url, relocate: true)
    }

    func editorChanged(_ newText: String) {
        guard newText != text else { return }
        text = newText
        guard current != nil else { return }
        dirty = true
        autosave?.cancel()
        autosave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        guard let current, dirty else { return }
        do {
            try text.write(to: current, atomically: true, encoding: .utf8)
            dirty = false
            watch(current)  // atomic write replaced the inode
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Reloads when the file changes underneath us (Claude rewrites scripts in place).
    private func watch(_ url: URL) {
        watcher?.cancel()
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, !self.dirty, self.current == url else { return }
            // Writers truncate then write; give them a moment.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !self.dirty, self.current == url,
                      let fresh = try? String(contentsOf: url, encoding: .utf8), fresh != self.text else { return }
                self.text = fresh
            }
            if source.data.contains(.rename) || source.data.contains(.delete) { self.watch(url) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private static func scan(_ dir: URL) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        let skipped: Set<String> = ["node_modules", ".build", "build", "dist", "DerivedData", "Pods", "target"]
        var nodes: [FileNode] = []
        for url in items {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if skipped.contains(url.lastPathComponent) { continue }
                let children = scan(url)
                if !children.isEmpty { nodes.append(FileNode(url: url, children: children)) }
            } else if ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()) {
                nodes.append(FileNode(url: url, children: nil))
            }
        }
        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

/// View preferences, persisted in UserDefaults.
@MainActor
final class Prefs: ObservableObject {
    @Published var baseSize: CGFloat = UserDefaults.standard.object(forKey: "baseSize") as? CGFloat ?? 16 {
        didSet { UserDefaults.standard.set(baseSize, forKey: "baseSize") }
    }
    @Published var teleprompter = UserDefaults.standard.bool(forKey: "teleprompter") {
        didSet { UserDefaults.standard.set(teleprompter, forKey: "teleprompter") }
    }
    @Published var hiddenFromCapture = UserDefaults.standard.object(forKey: "hiddenFromCapture") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hiddenFromCapture, forKey: "hiddenFromCapture") }
    }
    @Published var opacity: CGFloat = 1
    /// Space above the first line, in points. Reading from a distance wants more of it.
    @Published var topMargin: Double = UserDefaults.standard.object(forKey: "topMargin") as? Double ?? 32 {
        didSet { UserDefaults.standard.set(topMargin, forKey: "topMargin") }
    }
    /// Widest the text column gets, in points; the rest is side margin.
    @Published var columnWidth: Double = UserDefaults.standard.object(forKey: "columnWidth") as? Double ?? 760 {
        didSet { UserDefaults.standard.set(columnWidth, forKey: "columnWidth") }
    }
    @Published var themeName: String = UserDefaults.standard.string(forKey: "theme") ?? Theme.system.name {
        didSet { UserDefaults.standard.set(themeName, forKey: "theme") }
    }

    var theme: Theme { Theme.all.first { $0.name == themeName } ?? .system }

    /// Teleprompter reads from across the desk; bump the type.
    var editorSize: CGFloat { teleprompter ? baseSize * 1.4 : baseSize }
}
