namespace Bergamote.Core;

/// <summary>Touches de modification, mêmes bits que le cœur et l'app Mac.</summary>
[Flags]
public enum WheelModifier : uint
{
    None = 0,
    Shift = 1 << 0,
    Control = 1 << 1,
    /// <summary>Alt (Option sur Mac).</summary>
    Alt = 1 << 2,
    /// <summary>Touche Windows (Commande sur Mac).</summary>
    Windows = 1 << 3,
}

/// <summary>Les deux camemberts : un pour convertir, un pour les outils.</summary>
public enum WheelKind : byte
{
    Conversion = 1,
    Tools = 2,
}

public enum WheelDecision
{
    None = 0,
    ShowConversion = 1,
    ShowTools = 2,
    Hide = 3,
}

public static class WheelKindExtensions
{
    public static string Title(this WheelKind kind) => kind == WheelKind.Conversion ? "Convertir" : "Outils";

    public static WheelKind? ShownKind(this WheelDecision decision) => decision switch
    {
        WheelDecision.ShowConversion => WheelKind.Conversion,
        WheelDecision.ShowTools => WheelKind.Tools,
        _ => null,
    };
}

/// <summary>
/// Machine à états du geste : « glisser des fichiers, puis taper une touche de modification ».
/// La logique vit dans le cœur partagé (core/src/detector.rs) ; cette classe lui transmet les
/// échantillons. La génération du glisser change quand un glisser commence.
/// </summary>
public sealed class WheelDetector : IDisposable
{
    private readonly DetectorHandle handle = NativeMethods.bgm_detector_new();

    /// <summary>Raccourcis par défaut de Windows : Maj pour convertir, Ctrl pour les outils.</summary>
    public WheelDetector() : this(new Dictionary<WheelModifier, WheelKind>
    {
        [WheelModifier.Shift] = WheelKind.Conversion,
        [WheelModifier.Control] = WheelKind.Tools,
    })
    { }

    public WheelDetector(IReadOnlyDictionary<WheelModifier, WheelKind> bindings) => SetBindings(bindings);

    public WheelKind? Visible => NativeMethods.bgm_detector_visible(handle) switch
    {
        1 => WheelKind.Conversion,
        2 => WheelKind.Tools,
        _ => null,
    };

    public void SetBindings(IReadOnlyDictionary<WheelModifier, WheelKind> bindings)
    {
        NativeMethods.bgm_detector_clear_bindings(handle);
        foreach (var (modifiers, kind) in bindings)
        {
            NativeMethods.bgm_detector_set_binding(handle, (uint)modifiers, (byte)kind);
        }
    }

    public WheelDecision Update(bool isMouseDown, long dragGeneration, WheelModifier modifiers) =>
        (WheelDecision)NativeMethods.bgm_detector_update(handle, isMouseDown, dragGeneration, (uint)modifiers);

    /// <summary>À appeler quand le camembert se ferme de lui-même (dépôt effectué, Échap).</summary>
    public void Dismiss() => NativeMethods.bgm_detector_dismiss(handle);

    public void Dispose() => handle.Dispose();
}

/// <summary>Géométrie du camembert : la part 0 est centrée en haut, puis sens horaire.</summary>
public static class WheelGeometry
{
    /// <summary>
    /// Part sous le point, exprimé par rapport au centre avec l'axe y vers le haut ; null dans le
    /// trou central ou hors du disque.
    /// </summary>
    public static int? SliceAt(double x, double y, int count, double innerRadius, double outerRadius)
    {
        var index = NativeMethods.bgm_slice_at(x, y, count, innerRadius, outerRadius);
        return index >= 0 ? index : null;
    }

    /// <summary>Angle du milieu de la part, en radians depuis le haut, sens horaire.</summary>
    public static double CenterAngle(int index, int count) => NativeMethods.bgm_center_angle(index, count);
}
