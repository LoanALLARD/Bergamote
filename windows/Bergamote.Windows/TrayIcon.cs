using Bergamote.Core;
using Microsoft.Win32;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace Bergamote.Desktop;

/// <summary>
/// L'icône de la zone de notification : rappel du geste, interrupteur, dernier résultat,
/// réglages. C'est la seule présence de l'app à l'écran.
/// </summary>
internal sealed class TrayIcon : IDisposable
{
    private readonly AppSettings settings;
    private readonly Forms.NotifyIcon icon;
    private readonly Forms.ToolStripMenuItem enabledItem;
    private readonly Forms.ToolStripMenuItem conversionHint = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem toolsHint = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem resultItem = new() { Enabled = false, Visible = false };
    private readonly Forms.ToolStripMenuItem hintItem = new() { Enabled = false };
    private readonly Forms.ToolStripMenuItem settingsItem = new();
    private readonly Forms.ToolStripMenuItem quitItem = new();
    private string? lastResult;
    private readonly Drawing.Icon image;

    public TrayIcon(AppSettings settings, WheelController controller, Action openSettings, Action quit)
    {
        this.settings = settings;
        enabledItem = new Forms.ToolStripMenuItem { CheckOnClick = true, Checked = settings.Enabled };
        settingsItem.Click += (_, _) => openSettings();
        quitItem.Click += (_, _) => quit();
        enabledItem.CheckedChanged += (_, _) =>
        {
            if (settings.Enabled == enabledItem.Checked) return;
            settings.Enabled = enabledItem.Checked;
            settings.Save();
        };

        var title = new Forms.ToolStripMenuItem("Bergamote") { Enabled = false };
        title.Font = new Drawing.Font(title.Font, Drawing.FontStyle.Bold);
        var menu = new Forms.ContextMenuStrip();
        menu.Items.AddRange(
        [
            title,
            enabledItem,
            new Forms.ToolStripSeparator(),
            hintItem,
            conversionHint,
            toolsHint,
            resultItem,
            new Forms.ToolStripSeparator(),
            settingsItem,
            quitItem,
        ]);

        image = MakeIcon();
        icon = new Forms.NotifyIcon { Icon = image, Text = "Bergamote", ContextMenuStrip = menu, Visible = true };
        icon.DoubleClick += (_, _) => openSettings();

        settings.Changed += Refresh;
        controller.ResultChanged += result =>
        {
            lastResult = result;
            Refresh();
        };
        Refresh();
    }

    public void ShowWelcome() => icon.ShowBalloonTip(
        6000, AppLanguage.Text("welcome.title"),
        AppLanguage.Text(
            "welcome.body", ("source", AppLanguage.Text("source.explorer")),
            ("convert", GlobalInput.Name(settings.ConversionKey)), ("tools", GlobalInput.Name(settings.ToolsKey))),
        Forms.ToolTipIcon.None);

    /// <summary>Remet le menu à jour : réglages, dernier résultat, langue.</summary>
    private void Refresh()
    {
        enabledItem.Checked = settings.Enabled;
        enabledItem.Text = AppLanguage.Text("settings.enable");
        hintItem.Text = AppLanguage.Text("menu.tap_hint");
        conversionHint.Text = "    " + AppLanguage.Text("menu.convert_hint", ("key", GlobalInput.Name(settings.ConversionKey)));
        toolsHint.Text = "    " + AppLanguage.Text("menu.tools_hint", ("key", GlobalInput.Name(settings.ToolsKey)));
        resultItem.Text = AppLanguage.Text("menu.last_result", ("result", lastResult ?? ""));
        resultItem.Visible = lastResult is not null;
        settingsItem.Text = AppLanguage.Text("menu.settings");
        quitItem.Text = AppLanguage.Text("menu.quit");
    }

    /// <summary>
    /// Le logo, « le B en deux parts », d'une seule couleur : blanc sur barre des tâches sombre,
    /// noir sur claire. Même tracé que brand/mark.svg, dans un repère de 100 unités.
    /// </summary>
    private static Drawing.Icon MakeIcon()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        var lightTaskbar = key?.GetValue("SystemUsesLightTheme") is int light && light != 0;
        var color = lightTaskbar ? Drawing.Color.FromArgb(32, 32, 32) : Drawing.Color.White;

        using var bitmap = new Drawing.Bitmap(32, 32);
        using (var graphics = Drawing.Graphics.FromImage(bitmap))
        using (var brush = new Drawing.SolidBrush(color))
        {
            graphics.SmoothingMode = Drawing.Drawing2D.SmoothingMode.AntiAlias;
            graphics.ScaleTransform(0.32f, 0.32f);
            graphics.TranslateTransform(1, -3);
            graphics.FillRectangle(brush, 26, 20, 15, 66);                 // le fût
            graphics.FillRectangle(brush, 46, 20, 7.5f, 28);               // la panse haute…
            graphics.FillPie(brush, 39, 20, 28, 28, -90, 180);             // …et son demi-disque
            graphics.FillRectangle(brush, 46, 54, 10.5f, 32);              // la panse basse
            graphics.FillPie(brush, 40, 54, 32, 32, -90, 180);
        }
        var handle = bitmap.GetHicon();
        try
        {
            return (Drawing.Icon)Drawing.Icon.FromHandle(handle).Clone();
        }
        finally
        {
            Win32.DestroyIcon(handle);
        }
    }

    public void Dispose()
    {
        icon.Visible = false;
        icon.Dispose();
        image.Dispose();
    }
}
