using System.Windows.Media.Imaging;
using Windows.Data.Pdf;
using Windows.Storage;
using Windows.Storage.Streams;

namespace Bergamote.Desktop.Conversion;

/// <summary>Rendu des pages PDF avec le moteur de Windows (Windows.Data.Pdf).</summary>
internal static class PdfRendering
{
    public static PdfDocument Open(string path)
    {
        try
        {
            var file = StorageFile.GetFileFromPathAsync(Path.GetFullPath(path)).AsTask().GetAwaiter().GetResult();
            return PdfDocument.LoadFromFileAsync(file).AsTask().GetAwaiter().GetResult();
        }
        catch (Exception error)
        {
            throw new ConversionException($"Impossible d'ouvrir « {Path.GetFileName(path)} » ({error.Message})");
        }
    }

    /// <summary>Page sur fond blanc, à la résolution demandée (points par pouce).</summary>
    public static BitmapSource Render(PdfDocument document, uint index, double dpi)
    {
        using var page = document.GetPage(index);
        // La taille de la page est donnée en pixels indépendants (1/96 de pouce).
        var options = new PdfPageRenderOptions
        {
            DestinationWidth = (uint)Math.Max(1, Math.Round(page.Size.Width * dpi / 96)),
            DestinationHeight = (uint)Math.Max(1, Math.Round(page.Size.Height * dpi / 96)),
        };
        using var stream = new InMemoryRandomAccessStream();
        page.RenderToStreamAsync(stream, options).AsTask().GetAwaiter().GetResult();
        stream.Seek(0);
        using var managed = stream.AsStreamForRead();
        var decoder = BitmapDecoder.Create(managed, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        var image = decoder.Frames[0];
        image.Freeze();
        return image;
    }
}
