using Bergamote.Core;

namespace Bergamote.Core.Tests;

/// <summary>Le cœur vu depuis .NET : mêmes réponses que pour l'app Mac.</summary>
public class GestureTests
{
    [Fact]
    public void TapDuringDragOpensTheBoundWheel()
    {
        using var detector = new WheelDetector();
        Assert.Equal(WheelDecision.None, detector.Update(false, 0, WheelModifier.None));
        Assert.Equal(WheelDecision.None, detector.Update(true, 0, WheelModifier.None));
        Assert.Equal(WheelDecision.None, detector.Update(true, 1, WheelModifier.None)); // le glisser commence
        Assert.Equal(WheelDecision.ShowConversion, detector.Update(true, 1, WheelModifier.Shift));
        Assert.Equal(WheelKind.Conversion, detector.Visible);
        Assert.Equal(WheelDecision.None, detector.Update(true, 1, WheelModifier.None));
        Assert.Equal(WheelDecision.ShowTools, detector.Update(true, 1, WheelModifier.Control));
        Assert.Equal(WheelDecision.Hide, detector.Update(false, 1, WheelModifier.None));
        Assert.Null(detector.Visible);
    }

    [Fact]
    public void HeldKeyOpensWhenTheDragStarts()
    {
        using var detector = new WheelDetector();
        detector.Update(false, 4, WheelModifier.None);
        Assert.Equal(WheelDecision.None, detector.Update(true, 4, WheelModifier.Shift));
        Assert.Equal(WheelDecision.ShowConversion, detector.Update(true, 5, WheelModifier.Shift));
    }

    [Fact]
    public void KeysWithoutADragDoNothing()
    {
        using var detector = new WheelDetector();
        detector.Update(false, 0, WheelModifier.None);
        Assert.Equal(WheelDecision.None, detector.Update(true, 0, WheelModifier.Shift));
        Assert.Equal(WheelDecision.None, detector.Update(false, 0, WheelModifier.Shift));
    }

    [Fact]
    public void BindingsCanBeChanged()
    {
        using var detector = new WheelDetector(new Dictionary<WheelModifier, WheelKind> { [WheelModifier.Alt] = WheelKind.Tools });
        detector.Update(false, 0, WheelModifier.None);
        detector.Update(true, 1, WheelModifier.None);
        Assert.Equal(WheelDecision.None, detector.Update(true, 1, WheelModifier.Shift));
        Assert.Equal(WheelDecision.ShowTools, detector.Update(true, 1, WheelModifier.Alt));
    }

    [Fact]
    public void SlicesStartAtTheTopAndGoClockwise()
    {
        Assert.Equal(0, WheelGeometry.SliceAt(0, 100, 4, 60, 160));
        Assert.Equal(1, WheelGeometry.SliceAt(100, 0, 4, 60, 160));
        Assert.Equal(2, WheelGeometry.SliceAt(0, -100, 4, 60, 160));
        Assert.Null(WheelGeometry.SliceAt(10, 10, 4, 60, 160));   // trou central
        Assert.Null(WheelGeometry.SliceAt(0, 300, 4, 60, 160));   // hors du disque
        Assert.Equal(Math.PI / 2, WheelGeometry.CenterAngle(1, 4), 6);
    }
}

public class CatalogTests
{
    private static readonly PlatformAbilities Windows = new(
        ["png", "jpeg", "tiff", "gif", "bmp"],
        ["convert_images", "render_pages", "extract_text", "compress", "strip_metadata", "merge_pdf"]);

    private static FileInput Image(string format) => new(FileCategory.Image, format);

    [Fact]
    public void ConversionWheelSkipsTheSourceFormat()
    {
        var actions = FileActionCatalog.Actions(WheelKind.Conversion, [Image("jpeg"), Image("jpeg")], Windows);
        Assert.Equal(["PNG", "TIFF", "GIF", "BMP", "PDF"], actions.Select(a => a.Title));
        Assert.Equal("convert_images:png", actions[0].Id);
        Assert.Equal(FileOperation.ConvertImages, actions[0].Operation);
        Assert.Equal("png", actions[0].Format);
        Assert.Equal(FileOperation.MergePdf, actions[^1].Operation);
    }

