import BergamoteKit
import SwiftUI

/// Palette ⌘K : recherche hybride au fil de la frappe, ↑↓ pour naviguer, ↩ pour ouvrir.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [SearchHit] = []
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher : « facture électricité mars », « contrat de bail »…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                    .onSubmit(openSelection)
            }
            .padding(14)
            Divider()
            List(Array(results.enumerated()), id: \.element.id) { index, hit in
                SearchHitRow(hit: hit)
                    .listRowBackground(index == selectedIndex ? Color.accentColor.opacity(0.15) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedIndex = index
                        openSelection()
                    }
            }
            .listStyle(.plain)
        }
        .frame(width: 640, height: 420)
        .onAppear { isFocused = true }
        .onKeyPress(.downArrow) {
            selectedIndex = min(selectedIndex + 1, max(results.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let engine = model.engine else { return }
            results = (try? await engine.search.search(query, limit: 12)) ?? []
            selectedIndex = 0
        }
    }

    private func openSelection() {
        guard results.indices.contains(selectedIndex) else { return }
        model.query = ""
        model.open(results[selectedIndex], query: query)
        dismiss()
    }
}
