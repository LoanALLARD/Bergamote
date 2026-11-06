using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Bergamote.Core;

namespace Bergamote.Desktop;

/// <summary>Réglages : touches des deux camemberts, clic sonore, lancement à l'ouverture de session.</summary>
internal sealed class SettingsWindow : Window
{
    private static readonly WheelModifier[] Keys = [WheelModifier.Shift, WheelModifier.Control, WheelModifier.Alt];

    private readonly AppSettings settings;
    private readonly TextBlock conflict;

    public SettingsWindow(AppSettings settings)
    {
        this.settings = settings;
        Title = "Réglages de Bergamote";
        SizeToContent = SizeToContent.WidthAndHeight;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontSize = 13;

        var panel = new StackPanel { Margin = new Thickness(22), Width = 440 };

        var enabled = new CheckBox { Content = "Activer le camembert", IsChecked = settings.Enabled, Margin = new Thickness(0, 0, 0, 14) };
        enabled.Click += (_, _) => Update(() => settings.Enabled = enabled.IsChecked == true);
        panel.Children.Add(enabled);

        panel.Children.Add(KeyRow("Camembert de conversion", settings.ConversionKey, key => settings.ConversionKey = key));
        panel.Children.Add(KeyRow("Camembert d'outils", settings.ToolsKey, key => settings.ToolsKey = key));

        conflict = new TextBlock
        {
            Text = "Les deux camemberts utilisent la même touche : seul celui de conversion s'ouvrira.",
            Foreground = Brushes.DarkOrange,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 2, 0, 8),
        };
        panel.Children.Add(conflict);

        var sound = new CheckBox { Content = "Clic au passage d'une part", IsChecked = settings.Sound, VerticalAlignment = VerticalAlignment.Center };
        sound.Click += (_, _) => Update(() => settings.Sound = sound.IsChecked == true);
        var listen = new Button { Content = "Écouter", Padding = new Thickness(12, 2, 12, 2), HorizontalAlignment = HorizontalAlignment.Right };
        listen.Click += async (_, _) =>
        {
            WheelSound.Tick();
            await Task.Delay(140);
            WheelSound.Tick();
        };
        var soundRow = new DockPanel { Margin = new Thickness(0, 6, 0, 10) };
        DockPanel.SetDock(listen, Dock.Right);
        soundRow.Children.Add(listen);
        soundRow.Children.Add(sound);
        panel.Children.Add(soundRow);

        var startup = new CheckBox { Content = "Lancer Bergamote à l'ouverture de session", IsChecked = AppSettings.LaunchAtLogin };
        startup.Click += (_, _) => AppSettings.LaunchAtLogin = startup.IsChecked == true;
        panel.Children.Add(startup);

        panel.Children.Add(new TextBlock
        {
            Text = "Glissez des fichiers depuis l'Explorateur, puis tapez la touche choisie (ou maintenez-la avant de "
                + "glisser) : le camembert s'ouvre sous le curseur. Lâchez les fichiers sur une part : le résultat est "
                + "créé à côté de l'original, qui n'est jamais modifié.",
            Foreground = Brushes.DimGray,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 16, 0, 16),
        });

        var close = new Button { Content = "Fermer", IsDefault = true, IsCancel = true, Padding = new Thickness(18, 3, 18, 3), HorizontalAlignment = HorizontalAlignment.Right };
        close.Click += (_, _) => Close();
        panel.Children.Add(close);

        Content = panel;
        RefreshConflict();
    }

    private FrameworkElement KeyRow(string label, WheelModifier current, Action<WheelModifier> apply)
    {
        var choices = new ComboBox { Width = 120, HorizontalAlignment = HorizontalAlignment.Right };
        foreach (var key in Keys) choices.Items.Add(GlobalInput.Name(key));
        choices.SelectedIndex = Math.Max(0, Array.IndexOf(Keys, current));
        choices.SelectionChanged += (_, _) => Update(() => apply(Keys[choices.SelectedIndex]));

        var row = new DockPanel { Margin = new Thickness(0, 0, 0, 8) };
        DockPanel.SetDock(choices, Dock.Right);
        row.Children.Add(choices);
        row.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center });
        return row;
    }

    private void Update(Action change)
    {
        change();
        settings.Save();
        RefreshConflict();
    }

    private void RefreshConflict()
    {
        if (conflict is not null) conflict.Visibility = settings.ConversionKey == settings.ToolsKey ? Visibility.Visible : Visibility.Collapsed;
    }
}
