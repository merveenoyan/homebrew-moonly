// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "moonly",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // In-process llama.cpp via pcuenca's LlamaKit (Hub trait enabled by
        // default, which pulls in swift-huggingface for model downloads).
        .package(url: "https://github.com/pcuenca/LlamaKit", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "moonly",
            dependencies: [
                .product(name: "LlamaKit", package: "LlamaKit"),
            ],
            path: "Sources/moonly",
            // LlamaKit requires the 6.1 toolchain (package traits), but the app
            // code targets the Swift 5 language mode; opting in to Swift 6's
            // strict concurrency is out of scope for this migration.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
