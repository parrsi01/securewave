// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WireGuardKit",
    platforms: [
        .macOS(.v10_14),
        .iOS(.v12)
    ],
    products: [
        .library(name: "WireGuardKit", targets: ["WireGuardKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WireGuardKit",
            dependencies: ["WireGuardKitGo", "WireGuardKitC"],
            swiftSettings: [
                .unsafeFlags([
                    "-Xcc", "-IThirdParty/wireguard-apple/Sources/WireGuardKitC/include",
                    "-Xcc", "-IThirdParty/wireguard-apple/Sources/WireGuardKitGo/include"
                ])
            ]
        ),
        .target(
            name: "WireGuardKitC",
            dependencies: [],
            publicHeadersPath: "include"
        ),
        .target(
            name: "WireGuardKitGo",
            dependencies: [],
            exclude: [
                "goruntime-boottime-over-monotonic.diff",
                "go.mod",
                "go.sum",
                "api-apple.go",
                "Makefile"
            ],
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("wg-go")]
        )
    ]
)
