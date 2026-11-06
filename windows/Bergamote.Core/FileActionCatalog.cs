using System.Text.Json;
using System.Text.Json.Serialization;

namespace Bergamote.Core;

public enum FileCategory { Image, Pdf, Text, Other }

public enum FileOperation
{
    ConvertImages,
    RenderPages,
    TextToPdf,
    ConvertText,
    ExtractText,
    MakeSearchable,
    Compress,
    StripMetadata,
    MergePdf,
}

/// <summary>Un fichier glissé : sa catégorie et un identifiant de format (png, jpeg, pdf, txt…).</summary>
public sealed record FileInput(FileCategory Category, string Format);

/// <summary>
/// Une part du camembert. <c>Icon</c> est un nom abstrait (photo, document, compress…) que l'app
/// traduit dans sa police d'icônes ; <c>Format</c> est le format produit, s'il y en a un.
/// </summary>
public sealed record FileAction(string Id, string Title, string Icon, FileOperation Operation, string? Format);

/// <summary>
/// Ce que l'app sait faire : formats d'image qu'elle peut écrire et opérations disponibles
/// (null : toutes). Une part que l'app ne saurait pas exécuter n'apparaît pas.
/// </summary>
public sealed record PlatformAbilities(IReadOnlyList<string> Writable, IReadOnlyList<string>? Capabilities);

/// <summary>Les parts proposées selon le camembert et les fichiers glissés (core/src/catalog.rs).</summary>
public static class FileActionCatalog
{
    public const int MaximumSlices = 8;

    internal static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) },
    };

    private sealed record Request(
        byte Kind, IReadOnlyList<FileInput> Inputs, bool Common,
        IReadOnlyList<string> Writable, IReadOnlyList<string>? Capabilities);

    public static IReadOnlyList<FileAction> Actions(WheelKind kind, IEnumerable<FileInput> inputs, PlatformAbilities platform) =>
        Catalog(new Request((byte)kind, inputs.ToList(), false, platform.Writable, platform.Capabilities));

    /// <summary>Actions proposées quand les fichiers glissés ne sont pas encore connus.</summary>
    public static IReadOnlyList<FileAction> CommonActions(WheelKind kind, PlatformAbilities platform) =>
        Catalog(new Request((byte)kind, [], true, platform.Writable, platform.Capabilities));

    /// <summary>Catégorie et format d'après l'extension (« .JPG » donne image/jpeg).</summary>
    public static FileInput InputForExtension(string extension)
    {
        var json = NativeMethods.Take(NativeMethods.bgm_input_for_extension(extension));
        return (json is null ? null : JsonSerializer.Deserialize<FileInput>(json, Json))
            ?? new FileInput(FileCategory.Other, extension);
    }

    public static FileInput InputForPath(string path) => InputForExtension(Path.GetExtension(path));

    private static IReadOnlyList<FileAction> Catalog(Request request)
    {
        var json = NativeMethods.Take(NativeMethods.bgm_catalog(JsonSerializer.Serialize(request, Json)));
        return json is null ? [] : JsonSerializer.Deserialize<List<FileAction>>(json, Json) ?? [];
    }
}
