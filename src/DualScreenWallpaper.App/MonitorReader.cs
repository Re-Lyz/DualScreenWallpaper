using System.Runtime.InteropServices;

namespace DualScreenWallpaper.App;

internal sealed record MonitorInfo(string Id, bool Primary, int Width, int Height, string Wallpaper, int Left = 0, int Top = 0);

internal static class MonitorReader
{
    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromRect(ref Wallpaper.Rect rect, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref NativeMonitorInfo info);
    [StructLayout(LayoutKind.Sequential)]
    private struct NativeMonitorInfo
    {
        public int Size;
        public Wallpaper.Rect Monitor;
        public Wallpaper.Rect Work;
        public uint Flags;
    }

    public static IReadOnlyList<MonitorInfo> Read()
    {
        using var desktop = Wallpaper.Desktop.Open();
        var result = new List<MonitorInfo>();
        for (uint i = 0; i < desktop.GetMonitorDevicePathCount(); i++)
        {
            string id = desktop.GetMonitorDevicePathAt(i);
            Wallpaper.Rect rect;
            try { rect = desktop.GetMonitorRECT(id); }
            catch (COMException) { continue; } // Disconnected devices can remain enumerated.
            int width = rect.Right - rect.Left, height = rect.Bottom - rect.Top;
            if (width <= 0 || height <= 0) continue;
            var native = new NativeMonitorInfo { Size = Marshal.SizeOf<NativeMonitorInfo>() };
            if (!GetMonitorInfo(MonitorFromRect(ref rect, 0), ref native))
                throw new InvalidOperationException("Cannot determine the Windows primary monitor.");
            result.Add(new(id, (native.Flags & 1) != 0, width, height, desktop.GetWallpaper(id), rect.Left, rect.Top));
        }
        return result;
    }
}
