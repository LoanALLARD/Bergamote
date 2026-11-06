using System.Runtime.InteropServices;
using Bergamote.Core;

namespace Bergamote.Desktop;

/// <summary>Les quelques appels Win32 dont l'app a besoin.</summary>
internal static partial class Win32
{
    [StructLayout(LayoutKind.Sequential)]
    internal struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MONITORINFO
    {
        public int Size;
        public RECT Monitor;
        public RECT Work;
        public uint Flags;
    }

    internal const int SM_SWAPBUTTON = 23;
    internal const int SM_CXDRAG = 68;
    internal const int SM_CYDRAG = 69;
    internal const int GWL_EXSTYLE = -20;
    internal const long WS_EX_TOOLWINDOW = 0x00000080;
    internal const long WS_EX_NOACTIVATE = 0x08000000;
    internal const uint MONITOR_DEFAULTTONEAREST = 2;
    internal const uint SWP_NOACTIVATE = 0x0010;
    internal const uint SWP_SHOWWINDOW = 0x0040;
    internal static readonly IntPtr HWND_TOPMOST = new(-1);

    [LibraryImport("user32.dll")]
    internal static partial short GetAsyncKeyState(int key);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool GetCursorPos(out POINT point);

    [LibraryImport("user32.dll")]
    internal static partial int GetSystemMetrics(int index);

    [LibraryImport("user32.dll")]
    internal static partial IntPtr MonitorFromPoint(POINT point, uint flags);

    [LibraryImport("user32.dll", EntryPoint = "GetMonitorInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

    [LibraryImport("shcore.dll")]
    internal static partial int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool DestroyIcon(IntPtr icon);

    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static partial IntPtr GetWindowLongPtr64(IntPtr window, int index);

    [LibraryImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static partial IntPtr SetWindowLongPtr64(IntPtr window, int index, IntPtr value);

    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static partial int GetWindowLong32(IntPtr window, int index);

    [LibraryImport("user32.dll", EntryPoint = "SetWindowLongW")]
    private static partial int SetWindowLong32(IntPtr window, int index, int value);

    internal static long GetWindowLong(IntPtr window, int index) =>
        IntPtr.Size == 8 ? GetWindowLongPtr64(window, index) : GetWindowLong32(window, index);

    internal static void SetWindowLong(IntPtr window, int index, long value)
    {
        if (IntPtr.Size == 8) SetWindowLongPtr64(window, index, new IntPtr(value));
        else SetWindowLong32(window, index, unchecked((int)value));
    }

    /// <summary>Zone de travail (sans la barre des tâches) et échelle de l'écran sous un point.</summary>
    internal static (RECT Work, double Scale) Screen(POINT point)
    {
        var monitor = MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST);
        var info = new MONITORINFO { Size = Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(monitor, ref info);
        var scale = GetDpiForMonitor(monitor, 0, out var dpi, out _) == 0 && dpi > 0 ? dpi / 96.0 : 1.0;
        return (info.Work, scale);
    }
}

/// <summary>État global du clavier et de la souris, lu à chaque relevé.</summary>
internal static class GlobalInput
{
    private const int VK_LBUTTON = 0x01, VK_RBUTTON = 0x02, VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12;
    private const int VK_LWIN = 0x5B, VK_RWIN = 0x5C;

    private static bool Pressed(int key) => (Win32.GetAsyncKeyState(key) & 0x8000) != 0;

    /// <summary>Bouton principal, même si les boutons sont inversés pour les gauchers.</summary>
    public static bool IsPrimaryButtonDown() =>
        Pressed(Win32.GetSystemMetrics(Win32.SM_SWAPBUTTON) != 0 ? VK_RBUTTON : VK_LBUTTON);

    public static WheelModifier Modifiers()
    {
        var modifiers = WheelModifier.None;
        if (Pressed(VK_SHIFT)) modifiers |= WheelModifier.Shift;
        if (Pressed(VK_CONTROL)) modifiers |= WheelModifier.Control;
        if (Pressed(VK_MENU)) modifiers |= WheelModifier.Alt;
        if (Pressed(VK_LWIN) || Pressed(VK_RWIN)) modifiers |= WheelModifier.Windows;
        return modifiers;
    }

    public static Win32.POINT Cursor()
    {
        Win32.GetCursorPos(out var point);
        return point;
    }

    /// <summary>Le curseur s'est éloigné du point d'appui au-delà du seuil de glisser du système.</summary>
    public static bool BeyondDragThreshold(Win32.POINT from, Win32.POINT to) =>
        Math.Abs(to.X - from.X) > Win32.GetSystemMetrics(Win32.SM_CXDRAG)
        || Math.Abs(to.Y - from.Y) > Win32.GetSystemMetrics(Win32.SM_CYDRAG);

    public static string Name(WheelModifier key) => key switch
    {
        WheelModifier.Shift => "Maj",
        WheelModifier.Control => "Ctrl",
        WheelModifier.Alt => "Alt",
        WheelModifier.Windows => "Windows",
        _ => key.ToString(),
    };
}
