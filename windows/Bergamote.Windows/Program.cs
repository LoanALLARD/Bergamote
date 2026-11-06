using System.Windows;
using System.Windows.Threading;

namespace Bergamote.Desktop;

public static class Program
{
    [STAThread]
    public static void Main()
    {
        // Une seule instance par session.
        using var instance = new Mutex(initiallyOwned: true, @"Local\Bergamote.Desktop", out var isFirst);
        if (!isFirst) return;
        System.Windows.Forms.Application.EnableVisualStyles();
        new BergamoteApp().Run();
    }
}

/// <summary>Pas de fenêtre principale : l'app vit dans la zone de notification.</summary>
internal sealed class BergamoteApp : Application
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
        controller = new WheelController(settings);
        tray = new TrayIcon(settings, controller, OpenSettings, Shutdown);
        controller.Start();
        if (settings.IsFirstLaunch) tray.ShowWelcome();
    }

    private void OpenSettings()
    {
        if (settingsWindow is null)
        {
            settingsWindow = new SettingsWindow(settings);
            settingsWindow.Closed += (_, _) => settingsWindow = null;
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
