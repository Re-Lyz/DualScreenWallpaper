using System.Diagnostics;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Media.Imaging;

namespace DualScreenWallpaper.App;

/// <summary>Short-lived child of Explorer's wallpaper host, never a topmost application overlay.</summary>
internal sealed class CrossfadeLayer : Form
{
    private readonly Bitmap oldImage, nextImage;
    private float alpha;
    private delegate bool EnumWindowProc(IntPtr hwnd, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowProc callback, IntPtr parameter);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindow(string cls, string? title);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string? title);
    [DllImport("user32.dll")] private static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr child);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out Wallpaper.Rect rect);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam, uint flags, uint timeout, out IntPtr result);
    private CrossfadeLayer(Bitmap oldImage, Bitmap nextImage)
    {
        this.oldImage = oldImage; this.nextImage = nextImage;
        TopLevel = false; FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false;
        AutoScaleMode = AutoScaleMode.None;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
    }
    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams
    {
        get { var value = base.CreateParams; value.ExStyle |= 0x08000000 | 0x00000020; return value; } // NOACTIVATE | TRANSPARENT
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.DrawImageUnscaled(oldImage, 0, 0);
        using var attributes = new ImageAttributes();
        attributes.SetColorMatrix(new ColorMatrix { Matrix33 = alpha });
        e.Graphics.DrawImage(nextImage, ClientRectangle, 0, 0, nextImage.Width, nextImage.Height, GraphicsUnit.Pixel, attributes);
    }
    private static Bitmap Bitmap(BitmapSource image)
    {
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image));
        using var stream = new MemoryStream(); encoder.Save(stream); stream.Position = 0;
        using var decoded = Image.FromStream(stream); return new Bitmap(decoded);
    }
    public static bool TryAnimate(BitmapSource old, BitmapSource next, Wallpaper.Rect screen, Action applyFinal, CancellationToken token, out string reason)
    {
        IntPtr host = IntPtr.Zero;
        IntPtr manager = FindWindow("Progman", null);
        if (manager == IntPtr.Zero) { reason = "Explorer wallpaper host unavailable"; return false; }
        // Request the background WorkerW. If this shell arrangement is unavailable, fall back safely.
        SendMessageTimeout(manager, 0x052C, IntPtr.Zero, IntPtr.Zero, 2, 1000, out _);
        EnumWindows((window, _) =>
        {
            if (FindWindowEx(window, IntPtr.Zero, "SHELLDLL_DefView", null) != IntPtr.Zero)
                host = FindWindowEx(IntPtr.Zero, window, "WorkerW", null);
            return host == IntPtr.Zero;
        }, IntPtr.Zero);
        if (host == IntPtr.Zero || !GetWindowRect(host, out var hostBounds)) { reason = "Compatible desktop background layer not found"; return false; }
        using var oldBitmap = Bitmap(old); using var nextBitmap = Bitmap(next);
        using var layer = new CrossfadeLayer(oldBitmap, nextBitmap);
        layer.ClientSize = new Size(screen.Right - screen.Left, screen.Bottom - screen.Top);
        _ = layer.Handle;
        SetParent(layer.Handle, host);
        if (GetParent(layer.Handle) != host) { reason = "Cannot attach desktop animation layer"; return false; }
        layer.Show();
        if (!SetWindowPos(layer.Handle, new IntPtr(1), screen.Left - hostBounds.Left, screen.Top - hostBounds.Top, layer.Width, layer.Height, 0x0010 | 0x0040))
        { reason = "Cannot position desktop animation layer"; return false; }
        layer.Update(); applyFinal();
        var watch = Stopwatch.StartNew();
        while (watch.ElapsedMilliseconds < 1200)
        {
            token.ThrowIfCancellationRequested();
            if (!IsWindow(host)) throw new IOException("Explorer restarted during crossfade.");
            layer.alpha = Math.Min(1, watch.ElapsedMilliseconds / 800f);
            layer.Invalidate(); layer.Update(); Application.DoEvents(); Thread.Sleep(15);
        }
        reason = "Desktop layer: 800 ms crossfade, 400 ms final settle"; return true;
    }
    internal static void VerifyRenderer()
    {
        using var old = new Bitmap(8, 8); using var next = new Bitmap(8, 8);
        using (var g = Graphics.FromImage(old)) g.Clear(Color.Red);
        using (var g = Graphics.FromImage(next)) g.Clear(Color.Blue);
        using var form = new CrossfadeLayer(old, next) { ClientSize = new Size(8, 8), alpha = .5f };
        using var output = new Bitmap(8, 8); using var graphics = Graphics.FromImage(output);
        form.OnPaint(new PaintEventArgs(graphics, new Rectangle(0, 0, 8, 8)));
        var pixel = output.GetPixel(3, 3);
        if (pixel.R is < 126 or > 129 || pixel.B is < 126 or > 129) throw new InvalidOperationException("Desktop-layer blend rendering failed.");
    }
}
