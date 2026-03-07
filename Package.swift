// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "InstantExplain",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "InstantExplain",
            path: "Sources/InstantExplain",
            resources: [
                .copy("../../Resources/default-prompt.md")
            ]
        )
    ]
)
