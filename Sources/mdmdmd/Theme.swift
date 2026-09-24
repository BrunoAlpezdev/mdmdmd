import AppKit

/// A theme is a small JSON file. Every field is optional; a missing field
/// falls back to the system look, so `{"name": "Mine", "accent": "#FF5FA2"}`
/// is a complete theme.
struct Theme: Codable, Equatable {
    var name: String
    var appearance: String?      // "light" | "dark"; nil follows the system
    var background: String?      // colors are "#RRGGBB"
    var text: String?
    var secondary: String?       // markers, blockquotes, list bullets
    var accent: String?          // links
    var codeBackground: String?
    var font: String?            // "system" | "serif" | "rounded" | a family name
    var monoFont: String?        // a family name; nil is the system mono
    var lineHeight: CGFloat?     // multiple of the font's line height

    static let system = Theme(name: "System")

    static let builtIn: [Theme] = [
        system,
        Theme(name: "Paper", appearance: "light", background: "#F6F1E7", text: "#2A2622", secondary: "#9A9082",
              accent: "#B5562D", codeBackground: "#EDE5D5", font: "serif", lineHeight: 1.45),
        Theme(name: "Night", appearance: "dark", background: "#1C1917", text: "#ECE4D6", secondary: "#857B6E",
              accent: "#E3A857", codeBackground: "#27221E", font: "serif", lineHeight: 1.45),
        Theme(name: "Graphite", appearance: "dark", background: "#111417", text: "#D6DAE0", secondary: "#6F7681",
              accent: "#63B3ED", codeBackground: "#1A1F25", font: "system", lineHeight: 1.35),
        Theme(name: "Prompter", appearance: "dark", background: "#000000", text: "#FFFFFF", secondary: "#8A8A8A",
              accent: "#FFD60A", codeBackground: "#1A1A1A", font: "rounded", lineHeight: 1.6),
    ]

    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("mdmdmd/Themes", isDirectory: true)

    /// Built-in themes followed by every readable JSON in the themes folder.
    static var all: [Theme] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let custom = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Theme.self, from: $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return builtIn + custom
    }

    /// Creates the folder with an example file so there is something to edit.
    static func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let example = folder.appendingPathComponent("Example.json")
        if !FileManager.default.fileExists(atPath: example.path) {
            var sample = builtIn[1]
            sample.name = "Example"
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(sample).write(to: example)
        }
        NSWorkspace.shared.activateFileViewerSelecting([example])
    }

    // MARK: resolved values

    var nsAppearance: NSAppearance? {
        switch appearance {
        case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    var backgroundColor: NSColor { color(background) ?? .textBackgroundColor }
    var textColor: NSColor { color(text) ?? .textColor }
    var secondaryColor: NSColor { color(secondary) ?? .secondaryLabelColor }
    var tertiaryColor: NSColor { color(secondary)?.withAlphaComponent(0.55) ?? .tertiaryLabelColor }
    var accentColor: NSColor { color(accent) ?? .linkColor }
    var codeBackgroundColor: NSColor { color(codeBackground) ?? .quaternarySystemFill }
    var lineHeightMultiple: CGFloat { lineHeight ?? 1.3 }

    func bodyFont(size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size)
        switch font {
        case nil, "system": return system
        case "serif": return NSFont(descriptor: system.fontDescriptor.withDesign(.serif)!, size: size) ?? system
        case "rounded": return NSFont(descriptor: system.fontDescriptor.withDesign(.rounded)!, size: size) ?? system
        case let family?: return NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: size) ?? system
        }
    }

    func monoFont(size: CGFloat, bold: Bool) -> NSFont {
        let fallback = NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
        guard let monoFont else { return fallback }
        var descriptor = NSFontDescriptor(fontAttributes: [.family: monoFont])
        if bold { descriptor = descriptor.withSymbolicTraits(.bold) }
        return NSFont(descriptor: descriptor, size: size) ?? fallback
    }

    private func color(_ hex: String?) -> NSColor? {
        guard var hex, hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
