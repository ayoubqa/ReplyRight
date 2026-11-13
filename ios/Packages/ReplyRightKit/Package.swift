// swift-tools-version: 5.9
import PackageDescription

// ReplyRightKit holds everything shared by the app, the keyboard extension and
// the share extension.
//
//   ReplyRightCore  Foundation-only: models, API client, App Group storage,
//                   keyboard layout and typing logic, design tokens.
//   ReplyRightUI    SwiftUI design system (theme, typography, components)
//                   and the bundled display typeface.
//
// Core has no UI dependencies, so its tests run with `swift test` on a Mac
// as well as from Xcode.
let package = Package(
    name: "ReplyRightKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReplyRightCore", targets: ["ReplyRightCore"]),
        .library(name: "ReplyRightUI", targets: ["ReplyRightUI"]),
    ],
    targets: [
        .target(name: "ReplyRightCore"),
        .target(
            name: "ReplyRightUI",
            dependencies: ["ReplyRightCore"],
            // The display typeface (Young Serif, SIL Open Font License) and its licence.
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ReplyRightCoreTests", dependencies: ["ReplyRightCore"]),
    ]
)
