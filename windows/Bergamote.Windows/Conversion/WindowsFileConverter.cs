using System.Text;
using Bergamote.Core;
using PdfSharp.Drawing;
using PdfSharp.Pdf.IO;
using SharpPdf = PdfSharp.Pdf.PdfDocument;

namespace Bergamote.Desktop.Conversion;

public sealed class ConversionException(string message) : Exception(message);

/// <summary>
/// Les opérations du camembert sous Windows. Les originaux ne sont jamais modifiés : chaque
/// résultat est un nouveau fichier, posé à côté de l'original (ou dans <see cref="OutputDirectory"/>),
/// sans jamais écraser un fichier existant. Mêmes réglages que l'app Mac.
/// </summary>
public sealed class WindowsFileConverter
{
    /// <summary>
    /// Ce que l'app sait faire, déclaré au cœur : il ne propose que ces parts. Les formats écrits
    /// sont ceux des encodeurs livrés avec Windows ; HEIC, WEBP et AVIF restent lisibles si leurs
    /// extensions d'images sont installées.
    /// </summary>
    public static readonly PlatformAbilities Abilities = new(
        ["png", "jpeg", "tiff", "gif", "bmp"],
        ["convert_images", "render_pages", "extract_text", "compress", "strip_metadata", "merge_pdf"]);

    public string? OutputDirectory { get; init; }
    public double ImageQuality { get; init; } = 0.85;
    public double CompressionQuality { get; init; } = 0.6;
    public int CompressionMaxPixelSize { get; init; } = 2560;
    public double RenderDpi { get; init; } = 150;

    /// <summary>Exécute l'action et renvoie les fichiers créés. Une compression qui ne gagne rien ne produit rien.</summary>
    public IReadOnlyList<string> Perform(FileAction action, IReadOnlyList<string> paths)
    {
        if (OutputDirectory is not null) Directory.CreateDirectory(OutputDirectory);
        return action.Operation switch
        {
            FileOperation.ConvertImages => paths.Select(path => ConvertImage(path, FormatOf(action))).ToList(),
            FileOperation.RenderPages => paths.SelectMany(path => RenderPages(path, FormatOf(action))).ToList(),
            FileOperation.ExtractText => paths.Select(ExtractText).ToList(),
            FileOperation.Compress => paths.Select(Compress).OfType<string>().ToList(),
            FileOperation.StripMetadata => paths.Select(StripMetadata).ToList(),
            FileOperation.MergePdf => [MergeIntoPdf(paths)],
            _ => throw new ConversionException($"« {action.Title} » n'est pas encore disponible sur Windows"),
        };
    }

    private static string FormatOf(FileAction action) =>
        action.Format ?? throw new ConversionException($"« {action.Title} » : format de sortie manquant");

    private string Output(string source, string suffix, string extension) =>
        OutputPath.Unique(source, suffix, extension, OutputDirectory);

    // MARK: Images

    public string ConvertImage(string path, string format)
    {
        var image = ImageCodec.Load(path);
        var output = Output(path, "", format);
        ImageCodec.Save(image, output, format, ImageQuality);
        return output;
    }

    /// <summary>Réduit à 2560 px au plus et réencode (JPEG, ou PNG s'il y a de la transparence).</summary>
    public string? Compress(string path)
    {
        if (FileActionCatalog.InputForPath(path).Category == FileCategory.Pdf)
        {
            throw new ConversionException("La compression des PDF n'est pas encore disponible sur Windows");
        }
        var image = ImageCodec.Resize(ImageCodec.Load(path), CompressionMaxPixelSize);
        var format = ImageCodec.HasAlpha(image) ? "png" : "jpeg";
        var output = Output(path, " (compressé)", format);
        ImageCodec.Save(image, output, format, CompressionQuality);
        if (new FileInfo(output).Length >= new FileInfo(path).Length)
        {
            File.Delete(output);
            return null;
        }
        return output;
    }

