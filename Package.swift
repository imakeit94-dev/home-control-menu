// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AirControl",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "AirControl")],
    swiftLanguageModes: [.v5]
)
