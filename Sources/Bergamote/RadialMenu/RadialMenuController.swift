import AppKit
import BergamoteKit
import os
import SwiftUI
import UniformTypeIdentifiers

/// Fait apparaître le camembert : on glisse des fichiers depuis n'importe quelle
/// app, on tape ⇧ (convertir) ou ⌘ (outils), et le camembert s'ouvre sous le curseur.
///
/// - Détection : relevé permanent à 20 Hz de l'état global (bouton, presse-papiers de glisser,
///   touches de modification), doublé de moniteurs d'événements pour réagir plus vite. Le relevé ne
///   dépend pas des événements livrés pendant un glisser du Finder. La décision est prise par
///   `WheelTriggerDetector`.
/// - App Nap désactivé pendant la surveillance, : sinon la minuterie est ralentie dès que
///   l'app passe en arrière-plan.
/// - Fichiers : aperçu lu dans le presse-papiers de glisser-déposer ; l'accès réel vient du dépôt.
/// - Diagnostic : `open Bergamote.app --args -wheel.debug YES` journalise chaque transition.
@MainActor
final class RadialMenuController {
    static let enabledKey = "wheel.enabled"
    static let conversionModifierKey = "wheel.conversion.modifier"
    static let toolsModifierKey = "wheel.tools.modifier"
    static let revealResultsKey = "wheel.revealResults"
    static let debugKey = "wheel.debug"

    let model = RadialMenuModel()
    private let engine: BergamoteEngine
    private var detector = WheelTriggerDetector()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var clickModeMonitors: [Any] = []
    private var pollTimer: Timer?
    private var activity: NSObjectProtocol?
    private var trace = Trace()

    init(engine: BergamoteEngine) {
        self.engine = engine
    }

    // MARK: Surveillance du geste

    func startMonitoring() {
        guard pollTimer == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Surveillance du geste du camembert")

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

        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.01
        // Mode « common » : la minuterie tourne aussi pendant un glisser lancé depuis Bergamote.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        Logger.wheel.notice("Camembert : surveillance active, \(self.monitors.count, privacy: .public) moniteur(s), App Nap désactivé")

        // Diagnostic : `--args -wheel.demo conversion` ouvre le camembert du glisser en cours au bout de
        // 2 s, comme si la touche avait été tapée, puis le referme. Sert à vérifier l'affichage seul.
        if let demo = UserDefaults.standard.string(forKey: "wheel.demo").flatMap(WheelKind.init(rawValue:)) {
            Task {
                try? await Task.sleep(for: .seconds(2))
                presentForDrag(demo)
                try? await Task.sleep(for: .seconds(4))
                hidePanel()
            }
        }
    }

    private func sample() {
        guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true else { return }
        detector.bindings = Self.bindings()
        let sample = WheelTriggerDetector.Sample(
            isMouseDown: NSEvent.pressedMouseButtons & 1 != 0,
            dragPasteboardChangeCount: NSPasteboard(name: .drag).changeCount,
            modifiers: WheelModifier(NSEvent.modifierFlags))
        let decision = detector.update(sample)
        if UserDefaults.standard.bool(forKey: Self.debugKey) { trace.record(sample, decision) }
        switch decision {
        case .show(let kind): presentForDrag(kind)
        case .hide: dismissAfterDrag()
        case .none: break
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

    /// Fichiers du glisser en cours. `readObjects` résout en principe les références de fichier du
    /// Finder (`file:///.file/id=…`) ; `filePathURL` garantit un chemin, donc une extension, dans tous les cas.
    static func draggedFiles() -> [URL] {
        let pasteboard = NSPasteboard(name: .drag)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.map { ($0 as NSURL).filePathURL ?? $0 }
    }

    static func contentType(of url: URL) -> UTType? {
        if !url.pathExtension.isEmpty, let type = UTType(filenameExtension: url.pathExtension) { return type }
        return try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
    }

    private func presentForDrag(_ kind: WheelKind) {
        let urls = Self.draggedFiles()
        let types = urls.compactMap(Self.contentType)
        var actions = FileActionCatalog.actions(for: kind, inputs: types)
        // Des fichiers sont glissés mais leur type reste illisible avant le dépôt : on propose les
        // actions courantes, vérifiées au dépôt, quand la sandbox donne accès aux fichiers.
        if actions.isEmpty, !urls.isEmpty, types.count < urls.count {
            actions = FileActionCatalog.commonActions(for: kind)
        }
        Logger.wheel.notice("""
            Camembert \(kind.rawValue, privacy: .public) demandé : \(urls.count, privacy: .public) fichier(s), \
            \(types.count, privacy: .public) typé(s) [\(Set(types.compactMap(\.preferredFilenameExtension)).sorted().joined(separator: ","), privacy: .public)], \
            \(actions.count, privacy: .public) action(s)
            """)
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
        // Après un camembert « actions courantes », on vérifie maintenant que les fichiers déposés
        // (désormais accessibles) se prêtent à l'action choisie.
        let types = urls.map { DocumentLibrary.contentType(of: $0) ?? .data }
        guard FileActionCatalog.actions(for: model.kind, inputs: types).contains(where: { $0.operation == action.operation }) else {
            model.status = .failed("« \(action.title) » ne s'applique pas à ces fichiers")
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                hidePanel()
            }
            return
        }
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

/// Journal de diagnostic (`-wheel.debug YES`) : chaque transition d'état, et toutes les 5 s le
/// rythme réel des relevés, pour voir si App Nap ou la sandbox bloquent la détection.
@MainActor
private struct Trace {
    private var last: WheelTriggerDetector.Sample?
    private var samples = 0
    private var windowStart = Date()

    mutating func record(_ sample: WheelTriggerDetector.Sample, _ decision: WheelTriggerDetector.Decision) {
        samples += 1
        let changed = last.map {
            $0.isMouseDown != sample.isMouseDown || $0.dragPasteboardChangeCount != sample.dragPasteboardChangeCount
                || $0.modifiers != sample.modifiers
        } ?? true
        if changed || decision != .none {
            Logger.wheel.notice("""
                relevé : bouton \(sample.isMouseDown ? "enfoncé" : "relâché", privacy: .public), \
                glisser #\(sample.dragPasteboardChangeCount, privacy: .public), \
                touches \(sample.modifiers.symbol.isEmpty ? "aucune" : sample.modifiers.symbol, privacy: .public), \
                décision \(String(describing: decision), privacy: .public)
                """)
        }
        last = sample
        if Date().timeIntervalSince(windowStart) >= 5 {
            let items = NSPasteboard(name: .drag).pasteboardItems?.count ?? 0
            let files = RadialMenuController.draggedFiles()
            let typed = files.compactMap(RadialMenuController.contentType).count
            let rate = samples
            Logger.wheel.notice("""
                rythme : \(rate, privacy: .public) relevés en 5 s ; presse-papiers de glisser : \
                \(items, privacy: .public) élément(s), \(files.count, privacy: .public) fichier(s), \(typed, privacy: .public) typé(s)
                """)
            samples = 0
            windowStart = Date()
        }
    }
}

extension Logger {
    static let wheel = Logger(subsystem: "com.example.bergamote", category: "camembert")
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
