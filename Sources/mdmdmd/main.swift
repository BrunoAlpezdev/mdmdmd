import AppKit
import Combine
import SwiftUI

/// AppKit owns the split so a divider double-click fits the sidebar to its
/// content. SwiftUI's NavigationSplitView expands it to the maximum instead.
final class SplitController: NSSplitViewController {
    var fittedWidth: () -> CGFloat = { 260 }
    private var positioned = false

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !positioned else { return }
        positioned = true
        splitView.setPosition(fittedWidth(), ofDividerAt: 0)
    }

    override func splitView(_ splitView: NSSplitView, shouldCollapseSubview subview: NSView, forDoubleClickOnDividerAt dividerIndex: Int) -> Bool {
        splitView.setPosition(fittedWidth(), ofDividerAt: dividerIndex)
        return false
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    // All items are system-provided; AppKit builds them when this returns nil.
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        nil
    }

    let workspace = Workspace()
    let prefs = Prefs()
    var panel: NSPanel!
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.titlebarAppearsTransparent = false
        panel.setFrameAutosaveName("main")
        let split = SplitController()
        split.fittedWidth = { [unowned self] in workspace.fittedSidebarWidth }
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: SidebarView().environmentObject(workspace)))
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 600
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: NSHostingController(rootView: DetailView().environmentObject(workspace).environmentObject(prefs))))
        panel.contentViewController = split
        panel.setContentSize(NSSize(width: 1100, height: 760))
        // Only takes effect once the item is installed in a live split view.
        sidebarItem.isCollapsed = prefs.teleprompter
        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        panel.toolbar = toolbar
        panel.toolbarStyle = .unified
        prefs.$teleprompter.dropFirst().sink { sidebarItem.animator().isCollapsed = $0 }.store(in: &bag)
        prefs.$themeName.sink { [unowned self] _ in panel.appearance = prefs.theme.nsAppearance }.store(in: &bag)
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        NSApp.mainMenu = buildMenu()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        prefs.$hiddenFromCapture.sink { [unowned self] hidden in panel.sharingType = hidden ? .none : .readOnly }.store(in: &bag)
        prefs.$opacity.sink { [unowned self] in panel.alphaValue = $0 }.store(in: &bag)
        prefs.$teleprompter.sink { [unowned self] in applyTeleprompter($0) }.store(in: &bag)
        workspace.$current.sink { [unowned self] url in
            panel.title = url?.lastPathComponent ?? "mdmdmd"
            panel.representedURL = url
        }.store(in: &bag)
    }

    /// Floats over everything (full-screen Chrome included), never steals
    /// focus from the app being recorded, and stays out of the recording.
    private func applyTeleprompter(_ on: Bool) {
        panel.level = on ? .floating : .normal
        panel.isFloatingPanel = on
        panel.becomesKeyOnlyIfNeeded = on
        panel.isMovableByWindowBackground = on
        panel.collectionBehavior = on ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
        if on { panel.styleMask.insert(.nonactivatingPanel) } else { panel.styleMask.remove(.nonactivatingPanel) }
        if on, prefs.opacity == 1 { prefs.opacity = 0.9 }
        if !on { prefs.opacity = 1 }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(workspace.open)
        // Opening a file is an explicit ask for this window, even when the app
        // was already running behind something else.
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    // MARK: actions

    @objc func openFolder(_ sender: Any?) {
        let dialog = NSOpenPanel()
        dialog.canChooseDirectories = true
        dialog.canChooseFiles = false
        if dialog.runModal() == .OK, let url = dialog.url { workspace.openFolder(url) }
    }

    @objc func openFile(_ sender: Any?) {
        let dialog = NSOpenPanel()
        dialog.allowedContentTypes = [.plainText, .init(filenameExtension: "md")!].compactMap { $0 }
        if dialog.runModal() == .OK, let url = dialog.url { workspace.openFile(url) }
    }

    @objc func save(_ sender: Any?) { workspace.save() }

    @objc func exportHTML(_ sender: Any?) {
        guard let url = savePanel(extension: "html") else { return }
        let rendered = Styler.rendered(workspace.text, baseSize: 16)
        do {
            let data = try rendered.data(from: NSRange(location: 0, length: rendered.length),
                                         documentAttributes: [.documentType: NSAttributedString.DocumentType.html,
                                                              .characterEncoding: String.Encoding.utf8.rawValue])
            try data.write(to: url)
        } catch { NSAlert(error: error).runModal() }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let url = savePanel(extension: "pdf") else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        info.topMargin = 56; info.bottomMargin = 56; info.leftMargin = 56; info.rightMargin = 56
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        view.textStorage?.setAttributedString(Styler.rendered(workspace.text, baseSize: 12))
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.sizeToFit()
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        view.frame.size.height = view.layoutManager?.usedRect(for: view.textContainer!).height ?? 10
        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.run()
    }

    private func savePanel(extension ext: String) -> URL? {
        let dialog = NSSavePanel()
        dialog.nameFieldStringValue = (workspace.current?.deletingPathExtension().lastPathComponent ?? "document") + "." + ext
        dialog.directoryURL = workspace.current?.deletingLastPathComponent()
        return dialog.runModal() == .OK ? dialog.url : nil
    }

    @objc func toggleTeleprompter(_ sender: Any?) { prefs.teleprompter.toggle() }
    @objc func setTheme(_ sender: NSMenuItem) { prefs.themeName = sender.representedObject as! String }
    @objc func openThemesFolder(_ sender: Any?) { Theme.revealFolder() }
    @objc func reloadThemes(_ sender: Any?) { rebuildThemeMenu(); prefs.themeName = prefs.themeName }
    @objc func toggleCapture(_ sender: Any?) { prefs.hiddenFromCapture.toggle() }
    @objc func zoomIn(_ sender: Any?) { prefs.baseSize = min(prefs.baseSize + 2, 48) }
    @objc func zoomOut(_ sender: Any?) { prefs.baseSize = max(prefs.baseSize - 2, 10) }
    @objc func zoomReset(_ sender: Any?) { prefs.baseSize = 16 }
    @objc func setOpacity(_ sender: NSMenuItem) { prefs.opacity = CGFloat(sender.tag) / 100 }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleTeleprompter): item.state = prefs.teleprompter ? .on : .off
        case #selector(toggleCapture): item.state = prefs.hiddenFromCapture ? .off : .on
        case #selector(setTheme): item.state = (item.representedObject as? String) == prefs.themeName ? .on : .off
        case #selector(setOpacity): item.state = Int(prefs.opacity * 100) == item.tag ? .on : .off
        case #selector(save): return workspace.dirty
        case #selector(exportHTML), #selector(exportPDF): return workspace.current != nil
        default: break
        }
        return true
    }

    // MARK: menu

    private func buildMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About mdmdmd", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide mdmdmd", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit mdmdmd", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app, title: "mdmdmd"))

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Open…", action: #selector(openFile), keyEquivalent: "o")
        file.addItem(item("Open Folder…", #selector(openFolder), "o", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(withTitle: "Save", action: #selector(save), keyEquivalent: "s")
        file.addItem(.separator())
        file.addItem(withTitle: "Export as HTML…", action: #selector(exportHTML), keyEquivalent: "")
        file.addItem(withTitle: "Export as PDF…", action: #selector(exportPDF), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(file, title: "File"))

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = NSMenuItem(title: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        edit.addItem(find)
        main.addItem(submenu(edit, title: "Edit"))

        let view = NSMenu(title: "View")
        view.addItem(item("Teleprompter Mode", #selector(toggleTeleprompter), "t", [.command, .shift]))
        view.addItem(withTitle: "Visible in Screen Capture", action: #selector(toggleCapture), keyEquivalent: "")
        view.addItem(item("Toggle Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]))
        view.addItem(.separator())
        view.addItem(submenu(themeMenu, title: "Theme"))
        rebuildThemeMenu()
        view.addItem(.separator())
        view.addItem(withTitle: "Zoom In", action: #selector(zoomIn), keyEquivalent: "+")
        view.addItem(withTitle: "Zoom Out", action: #selector(zoomOut), keyEquivalent: "-")
        view.addItem(withTitle: "Actual Size", action: #selector(zoomReset), keyEquivalent: "0")
        view.addItem(.separator())
        let opacity = NSMenu(title: "Opacity")
        for pct in [100, 90, 75, 60] {
            let entry = NSMenuItem(title: "\(pct)%", action: #selector(setOpacity), keyEquivalent: "")
            entry.tag = pct
            opacity.addItem(entry)
        }
        view.addItem(submenu(opacity, title: "Opacity"))
        main.addItem(submenu(view, title: "View"))

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        main.addItem(submenu(window, title: "Window"))
        NSApp.windowsMenu = window
        return main
    }

    private let themeMenu = NSMenu(title: "Theme")

    /// Built-in themes, then the JSON files in the themes folder.
    private func rebuildThemeMenu() {
        themeMenu.removeAllItems()
        for (index, theme) in Theme.all.enumerated() {
            if index == Theme.builtIn.count { themeMenu.addItem(.separator()) }
            let entry = NSMenuItem(title: theme.name, action: #selector(setTheme), keyEquivalent: "")
            entry.representedObject = theme.name
            themeMenu.addItem(entry)
        }
        themeMenu.addItem(.separator())
        themeMenu.addItem(withTitle: "Open Themes Folder…", action: #selector(openThemesFolder), keyEquivalent: "")
        themeMenu.addItem(withTitle: "Reload Themes", action: #selector(reloadThemes), keyEquivalent: "")
    }

    private func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.keyEquivalentModifierMask = mods
        return entry
    }

    private func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = menu
        return entry
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
