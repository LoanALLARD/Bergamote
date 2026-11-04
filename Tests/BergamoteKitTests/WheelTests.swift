import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import BergamoteKit

@Suite("Camembert : geste, géométrie, catalogue")
struct WheelTests {
    typealias Sample = WheelTriggerDetector.Sample

    @Test func tappingShiftWhileDraggingOpensConversionWheel() {
        var detector = WheelTriggerDetector()
        #expect(detector.update(Sample(isMouseDown: false, dragPasteboardChangeCount: 10, modifiers: [])) == .none)
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 10, modifiers: [])) == .none)
        // Pas encore de glisser : une touche seule ne fait rien.
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 10, modifiers: .shift)) == .none)
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 10, modifiers: [])) == .none)
        // Le Finder commence le glisser : le presse-papiers de glisser change.
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 11, modifiers: [])) == .none)
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 11, modifiers: .shift)) == .show(.conversion))
        // Maintenir la touche n'ouvre pas une seconde fois.
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 11, modifiers: .shift)) == .none)
        // ⌘ bascule sur le camembert d'outils, le relâchement du bouton ferme.
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 11, modifiers: .command)) == .show(.tools))
        #expect(detector.update(Sample(isMouseDown: false, dragPasteboardChangeCount: 11, modifiers: .command)) == .hide)
        #expect(detector.visible == nil)
    }

    @Test func lateMouseDownSampleStillSeesTheDrag() {
        var detector = WheelTriggerDetector()
        _ = detector.update(Sample(isMouseDown: false, dragPasteboardChangeCount: 4, modifiers: []))
        // Premier échantillon « bouton enfoncé » reçu après le début du glisser (moniteur en retard).
        _ = detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 5, modifiers: []))
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 5, modifiers: .shift)) == .show(.conversion))
    }

    /// Appui prolongé, tel que relevé dans les journaux d'un essai réel : ⇧ est maintenu avant le
    /// clic, puis le Finder démarre le glisser (#1257 → #1260) sans que la touche change.
    @Test func modifierHeldWhenTheDragStartsOpensTheWheel() {
        var detector = WheelTriggerDetector()
        _ = detector.update(Sample(isMouseDown: false, dragPasteboardChangeCount: 1257, modifiers: .shift))
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 1257, modifiers: .shift)) == .none)
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 1260, modifiers: .shift)) == .show(.conversion))
        // Toujours maintenu : pas de seconde ouverture, ni après une fermeture pendant le même glisser.
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 1260, modifiers: .shift)) == .none)
        detector.dismiss()
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 1260, modifiers: .shift)) == .none)
        // Le taper de nouveau rouvre.
        _ = detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 1260, modifiers: []))
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 1260, modifiers: .shift)) == .show(.conversion))
    }

    @Test func heldUnboundModifierDoesNothing() {
        var detector = WheelTriggerDetector()
        _ = detector.update(Sample(isMouseDown: false, dragPasteboardChangeCount: 1, modifiers: .option))
        _ = detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 1, modifiers: .option))
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 2, modifiers: .option)) == .none)
    }

    @Test func customBindingsAndUnboundCombinations() {
        var detector = WheelTriggerDetector(bindings: [.control: .conversion, [.control, .option]: .tools])
        _ = detector.update(Sample(isMouseDown: false, dragPasteboardChangeCount: 0, modifiers: []))
        _ = detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 1, modifiers: []))
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 1, modifiers: .shift)) == .none)
        #expect(detector.update(Sample(isMouseDown: true, dragPasteboardChangeCount: 1, modifiers: [.control, .option])) == .show(.tools))
    }

    @Test func sliceGeometry() {
        let hit = { (x: CGFloat, y: CGFloat) in WheelGeometry.slice(at: CGPoint(x: x, y: y), count: 4, innerRadius: 50, outerRadius: 150) }
        #expect(hit(0, 100) == 0)    // en haut
        #expect(hit(100, 0) == 1)    // à droite
        #expect(hit(0, -100) == 2)   // en bas
        #expect(hit(-100, 0) == 3)   // à gauche
        #expect(hit(70, 72) == 0 || hit(70, 72) == 1)
        #expect(hit(10, 10) == nil)  // trou central
        #expect(hit(200, 0) == nil)  // hors du disque
        #expect(WheelGeometry.slice(at: CGPoint(x: -1, y: 100), count: 8, innerRadius: 50, outerRadius: 150) == 0)
    }

    @Test func conversionWheelAdaptsToInputs() {
        let writable: Set<UTType> = [.png, .jpeg, .heic, .tiff, .gif, .bmp]
        let forJPEG = FileActionCatalog.actions(for: .conversion, inputs: [.jpeg, .jpeg], writableImageTypes: writable)
        #expect(forJPEG.map(\.title) == ["PNG", "HEIC", "TIFF", "GIF", "BMP", "PDF"])
        #expect(forJPEG.last?.operation == .mergeIntoPDF)

        let forPDF = FileActionCatalog.actions(for: .conversion, inputs: [.pdf], writableImageTypes: writable)
        #expect(forPDF.map(\.operation) == [.renderPages(.png), .renderPages(.jpeg), .renderPages(.heic), .extractText])

        let forWord = FileActionCatalog.actions(for: .conversion, inputs: [.docx], writableImageTypes: writable)
        #expect(forWord.map(\.title) == ["PDF", "RTF", "TXT"])

        #expect(FileActionCatalog.actions(for: .conversion, inputs: [.mp3], writableImageTypes: writable).isEmpty)
    }

    @Test func commonActionsWhenTypesAreUnknown() {
        let writable: Set<UTType> = [.png, .jpeg]
        let conversion = FileActionCatalog.commonActions(for: .conversion, writableImageTypes: writable).map(\.title)
        #expect(conversion == ["PDF", "PNG", "JPEG", "TXT"])
        let tools = FileActionCatalog.commonActions(for: .tools).map(\.operation)
        #expect(tools.first == .index && tools.contains(.compress) && tools.contains(.makeSearchable))
    }

    @Test func toolsWheelAdaptsToInputs() {
        let forImages = FileActionCatalog.actions(for: .tools, inputs: [.png, .jpeg]).map(\.operation)
        #expect(forImages == [.index, .compress, .stripMetadata, .makeSearchable, .mergeIntoPDF, .extractText])
        let forText = FileActionCatalog.actions(for: .tools, inputs: [.plainText]).map(\.operation)
        #expect(forText == [.index, .extractText])
    }
}
