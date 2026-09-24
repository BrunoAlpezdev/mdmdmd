# mdmdmd

A native, open source alternative to Typora for macOS.
One window, your Markdown rendered in place as you type, no Electron, no subscription.

It was built to read a script while recording a screen video, so it has one trick Typora does not: the window is invisible to screen capture.
Float it over whatever you are recording and it never shows up in the video.

## Install

Requires macOS 14 and Xcode 26 (Swift 6.3).

```sh
git clone https://github.com/BrunoAlpezdev/mdmdmd
cd mdmdmd
./build.sh          # builds mdmdmd.app, signs it and copies it into /Applications
```

`build.sh` signs with the first Apple Development certificate it finds, or ad hoc when there is none.
Both work for a personal machine.

## Features

- Typora-style live rendering over the raw Markdown.
  Syntax markers collapse everywhere except the paragraph under the caret, so the source is always one keystroke away.
- Sidebar with the folder tree (`.md`, `.markdown`, `.txt`), skipping `node_modules`, `.build`, `dist` and friends.
  Double-click the divider to fit the sidebar to its widest visible row.
- Autosave one second after the last edit, and reload when the file changes on disk.
- A status bar with spoken words and the minutes they take at 150 wpm.
  It counts paragraphs only, not headings, code, tables or lines that are just a file name in backticks.
- Export as HTML or PDF from the rendered document.
- Hidden from screen capture by default (`NSWindow.sharingType = .none`).
  View > Visible in Screen Capture turns it off.
- Teleprompter mode (⇧⌘T): floats above everything including full-screen apps, never steals focus from the app being recorded, hides the sidebar, bumps the type 40% and drops opacity to 90%.
- Lists continue on Enter; an empty item ends the list.
- Themes, under View > Theme.
  Five ship with the app: System, Paper, Night, Graphite and Prompter.

## Themes

A theme is a JSON file in `~/Library/Application Support/mdmdmd/Themes/`.
View > Theme > Open Themes Folder creates the folder with an example to copy from.
Every field is optional; whatever is missing falls back to the system look.

```json
{
  "name": "Paper",
  "appearance": "light",
  "background": "#F6F1E7",
  "text": "#2A2622",
  "secondary": "#9A9082",
  "accent": "#B5562D",
  "codeBackground": "#EDE5D5",
  "font": "serif",
  "monoFont": "JetBrains Mono",
  "lineHeight": 1.45
}
```

`appearance` is `light` or `dark` and drives the window chrome.
`secondary` colors syntax markers, list bullets and blockquotes; `accent` colors links.
`font` is `system`, `serif` (New York), `rounded` (SF Rounded) or any installed family name.
`lineHeight` is a multiple of the font's natural line height.

## Development

```sh
swift build
swift test
swift run            # runs without the bundle; menus and window work, the Dock icon does not
```

Layout:

- `Sources/mdmdmd/Styler.swift`: parses with [swift-markdown](https://github.com/swiftlang/swift-markdown) and lays attributes over the source text.
  The same pass produces the rendered document for export by deleting the marker ranges.
- `Sources/mdmdmd/Editor.swift`: the `NSTextView` subclass and its SwiftUI wrapper.
- `Sources/mdmdmd/Workspace.swift`: the open folder, the file tree, autosave and the on-disk watcher.
- `Sources/mdmdmd/main.swift`: the AppKit shell: panel, split view, menus, teleprompter and export.
- `Icon/make-icon.swift`: draws the app icon at build time, so no binaries live in the repo.

Things that bit once:

- `NavigationSplitView` expands the sidebar to its maximum on a divider double-click and has no hook to change it, so the split is an `NSSplitViewController`.
- To check that the capture exclusion holds, capture the window by id: `screencapture -l<id>` must fail with "could not create image from window".
- swift-markdown reports columns as UTF-8 byte offsets from the start of the line; `LineMap` converts them to UTF-16 for `NSRange`.

## License

MIT.
