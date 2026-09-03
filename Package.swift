// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GoveeKettle",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "GoveeKettle",
            path: "Sources/GoveeKettle"
        ),
        .testTarget(
            name: "GoveeKettleTests",
            dependencies: ["GoveeKettle"],
            path: "Tests/GoveeKettleTests"
        ),
    ]
)
