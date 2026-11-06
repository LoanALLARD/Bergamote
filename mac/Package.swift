// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bergamote",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Bergamote", targets: ["Bergamote"]),
        .library(name: "BergamoteKit", targets: ["BergamoteKit"]),
    ],
    targets: [
        // Le cœur Rust partagé avec l'app Windows (../core), compilé par scripts/build-core.sh.
        .binaryTarget(name: "BergamoteCoreFFI", path: "Frameworks/BergamoteCoreFFI.xcframework"),
        // Adaptation Swift du cœur, plus les conversions natives (ImageIO, PDFKit, Vision…).
        .target(name: "BergamoteKit", dependencies: ["BergamoteCoreFFI"]),
        // L'app de barre des menus : surveillance du geste, panneau du camembert, réglages.
        .executableTarget(
            name: "Bergamote",
            dependencies: ["BergamoteKit"]
        ),
        .testTarget(
            name: "BergamoteKitTests",
            dependencies: ["BergamoteKit"]
        ),
        // Rendu hors écran du camembert (activé par BERGAMOTE_SNAPSHOT_DIR, voir README).
        .testTarget(
            name: "BergamoteAppTests",
            dependencies: ["Bergamote", "BergamoteKit"]
        ),
    ]
)
