using System.Windows;
using System.Windows.Threading;
using Bergamote.Core;

namespace Bergamote.Desktop;

public static class Program
{
    [STAThread]
    public static void Main()
    {
        // Une seule instance par session. Relancer l'app pendant qu'elle tourne ouvre ses réglages :
        // c'est le moyen de la retrouver si l'icône de la zone de notification est masquée.
        using var instance = new Mutex(initiallyOwned: true, @"Local\Bergamote.Desktop", out var isFirst);
        using var showSettings = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\Bergamote.Desktop.ShowSettings");
        if (!isFirst)
        {
            showSettings.Set();
            return;
        }
        System.Windows.Forms.Application.EnableVisualStyles();
        new BergamoteApp(showSettings).Run();
    }
}

/// <summary>Pas de fenêtre principale : l'app vit dans la zone de notification.</summary>
internal sealed class BergamoteApp(EventWaitHandle showSettings) : Application
{
    private AppSettings settings = null!;
    private WheelController controller = null!;
    private TrayIcon tray = null!;
    private SettingsWindow? settingsWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        DispatcherUnhandledException += OnUnhandledException;

        settings = AppSettings.Load();
        // Avant tout affichage, et avant les autres abonnés : les textes viennent du cœur, dans
        // la langue choisie.
        AppLanguage.Apply(settings.Language);
        settings.Changed += () => AppLanguage.Apply(settings.Language);
        controller = new WheelController(settings);
        tray = new TrayIcon(settings, controller, OpenSettings, Shutdown);
        controller.Start();
        if (settings.IsFirstLaunch) tray.ShowWelcome();

        // Une relance de l'app signale cet événement : on ouvre les réglages.
        new Thread(() =>
        {
            while (showSettings.WaitOne()) Dispatcher.BeginInvoke(OpenSettings);
        })
        { IsBackground = true, Name = "Bergamote relaunch" }.Start();
    }

    private void OpenSettings()
    {
        if (settingsWindow is null)
        {
            settingsWindow = new SettingsWindow(settings);
            settingsWindow.Closed += (_, _) => settingsWindow = null;
            // La fenêtre est reconstruite dans la nouvelle langue.
            settingsWindow.LanguageChanged += () => Dispatcher.BeginInvoke(() =>
            {
                settingsWindow?.Close();
                OpenSettings();
            });
            settingsWindow.Show();
        }
        settingsWindow.Activate();
    }

    /// <summary>Une erreur inattendue est journalisée ; l'app reste dans la zone de notification.</summary>
    private static void OnUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        ErrorLog.Write(e.Exception);
        e.Handled = true;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        tray.Dispose();
        controller.Dispose();
        base.OnExit(e);
    }
}
