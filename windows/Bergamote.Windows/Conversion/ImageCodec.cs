using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Bergamote.Desktop.Conversion;

/// <summary>Lecture et écriture d'images avec WIC (via WPF), sans dépendance externe.</summary>
internal static class ImageCodec
{
    /// <summary>Première image du fichier, redressée selon son orientation EXIF.</summary>
    public static BitmapSource Load(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            var image = Oriented(decoder.Frames[0]);
            image.Freeze();
            return image;
        }
        catch (Exception error) when (error is NotSupportedException or FileFormatException or ArgumentException
                                          or System.Runtime.InteropServices.COMException)
        {
            var extension = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
            var hint = extension switch
            {
                "heic" or "heif" => " : installez « Extensions d'image HEIF » depuis le Microsoft Store",
                "avif" => " : installez « Extension AV1 » depuis le Microsoft Store",
                "webp" => " : installez « Extensions d'image Web » depuis le Microsoft Store",
                _ => "",
            };
            throw new ConversionException($"Impossible de lire « {Path.GetFileName(path)} »{hint}");
        }
    }

    public static void Save(BitmapSource image, string path, string format, double quality)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write);
            Write(image, stream, format, quality);
        }
        catch
        {
            TryDelete(path);
            throw;
        }
    }

    /// <summary>JPEG et BMP n'ont pas de transparence : on aplatit sur du blanc plutôt que sur du noir.</summary>
    public static void Write(BitmapSource image, Stream stream, string format, double quality)
    {
        if (format is "jpeg" or "bmp" && HasAlpha(image)) image = FlattenOnWhite(image);
        BitmapEncoder encoder = format switch
        {
            "png" => new PngBitmapEncoder(),
            "jpeg" => new JpegBitmapEncoder { QualityLevel = Math.Clamp((int)Math.Round(quality * 100), 1, 100) },
            "tiff" => new TiffBitmapEncoder { Compression = TiffCompressOption.Lzw },
            "gif" => new GifBitmapEncoder(),
            "bmp" => new BmpBitmapEncoder(),
            _ => throw new ConversionException($"Windows ne sait pas écrire le format {format.ToUpperInvariant()}"),
        };
        encoder.Frames.Add(BitmapFrame.Create(image));
        encoder.Save(stream);
    }

    public static bool HasAlpha(BitmapSource image)
    {
        var format = image.Format;
        if (format == PixelFormats.Bgra32 || format == PixelFormats.Pbgra32 || format == PixelFormats.Rgba64
            || format == PixelFormats.Prgba64 || format == PixelFormats.Rgba128Float || format == PixelFormats.Prgba128Float)
        {
            return true;
        }
        return image.Palette?.Colors.Any(color => color.A < 0xFF) == true;
    }

    /// <summary>Réduction de qualité (bicubique) pour que le plus grand côté tienne dans <paramref name="maxPixelSize"/>.</summary>
    public static BitmapSource Resize(BitmapSource image, int maxPixelSize)
    {
        var largest = Math.Max(image.PixelWidth, image.PixelHeight);
        if (largest <= maxPixelSize) return image;
        var scale = (double)maxPixelSize / largest;
        var width = Math.Max(1, (int)Math.Round(image.PixelWidth * scale));
        var height = Math.Max(1, (int)Math.Round(image.PixelHeight * scale));
        return Draw(image, width, height, background: null);
    }

    private static BitmapSource FlattenOnWhite(BitmapSource image)
    {
        var flattened = new FormatConvertedBitmap(Draw(image, image.PixelWidth, image.PixelHeight, Brushes.White), PixelFormats.Bgr24, null, 0);
        flattened.Freeze();
        return flattened;
    }

    private static BitmapSource Draw(BitmapSource image, int width, int height, Brush? background)
    {
        var visual = new DrawingVisual();
        RenderOptions.SetBitmapScalingMode(visual, BitmapScalingMode.HighQuality);
        using (var context = visual.RenderOpen())
        {
            var area = new Rect(0, 0, width, height);
            if (background is not null) context.DrawRectangle(background, null, area);
            context.DrawImage(image, area);
        }
        var target = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        target.Render(visual);
        target.Freeze();
        return target;
    }

    /// <summary>Applique l'orientation EXIF (1 à 8) aux pixels.</summary>
    private static BitmapSource Oriented(BitmapFrame frame)
    {
        var orientation = 1;
        try
        {
            if (frame.Metadata is BitmapMetadata metadata && metadata.GetQuery("System.Photo.Orientation") is ushort value)
            {
                orientation = value;
            }
        }
        catch (Exception error) when (error is NotSupportedException or InvalidOperationException or ArgumentException)
        {
            // Format sans métadonnées lisibles : image telle quelle.
        }
        var (angle, mirror) = orientation switch
        {
            2 => (0, true),
            3 => (180, false),
            4 => (180, true),
            5 => (90, true),
            6 => (90, false),
            7 => (270, true),
            8 => (270, false),
            _ => (0, false),
        };
        if (angle == 0 && !mirror) return frame;
        var transform = new TransformGroup();
        if (mirror) transform.Children.Add(new ScaleTransform(-1, 1));
        if (angle != 0) transform.Children.Add(new RotateTransform(angle));
        return new TransformedBitmap(frame, transform);
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
