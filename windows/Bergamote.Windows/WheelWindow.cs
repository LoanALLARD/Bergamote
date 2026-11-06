using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using Bergamote.Core;

namespace Bergamote.Desktop;

internal enum WheelState
{
    Hidden,
    /// <summary>Ouvert mais invisible : on attend que le glisser entre pour connaître les fichiers.</summary>
    Pending,
    Ready,
    Working,
    Done,
    Failed,
}

/// <summary>
/// Le camembert : des parts en anneau autour d'un centre qui résume les fichiers. C'est aussi la
/// cible du dépôt : la part visée suit le curseur, et lâcher les fichiers lance l'action.
///
/// Sous Windows, les fichiers d'un glisser ne sont lisibles qu'une fois le curseur sur notre
/// fenêtre : elle s'ouvre donc d'abord invisible sous le curseur (état Pending), puis se dessine
/// dès que le glisser y entre avec des fichiers. Un glisser sans fichiers (texte, fenêtre
/// déplacée) ne fait ainsi jamais apparaître de camembert.
/// </summary>
internal sealed class WheelWindow : Window
{
    public const double Diameter = 340;
    public const double OuterRadius = 160;
    public const double InnerRadius = 62;

    private readonly Canvas canvas = new() { Width = Diameter, Height = Diameter };
    private int? highlighted;
    private string message = "";
    private string summary = "";

    public WheelState State { get; private set; } = WheelState.Hidden;
    public WheelKind Kind { get; private set; } = WheelKind.Conversion;
    /// <summary>Fichiers du glisser en cours, connus une fois qu'il est entré dans la fenêtre.</summary>
    public IReadOnlyList<string>? Files { get; private set; }
    public IReadOnlyList<FileAction> Actions { get; private set; } = [];

    public event Action<IReadOnlyList<string>>? FilesEntered;
    public event Action<FileAction, IReadOnlyList<string>>? ActionDropped;
    public event Action? SliceEntered;

    public WheelWindow()
    {
        Title = "Bergamote";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        Focusable = false;
        AllowDrop = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Width = Diameter;
        Height = Diameter;
        Left = -32000;
        Top = -32000;
        Content = canvas;
        SourceInitialized += (_, _) => MakeNonActivating();
    }

    public void ShowPending(WheelKind kind, Win32.POINT cursor)
    {
        Kind = kind;
        Actions = [];
        State = WheelState.Pending;
        highlighted = null;
        Render();
        Place(cursor);
    }

    public void ShowActions(WheelKind kind, IReadOnlyList<FileAction> actions, Win32.POINT? cursor)
    {
        Kind = kind;
        Actions = actions;
        State = WheelState.Ready;
        highlighted = null;
        Render();
        if (cursor is { } point) Place(point);
    }

    public void ShowStatus(WheelState state, string text)
    {
        State = state;
        message = text;
        highlighted = null;
        Render();
    }

    public void HideWheel()
    {
        Hide();
        State = WheelState.Hidden;
        Files = null;
        Actions = [];
        highlighted = null;
    }

    // MARK: Position

    /// <summary>Centre la fenêtre sur le curseur, sans déborder de l'écran ni de la barre des tâches.</summary>
    private void Place(Win32.POINT cursor)
    {
        if (!IsVisible) Show();
        var handle = new WindowInteropHelper(this).Handle;
        var (work, scale) = Win32.Screen(cursor);
        var size = (int)Math.Round(Diameter * scale);
        var x = Math.Clamp(cursor.X - size / 2, work.Left, Math.Max(work.Left, work.Right - size));
        var y = Math.Clamp(cursor.Y - size / 2, work.Top, Math.Max(work.Top, work.Bottom - size));
        // Deux passes : en changeant d'écran, WPF s'adapte d'abord à la nouvelle échelle.
        for (var pass = 0; pass < 2; pass++)
        {
            Win32.SetWindowPos(handle, Win32.HWND_TOPMOST, x, y, size, size, Win32.SWP_NOACTIVATE | Win32.SWP_SHOWWINDOW);
        }
    }

