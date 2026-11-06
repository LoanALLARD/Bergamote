using System.Text.Json;
using System.Text.Json.Serialization;
using Bergamote.Core;
using Microsoft.Win32;

namespace Bergamote.Desktop;

/// <summary>Réglages, enregistrés dans %APPDATA%\Bergamote\settings.json.</summary>
internal sealed class AppSettings
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValue = "Bergamote";

    public bool Enabled { get; set; } = true;
    public WheelModifier ConversionKey { get; set; } = WheelModifier.Shift;
    public WheelModifier ToolsKey { get; set; } = WheelModifier.Control;
    public bool Sound { get; set; } = true;

    /// <summary>Vrai au tout premier lancement (pas encore de fichier de réglages).</summary>
    [JsonIgnore]
    public bool IsFirstLaunch { get; private set; }

    public event Action? Changed;

    private static string FilePath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Bergamote", "settings.json");

    /// <summary>En cas de conflit, la conversion l'emporte.</summary>
    public IReadOnlyDictionary<WheelModifier, WheelKind> Bindings() => new Dictionary<WheelModifier, WheelKind>
    {
        [ToolsKey] = WheelKind.Tools,
        [ConversionKey] = WheelKind.Conversion,
    };

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new AppSettings();
            }
        }
        catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException)
        {
            ErrorLog.Write(error);
        }
        var settings = new AppSettings { IsFirstLaunch = true };
        settings.Save();
        return settings;
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            ErrorLog.Write(error);
        }
        Changed?.Invoke();
    }

    /// <summary>Lancement à l'ouverture de session (clé Run de l'utilisateur).</summary>
    public static bool LaunchAtLogin
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(RunValue) is string;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value) key.SetValue(RunValue, $"\"{Environment.ProcessPath}\"");
            else key.DeleteValue(RunValue, throwOnMissingValue: false);
        }
    }
}

/// <summary>Journal des erreurs : %LOCALAPPDATA%\Bergamote\bergamote.log.</summary>
internal static class ErrorLog
{
    private static readonly object Gate = new();

    public static string FilePath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Bergamote", "bergamote.log");

    public static void Write(Exception error) => Write(error.ToString());

    public static void Write(string message)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
                File.AppendAllText(FilePath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {message}{Environment.NewLine}");
            }
        }
        catch (IOException)
        {
            // Pas de journal : on n'interrompt pas l'app pour autant.
        }
    }
}
