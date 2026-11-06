import AppKit
import BergamoteKit
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Bergamote

/// Rend le camembert et le panneau de la barre des menus dans des fenêtres hors écran, et les
/// enregistre en PNG (images du README).
///
///     BERGAMOTE_SNAPSHOT_DIR=build/snapshots swift test --filter Snapshot
///
/// Rien ne s'affiche à l'écran : les fenêtres ne sont jamais mises au premier plan.
@MainActor
@Suite("Rendu de l'interface", .serialized, .enabled(if: ProcessInfo.processInfo.environment["BERGAMOTE_SNAPSHOT_DIR"] != nil))
struct SnapshotTests {
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BERGAMOTE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory() + "bergamote-snapshots")

    @Test func renderWheelsAndMenuBarPanel() async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let files = try sampleFiles()
        let images = files.filter { $0.pathExtension == "png" }
        let pdfs = files.filter { $0.pathExtension == "pdf" }
        let size = CGSize(width: RadialMenuView.size, height: RadialMenuView.size)

        let conversion = RadialMenuModel()
        let imageActions = FileActionCatalog.actions(for: .conversion, inputs: images.map { _ in .png })
        conversion.configure(kind: .conversion, files: images, actions: imageActions)
        conversion.highlighted = 1
        try await snapshot(RadialMenuView(model: conversion) { _, _ in }, size: size, name: "wheel-convert", borderless: true)

        let tools = RadialMenuModel()
        tools.configure(kind: .tools, files: pdfs, actions: FileActionCatalog.actions(for: .tools, inputs: pdfs.map { _ in .pdf }))
        tools.highlighted = 2
        try await snapshot(RadialMenuView(model: tools) { _, _ in }, size: size, name: "wheel-tools", borderless: true)

        tools.highlighted = nil
        tools.status = .done(FileConverter.summary(ofCreated: pdfs.count))
        try await snapshot(RadialMenuView(model: tools) { _, _ in }, size: size, name: "wheel-done", borderless: true)

        tools.lastResult = FileConverter.summary(ofCreated: 1)
        // Fond explicite : dans la barre des menus, macOS le fournit ; dans une capture, il serait transparent.
        let panel = MenuBarPanel(model: tools).background(Color(nsColor: .windowBackgroundColor))
        try await snapshot(panel, size: CGSize(width: 320, height: 250), name: "menu-bar-panel", borderless: true)

        // La part touchée par un point correspond bien à celle dessinée.
        let center = RadialMenuView.size / 2
        let radius = (RadialMenuView.innerRadius + RadialMenuView.outerRadius) / 2
        for index in imageActions.indices {
            let offset = RadialMenuView.labelOffset(index: index, count: imageActions.count)
            let point = CGPoint(x: center + offset.width * radius / (radius + 4), y: center + offset.height * radius / (radius + 4))
            #expect(RadialMenuView.slice(at: point, count: imageActions.count) == index)
        }
    }

    /// Trois PNG et quatre PDF d'une page, pour des résumés réalistes au centre du camembert.
    private func sampleFiles() throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bergamote-snapshot-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [URL] = []
        for index in 1...3 {
            let url = folder.appendingPathComponent("photo-\(index).png")
            let context = CGContext(
                data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            #expect(CGImageDestinationFinalize(destination))
            files.append(url)
        }
        for index in 1...4 {
            let url = folder.appendingPathComponent("document-\(index).pdf")
            var box = CGRect(x: 0, y: 0, width: 595, height: 842)
            let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
            context.beginPDFPage(nil)
            context.endPDFPage()
            context.closePDF()
            files.append(url)
        }
        return files
    }

    private func snapshot(_ view: some View, size: CGSize, name: String, borderless: Bool = false) async throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: borderless ? [.borderless] : [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if borderless {
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.setContentSize(size)

        // Laisse SwiftUI exécuter les .task et dessiner.
        for _ in 0..<20 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }

        let frameView = hosting.superview ?? hosting
        let bounds = frameView.bounds
        let representation = try #require(frameView.bitmapImageRepForCachingDisplay(in: bounds))
        frameView.cacheDisplay(in: bounds, to: representation)
        let png = try #require(representation.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
        window.close()
    }
}
