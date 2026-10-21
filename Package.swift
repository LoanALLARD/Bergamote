// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bergamote",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Bergamote", targets: ["Bergamote"]),
        .library(name: "BergamoteKit", targets: ["BergamoteKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
    ],
    targets: [
        // sqlite-vec compilé dans le binaire, contre le SQLite du système (voir vendor/README.md).
        .target(
            name: "CSQLiteVec",
            exclude: ["vendor"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // Tout le métier : index, file de jobs, extraction, NLP, recherche. Sans UI, donc testable.
        .target(
            name: "BergamoteKit",
            dependencies: [
                "CSQLiteVec",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        // L'app SwiftUI : bibliothèque, aperçu PDF, palette ⌘K, zone de dépôt dans la barre des menus.
        .executableTarget(
            name: "Bergamote",
            dependencies: [
                "BergamoteKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "BergamoteKitTests",
            dependencies: ["BergamoteKit"]
        ),
        // Rendu hors écran des vues SwiftUI (activé par BERGAMOTE_SAMPLES_DIR, voir README).
        .testTarget(
            name: "BergamoteAppTests",
            dependencies: ["Bergamote", "BergamoteKit"]
        ),
    ]
)
