using System.Runtime.InteropServices;
using System.Text.Json;

namespace Bergamote.Core;

public static class CoreLibrary
{
    public static string Version => Marshal.PtrToStringUTF8(NativeMethods.bgm_core_version()) ?? "";
}

/// <summary>Textes affichés au centre du camembert, identiques sur Mac et Windows.</summary>
public static class WheelTexts
{
    /// <summary>« 1 fichier créé à côté de l'original », « Rien à gagner… ».</summary>
    public static string Created(int count) =>
        NativeMethods.Take(NativeMethods.bgm_created_summary((uint)Math.Max(count, 0))) ?? "";

    /// <summary>« 3 PNG · 39,7 Mo » ; la taille est omise si elle est inconnue.</summary>
    public static string Files(IEnumerable<string> paths, long? totalBytes)
    {
        var extensions = paths.Select(path => Path.GetExtension(path).TrimStart('.')).ToList();
        var json = JsonSerializer.Serialize(extensions);
        return NativeMethods.Take(NativeMethods.bgm_files_summary(json, totalBytes ?? -1)) ?? "";
    }
}

public static class OutputPath
{
    /// <summary>
    /// <c>nom.ext</c>, puis <c>nom 2.ext</c>, <c>nom 3.ext</c>… à côté de l'original (ou dans
    /// <paramref name="outputDirectory"/>) : on n'écrase jamais rien.
    /// </summary>
    public static string Unique(string source, string suffix, string extension, string? outputDirectory = null) =>
        NativeMethods.Take(NativeMethods.bgm_unique_output_path(source, suffix, extension, outputDirectory))
        ?? Path.ChangeExtension(source, extension);
}

/// <summary>Le « tic » joué au passage d'une part : fichier WAV synthétisé par le cœur.</summary>
public static class ClickSound
{
    public static byte[] Wav()
    {
        var bytes = NativeMethods.bgm_click_wav(out var length);
        if (bytes == IntPtr.Zero) return [];
        try
        {
            var data = new byte[(int)length];
            Marshal.Copy(bytes, data, 0, data.Length);
            return data;
        }
        finally
        {
            NativeMethods.bgm_bytes_free(bytes, length);
        }
    }
}
