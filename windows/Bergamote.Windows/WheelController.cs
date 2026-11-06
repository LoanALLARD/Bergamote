using System.Media;
using System.Windows.Threading;
using Bergamote.Core;
using Bergamote.Desktop.Conversion;

namespace Bergamote.Desktop;

/// <summary>
/// Fait apparaître le camembert : on glisse des fichiers depuis l'Explorateur, on tape Maj
/// (convertir) ou Ctrl (outils), et le camembert s'ouvre sous le curseur.
///
/// Détection : relevé à 20 Hz de l'état global (bouton principal, position du curseur, touches de
/// modification). Un glisser commence quand le curseur s'éloigne du point d'appui au-delà du seuil
/// du système ; la décision est prise par le cœur partagé (<see cref="WheelDetector"/>).
/// </summary>
internal sealed class WheelController : IDisposable
{
    private readonly AppSettings settings;
    private readonly WheelDetector detector = new();
    private readonly WheelWindow window = new();
    private readonly DispatcherTimer timer;
    private long dragGeneration;
    private bool wasMouseDown;
    private bool dragCounted;
    private Win32.POINT pressPoint;

    /// <summary>Résultat de la dernière action, repris dans le menu de l'icône.</summary>
    public string? LastResult { get; private set; }
    public event Action<string>? ResultChanged;

    public WheelController(AppSettings settings)
    {
        this.settings = settings;
        timer = new DispatcherTimer(DispatcherPriority.Input) { Interval = TimeSpan.FromMilliseconds(50) };
        timer.Tick += (_, _) => Sample();
        window.FilesEntered += files => Reveal(window.Kind, files, cursor: null);
        window.ActionDropped += Run;
        window.SliceEntered += () =>
        {
            if (settings.Sound) WheelSound.Tick();
        };
        settings.Changed += ApplySettings;
        ApplySettings();
    }

    public void Start() => timer.Start();

    private void ApplySettings()
    {
        detector.SetBindings(settings.Bindings());
        if (!settings.Enabled && window.State is WheelState.Pending or WheelState.Ready) Hide();
    }

    // MARK: Geste

    private void Sample()
    {
        if (!settings.Enabled) return;
        var isMouseDown = GlobalInput.IsPrimaryButtonDown();
        var cursor = GlobalInput.Cursor();
        if (isMouseDown && !wasMouseDown)
        {
            pressPoint = cursor;
            dragCounted = false;
        }
        if (isMouseDown && !dragCounted && GlobalInput.BeyondDragThreshold(pressPoint, cursor))
        {
            dragGeneration++;
            dragCounted = true;
        }
        wasMouseDown = isMouseDown;

        var decision = detector.Update(isMouseDown, dragGeneration, GlobalInput.Modifiers());
        if (decision.ShownKind() is { } kind) Present(kind, cursor);
        else if (decision == WheelDecision.Hide) DismissAfterDrag();
    }

    private void Present(WheelKind kind, Win32.POINT cursor)
    {
        if (window.State is WheelState.Working or WheelState.Done or WheelState.Failed) return;
        if (window.Files is { } files) Reveal(kind, files, cursor);
        else window.ShowPending(kind, cursor);
    }

    /// <summary>Les fichiers sont connus : on dessine les parts qui leur conviennent, sinon on referme.</summary>
    private void Reveal(WheelKind kind, IReadOnlyList<string> files, Win32.POINT? cursor)
    {
        var inputs = files.Select(FileActionCatalog.InputForPath);
        var actions = files.Count == 0 ? [] : FileActionCatalog.Actions(kind, inputs, WindowsFileConverter.Abilities);
        if (actions.Count == 0)
        {
            Hide();
            return;
        }
        window.ShowActions(kind, actions, cursor);
    }

    /// <summary>
    /// Le dépôt arrive au même moment que le relâchement du bouton : on laisse un instant à
    /// l'action pour démarrer, sinon on ferme.
    /// </summary>
    private async void DismissAfterDrag()
    {
        await Task.Delay(250);
        if (window.State is WheelState.Pending or WheelState.Ready) window.HideWheel();
    }

    private void Hide()
    {
        window.HideWheel();
        detector.Dismiss();
    }

    // MARK: Action

    private async void Run(FileAction action, IReadOnlyList<string> files)
    {
        if (window.State != WheelState.Ready || files.Count == 0) return;
        var inputs = files.Select(FileActionCatalog.InputForPath).ToList();
        if (!FileActionCatalog.Actions(window.Kind, inputs, WindowsFileConverter.Abilities).Any(a => a.Operation == action.Operation))
        {
            Finish(WheelState.Failed, $"« {action.Title} » ne s'applique pas à ces fichiers");
            return;
        }
        window.ShowStatus(WheelState.Working, action.Title);
        try
        {
            // Conversion hors du fil de l'interface ; rien ne s'ouvre : le résultat apparaît
            // simplement à côté de l'original.
            var produced = await StaTask.Run(() => new WindowsFileConverter().Perform(action, files));
            Finish(WheelState.Done, WheelTexts.Created(produced.Count));
        }
        catch (Exception error)
        {
            ErrorLog.Write(error);
            Finish(WheelState.Failed, error is ConversionException ? error.Message : $"Échec : {error.Message}");
        }
    }

    /// <summary>Affiche le résultat au centre du camembert, le garde pour le menu, puis referme.</summary>
    private async void Finish(WheelState state, string message)
    {
        window.ShowStatus(state, message);
        LastResult = message;
        ResultChanged?.Invoke(message);
        await Task.Delay(1200);
        Hide();
    }

    public void Dispose()
    {
        timer.Stop();
        window.Close();
        detector.Dispose();
    }
}

/// <summary>Le clic au passage d'une part : le WAV synthétisé par le cœur, chargé une fois.</summary>
internal static class WheelSound
{
    private static readonly Lazy<SoundPlayer> Player = new(() =>
    {
        var player = new SoundPlayer(new MemoryStream(ClickSound.Wav()));
        player.Load();
        return player;
    });

    public static void Tick() => Player.Value.Play();
}

/// <summary>Exécute un travail sur un fil STA dédié (WPF et WIC y sont à l'aise).</summary>
internal static class StaTask
{
    public static Task<T> Run<T>(Func<T> work)
    {
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try { completion.SetResult(work()); }
            catch (Exception error) { completion.SetException(error); }
        })
        { IsBackground = true, Name = "Bergamote conversion" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return completion.Task;
    }
}
