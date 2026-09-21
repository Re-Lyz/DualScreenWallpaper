using System;
using System.Runtime.InteropServices;
namespace Wallpaper {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
 [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 public interface IDesktop {
  void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitor,[MarshalAs(UnmanagedType.LPWStr)] string path);
  [return:MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitor);
  [return:MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint index);
  uint GetMonitorDevicePathCount();
  Rect GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitor);
  void SetBackgroundColor(uint color);
  uint GetBackgroundColor();
  void SetPosition(int position);
  int GetPosition();
 }
 public sealed class Desktop : IDisposable {
  private IDesktop instance;
  public static Desktop Open() { return new Desktop { instance = (IDesktop)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD"))) }; }
  public uint GetMonitorDevicePathCount() { return instance.GetMonitorDevicePathCount(); }
  public string GetMonitorDevicePathAt(uint i) { return instance.GetMonitorDevicePathAt(i); }
  public Rect GetMonitorRECT(string id) { return instance.GetMonitorRECT(id); }
  public string GetWallpaper(string id) { return instance.GetWallpaper(id); }
  public void SetWallpaper(string id, string path) { instance.SetWallpaper(id,path); }
  public int GetPosition() { return instance.GetPosition(); }
  public void SetPosition(int position) { instance.SetPosition(position); }
  public void Dispose() { if (instance != null) { Marshal.ReleaseComObject(instance); instance = null; } }
 }
}
