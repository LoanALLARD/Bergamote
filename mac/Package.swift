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
        // Le cœur : geste du camembert, catalogue d'actions, conversions. Sans UI, donc testable.
        .target(name: "BergamoteKit"),
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
