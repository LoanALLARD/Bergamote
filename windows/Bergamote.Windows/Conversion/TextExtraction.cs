using System.IO.Compression;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Windows;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Xml.Linq;
using Bergamote.Core;
using UglyToad.PdfPig.DocumentLayoutAnalysis.TextExtractor;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using PigDocument = UglyToad.PdfPig.PdfDocument;

namespace Bergamote.Desktop.Conversion;

/// <summary>
/// Texte d'un document : couche texte des PDF (PdfPig), OCR de Windows pour les images et les
/// pages scannées, lecture directe des documents texte.
/// </summary>
internal static class TextExtraction
{
    /// <summary>En dessous, la page est considérée comme scannée et passe à l'OCR.</summary>
    private const int MinimumTextPerPage = 20;
    /// <summary>Résolution de rendu des pages envoyées à l'OCR.</summary>
    private const double OcrDpi = 220;

    public static string Text(string path)
    {
        var input = FileActionCatalog.InputForPath(path);
        return input.Category switch
        {
            FileCategory.Pdf => PdfText(path),
            FileCategory.Image => Ocr.Recognize(ImageCodec.Load(path)),
            FileCategory.Text => DocumentText(path, input.Format),
            _ => throw new ConversionException($"Impossible de lire le texte de « {Path.GetFileName(path)} »"),
        };
    }

    private static string PdfText(string path)
    {
        PigDocument document;
        try
        {
            document = PigDocument.Open(path);
        }
        catch (Exception error)
        {
            throw new ConversionException($"Impossible d'ouvrir « {Path.GetFileName(path)} » ({error.Message})");
        }
        using (document)
        {
            global::Windows.Data.Pdf.PdfDocument? rendered = null;
            var pages = new List<string>();
            foreach (var page in document.GetPages())
            {
                var text = ContentOrderTextExtractor.GetText(page);
                if (text.Trim().Length >= MinimumTextPerPage)
                {
                    pages.Add(text);
                }
                else
                {
                    rendered ??= PdfRendering.Open(path);
                    pages.Add(Ocr.Recognize(PdfRendering.Render(rendered, (uint)(page.Number - 1), OcrDpi)));
                }
            }
            return string.Join("\n\n", pages);
        }
    }

    private static string DocumentText(string path, string format) => format switch
    {
        "txt" => File.ReadAllText(path),
        "rtf" => RtfText(path),
        "docx" => ZipXmlText(path, "word/document.xml", Word.Paragraph, Word.Text, Word.Breaks, Word.Tabs, space: null),
        "odt" => ZipXmlText(path, "content.xml", OpenDocument.Paragraphs, null, OpenDocument.Breaks, OpenDocument.Tabs, OpenDocument.Space),
        "doc" => throw new ConversionException("Les documents Word 97-2003 (.doc) ne sont pas pris en charge : enregistrez-les en .docx"),
        _ => throw new ConversionException($"Impossible de lire le texte de « {Path.GetFileName(path)} »"),
    };

    /// <summary>RTF lu par WPF (fil STA requis, fourni par <see cref="StaTask"/>).</summary>
    private static string RtfText(string path)
    {
        var document = new FlowDocument();
        var range = new TextRange(document.ContentStart, document.ContentEnd);
        using var stream = File.OpenRead(path);
        range.Load(stream, DataFormats.Rtf);
        return range.Text;
    }

    /// <summary>Texte des paragraphes d'un document bureautique (une archive ZIP de XML).</summary>
    private static string ZipXmlText(
        string path, string entryName, XName[] paragraphs, XName? textElement, XName[] breaks, XName[] tabs, XName? space)
    {
        try
        {
            using var archive = ZipFile.OpenRead(path);
            var entry = archive.GetEntry(entryName) ?? throw new InvalidDataException(entryName);
            using var stream = entry.Open();
            var xml = XDocument.Load(stream);
            var lines = xml.Descendants()
                .Where(element => paragraphs.Contains(element.Name))
                .Where(element => !element.Ancestors().Any(parent => paragraphs.Contains(parent.Name)))
                .Select(paragraph => string.Concat(paragraph.DescendantNodes().Select(node => node switch
                {
                    XText text when textElement is null || text.Parent?.Name == textElement => text.Value,
                    XElement element when breaks.Contains(element.Name) => "\n",
                    XElement element when tabs.Contains(element.Name) => "\t",
                    XElement element when element.Name == space => new string(' ', (int?)element.Attribute(OpenDocument.Count) ?? 1),
                    _ => "",
                })));
            return string.Join("\n", lines);
        }
        catch (Exception error) when (error is InvalidDataException or System.Xml.XmlException)
        {
            throw new ConversionException($"Impossible de lire « {Path.GetFileName(path)} »");
        }
    }

    private static class Word
    {
        private static readonly XNamespace W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
        public static readonly XName[] Paragraph = [W + "p"];
        public static readonly XName Text = W + "t";
        public static readonly XName[] Breaks = [W + "br", W + "cr"];
        public static readonly XName[] Tabs = [W + "tab"];
    }

    private static class OpenDocument
    {
        private static readonly XNamespace T = "urn:oasis:names:tc:opendocument:xmlns:text:1.0";
        public static readonly XName[] Paragraphs = [T + "p", T + "h"];
        public static readonly XName[] Breaks = [T + "line-break"];
        public static readonly XName[] Tabs = [T + "tab"];
        /// <summary>Espaces répétées : &lt;text:s text:c="3"/&gt;.</summary>
        public static readonly XName Space = T + "s";
        public static readonly XName Count = T + "c";
    }
}

/// <summary>Reconnaissance de texte de Windows, dans les langues de l'utilisateur.</summary>
internal static class Ocr
{
    public static string Recognize(BitmapSource image)
    {
        var engine = OcrEngine.TryCreateFromUserProfileLanguages()
            ?? throw new ConversionException("Aucune langue de reconnaissance de texte n'est installée (Paramètres › Heure et langue)");
        var largest = Math.Max(image.PixelWidth, image.PixelHeight);
        if (largest > OcrEngine.MaxImageDimension) image = ImageCodec.Resize(image, (int)OcrEngine.MaxImageDimension);
        using var bitmap = ToSoftwareBitmap(image);
        var result = engine.RecognizeAsync(bitmap).AsTask().GetAwaiter().GetResult();
        return string.Join("\n", result.Lines.Select(line => line.Text));
    }

    private static SoftwareBitmap ToSoftwareBitmap(BitmapSource image)
    {
        var bgra = new FormatConvertedBitmap(image, PixelFormats.Bgra32, null, 0);
        var stride = bgra.PixelWidth * 4;
        var pixels = new byte[stride * bgra.PixelHeight];
        bgra.CopyPixels(pixels, stride, 0);
        var bitmap = new SoftwareBitmap(BitmapPixelFormat.Bgra8, bgra.PixelWidth, bgra.PixelHeight, BitmapAlphaMode.Premultiplied);
        bitmap.CopyFromBuffer(pixels.AsBuffer());
        return bitmap;
    }
}
