using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Bergamote.Core;

namespace Bergamote.Desktop;

/// <summary>
/// Réglages : touches des deux camemberts, clic sonore, lancement à l'ouverture de session, langue.
/// Chaque changement s'applique et s'enregistre aussitôt.
/// </summary>
internal sealed class SettingsWindow : Window
{
    private static readonly WheelModifier[] Keys = [WheelModifier.Shift, WheelModifier.Control, WheelModifier.Alt];

    private readonly AppSettings settings;
    private readonly TextBlock conflict;

    /// <summary>La langue a changé : la fenêtre est à reconstruire.</summary>
    public event Action? LanguageChanged;

    public SettingsWindow(AppSettings settings)
    {
        this.settings = settings;
        Title = AppLanguage.Text("settings.title");
        SizeToContent = SizeToContent.WidthAndHeight;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontSize = 13;

        var panel = new StackPanel { Margin = new Thickness(22), Width = 440 };

        var enabled = new CheckBox { Content = AppLanguage.Text("settings.enable"), IsChecked = settings.Enabled, Margin = new Thickness(0, 0, 0, 14) };
        OnToggled(enabled, () => Update(() => settings.Enabled = enabled.IsChecked == true));
        panel.Children.Add(enabled);

        var keyNames = Keys.Select(GlobalInput.Name).ToList();
        panel.Children.Add(ChoiceRow(AppLanguage.Text("settings.conversion_key"), keyNames, Array.IndexOf(Keys, settings.ConversionKey), index => settings.ConversionKey = Keys[index]));
        panel.Children.Add(ChoiceRow(AppLanguage.Text("settings.tools_key"), keyNames, Array.IndexOf(Keys, settings.ToolsKey), index => settings.ToolsKey = Keys[index]));

        conflict = new TextBlock
        {
            Text = AppLanguage.Text("settings.key_conflict"),
            Foreground = Brushes.DarkOrange,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 2, 0, 8),
        };
        panel.Children.Add(conflict);

        var sound = new CheckBox { Content = AppLanguage.Text("settings.sound"), IsChecked = settings.Sound, VerticalAlignment = VerticalAlignment.Center };
        OnToggled(sound, () => Update(() => settings.Sound = sound.IsChecked == true));
        var listen = new Button { Content = AppLanguage.Text("settings.listen"), Padding = new Thickness(12, 2, 12, 2), HorizontalAlignment = HorizontalAlignment.Right };
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

        var startup = new CheckBox { Content = AppLanguage.Text("settings.login"), IsChecked = AppSettings.LaunchAtLogin, Margin = new Thickness(0, 0, 0, 12) };
        OnToggled(startup, () => AppSettings.LaunchAtLogin = startup.IsChecked == true);
        panel.Children.Add(startup);

        // Langue : celle du système, puis les langues du cœur, sous leur propre nom.
        var codes = new[] { AppLanguage.SystemPreference }.Concat(AppLanguage.Languages.Select(language => language.Code)).ToList();
        var names = new[] { AppLanguage.Text("settings.language_system") }.Concat(AppLanguage.Languages.Select(language => language.Name)).ToList();
        panel.Children.Add(ChoiceRow(AppLanguage.Text("settings.language"), names, codes.IndexOf(settings.Language), index =>
        {
            settings.Language = codes[index];
            Dispatcher.BeginInvoke(() => LanguageChanged?.Invoke());
        }));

        panel.Children.Add(Note(AppLanguage.Text("settings.gesture_help", ("source", AppLanguage.Text("source.explorer"))), new Thickness(0, 12, 0, 6)));
        panel.Children.Add(Note(AppLanguage.Text("settings.result_help"), new Thickness(0, 0, 0, 16)));

        var close = new Button { Content = AppLanguage.Text("settings.close"), IsDefault = true, IsCancel = true, Padding = new Thickness(18, 3, 18, 3), HorizontalAlignment = HorizontalAlignment.Right };
        close.Click += (_, _) => Close();
        panel.Children.Add(close);

        Content = panel;
        RefreshConflict();
    }

    /// <summary>
    /// Réagit au changement d'état, quelle qu'en soit l'origine : un clic, le clavier, ou un outil
    /// d'accessibilité (qui change l'état sans cliquer).
    /// </summary>
    private static void OnToggled(CheckBox box, Action changed)
    {
        box.Checked += (_, _) => changed();
        box.Unchecked += (_, _) => changed();
    }

    private static TextBlock Note(string text, Thickness margin) =>
        new() { Text = text, Foreground = Brushes.DimGray, TextWrapping = TextWrapping.Wrap, Margin = margin };

    /// <summary>Une ligne « libellé … liste de choix » ; <paramref name="apply"/> reçoit l'index choisi.</summary>
    private FrameworkElement ChoiceRow(string label, IReadOnlyList<string> names, int selected, Action<int> apply)
    {
        var choices = new ComboBox { MinWidth = 120, HorizontalAlignment = HorizontalAlignment.Right };
        foreach (var name in names) choices.Items.Add(name);
        choices.SelectedIndex = Math.Max(0, selected);
        choices.SelectionChanged += (_, _) => Update(() => apply(choices.SelectedIndex));

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

    private void RefreshConflict() =>
        conflict.Visibility = settings.ConversionKey == settings.ToolsKey ? Visibility.Visible : Visibility.Collapsed;
}