    [Fact]
    public void ToolsWheelHidesWhatWindowsCannotDo()
    {
        var images = FileActionCatalog.Actions(WheelKind.Tools, [Image("png"), Image("png")], Windows);
        Assert.Equal(["Compresser", "Anonymiser", "Fusionner", "Texte"], images.Select(a => a.Title));
        var pdf = FileActionCatalog.Actions(WheelKind.Tools, [new FileInput(FileCategory.Pdf, "pdf")], Windows);
        Assert.Equal(["Anonymiser", "Texte"], pdf.Select(a => a.Title));
    }

    [Fact]
    public void PdfPagesBecomeImages()
    {
        var actions = FileActionCatalog.Actions(WheelKind.Conversion, [new FileInput(FileCategory.Pdf, "pdf")], Windows);
        Assert.Equal(["render_pages:png", "render_pages:jpeg", "extract_text"], actions.Select(a => a.Id));
    }

    [Fact]
    public void UnknownFilesGetNoWheel()
    {
        Assert.Empty(FileActionCatalog.Actions(WheelKind.Conversion, [FileActionCatalog.InputForPath(@"C:\Musique\titre.mp3")], Windows));
        Assert.Empty(FileActionCatalog.Actions(WheelKind.Conversion, [], Windows));
    }

    [Fact]
    public void CommonActionsWhenFilesAreNotKnownYet()
    {
        var actions = FileActionCatalog.CommonActions(WheelKind.Conversion, Windows);
        Assert.Equal(["PDF", "PNG", "JPEG", "TXT"], actions.Select(a => a.Title));
    }

    [Fact]
    public void ExtensionsMapToFormats()
    {
        Assert.Equal(Image("jpeg"), FileActionCatalog.InputForExtension(".JPG"));
        Assert.Equal(Image("tiff"), FileActionCatalog.InputForPath("scan.tif"));
        Assert.Equal(new FileInput(FileCategory.Pdf, "pdf"), FileActionCatalog.InputForPath("contrat.pdf"));
        Assert.Equal(FileCategory.Text, FileActionCatalog.InputForPath("notes.docx").Category);
        Assert.Equal(FileCategory.Other, FileActionCatalog.InputForPath("titre.mp3").Category);
    }
}

public class TextAndFileTests
{
    [Fact]
    public void CentreTexts()
    {
        Assert.Equal("Rien à gagner : fichiers déjà optimisés", WheelTexts.Created(0));
        Assert.Equal("1 fichier créé à côté de l'original", WheelTexts.Created(1));
        Assert.Equal("3 fichiers créés à côté des originaux", WheelTexts.Created(3));
        Assert.Equal("3 PNG · 39,7 Mo", WheelTexts.Files(["a.png", "b.PNG", "c.png"], 39_700_000));
        Assert.Equal("2 fichiers", WheelTexts.Files(["a.png", "b.pdf"], null));
    }

    [Fact]
    public void OutputNeverOverwrites()
    {
        var folder = Directory.CreateTempSubdirectory("bergamote-");
        try
        {
            var source = Path.Combine(folder.FullName, "logo.png");
            var first = OutputPath.Unique(source, "", "jpeg");
            Assert.Equal(Path.Combine(folder.FullName, "logo.jpeg"), first);
            File.WriteAllText(first, "x");
            Assert.Equal(Path.Combine(folder.FullName, "logo 2.jpeg"), OutputPath.Unique(source, "", "jpeg"));
            Assert.Equal(Path.Combine(folder.FullName, "logo (compressé).jpeg"), OutputPath.Unique(source, " (compressé)", "jpeg"));
        }
        finally
        {
            folder.Delete(recursive: true);
        }
    }

    [Fact]
    public void ClickIsAShortWav()
    {
        var wav = ClickSound.Wav();
        Assert.Equal(2_690, wav.Length); // 44 octets d'en-tête + 30 ms à 44,1 kHz en 16 bits
        Assert.Equal("RIFF"u8.ToArray(), wav[..4]);
        Assert.Equal("WAVEfmt "u8.ToArray(), wav[8..16]);
    }

    [Fact]
    public void VersionIsReported() => Assert.Matches(@"^\d+\.\d+\.\d+$", CoreLibrary.Version);
}
