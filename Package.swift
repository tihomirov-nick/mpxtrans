// swift-tools-version:5.10
import PackageDescription
import Foundation

// Absolute path to the package root: the prebuilt whisper.cpp static library lives in Vendor/.
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "Slovo",
    platforms: [.macOS("13.3")],
    products: [
        .executable(name: "Slovo", targets: ["Slovo"]),
        .executable(name: "slovo-cli", targets: ["SlovoCLI"]),
    ],
    targets: [
        // whisper.cpp (built by scripts/build_whisper.sh as a universal static library)
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            linkerSettings: [
                .unsafeFlags(["-L\(packageRoot)/Vendor/whisper/lib"]),
                .linkedLibrary("whisper_all"),
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Foundation"),
            ]
        ),
        // Audio extraction (ffmpeg), speech recognition, transcript formats, model catalog (no UI)
        .target(
            name: "TransCore",
            dependencies: ["CWhisper"],
            path: "Sources/TransCore"
        ),
        // SwiftUI application
        .executableTarget(
            name: "Slovo",
            dependencies: ["TransCore"],
            path: "Sources/Slovo"
        ),
        // Command line tool for testing recognition without the UI
        .executableTarget(
            name: "SlovoCLI",
            dependencies: ["TransCore"],
            path: "Sources/SlovoCLI"
        ),
    ]
)
