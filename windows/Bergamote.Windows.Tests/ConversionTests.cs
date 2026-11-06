using System.IO.Compression;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bergamote.Core;
using Bergamote.Desktop;
using Bergamote.Desktop.Conversion;
using PdfSharp.Drawing;
using PdfSharp.Pdf.IO;
using SharpPdf = PdfSharp.Pdf.PdfDocument;

namespace Bergamote.Windows.Tests;

/// <summary>Chaque opération du camembert sur de vrais fichiers, dans un dossier temporaire.</summary>
public sealed class ConversionTests : IDisposable
{
    private readonly string folder = Directory.CreateTempSubdirectory("bergamote-").FullName;
    private readonly WindowsFileConverter converter = new();

    public void Dispose() => Directory.Delete(folder, recursive: true);

    private static T Sta<T>(Func<T> work) => StaTask.Run(work).GetAwaiter().GetResult();

    private static FileAction Action(WheelKind kind, string id, params string[] files)
    {
        var inputs = files.Select(FileActionCatalog.InputForPath);
        return FileActionCatalog.Actions(kind, inputs, WindowsFileConverter.Abilities).Single(action => action.Id == id);
    }

    /// <summary>Image de test : un dégradé, avec ou sans transparence, ou du bruit (peu compressible).</summary>
    private string MakeImage(string name, int width, int height, bool alpha = false, bool noise = false)
    {
        var path = Path.Combine(folder, name);
        Sta(() =>
        {
            var pixels = new byte[width * height * 4];
            var random = new Random(7);
            for (var y = 0; y < height; y++)
            {
                for (var x = 0; x < width; x++)
                {
                    var i = (y * width + x) * 4;
                    pixels[i] = noise ? (byte)random.Next(256) : (byte)(x * 255 / width);
                    pixels[i + 1] = noise ? (byte)random.Next(256) : (byte)(y * 255 / height);
                    pixels[i + 2] = 180;
                    pixels[i + 3] = alpha && x < width / 2 ? (byte)0 : (byte)255;
                }
            }
            var image = BitmapSource.Create(width, height, 96, 96, alpha ? PixelFormats.Bgra32 : PixelFormats.Bgr32, null, pixels, width * 4);
            ImageCodec.Save(image, path, Path.GetExtension(name).TrimStart('.') switch { "jpg" => "jpeg", var other => other }, 0.9);
            return 0;
        });
        return path;
    }

