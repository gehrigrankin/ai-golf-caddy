// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AICaddy",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AICaddy", targets: ["AICaddy"]),
    ],
    targets: [
        .target(name: "AICaddy"),
    ]
)
