// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mdmdmd",
    platforms: [.macOS(.v14)],
    dependencies: [
        // cmark-gfm with source ranges per node; the styler needs the ranges.
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "mdmdmd",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            path: "Sources/mdmdmd"
        ),
        .testTarget(
            name: "mdmdmdTests",
            dependencies: ["mdmdmd"],
            path: "Tests/mdmdmdTests"
        ),
    ]
)
