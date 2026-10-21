import AppKit
import BergamoteKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentDetailView: View {
    @Environment(AppModel.self) private var model
    let document: Document

    var body: some View {
        HSplitView {
            DocumentPreview(document: document)
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            DocumentInspector(document: document)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
        }
        .navigationTitle(document.title)
    }
}

/// Aperçu : PDFKit pour les PDF et les images (une image devient une page PDF, ce qui permet
/// de surligner les rectangles de l'OCR), texte extrait pour les autres formats.
struct DocumentPreview: View {
    @Environment(AppModel.self) private var model
    let document: Document
    @State private var pdf: PDFDocument?
    @State private var extractedText = ""

    var body: some View {
        Group {
            if let pdf {
                PDFKitView(document: pdf, highlight: model.highlight?.documentID == document.id ? model.highlight : nil)
            } else {
                ScrollView {
                    Text(extractedText.isEmpty ? "Aperçu indisponible." : extractedText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .task(id: "\(document.id ?? -1)-\(document.status.rawValue)") { await load() }
    }

    private func load() async {
        guard let url = model.fileURL(of: document) else { return }
        let type = UTType(document.contentType)
        if type?.conforms(to: .pdf) == true {
            pdf = PDFDocument(url: url)
        } else if type?.conforms(to: .image) == true, let image = NSImage(contentsOf: url), let page = PDFPage(image: image) {
            let wrapper = PDFDocument()
            wrapper.insert(page, at: 0)
            pdf = wrapper
        } else {
            pdf = nil
            let chunks = (try? await model.engine?.chunks(of: document.id ?? -1)) ?? []
            extractedText = chunks.map(\.content).joined(separator: "\n\n")
        }
    }
}

struct DocumentInspector: View {
    @Environment(AppModel.self) private var model
    let document: Document
    @State private var entities: [EntityRecord] = []

    var body: some View {
        Form {
            Section("Classement") {
                Picker("Type", selection: Binding(
                    get: { document.docType },
                    set: { model.confirmDocType($0, for: document) })
                ) {
                    Text("Non classé").tag(String?.none)
                    ForEach(DocTypeDefinition.defaults) { definition in
                        Text(definition.label).tag(Optional(definition.id))
                    }
                }
                if document.docTypeSource == .suggested, let confidence = document.docTypeConfidence {
                    HStack {
                        Text("Suggestion à \(confidence, format: .percent.precision(.fractionLength(0)))")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Valider") { model.confirmDocType(document.docType, for: document) }
                    }
                } else if document.docTypeSource == .automatic {
                    Text("Classé automatiquement").foregroundStyle(.secondary)
                }
            }

            Section("Document") {
                LabeledContent("État", value: statusLabel)
                if let pages = document.pageCount { LabeledContent("Pages", value: "\(pages)") }
                LabeledContent("Taille", value: ByteCountFormatter.string(fromByteCount: document.byteCount, countStyle: .file))
                LabeledContent("Importé le", value: document.importedAt.formatted(date: .abbreviated, time: .shortened))
                if let error = document.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                    Button("Réessayer") { model.retry(document) }
                }
            }

            ForEach(EntityKind.allCases, id: \.self) { kind in
                let values = entities.filter { $0.kind == kind }
                if !values.isEmpty {
                    Section(kind.label) {
                        ForEach(values) { entity in
                            HStack {
                                Text(entity.displayValue).textSelection(.enabled)
                                Spacer()
                                if let page = entity.page { Text("p. \(page)").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }

            Section {
                if let url = model.fileURL(of: document) {
                    Button("Ouvrir avec l'app par défaut") { NSWorkspace.shared.open(url) }
                }
                Button("Supprimer de la bibliothèque", role: .destructive) { model.delete(document) }
            }
        }
        .formStyle(.grouped)
        .task(id: "\(document.id ?? -1)-\(document.status.rawValue)") {
            entities = (try? await model.engine?.entities(of: document.id ?? -1)) ?? []
        }
    }

    private var statusLabel: String {
        switch document.status {
        case .queued: "En attente"
        case .extracting: "Lecture du contenu"
        case .searchable: "Cherchable (analyse à venir)"
        case .enriching: "Analyse sémantique"
        case .ready: "Prêt"
        case .failed: "Échec"
        }
    }
}
