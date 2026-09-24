using System.Text.Json;

namespace DualScreenWallpaper.Core;

public static class Storage
{
    public static T? Read<T>(string path) => File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path)) : default;
    public static void Write<T>(string path, T value, bool backup = false)
    {
        string full = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        string temp = full + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                JsonSerializer.Serialize(stream, value, new JsonSerializerOptions { WriteIndented = true });
                stream.Flush(true);
            }
            if (File.Exists(full))
                File.Replace(temp, full, backup ? full + ".backup-" + DateTime.UtcNow.ToString("yyyyMMddHHmmssfff") + ".json" : null);
            else File.Move(temp, full);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    public static void SaveSettings(string path, Settings settings)
    {
        _ = SettingsReader.Parse(SettingsReader.Serialize(settings));
        Write(path, settings, true);
    }
}