    /// <summary>
    /// Retire EXIF, GPS, IPTC et XMP en réécrivant l'image ; l'orientation est appliquée aux
    /// pixels pour que la photo reste à l'endroit. Pour un PDF : auteur, titre, métadonnées XMP.
    /// </summary>
    public string StripMetadata(string path)
    {
        var input = FileActionCatalog.InputForPath(path);
        if (input.Category == FileCategory.Pdf)
        {
            var output = Output(path, " (sans métadonnées)", "pdf");
            using var document = PdfFiles.Open(path, PdfDocumentOpenMode.Modify);
            document.Info.Elements.Clear();
            document.Internals.Catalog.Elements.Remove("/Metadata");
            document.Save(output);
            return output;
        }
        var image = ImageCodec.Load(path);
        var format = Abilities.Writable.Contains(input.Format) ? input.Format : ImageCodec.HasAlpha(image) ? "png" : "jpeg";
        var result = Output(path, " (sans métadonnées)", format);
        ImageCodec.Save(image, result, format, quality: 0.95);
        return result;
    }

    // MARK: PDF

    /// <summary>PDF et images assemblés dans l'ordre du glisser, une page par image.</summary>
    public string MergeIntoPdf(IReadOnlyList<string> paths)
    {
        if (paths.Count == 0) throw new ConversionException("Aucun fichier à fusionner");
        using var merged = new SharpPdf();
        foreach (var path in paths)
        {
            switch (FileActionCatalog.InputForPath(path).Category)
            {
                case FileCategory.Pdf:
                    using (var source = PdfFiles.Open(path, PdfDocumentOpenMode.Import))
                    {
                        foreach (var page in source.Pages) merged.AddPage(page);
                    }
                    break;
                case FileCategory.Image:
                    AddImagePage(merged, path);
                    break;
                default:
                    throw new ConversionException($"« {Path.GetFileName(path)} » ne peut pas être ajouté à un PDF");
            }
        }
        var output = Output(paths[0], paths.Count > 1 ? " (fusion)" : "", "pdf");
        merged.Save(output);
        return output;
    }

    private void AddImagePage(SharpPdf document, string path)
    {
        // Image redressée et réencodée par WPF : tous les formats lisibles par Windows passent.
        var image = ImageCodec.Load(path);
        using var stream = new MemoryStream();
        ImageCodec.Write(image, stream, ImageCodec.HasAlpha(image) ? "png" : "jpeg", ImageQuality);
        stream.Position = 0;
        using var picture = XImage.FromStream(stream);
        var page = document.AddPage();
        page.Width = XUnit.FromPoint(picture.PointWidth);
        page.Height = XUnit.FromPoint(picture.PointHeight);
        using var graphics = XGraphics.FromPdfPage(page);
        graphics.DrawImage(picture, 0, 0, picture.PointWidth, picture.PointHeight);
    }

    /// <summary>Chaque page en image, 150 ppp ; « -p2 », « -p3 »… quand il y a plusieurs pages.</summary>
    public IReadOnlyList<string> RenderPages(string path, string format)
    {
        var document = PdfRendering.Open(path);
        var outputs = new List<string>();
        for (uint index = 0; index < document.PageCount; index++)
        {
            var image = PdfRendering.Render(document, index, RenderDpi);
            var output = Output(path, document.PageCount > 1 ? $"-p{index + 1}" : "", format);
            ImageCodec.Save(image, output, format, ImageQuality);
            outputs.Add(output);
        }
        return outputs;
    }

    // MARK: Texte

    public string ExtractText(string path)
    {
        var text = TextExtraction.Text(path);
        var output = Output(path, "", "txt");
        File.WriteAllText(output, text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        return output;
    }
}

internal static class PdfFiles
{
    public static SharpPdf Open(string path, PdfDocumentOpenMode mode)
    {
        try
        {
            return PdfReader.Open(path, mode);
        }
        catch (Exception error) when (error is not ConversionException)
        {
            throw new ConversionException($"Impossible d'ouvrir « {Path.GetFileName(path)} » ({error.Message})");
        }
    }
}
