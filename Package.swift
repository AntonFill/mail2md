// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mail2md",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        // Reads the command line the way getopt does. A copy of realdate's module, kept
        // identical to it; it moves into a package of its own once a third tool uses it.
        .target(
            name: "CommandLineOptions"
        ),
        .executableTarget(
            name: "mail2md",
            dependencies: [
                "CommandLineOptions",
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .testTarget(
            name: "CommandLineOptionsTests",
            dependencies: [
                "CommandLineOptions"
            ]
        ),
        .testTarget(
            name: "mail2mdTests",
            dependencies: [
                "mail2md"
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
