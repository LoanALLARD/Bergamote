// Génère un jeu de documents d'essai fictifs (PDF texte, PDF scanné, image, .docx, .txt).
//
//   swift scripts/make-samples.swift SampleDocs
import AppKit
import CoreText

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "SampleDocs", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)

func draw(_ text: String, in context: CGContext, rect: CGRect, size: CGFloat) {
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    let frame = CTFramesetterCreateFrame(
        CTFramesetterCreateWithAttributedString(attributed), CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
    CTFrameDraw(frame, context)
}

func textPDF(_ name: String, pages: [String]) {
    var box = a4
    let context = CGContext(output.appendingPathComponent(name) as CFURL, mediaBox: &box, nil)!
    for page in pages {
        context.beginPDFPage(nil)
        draw(page, in: context, rect: a4.insetBy(dx: 56, dy: 64), size: 12.5)
        context.endPDFPage()
    }
    context.closePDF()
}

func rasterize(_ text: String, size: CGSize, fontSize: CGFloat, scale: CGFloat = 3) -> CGImage {
    let context = CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(gray: 0.97, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
    context.scaleBy(x: scale, y: scale)
    draw(text, in: context, rect: CGRect(origin: .zero, size: size).insetBy(dx: 40, dy: 48), size: fontSize)
    return context.makeImage()!
}

func scannedPDF(_ name: String, text: String) {
    var box = a4
    let context = CGContext(output.appendingPathComponent(name) as CFURL, mediaBox: &box, nil)!
    context.beginPDFPage(nil)
    context.draw(rasterize(text, size: a4.size, fontSize: 15), in: a4)
    context.endPDFPage()
    context.closePDF()
}

func png(_ name: String, text: String) {
    let image = rasterize(text, size: CGSize(width: 320, height: 420), fontSize: 13, scale: 2.5)
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! data.write(to: output.appendingPathComponent(name))
}

textPDF("facture-volt-fevrier-2025.pdf", pages: ["""
    FACTURE N° 2025-118
    Volt & Fils SARL – 12 rue des Lilas, 69003 Lyon
    SIRET : 732 829 320 00074

    Client : Camille Martin, 8 avenue Jean Jaurès, 69007 Lyon

    Fourniture d'électricité – période du 01/02/2025 au 28/02/2025
    Consommation : 412 kWh – option heures pleines / heures creuses

    Total HT : 1 028,80 €
    TVA 20 % : 205,76 €
    Total TTC : 1 234,56 €

    Échéance : 15 mars 2025
    Règlement par virement – IBAN : FR76 3000 6000 0112 3456 7890 189
    Contact : facturation@volt-fils.fr – 04 72 00 11 22
    """])

textPDF("bail-appartement-lyon.pdf", pages: [
    """
    CONTRAT DE BAIL D'HABITATION (LOCAL VIDE)

    Entre les soussignés : la SCI Les Tilleuls, représentée par Paul Durand, ci-après « le bailleur »,
    et Camille Martin, ci-après « le locataire », il a été convenu ce qui suit.

    Article 1 – Objet : location d'un appartement de trois pièces situé 8 avenue Jean Jaurès, 69007 Lyon,
    à usage d'habitation principale.
    Article 2 – Durée : le présent bail est conclu pour une durée de trois ans à compter du 01/09/2024,
    renouvelable par tacite reconduction.
    Article 3 – Loyer : le loyer mensuel est fixé à 890,00 € hors charges, payable d'avance le 5 de chaque mois.
    Provision sur charges locatives : 85,00 € par mois.
    Article 4 – Dépôt de garantie : 890,00 €, restitué dans un délai de deux mois après la remise des clés.
    """,
    """
    Article 5 – Résiliation : le locataire peut donner congé à tout moment avec un préavis d'un mois
    en zone tendue. Le bailleur ne peut donner congé qu'à l'échéance du bail.
    Article 6 – État des lieux : un état des lieux contradictoire est annexé au présent contrat.

    Fait à Lyon, le 28 août 2024, en deux exemplaires.
    Signatures des parties.
    """,
])

textPDF("bulletin-paie-mars-2025.pdf", pages: ["""
    BULLETIN DE PAIE – Période du 01/03/2025 au 31/03/2025

    Employeur : Atelier Numérique SAS – SIRET 443 061 841 00047 – 3 quai Saint-Antoine, 69002 Lyon
    Salarié : Camille Martin – Emploi : développeuse – Statut : cadre

    Salaire de base : 3 500,00 €
    Cotisations salariales (santé, retraite, chômage) : 770,00 €
    CSG / CRDS : 340,20 €
    Net à payer avant impôt : 2 389,80 €
    Prélèvement à la source (taux 7,5 %) : 179,24 €
    Net payé : 2 210,56 €

    Congés payés acquis : 2,5 jours – Paiement par virement le 31/03/2025
    """])

scannedPDF("scan-avis-echeance-loyer.pdf", text: """
    SCI LES TILLEULS
    AVIS D'ÉCHÉANCE – QUITTANCE DE LOYER

    Locataire : Camille Martin
    Logement : 8 avenue Jean Jaurès, 69007 Lyon

    Période : avril 2025
    Loyer hors charges : 890,00 €
    Provision sur charges : 85,00 €
    Total réglé : 975,00 €

    Reçu le 05/04/2025 – Le bailleur
    """)

png("ticket-librairie.png", text: """
    LIBRAIRIE DU QUAI
    Lyon 2e

    12/04/2025  15:42
    Roman policier        19,90 €
    Carnet A5              8,50 €

    TOTAL                 28,40 €
    Carte bancaire
    Merci de votre visite
    """)

let attestation = NSAttributedString(string: """
    ATTESTATION D'ASSURANCE HABITATION

    Assureur Mutuelle du Rhône atteste que Camille Martin, demeurant 8 avenue Jean Jaurès, 69007 Lyon,
    est titulaire du contrat n° MRH-2024-55821 garantissant les risques locatifs (incendie, dégât des eaux,
    responsabilité civile) pour la période du 01/09/2024 au 31/08/2025.

    Attestation délivrée pour servir et valoir ce que de droit.
    Fait à Lyon, le 2 septembre 2024.
    """, attributes: [.font: NSFont.systemFont(ofSize: 12)])
let docx = try attestation.data(
    from: NSRange(location: 0, length: attestation.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
try docx.write(to: output.appendingPathComponent("attestation-assurance.docx"))

try """
    Camille Martin
    8 avenue Jean Jaurès, 69007 Lyon

    Objet : résiliation de mon abonnement internet

    Madame, Monsieur,
    Je vous prie de bien vouloir résilier mon abonnement internet n° 0478123456 à compter du 30 juin 2025.
    Je vous remercie de me confirmer la prise en compte de cette demande par courrier ou par e-mail
    à camille.martin@exemple.fr.

    Veuillez agréer, Madame, Monsieur, l'expression de mes salutations distinguées.
    """.write(to: output.appendingPathComponent("courrier-resiliation.txt"), atomically: true, encoding: .utf8)

print("Documents d'essai écrits dans \(output.path)")
