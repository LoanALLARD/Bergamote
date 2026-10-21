import AppKit
import BergamoteKit
import PDFKit
import SwiftUI

/// PDFView qui montre le passage trouvé :
/// - les mots de la requête sont surlignés ligne par ligne dans la zone du passage ;
/// - sans couche texte (scan) ou sans mot commun (résultat « par sens »), un cadre translucide
///   entoure le passage ;
/// - à défaut de position connue, on cherche le début du passage dans le texte.
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let highlight: AppModel.Highlight?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
            context.coordinator.marks = []
            context.coordinator.applied = nil
        }
        context.coordinator.apply(highlight, in: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var marks: [(page: PDFPage, annotation: PDFAnnotation)] = []
        var applied: AppModel.Highlight?

        func apply(_ highlight: AppModel.Highlight?, in view: PDFView) {
            guard highlight != applied else { return }
            applied = highlight
            for mark in marks { mark.page.removeAnnotation(mark.annotation) }
            marks = []
            view.clearSelection()
            guard let highlight, let document = view.document else { return }
            let page = highlight.page.flatMap { document.page(at: $0 - 1) }

            if let page {
                let box = page.bounds(for: .mediaBox)
                // Marge : la zone du passage vient de l'union des lignes, les mots peuvent déborder un peu.
                let area = highlight.bbox.map { $0.denormalized(in: box).insetBy(dx: -6, dy: -6) }
                let lines = termLines(highlight.terms, on: page, in: document, within: area)
                if !lines.isEmpty {
                    for rect in lines { add(.highlight, rect: rect, color: NSColor.systemYellow.withAlphaComponent(0.45), on: page) }
                    view.go(to: lines[0].insetBy(dx: 0, dy: -80), on: page)
                    return
                }
                if let area {
                    add(.square, rect: area.insetBy(dx: -2, dy: -2), color: NSColor.systemYellow.withAlphaComponent(0.18), on: page)
                    view.go(to: area, on: page)
                    return
                }
            }

            let probe = highlight.text
                .trimmingCharacters(in: CharacterSet(charactersIn: "… "))
                .split(separator: " ").prefix(6).joined(separator: " ")
            if let selection = document.findString(probe, withOptions: [.caseInsensitive, .diacriticInsensitive]).first {
                view.setCurrentSelection(selection, animate: true)
                view.go(to: selection)
            } else if let page {
                view.go(to: page)
            }
        }

        /// Rectangles (une par ligne) des occurrences des termes sur la page, limités à la zone du passage.
        private func termLines(_ terms: [String], on page: PDFPage, in document: PDFDocument, within area: CGRect?) -> [CGRect] {
            var rects: [CGRect] = []
            for term in terms {
                for selection in document.findString(term, withOptions: [.caseInsensitive, .diacriticInsensitive]) where selection.pages.contains(page) {
                    for line in selection.selectionsByLine() {
                        let rect = line.bounds(for: page)
                        if area.map({ $0.intersects(rect) }) ?? true { rects.append(rect) }
                    }
                }
            }
            return rects.sorted { $0.maxY > $1.maxY }  // de haut en bas
        }

        private func add(_ subtype: PDFAnnotationSubtype, rect: CGRect, color: NSColor, on page: PDFPage) {
            let annotation = PDFAnnotation(bounds: rect, forType: subtype, withProperties: nil)
            if subtype == .square {
                annotation.interiorColor = color
                annotation.color = NSColor.systemYellow.withAlphaComponent(0.6)
                let border = PDFBorder()
                border.lineWidth = 1
                annotation.border = border
            } else {
                annotation.color = color
            }
            page.addAnnotation(annotation)
            marks.append((page, annotation))
        }
    }
}