    /// <summary>Ne prend jamais le focus et n'apparaît pas dans Alt+Tab.</summary>
    private void MakeNonActivating()
    {
        var handle = new WindowInteropHelper(this).Handle;
        var style = Win32.GetWindowLong(handle, Win32.GWL_EXSTYLE);
        Win32.SetWindowLong(handle, Win32.GWL_EXSTYLE, style | Win32.WS_EX_NOACTIVATE | Win32.WS_EX_TOOLWINDOW);
    }

    // MARK: Dépôt

    protected override void OnDragEnter(DragEventArgs e)
    {
        base.OnDragEnter(e);
        if (State is WheelState.Pending or WheelState.Ready)
        {
            var files = DroppedFiles(e.Data);
            if (Files is null || !Files.SequenceEqual(files))
            {
                Files = files;
                summary = WheelTexts.Files(files, TotalSize(files));
                FilesEntered?.Invoke(files);
            }
        }
        Track(e);
    }

    protected override void OnDragOver(DragEventArgs e)
    {
        base.OnDragOver(e);
        Track(e);
    }

    protected override void OnDragLeave(DragEventArgs e)
    {
        base.OnDragLeave(e);
        if (highlighted is not null)
        {
            highlighted = null;
            Render();
        }
        e.Handled = true;
    }

    protected override void OnDrop(DragEventArgs e)
    {
        base.OnDrop(e);
        var slice = State == WheelState.Ready ? SliceAt(e.GetPosition(canvas)) : null;
        var files = Files ?? [];
        e.Effects = slice is null || files.Count == 0 ? DragDropEffects.None : DragDropEffects.Copy;
        e.Handled = true;
        if (slice is int index && files.Count > 0)
        {
            var action = Actions[index];
            // On rend la main à l'Explorateur tout de suite ; l'action démarre juste après.
            Dispatcher.BeginInvoke(() => ActionDropped?.Invoke(action, files));
        }
    }

    /// <summary>
    /// Toujours une copie : l'original reste en place, même si Maj (qui signifie « déplacer »
    /// dans l'Explorateur) est enfoncée.
    /// </summary>
    private void Track(DragEventArgs e)
    {
        int? slice = State == WheelState.Ready ? SliceAt(e.GetPosition(canvas)) : null;
        if (slice != highlighted)
        {
            highlighted = slice;
            Render();
            if (slice is not null) SliceEntered?.Invoke();
        }
        e.Effects = slice is null ? DragDropEffects.None : DragDropEffects.Copy & e.AllowedEffects;
        e.Handled = true;
    }

    private int? SliceAt(Point point) =>
        WheelGeometry.SliceAt(point.X - Diameter / 2, Diameter / 2 - point.Y, Actions.Count, InnerRadius, OuterRadius);

    private static IReadOnlyList<string> DroppedFiles(IDataObject data)
    {
        try
        {
            return data.GetDataPresent(DataFormats.FileDrop) && data.GetData(DataFormats.FileDrop) is string[] paths ? paths : [];
        }
        catch (Exception error) when (error is System.Runtime.InteropServices.COMException or OutOfMemoryException)
        {
            return [];
        }
    }

