import AppKit
import BergamoteKit
import SwiftUI
import UniformTypeIdentifiers

/// Fait apparaître le camembert : on glisse des fichiers depuis n'importe quelle
/// app, on tape ⇧ (convertir) ou ⌘ (outils), et le camembert s'ouvre sous le curseur.
///
/// - Détection : moniteurs d'événements globaux et locaux (souris, touches de modification), plus
///   un relevé à 30 Hz tant que le bouton est enfoncé, pour voir une touche tapée sans bouger la
///   souris. La décision est prise par `WheelTriggerDetector`.
/// - Fichiers : aperçu lu dans le presse-papiers de glisser-déposer ; l'accès réel vient du dépôt.
@MainActor
final class RadialMenuController {
    static let enabledKey = "wheel.enabled"
    static let conversionModifierKey = "wheel.conversion.modifier"
    static let toolsModifierKey = "wheel.tools.modifier"
    static let revealResultsKey = "wheel.revealResults"

    let model = RadialMenuModel()
    private let engine: BergamoteEngine
    private var detector = WheelTriggerDetector()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var clickModeMonitors: [Any] = []
    private var pollTimer: Timer?

    init(engine: BergamoteEngine) {
        self.engine = engine
    }

    // MARK: Surveillance du geste

    func startMonitoring() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.sample() }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func sample() {
        guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true else { return }
        detector.bindings = Self.bindings()
        let isMouseDown = NSEvent.pressedMouseButtons & 1 != 0
        let decision = detector.update(.init(
            isMouseDown: isMouseDown,
            dragPasteboardChangeCount: NSPasteboard(name: .drag).changeCount,
            modifiers: WheelModifier(NSEvent.modifierFlags)))
        updatePolling(isMouseDown: isMouseDown)
        switch decision {
        case .show(let kind): presentForDrag(kind)
        case .hide: dismissAfterDrag()
        case .none: break
        }
    }

    private func updatePolling(isMouseDown: Bool) {
        if isMouseDown, pollTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            // Mode « common » : la minuterie tourne aussi pendant un glisser lancé depuis Bergamote.
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else if !isMouseDown, let timer = pollTimer {
            timer.invalidate()
            pollTimer = nil
        }
    }

    static func bindings() -> [WheelModifier: WheelKind] {
        let defaults = UserDefaults.standard
        let conversion = WheelModifier(rawValue: defaults.object(forKey: conversionModifierKey) as? Int ?? WheelModifier.shift.rawValue)
        let tools = WheelModifier(rawValue: defaults.object(forKey: toolsModifierKey) as? Int ?? WheelModifier.command.rawValue)
        var bindings = [tools: WheelKind.tools]
        bindings[conversion] = .conversion  // en cas de conflit, la conversion l'emporte
        return bindings
    }

    // MARK: Affichage

    private func presentForDrag(_ kind: WheelKind) {
        let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let types = urls.map { UTType(filenameExtension: $0.pathExtension) ?? .data }
        let actions = FileActionCatalog.actions(for: kind, inputs: types)
        guard !actions.isEmpty else {
            detector.dismiss()
            hidePanel()
            return
        }
        model.configure(kind: kind, mode: .drop, files: urls, actions: actions)
        showPanel(at: NSEvent.mouseLocation)
    }

    /// Ouvre le camembert sur des fichiers déjà accessibles (documents de la bibliothèque).
    func present(_ kind: WheelKind, for urls: [URL], at location: NSPoint = NSEvent.mouseLocation) {
        let types = urls.map { DocumentLibrary.contentType(of: $0) ?? .data }
        let actions = FileActionCatalog.actions(for: kind, inputs: types)
        guard !actions.isEmpty else { return }
        model.configure(kind: kind, mode: .click, files: urls, actions: actions)
        showPanel(at: location)
        panel?.makeKey()
        watchOutsideClicksAndEscape()
    }

    private func dismissAfterDrag() {
        // Le dépôt (performDrop) arrive au même moment que le relâchement du bouton : on laisse
        // un instant à l'action pour démarrer, sinon on ferme.
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            if model.status == .idle, model.mode == .drop { hidePanel() }
        }
    }

    private func showPanel(at location: NSPoint) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = RadialMenuView.size
        var origin = NSPoint(x: location.x - size / 2, y: location.y - size / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) {
            origin.x = min(max(origin.x, screen.visibleFrame.minX), screen.visibleFrame.maxX - size)
            origin.y = min(max(origin.y, screen.visibleFrame.minY), screen.visibleFrame.maxY - size)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let size = RadialMenuView.size
        let panel = RadialMenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: RadialMenuView(model: model) { [weak self] action, urls in
            self?.run(action, on: urls)
        })
        return panel
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        detector.dismiss()
        model.configure(kind: model.kind, mode: .drop, files: [], actions: [])
        clickModeMonitors.forEach(NSEvent.removeMonitor)
        clickModeMonitors.removeAll()
    }

    private func watchOutsideClicksAndEscape() {
        clickModeMonitors.forEach(NSEvent.removeMonitor)
        clickModeMonitors.removeAll()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }
        }) {
            clickModeMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown], handler: { [weak self] event in
            let isEscape = event.type == .keyDown && event.keyCode == 53
            let isOutside = event.type == .leftMouseDown && !(event.window is RadialMenuPanel)
            if isEscape || isOutside {
                MainActor.assumeIsolated { self?.hidePanel() }
            }
            return isEscape ? nil : event
        }) {
            clickModeMonitors.append(local)
        }
    }

    // MARK: Action

    private func run(_ action: FileAction, on urls: [URL]) {
        guard model.status == .idle, !urls.isEmpty else { return }
        model.status = .working(action.title)
        let engine = engine
        Task {
            do {
                let outcome = try await engine.perform(action, on: urls)
                model.status = .done(outcome.message)
                let reveal = UserDefaults.standard.object(forKey: Self.revealResultsKey) as? Bool ?? true
                if reveal, !outcome.produced.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(outcome.produced)
                }
            } catch {
                model.status = .failed(error.localizedDescription)
            }
            try? await Task.sleep(for: .seconds(1.4))
            hidePanel()
        }
    }
}

/// Panneau sans bordure qui peut recevoir le clavier (Échap) sans activer l'app.
final class RadialMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

extension WheelModifier {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.command) { insert(.command) }
    }
}
