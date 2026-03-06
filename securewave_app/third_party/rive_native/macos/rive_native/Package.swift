// swift-tools-version: 5.9
import PackageDescription

// Version and checksum are auto-updated by native/build_xcframework.sh
let riveNativeVersion = "0.1.4+1"
let riveNativeVersionURLComponent = riveNativeVersion.replacingOccurrences(of: "+", with: "%2B")
let riveNativeChecksum = "662af49c6c11e864a2986b3c9cbf52c1adf2be6de2e4c1f4acc100dc00739794"

let package = Package(
    name: "rive_native",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "rive-native", targets: ["rive_native"])
    ],
    targets: [
        // Binary target for the pre-built Rive native libraries
        //
        // FOR LOCAL TESTING: Comment out the url/checksum version and uncomment the path version:
        // .binaryTarget(
        //     name: "RiveNative",
        //     path: "Frameworks/RiveNative_macos.xcframework"
        // ),
        // FOR RELEASE: Use url/checksum (auto-updated by build_xcframework.sh):
        .binaryTarget(
            name: "RiveNative",
            url: "https://rive-flutter-artifacts.rive.app/rive_native_versions/\(riveNativeVersionURLComponent)/RiveNative_macos.xcframework.zip",
            checksum: riveNativeChecksum
        ),
        // Plugin target that wraps the binary and provides Flutter integration
        .target(
            name: "rive_native",
            dependencies: ["RiveNative"],
            path: "Sources/rive_native",
            sources: ["rive_native_plugin.mm"],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
