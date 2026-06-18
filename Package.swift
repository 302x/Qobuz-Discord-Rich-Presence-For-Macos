// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QobuzDiscordPresence",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QobuzDiscordPresence", targets: ["QobuzDiscordPresence"])
    ],
    targets: [
        .executableTarget(
            name: "QobuzDiscordPresence",
            path: "Sources/QobuzDiscordPresence"
        )
    ]
)
