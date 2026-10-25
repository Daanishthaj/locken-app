// swift-tools-version: 6.2
// Vendored from https://github.com/Jud/kokoro-coreml at v0.11.2 (commit 6bfc02afb237a311caee927482e58c028edb6acb),
// Apache-2.0 (see LICENSE). Locken's changes: library target only (no CLI or tests), swift-bart-g2p pinned
// exactly, and MLArrayHelpers reads float16 output without the Float16 type on Intel Macs. See UPSTREAM.md.
import PackageDescription

let package = Package(
    name: "KokoroCoreML",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "KokoroCoreML", targets: ["KokoroCoreML"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Jud/swift-bart-g2p.git", exact: "0.4.0"),
    ],
    targets: [
        .target(
            name: "KokoroCoreML",
            dependencies: [
                .product(name: "BARTG2P", package: "swift-bart-g2p")
            ],
            path: "Sources/KokoroCoreML",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
