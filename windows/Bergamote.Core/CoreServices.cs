using System.Globalization;
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

/// <summary>Langue de l'app et textes partagés avec le Mac et Linux (core/src/i18n.rs).</summary>
public static class AppLanguage
{
    /// <summary>Réglage « langue du système ».</summary>
    public const string SystemPreference = "system";

    /// <summary>Langues proposées : code et nom, qui ne se traduit pas.</summary>
    public static readonly IReadOnlyList<(string Code, string Name)> Languages = [("fr", "Français"), ("en", "English")];

    /// <summary>Langue retenue pour un réglage (system, fr, en) et une langue du système (fr-FR, en-GB…).</summary>
    public static string Resolve(string preference, string systemLocale) =>
        Marshal.PtrToStringUTF8(NativeMethods.bgm_resolve_language(preference, systemLocale)) ?? "en";

    /// <summary>Applique le réglage au cœur : titres des parts et textes changent aussitôt.</summary>
    public static void Apply(string preference) =>
        NativeMethods.bgm_set_language(Resolve(preference, CultureInfo.CurrentUICulture.Name));

    /// <summary>Code de la langue courante : fr ou en.</summary>
    public static string Current => Marshal.PtrToStringUTF8(NativeMethods.bgm_language()) ?? "fr";

    /// <summary>
    /// Texte d'une clé dans la langue courante, variables remplacées :
    /// <c>Text("error.unreadable", ("name", "photo.png"))</c>. Une clé inconnue est renvoyée telle
    /// quelle, pour qu'un oubli se voie.
    /// </summary>
    public static string Text(string key, params (string Name, string Value)[] values)
    {
        var text = NativeMethods.Take(NativeMethods.bgm_text(key)) ?? key;
        foreach (var (name, value) in values) text = text.Replace("{" + name + "}", value);
        return text;
    }
}
