// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AICaddy",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AICaddy", targets: ["AICaddy"]),
    ],
    targets: [
        .target(
            name: "AICaddy",
            path: "AICaddy",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "AICaddyTests",
            dependencies: ["AICaddy"],
            path: "Tests/AICaddyTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
