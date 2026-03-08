// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "wutmean",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "wutmean",
            path: "Sources/wutmean",
            resources: [
                .copy("../../Resources/default-prompt.md")
            ]
        )
    ]
)
