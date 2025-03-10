// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "ProductivityAssistant",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "ProductivityAssistant",
            targets: ["ProductivityAssistant"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.15.0"),
        // Other dependencies will be added as needed
    ],
    targets: [
        .executableTarget(
            name: "ProductivityAssistant",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "ProductivityAssistantTests",
            dependencies: ["ProductivityAssistant"],
            path: "Tests"
        )
    ]
) 