    /// <summary>Taille totale, ou null si un fichier n'est pas lisible.</summary>
    private static long? TotalSize(IReadOnlyList<string> files)
    {
        try
        {
            return files.Sum(file => new FileInfo(file).Length);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    // MARK: Dessin

    private void Render()
    {
        canvas.Children.Clear();
        if (State == WheelState.Pending)
        {
            // Presque transparent mais pas tout à fait : la fenêtre reste une cible de dépôt.
            canvas.Children.Add(Disk(OuterRadius, Palette.HitArea));
            return;
        }

        var disk = Disk(OuterRadius, Palette.Disk);
        disk.Stroke = Palette.Rim;
        disk.StrokeThickness = 1;
        disk.Effect = new DropShadowEffect { BlurRadius = 24, ShadowDepth = 6, Direction = 270, Opacity = 0.3, Color = Colors.Black };
        canvas.Children.Add(disk);

        const double center = Diameter / 2;
        for (var index = 0; index < Actions.Count; index++)
        {
            var lit = highlighted == index;
            canvas.Children.Add(new System.Windows.Shapes.Path
            {
                Data = SliceGeometry(index, Actions.Count, InnerRadius + 6, OuterRadius - 6),
                Fill = lit ? Palette.Accent : Palette.Slice,
            });
            var angle = WheelGeometry.CenterAngle(index, Actions.Count);
            var radius = (InnerRadius + OuterRadius) / 2 + 4;
            Place(SliceLabel(Actions[index], lit), center + Math.Sin(angle) * radius, center - Math.Cos(angle) * radius);
        }

        canvas.Children.Add(Disk(InnerRadius - 4, Palette.Centre));
        Place(CentreLabel(), center, center);
    }

    private static Ellipse Disk(double radius, Brush fill)
    {
        var disk = new Ellipse { Width = radius * 2, Height = radius * 2, Fill = fill };
        Canvas.SetLeft(disk, Diameter / 2 - radius);
        Canvas.SetTop(disk, Diameter / 2 - radius);
        return disk;
    }

    /// <summary>Ajoute un élément centré sur (x, y).</summary>
    private void Place(FrameworkElement element, double x, double y)
    {
        element.IsHitTestVisible = false;
        element.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        Canvas.SetLeft(element, x - element.DesiredSize.Width / 2);
        Canvas.SetTop(element, y - element.DesiredSize.Height / 2);
        canvas.Children.Add(element);
    }

    /// <summary>Secteur d'anneau, part 0 centrée en haut puis sens horaire (y vers le bas).</summary>
    private static Geometry SliceGeometry(int index, int count, double inner, double outer)
    {
        const double center = Diameter / 2;
        if (count <= 1)
        {
            return new CombinedGeometry(
                GeometryCombineMode.Exclude,
                new EllipseGeometry(new Point(center, center), outer, outer),
                new EllipseGeometry(new Point(center, center), inner, inner));
        }
        var width = 2 * Math.PI / count;
        const double gap = 0.025;
        var start = WheelGeometry.CenterAngle(index, count) - width / 2 + gap;
        var end = start + width - 2 * gap;
        static Point At(double radius, double angle) =>
            new(center + Math.Sin(angle) * radius, center - Math.Cos(angle) * radius);
        var large = end - start > Math.PI;
        var figure = new PathFigure { StartPoint = At(outer, start), IsClosed = true, IsFilled = true };
        figure.Segments.Add(new ArcSegment(At(outer, end), new Size(outer, outer), 0, large, SweepDirection.Clockwise, true));
        figure.Segments.Add(new LineSegment(At(inner, end), true));
        figure.Segments.Add(new ArcSegment(At(inner, start), new Size(inner, inner), 0, large, SweepDirection.Counterclockwise, true));
        var geometry = new PathGeometry([figure]);
        geometry.Freeze();
        return geometry;
    }

    private static FrameworkElement SliceLabel(FileAction action, bool lit)
    {
        var brush = lit ? Brushes.White : Palette.Text;
        var panel = new StackPanel { Width = 78 };
        panel.Children.Add(new TextBlock
        {
            Text = Icons.Glyph(action.Icon),
            FontFamily = Icons.Font,
            FontSize = 18,
            Foreground = brush,
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        panel.Children.Add(new TextBlock
        {
            Text = action.Title.ToUpperInvariant(),
            FontSize = 10.5,
            FontWeight = FontWeights.SemiBold,
            Foreground = brush,
            HorizontalAlignment = HorizontalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(0, 5, 0, 0),
        });
        return panel;
    }

    private FrameworkElement CentreLabel()
    {
        var panel = new StackPanel { Width = (InnerRadius - 4) * 2 - 18 };
        TextBlock Line(string text, double size, FontWeight weight, Brush brush) => new()
        {
            Text = text,
            FontSize = size,
            FontWeight = weight,
            Foreground = brush,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        TextBlock Glyph(string glyph, Brush brush) => new()
        {
            Text = glyph,
            FontFamily = Icons.Font,
            FontSize = 22,
            Foreground = brush,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 4),
        };

        switch (State)
        {
            case WheelState.Working:
                panel.Children.Add(new ProgressBar { IsIndeterminate = true, Width = 56, Height = 4, Margin = new Thickness(0, 0, 0, 6) });
                panel.Children.Add(Line(message, 10.5, FontWeights.SemiBold, Palette.Text));
                break;
            case WheelState.Done:
                panel.Children.Add(Glyph(Icons.Done, Palette.Success));
                panel.Children.Add(Line(message, 9.5, FontWeights.Normal, Palette.Text));
                break;
            case WheelState.Failed:
                panel.Children.Add(Glyph(Icons.Warning, Palette.Warning));
                panel.Children.Add(Line(message, 9.5, FontWeights.Normal, Palette.Text));
                break;
            default:
                panel.Children.Add(Line(Kind.Title().ToUpperInvariant(), 9, FontWeights.Bold, Palette.Secondary));
                panel.Children.Add(Line(summary, 11.5, FontWeights.SemiBold, Palette.Text));
                break;
        }
        return panel;
    }
}

/// <summary>Couleurs du camembert : sombre et translucide, la part visée à la couleur d'accent.</summary>
internal static class Palette
{
    public static readonly Brush Disk = Frozen(Color.FromArgb(0xEB, 0x20, 0x20, 0x20));
    public static readonly Brush Rim = Frozen(Color.FromArgb(0x59, 0xFF, 0xFF, 0xFF));
    public static readonly Brush Slice = Frozen(Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF));
    public static readonly Brush Centre = Frozen(Color.FromArgb(0xFF, 0x2A, 0x2A, 0x2A));
    public static readonly Brush Text = Frozen(Color.FromArgb(0xE6, 0xFF, 0xFF, 0xFF));
    public static readonly Brush Secondary = Frozen(Color.FromArgb(0x8C, 0xFF, 0xFF, 0xFF));
    public static readonly Brush Success = Frozen(Color.FromRgb(0x34, 0xC7, 0x59));
    public static readonly Brush Warning = Frozen(Color.FromRgb(0xFF, 0x9F, 0x0A));
    public static readonly Brush HitArea = Frozen(Color.FromArgb(0x01, 0x00, 0x00, 0x00));
    public static readonly Brush Accent = Frozen(AccentColor());

    private static Brush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    /// <summary>Couleur d'accent choisie dans les réglages de Windows.</summary>
    private static Color AccentColor()
    {
        try
        {
            var accent = new global::Windows.UI.ViewManagement.UISettings()
                .GetColorValue(global::Windows.UI.ViewManagement.UIColorType.Accent);
            return Color.FromArgb(0xFF, accent.R, accent.G, accent.B);
        }
        catch (Exception)
        {
            return Color.FromRgb(0x2F, 0x6B, 0xD6);
        }
    }
}

/// <summary>Icônes abstraites du cœur → glyphes Segoe Fluent Icons (Segoe MDL2 Assets sous Windows 10).</summary>
internal static class Icons
{
    public static readonly FontFamily Font = new("Segoe Fluent Icons, Segoe MDL2 Assets");
    public const string Done = "";
    public const string Warning = "";

    public static string Glyph(string icon) => icon switch
    {
        "photo" => "",
        "pages" => "",
        "document" => "",
        "text" => "",
        "word" => "",
        "rich_text" => "",
        "compress" => "",
        "anonymize" => "",
        "searchable" => "",
        "merge" => "",
        "extract" => "",
        _ => "",
    };
}
