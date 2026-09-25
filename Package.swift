// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ThreadSafeKit",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ThreadSafeKit",
            targets: ["ThreadSafeKit"]
        ),
    ],
    targets: [
        .target(
            name: "ThreadSafeKit"
        ),
        .testTarget(
            name: "ThreadSafeKitTests",
            dependencies: ["ThreadSafeKit"]
        ),
        // Release-mode benchmarks; not a product, so dependents never build it.
        .executableTarget(
            name: "ThreadSafeKitBenchmarks",
            dependencies: ["ThreadSafeKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
