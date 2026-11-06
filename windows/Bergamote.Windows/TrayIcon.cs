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
    private readonly Drawing.Icon image;

    public TrayIcon(AppSettings settings, WheelController controller, Action openSettings, Action quit)
    {
        this.settings = settings;
        enabledItem = new Forms.ToolStripMenuItem("Activer le camembert") { CheckOnClick = true, Checked = settings.Enabled };
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
            new Forms.ToolStripMenuItem("Glissez des fichiers, puis tapez :") { Enabled = false },
            conversionHint,
            toolsHint,
            resultItem,
            new Forms.ToolStripSeparator(),
            new Forms.ToolStripMenuItem("Réglages…", null, (_, _) => openSettings()),
            new Forms.ToolStripMenuItem("Quitter", null, (_, _) => quit()),
        ]);

        image = MakeIcon();
        icon = new Forms.NotifyIcon { Icon = image, Text = "Bergamote", ContextMenuStrip = menu, Visible = true };
        icon.DoubleClick += (_, _) => openSettings();

        settings.Changed += Refresh;
        controller.ResultChanged += result =>
        {
            resultItem.Text = $"Dernier résultat : {result}";
            resultItem.Visible = true;
        };
        Refresh();
    }

    public void ShowWelcome() => icon.ShowBalloonTip(
        6000, "Bergamote est prêt",
        $"Glissez des fichiers depuis l'Explorateur, puis tapez {GlobalInput.Name(settings.ConversionKey)} pour convertir "
        + $"ou {GlobalInput.Name(settings.ToolsKey)} pour les outils.",
        Forms.ToolTipIcon.None);

    private void Refresh()
    {
        enabledItem.Checked = settings.Enabled;
        conversionHint.Text = $"    {GlobalInput.Name(settings.ConversionKey)} : convertir (PNG, JPEG, PDF…)";
        toolsHint.Text = $"    {GlobalInput.Name(settings.ToolsKey)} : outils (compresser, anonymiser…)";
    }

    /// <summary>Un camembert monochrome, blanc sur barre des tâches sombre, noir sur claire.</summary>
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
            graphics.FillPie(brush, 3, 5, 24, 24, -45, 270);   // le camembert, une part en moins
            graphics.FillPie(brush, 6, 1, 24, 24, -90, 45);    // la part détachée
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