    private static BitmapFrame Decode(string path)
    {
        using var stream = File.OpenRead(path);
        return BitmapDecoder.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad).Frames[0];
    }

    [Fact]
    public void ConvertsNextToTheOriginalWithoutOverwriting()
    {
        var png = MakeImage("logo.png", 64, 48, alpha: true);
        var action = Action(WheelKind.Conversion, "convert_images:jpeg", png);

        var first = Sta(() => converter.Perform(action, [png])).Single();
        var second = Sta(() => converter.Perform(action, [png])).Single();

        Assert.Equal(Path.Combine(folder, "logo.jpeg"), first);
        Assert.Equal(Path.Combine(folder, "logo 2.jpeg"), second);
        var decoded = Decode(first);
        Assert.Equal((64, 48), (decoded.PixelWidth, decoded.PixelHeight));
        Assert.True(File.Exists(png), "l'original reste en place");
    }

    [Fact]
    public void CompressesLargeImagesAndSkipsUselessResults()
    {
        var photo = MakeImage("photo.png", 3000, 2000, noise: true);
        var compressed = Sta(() => converter.Perform(Action(WheelKind.Tools, "compress", photo), [photo])).Single();
        Assert.Equal(Path.Combine(folder, "photo (compressé).jpeg"), compressed);
        Assert.True(new FileInfo(compressed).Length < new FileInfo(photo).Length);
        Assert.Equal(2560, Decode(compressed).PixelWidth);

        // Un PNG minuscule : le JPEG, avec ses en-têtes, serait plus lourd. Rien n'est créé.
        var tiny = MakeImage("tiny.png", 8, 8);
        Assert.Empty(Sta(() => converter.Perform(Action(WheelKind.Tools, "compress", tiny), [tiny])));
    }

    [Fact]
    public void StripsMetadataFromImagesAndPdfs()
    {
        var jpeg = MakeImage("vacances.jpg", 40, 30);
        var clean = Sta(() => converter.Perform(Action(WheelKind.Tools, "strip_metadata", jpeg), [jpeg])).Single();
        Assert.Equal(Path.Combine(folder, "vacances (sans métadonnées).jpeg"), clean);

        var pdf = Path.Combine(folder, "rapport.pdf");
        using (var document = new SharpPdf())
        {
            document.AddPage();
            document.Info.Author = "Camille Martin";
            document.Save(pdf);
        }
        var cleanPdf = Sta(() => converter.Perform(Action(WheelKind.Tools, "strip_metadata", pdf), [pdf])).Single();
        using var reread = PdfReader.Open(cleanPdf, PdfDocumentOpenMode.Import);
        Assert.Equal("", reread.Info.Author);
    }

    [Fact]
    public void MergesPdfsAndImagesInDragOrder()
    {
        var pdf = Path.Combine(folder, "devis.pdf");
        using (var document = new SharpPdf())
        {
            document.AddPage();
            document.AddPage();
            document.Save(pdf);
        }
        var image = MakeImage("signature.png", 120, 60, alpha: true);
        var action = Action(WheelKind.Conversion, "merge_pdf", pdf, image);

        var merged = Sta(() => converter.Perform(action, [pdf, image])).Single();

        Assert.Equal(Path.Combine(folder, "devis (fusion).pdf"), merged);
        using var result = PdfReader.Open(merged, PdfDocumentOpenMode.Import);
        Assert.Equal(3, result.PageCount);
        Assert.Equal(XUnit.FromPoint(90).Point, result.Pages[2].Width.Point, 1); // 120 px à 96 ppp
    }

    [Fact]
    public void RendersEachPdfPageAsAnImage()
    {
        var pdf = Path.Combine(folder, "plan.pdf");
        using (var document = new SharpPdf())
        {
            for (var index = 0; index < 2; index++)
            {
                var page = document.AddPage();
                page.Width = XUnit.FromPoint(288); // 4 pouces
                page.Height = XUnit.FromPoint(144);
            }
            document.Save(pdf);
        }
        var pages = Sta(() => converter.Perform(Action(WheelKind.Conversion, "render_pages:png", pdf), [pdf]));

        Assert.Equal([Path.Combine(folder, "plan-p1.png"), Path.Combine(folder, "plan-p2.png")], pages);
        Assert.Equal(600, Decode(pages[0]).PixelWidth); // 4 pouces à 150 ppp
    }

    [Fact]
    public void ExtractsTextFromOfficeDocuments()
    {
        var docx = Path.Combine(folder, "lettre.docx");
        using (var archive = ZipFile.Open(docx, ZipArchiveMode.Create))
        using (var writer = new StreamWriter(archive.CreateEntry("word/document.xml").Open()))
        {
            writer.Write("""
                <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
                <w:p><w:r><w:t>Bonjour</w:t></w:r><w:r><w:tab/><w:t xml:space="preserve">Camille</w:t></w:r></w:p>
                <w:p><w:r><w:t>À bientôt</w:t></w:r></w:p>
                </w:body></w:document>
                """);
        }
        var rtf = Path.Combine(folder, "note.rtf");
        File.WriteAllText(rtf, @"{\rtf1\ansi Premi\'e8re ligne\par Seconde ligne}");

        var docxText = Sta(() => converter.Perform(Action(WheelKind.Tools, "extract_text", docx), [docx])).Single();
        var rtfText = Sta(() => converter.Perform(Action(WheelKind.Tools, "extract_text", rtf), [rtf])).Single();

        Assert.Equal("Bonjour\tCamille\nÀ bientôt", File.ReadAllText(docxText));
        Assert.Equal(Path.Combine(folder, "note.txt"), rtfText);
        Assert.Contains("Première ligne", File.ReadAllText(rtfText));
    }

    [Fact]
    public void WheelOffersOnlyWhatWindowsCanDo()
    {
        var jpeg = FileActionCatalog.InputForPath("photo.jpg");
        var titles = FileActionCatalog.Actions(WheelKind.Conversion, [jpeg], WindowsFileConverter.Abilities).Select(a => a.Title);
        Assert.Equal(["PNG", "TIFF", "GIF", "BMP", "PDF"], titles);
    }
}
