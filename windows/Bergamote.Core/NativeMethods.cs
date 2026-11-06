using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Bergamote.Core;

/// <summary>Interface C du cœur (core/include/bergamote_core.h).</summary>
internal static partial class NativeMethods
{
    private const string Library = "bergamote_core";

    [LibraryImport(Library)]
    internal static partial IntPtr bgm_core_version();

    [LibraryImport(Library)]
    internal static partial void bgm_string_free(IntPtr text);

    [LibraryImport(Library)]
    internal static partial DetectorHandle bgm_detector_new();

    [LibraryImport(Library)]
    internal static partial void bgm_detector_free(IntPtr detector);

    [LibraryImport(Library)]
    internal static partial void bgm_detector_clear_bindings(DetectorHandle detector);

    [LibraryImport(Library)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static partial bool bgm_detector_set_binding(DetectorHandle detector, uint modifiers, byte kind);

    [LibraryImport(Library)]
    internal static partial int bgm_detector_update(
        DetectorHandle detector, [MarshalAs(UnmanagedType.U1)] bool isMouseDown, long dragGeneration, uint modifiers);

    [LibraryImport(Library)]
    internal static partial byte bgm_detector_visible(DetectorHandle detector);

    [LibraryImport(Library)]
    internal static partial void bgm_detector_dismiss(DetectorHandle detector);

    [LibraryImport(Library)]
    internal static partial int bgm_slice_at(double x, double y, int count, double innerRadius, double outerRadius);

    [LibraryImport(Library)]
    internal static partial double bgm_center_angle(int index, int count);

    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
    internal static partial IntPtr bgm_catalog(string requestJson);

    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
    internal static partial IntPtr bgm_input_for_extension(string extension);

    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
    internal static partial IntPtr bgm_unique_output_path(string source, string suffix, string extension, string? outputDirectory);

    [LibraryImport(Library)]
    internal static partial IntPtr bgm_created_summary(uint count);

    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
    internal static partial IntPtr bgm_files_summary(string extensionsJson, long totalBytes);

    [LibraryImport(Library)]
    internal static partial IntPtr bgm_click_wav(out nuint length);

    [LibraryImport(Library)]
    internal static partial void bgm_bytes_free(IntPtr bytes, nuint length);

    /// <summary>Copie une chaîne renvoyée par le cœur, puis la libère.</summary>
    internal static string? Take(IntPtr text)
    {
        if (text == IntPtr.Zero) return null;
        try { return Marshal.PtrToStringUTF8(text); }
        finally { bgm_string_free(text); }
    }
}

/// <summary>Détecteur du cœur, libéré avec son enveloppe.</summary>
internal sealed class DetectorHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    public DetectorHandle() : base(ownsHandle: true) { }

    protected override bool ReleaseHandle()
    {
        NativeMethods.bgm_detector_free(handle);
        return true;
    }
}
