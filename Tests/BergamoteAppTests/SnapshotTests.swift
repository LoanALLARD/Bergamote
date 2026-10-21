import AppKit
import BergamoteKit
import PDFKit
import SwiftUI
import Testing
@testable import Bergamote

/// Rend les écrans principaux dans des fenêtres hors écran et les enregistre en PNG.
///
///     swift scripts/make-samples.swift SampleDocs
///     BERGAMOTE_SAMPLES_DIR=SampleDocs BERGAMOTE_SNAPSHOT_DIR=build/snapshots swift test --filter Snapshot
///
/// Rien ne s'affiche à l'écran : les fenêtres ne sont jamais mises au premier plan.
@MainActor
@Suite("Rendu de l'interface", .serialized, .enabled(if: ProcessInfo.processInfo.environment["BERGAMOTE_SAMPLES_DIR"] != nil))
struct SnapshotTests {
    let samples = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BERGAMOTE_SAMPLES_DIR"] ?? ".")
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BERGAMOTE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory() + "bergamote-snapshots")

    @Test func renderMainScreens() async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bergamote-ui-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        // Vrai moteur, embeddings de macOS, documents d'essai indexés jusqu'au bout.
        let engine = try await BergamoteEngine.bootstrap(root: root, bundledModels: nil)
        let report = try await engine.importItems([samples])
        #expect(report.failures.isEmpty && report.unsupported.isEmpty)
        try await engine.runner.drain()

        let model = AppModel()
        model.attach(engine)
        try await waitUntil { model.documents.count == report.added.count && model.documents.allSatisfy { $0.status == .ready } }
        let window = CGSize(width: 1280, height: 800)

        model.selectedDocumentID = model.documents.first { $0.title.hasPrefix("facture") }?.id
        try await snapshot(LibraryView().environment(model), size: window, name: "1-bibliotheque")

        model.query = "loyer et charges de l'appartement"
        model.scheduleSearch()
        try await waitUntil { !model.results.isEmpty }
        try await snapshot(LibraryView().environment(model), size: window, name: "2-resultats")

        // Résultat issu du scan (pas de couche texte) : cadre autour de la zone reconnue par l'OCR.
        let scanHit = try #require(model.results.first { $0.title.hasPrefix("scan") })
        model.open(scanHit)
        try await snapshot(LibraryView().environment(model), size: window, name: "3-surlignage-scan") { root in
            try checkHighlight(in: root, page: scanHit.page, expecting: "Square", name: "3b-page-scan")
        }

        // Résultat issu d'un PDF texte : les mots de la requête sont surlignés.
        model.query = "facture d'électricité de février"
        model.scheduleSearch()
        try await waitUntil { model.results.first?.title.hasPrefix("facture") == true }
        let invoiceHit = try #require(model.results.first)
        model.open(invoiceHit)
        try await snapshot(LibraryView().environment(model), size: window, name: "4-surlignage-pdf") { root in
            try checkHighlight(in: root, page: invoiceHit.page, expecting: "Highlight", name: "4b-page-facture")
        }

        try await snapshot(CommandPalette(initialQuery: "assurance habitation").environment(model), size: CGSize(width: 640, height: 420), name: "5-palette")
        try await snapshot(DropZoneView().environment(model), size: CGSize(width: 320, height: 300), name: "6-barre-des-menus")
    }

    private func waitUntil(timeout: Duration = .seconds(15), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition(), "condition non atteinte avant l'échéance")
    }

    /// PDFView ne se dessine pas dans un rendu hors écran : on vérifie l'annotation de surlignage
    /// dans le document affiché, et on rend la page seule (annotations comprises) en PNG.
    private func checkHighlight(in root: NSView, page: Int?, expecting kind: String, name: String) throws {
        let pdfView = try #require(Self.firstSubview(of: PDFView.self, in: root), "aucun PDFView affiché")
        let pdfPage = try #require(pdfView.document?.page(at: (page ?? 1) - 1))
        let marks = pdfPage.annotations.filter { $0.type == kind }
        #expect(!marks.isEmpty, "annotation « \(kind) » attendue, trouvé : \(pdfPage.annotations.compactMap(\.type))")
        #expect(pdfView.currentPage == pdfPage, "la vue doit être positionnée sur la page du passage")

        let image = pdfPage.thumbnail(of: NSSize(width: 595, height: 842), for: .mediaBox)
        let png = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
    }

    private static func firstSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = firstSubview(of: type, in: subview) { return match }
        }
        return nil
    }

    private func snapshot(_ view: some View, size: CGSize, name: String, inspect: (NSView) throws -> Void = { _ in }) async throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view)
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.contentView = hosting
        window.setContentSize(size)

        // Laisse SwiftUI exécuter les .task (chargement du PDF, entités) et dessiner.
        for _ in 0..<30 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }

        let frameView = hosting.superview ?? hosting  // inclut la barre de titre et d'outils
        let bounds = frameView.bounds
        let representation = try #require(frameView.bitmapImageRepForCachingDisplay(in: bounds))
        frameView.cacheDisplay(in: bounds, to: representation)
        let png = try #require(representation.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
        try inspect(hosting)
        window.close()
    }
}
