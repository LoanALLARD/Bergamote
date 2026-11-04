import AppKit
import BergamoteKit
import SwiftUI
import UniformTypeIdentifiers

/// Le camembert : des parts en anneau autour d'un centre qui résume les fichiers.
struct RadialMenuView: View {
    static let size: CGFloat = 340
    static let outerRadius: CGFloat = 160
    static let innerRadius: CGFloat = 62

    let model: RadialMenuModel
    let perform: (FileAction, [URL]) -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .frame(width: Self.outerRadius * 2, height: Self.outerRadius * 2)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)

            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                let isHighlighted = model.highlighted == index
                SliceShape(index: index, count: model.actions.count, innerRadius: Self.innerRadius + 6, outerRadius: Self.outerRadius - 6)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.07))
                SliceLabel(action: action, isHighlighted: isHighlighted)
                    .offset(Self.labelOffset(index: index, count: model.actions.count))
            }

            CenterLabel(model: model)
                .frame(width: (Self.innerRadius - 4) * 2, height: (Self.innerRadius - 4) * 2)
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.12), value: model.highlighted)
        .onDrop(of: [.fileURL], delegate: WheelDropDelegate(model: model, perform: perform))
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard model.mode == .click, model.status == .idle else { return }
            let slice: Int? = if case .active(let location) = phase {
                Self.slice(at: location, count: model.actions.count)
            } else {
                nil
            }
            if slice != model.highlighted {
                model.highlighted = slice
                if slice != nil { WheelSound.tick() }
            }
        }
        .onTapGesture(coordinateSpace: .local) { location in
            guard model.mode == .click, model.status == .idle,
                  let index = Self.slice(at: location, count: model.actions.count)
            else { return }
            perform(model.actions[index], model.files)
        }
    }

    /// Part sous un point de la vue (origine en haut à gauche).
    static func slice(at location: CGPoint, count: Int) -> Int? {
        let point = CGPoint(x: location.x - size / 2, y: size / 2 - location.y)
        return WheelGeometry.slice(at: point, count: count, innerRadius: innerRadius, outerRadius: outerRadius)
    }

    static func labelOffset(index: Int, count: Int) -> CGSize {
        let angle = WheelGeometry.centerAngle(of: index, count: count)
        let radius = (innerRadius + outerRadius) / 2 + 4
        return CGSize(width: sin(angle) * radius, height: -cos(angle) * radius)
    }
}

/// Secteur d'anneau, part 0 centrée en haut puis sens horaire. Tracé point par point pour ne
/// pas dépendre du sens des angles de SwiftUI dans son repère retourné.
struct SliceShape: Shape {
    let index: Int
    let count: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let width = 2 * CGFloat.pi / CGFloat(max(count, 1))
        let gap: CGFloat = count > 1 ? 0.025 : 0
        let start = WheelGeometry.centerAngle(of: index, count: count) - width / 2 + gap
        let end = start + width - 2 * gap
        func point(_ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + sin(angle) * radius, y: center.y - cos(angle) * radius)
        }
        let steps = 32
        var path = Path()
        path.move(to: point(outerRadius, start))
        for step in 1...steps { path.addLine(to: point(outerRadius, start + (end - start) * CGFloat(step) / CGFloat(steps))) }
        for step in (0...steps).reversed() { path.addLine(to: point(innerRadius, start + (end - start) * CGFloat(step) / CGFloat(steps))) }
        path.closeSubpath()
        return path
    }
}

private struct SliceLabel: View {
    let action: FileAction
    let isHighlighted: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: action.systemImage).font(.system(size: 17, weight: .medium))
            Text(action.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 78)
        .foregroundStyle(isHighlighted ? Color.white : Color.primary.opacity(0.85))
    }
}

private struct CenterLabel: View {
    let model: RadialMenuModel

    var body: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            VStack(spacing: 3) {
                switch model.status {
                case .idle:
                    Text(model.kind.title.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    Text(model.summary).font(.system(size: 11, weight: .semibold)).multilineTextAlignment(.center)
                case .working(let title):
                    ProgressView().controlSize(.small)
                    Text(title).font(.system(size: 10, weight: .semibold))
                case .done(let message):
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                    Text(message).font(.system(size: 9)).multilineTextAlignment(.center)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.orange)
                    Text(message).font(.system(size: 9)).multilineTextAlignment(.center)
                }
            }
            .padding(10)
        }
    }
}

/// Dépôt sur le camembert : la part visée suit le curseur, et lâcher les fichiers lance l'action.
/// Déposer sur notre propre fenêtre donne aussi à l'app sandboxée l'accès à ces fichiers.
struct WheelDropDelegate: DropDelegate {
    let model: RadialMenuModel
    let perform: (FileAction, [URL]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        model.status == .idle && info.hasItemsConforming(to: [.fileURL])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let slice = RadialMenuView.slice(at: info.location, count: model.actions.count)
        if slice != model.highlighted {
            model.highlighted = slice
            if slice != nil { WheelSound.tick() }
        }
        return DropProposal(operation: slice == nil ? .forbidden : .copy)
    }

    func dropExited(info: DropInfo) {
        model.highlighted = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let index = RadialMenuView.slice(at: info.location, count: model.actions.count) else { return false }
        let action = model.actions[index]
        let providers = info.itemProviders(for: [.fileURL])
        let collector = DroppedURLCollector(count: providers.count) { urls in perform(action, urls) }
        for (position, provider) in providers.enumerated() {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in collector.receive(url, at: position) }
            }
        }
        return true
    }
}

/// Rassemble les URL chargées en parallèle, dans l'ordre du glisser (utile pour fusionner en PDF).
@MainActor
final class DroppedURLCollector {
    private var urls: [URL?]
    private var remaining: Int
    private let completion: ([URL]) -> Void

    init(count: Int, completion: @escaping ([URL]) -> Void) {
        urls = Array(repeating: nil, count: count)
        remaining = count
        self.completion = completion
        if count == 0 { completion([]) }
    }

    func receive(_ url: URL?, at position: Int) {
        urls[position] = url
        remaining -= 1
        if remaining == 0 { completion(urls.compactMap { $0 }) }
    }
}
