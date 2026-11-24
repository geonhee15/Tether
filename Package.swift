// swift-tools-version:5.9
// Editor/indexing support only — the app bundle is produced by ./build.sh (swiftc, no Xcode needed).
import PackageDescription

let package = Package(
    name: "Tether",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Tether", path: "Sources/Tether")
    ]
)
