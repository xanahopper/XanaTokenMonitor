// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "XanaTokenMonitor",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "XanaTokenMonitorKit",
            targets: ["XanaTokenMonitorKit"]
        ),
    ],
    targets: [
        .target(
            name: "XanaTokenMonitorKit",
            path: "Sources/XanaTokenMonitorKit"
        ),
        .testTarget(
            name: "XanaTokenMonitorKitTests",
            dependencies: ["XanaTokenMonitorKit"],
            path: "Tests/XanaTokenMonitorKitTests"
        ),
    ]
)