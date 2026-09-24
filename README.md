# mdmdmd

A native macOS Markdown editor in the Typora style, built for reading Loom scripts while recording.
The window is excluded from screen capture, so it can float over the PR being recorded without showing up in the video.

## Build

```sh
./build.sh          # swift build -c release, bundles mdmdmd.app, signs it, installs to /Applications
swift test          # styler tests
open -a /Applications/mdmdmd.app ~/Downloads/ENG-1234-loom-script.md
```

## What it does

- Live Typora-style rendering over the raw Markdown: syntax markers collapse everywhere except the paragraph under the caret.
- Sidebar with the folder tree (`.md`, `.markdown`, `.txt`), skipping `node_modules`, `.build`, `dist` and friends.
- Autosave one second after the last edit, and reload when the file changes on disk (Claude rewrites scripts in place).
- Status bar with spoken words and minutes at 150 wpm, counting only paragraphs (not headings, code, tables or file-name cue lines).
- Export as HTML or PDF from the rendered document.
- Hidden from screen capture by default (`NSWindow.sharingType = .none`). View > Visible in Screen Capture turns it off.
- Teleprompter mode (⇧⌘T): floats above everything including full-screen apps, never steals focus from the app being recorded, hides the sidebar, bumps the type 40% and drops opacity to 90%.

## Gotchas

- `NavigationSplitView` needs `NSHostingController` as the panel's content view controller. With a bare `NSHostingView` the sidebar starts collapsed.
- To verify the capture exclusion, capture the window by id: `screencapture -l<id>` must fail with "could not create image from window".
- swift-markdown reports columns as UTF-8 byte offsets from the line start; `LineMap` converts them to UTF-16 for `NSRange`.
