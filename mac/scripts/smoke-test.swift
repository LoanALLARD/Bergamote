// Test de bout en bout de l'app Mac, pilotée comme le ferait une personne : une fenêtre sert de
// source de glisser, la souris et la touche Maj sont simulées, le fichier est déposé sur la
// première part du camembert, et on attend le fichier converti à côté de l'original.
//
//   swift build -c release --package-path mac
//   swift mac/scripts/smoke-test.swift mac/.build/release/Bergamote
//
// Simuler la souris et le clavier demande l'autorisation « Accessibilité » de macOS : sans elle
// (un terminal ordinaire), le test le signale et ne fait rien. Les machines de la CI l'ont.
import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IONBF, 0)
let binary = CommandLine.arguments.dropFirst().first ?? "mac/.build/release/Bergamote"

guard CGPreflightPostEventAccess() else {
    print("::warning title=Mac end-to-end test not run::This machine does not let the test drive the mouse and keyboard (no accessibility permission).")
    exit(0)
}

// Le fichier à convertir : un petit PNG, dans un dossier temporaire.
let work = FileManager.default.temporaryDirectory.appendingPathComponent("bergamote-smoke-\(getpid())")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
let photo = work.appendingPathComponent("photo.png")
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(red: 0.76, green: 0.81, blue: 0.23, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 400, height: 300).fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: photo)

// L'app, hors sandbox (binaire SwiftPM), avec son journal de diagnostic sur la sortie d'erreur.
let app = Process()
app.executableURL = URL(fileURLWithPath: binary)
var environment = ProcessInfo.processInfo.environment
environment["BERGAMOTE_DEBUG"] = "1"
app.environment = environment
let pipe = Pipe()
app.standardError = pipe
let lock = NSLock()
var log = ""
pipe.fileHandleForReading.readabilityHandler = { handle in
    guard let text = String(data: handle.availableData, encoding: .utf8) else { return }
    lock.lock(); log += text; lock.unlock()
}
func logged(_ text: String) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return log.contains(text)
}
func waitFor(_ text: String, seconds: Double) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !logged(text), Date() < deadline { usleep(200_000) }
    return logged(text)
}
try app.run()

var report: [String] = []
var failed = false
func check(_ ok: Bool, _ label: String) {
    let line = (ok ? "ok     " : "FAILED ") + label
    print(line)
    report.append(line)
    if !ok { failed = true }
}
func finish() -> Never {
    if app.isRunning { app.terminate() }
    lock.lock(); let lines = log; lock.unlock()
    print("--- app log ---")
    lines.split(separator: "\n").forEach { print("       \($0)") }
    try? FileManager.default.removeItem(at: work)
    // Le résultat, visible sur la page de l'exécution sans ouvrir le journal.
    print("::\(failed ? "error" : "notice") title=Mac end-to-end test::" + report.joined(separator: "%0A"))
    exit(failed ? 1 : 0)
}

/// La source du glisser : appuyer dans la vue puis bouger démarre un vrai glisser du fichier.
final class SourceView: NSView, NSDraggingSource {
    let file: URL
    var started = false

    init(file: URL, frame: NSRect) {
        self.file = file
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        guard !started else { return }
        started = true
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            rect.fill()
            return true
        }
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
// Coordonnées Quartz (origine en haut à gauche) : la fenêtre occupe (100, 100) à (400, 300).
let screen = CGDisplayBounds(CGMainDisplayID())
let window = NSWindow(
    contentRect: NSRect(x: 100, y: screen.height - 300, width: 300, height: 200),
    styleMask: [.titled], backing: .buffered, defer: false)
window.title = "Bergamote drag source"
window.level = .floating
window.contentView = SourceView(file: photo, frame: NSRect(x: 0, y: 0, width: 300, height: 200))
window.makeKeyAndOrderFront(nil)
application.activate(ignoringOtherApps: true)

func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func shift(down: Bool) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: down) else { return }
    event.type = .flagsChanged
    event.flags = down ? .maskShift : []
    event.post(tap: .cghidEventTap)
}

DispatchQueue.global().async {
    check(waitFor("started", seconds: 30), "the app starts")
    usleep(1_000_000)

    // Appui dans la source, puis glisser pas à pas vers le milieu de l'écran.
    let start = CGPoint(x: 250, y: 220)
    let target = CGPoint(x: screen.midX, y: screen.midY)
    post(.mouseMoved, start)
    usleep(300_000)
    post(.leftMouseDown, start)
    usleep(200_000)
    for step in 1...20 {
        let t = CGFloat(step) / 20
        post(.leftMouseDragged, CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t))
        usleep(40_000)
    }
    usleep(600_000)

    // Taper Maj : le camembert de conversion s'ouvre sous le curseur.
    shift(down: true)
    usleep(200_000)
    shift(down: false)
    usleep(400_000)
    post(.leftMouseDragged, CGPoint(x: target.x + 2, y: target.y + 1))
    usleep(100_000)
    post(.leftMouseDragged, target)
    check(waitFor("gesture: conversion; files: 1", seconds: 5), "the gesture (drag, then Shift) is detected and the dragged file is seen")
    check(logged("slices: JPEG"), "the wheel offers the conversion slices")
    usleep(800_000)

    // Vers la première part (en haut), puis lâcher.
    for step in 1...11 {
        post(.leftMouseDragged, CGPoint(x: target.x, y: target.y - CGFloat(step) * 10))
        usleep(40_000)
    }
    usleep(600_000)
    post(.leftMouseUp, CGPoint(x: target.x, y: target.y - 110))
    check(waitFor("action: JPEG", seconds: 8), "dropping on the JPEG slice starts the conversion")
    check(waitFor("result: done", seconds: 15), "the conversion succeeds")
    let converted = work.appendingPathComponent("photo.jpeg")
    check((try? converted.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0, "photo.jpeg is created next to the original")
    check(FileManager.default.fileExists(atPath: photo.path), "the original is still there")
    check(app.isRunning, "the app is still running")
    finish()
}
// Garde-fou : le test ne doit jamais rester bloqué.
DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
    check(false, "the test finished in time")
    finish()
}
application.run()
