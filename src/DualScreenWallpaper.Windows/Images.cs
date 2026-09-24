#nullable enable
using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DualScreenWallpaper.Core;

namespace DualScreenWallpaper.Windows;

public static class Images
{
    public static ImageSize Dimensions(string path)
    {
        var header = Wallpaper.ImageHeader.Read(path);
        if (header != null) return new(header[0], header[1]);
        var frame = Load(path);
        return new(frame.PixelWidth, frame.PixelHeight);
    }
    public static BitmapSource Load(string path)
    {
        using var input = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        var frame = BitmapDecoder.Create(input, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
        int orientation = 1;
        try { if (frame.Metadata is BitmapMetadata metadata && metadata.ContainsQuery("/app1/ifd/{ushort=274}")) orientation = Convert.ToInt32(metadata.GetQuery("/app1/ifd/{ushort=274}")); }
        catch (Exception ex) when (ex is NotSupportedException or ArgumentException or System.Runtime.InteropServices.COMException) { }
        Matrix matrix = Matrix.Identity;
        switch (orientation)
        {
            case 2: matrix.Scale(-1, 1); break;
            case 3: matrix.Rotate(180); break;
            case 4: matrix.Scale(1, -1); break;
            case 5: matrix = new(0, 1, 1, 0, 0, 0); break;
            case 6: matrix.Rotate(90); break;
            case 7: matrix = new(0, -1, -1, 0, 0, 0); break;
            case 8: matrix.Rotate(270); break;
        }
        BitmapSource result = matrix.IsIdentity ? frame : new TransformedBitmap(frame, new MatrixTransform(matrix));
        result.Freeze(); return result;
    }
    public static void Save(BitmapSource frame, string path)
    {
        var encoder = new JpegBitmapEncoder { QualityLevel = 95 };
        encoder.Frames.Add(BitmapFrame.Create(frame));
        using var output = File.Create(path); encoder.Save(output);
    }
    public static BitmapSource Canvas(BitmapSource image, int width, int height, string mode, uint color)
    {
        var visual = new DrawingVisual();
        using (var draw = visual.RenderOpen())
        {
            var bounds = new Rect(0, 0, width, height);
            draw.DrawRectangle(new SolidColorBrush(Color.FromRgb((byte)color, (byte)(color >> 8), (byte)(color >> 16))), null, bounds);
            draw.PushClip(new RectangleGeometry(bounds));
            double w = image.PixelWidth, h = image.PixelHeight;
            if (mode == "Tile")
            {
                var brush = new ImageBrush(image) { TileMode = TileMode.Tile, ViewportUnits = BrushMappingMode.Absolute, Viewport = new Rect(0, 0, w, h), Stretch = Stretch.Fill };
                draw.DrawRectangle(brush, null, bounds);
            }
            else
            {
                if (mode == "Stretch") { w = width; h = height; }
                else if (mode is "Fit" or "Fill")
                {
                    double factor = mode == "Fit" ? Math.Min(width / w, height / h) : Math.Max(width / w, height / h);
                    w *= factor; h *= factor;
                }
                draw.DrawImage(image, new Rect((width - w) / 2, (height - h) / 2, w, h));
            }
            draw.Pop();
        }
        var output = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        output.Render(visual); output.Freeze(); return output;
    }
    public static BitmapSource Blend(BitmapSource old, BitmapSource next, double alpha)
    {
        var visual = new DrawingVisual();
        using (var draw = visual.RenderOpen())
        {
            var rect = new Rect(0, 0, next.PixelWidth, next.PixelHeight);
            draw.DrawImage(old, rect); draw.PushOpacity(Math.Clamp(alpha, 0, 1)); draw.DrawImage(next, rect); draw.Pop();
        }
        var output = new RenderTargetBitmap(next.PixelWidth, next.PixelHeight, 96, 96, PixelFormats.Pbgra32);
        output.Render(visual); output.Freeze(); return output;
    }
}
