using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace Bergamote.DragSource;

/// <summary>
/// Une fenêtre à un endroit connu de l'écran (60, 60) : y appuyer puis bouger la souris démarre un
/// vrai glisser-déposer OLE des fichiers passés en arguments, comme le ferait l'Explorateur.
/// L'effet obtenu est écrit dans le fichier nommé par BERGAMOTE_DRAG_LOG.
/// </summary>
public static class Program
{
    [STAThread]
    public static void Main(string[] arguments)
    {
        var files = arguments.Select(Path.GetFullPath).ToArray();
        var log = Environment.GetEnvironmentVariable("BERGAMOTE_DRAG_LOG");
        var window = new Window
        {
            Title = "Bergamote drag source",
            WindowStartupLocation = WindowStartupLocation.Manual,
            Left = 60,
            Top = 60,
            Width = 320,
            Height = 240,
            Topmost = true,
            Background = Brushes.White,
            Content = new TextBlock
            {
                Text = $"Drag {files.Length} file(s)",
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        };
        var dragging = false;
        window.MouseMove += (_, e) =>
        {
            if (dragging || e.LeftButton != MouseButtonState.Pressed) return;
            dragging = true;
            var effect = DragDrop.DoDragDrop(window, new DataObject(DataFormats.FileDrop, files), DragDropEffects.Copy | DragDropEffects.Move);
            if (log is not null) File.AppendAllText(log, $"drag ended: {effect}{Environment.NewLine}");
            dragging = false;
        };
        new Application().Run(window);
    }
}
