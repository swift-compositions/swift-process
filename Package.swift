// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-process",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "Process", targets: ["Process"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-atoms/swift-path.git",
            branch: "main"
        ),
        .package(url: "https://github.com/swift-compositions/swift-kernel.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-posix.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-windows.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-strings.git", branch: "main"),
        .package(url: "https://github.com/swift-iso/swift-iso-9945.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Process",
            dependencies: [
                .product(name: "Kernel", package: "swift-kernel"),
                .product(name: "Path", package: "swift-path"),
                .product(
                    name: "POSIX Kernel",
                    package: "swift-posix",
                    condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux])
                ),

                .product(
                    name: "ISO 9945 Kernel Poll",
                    package: "swift-iso-9945",
                    condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux])
                ),
                .product(
                    name: "Windows Kernel Process",
                    package: "swift-windows",
                    condition: .when(platforms: [.windows])
                ),
                .product(
                    name: "Windows Kernel File",
                    package: "swift-windows",
                    condition: .when(platforms: [.windows])
                ),
                .product(
                    name: "Windows Kernel Thread",
                    package: "swift-windows",
                    condition: .when(platforms: [.windows])
                ),
                .product(name: "Strings", package: "swift-strings"),
            ],
            path: "Sources/Process"
        ),
        .testTarget(
            name: "Process Tests",
            dependencies: [
                "Process",
                .product(name: "ISO 9945 Core", package: "swift-iso-9945",
                    condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux])),
                .product(name: "ISO 9945 Kernel Process", package: "swift-iso-9945",
                    condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux])),
                .product(name: "POSIX Kernel", package: "swift-posix",
                    condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux])),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
