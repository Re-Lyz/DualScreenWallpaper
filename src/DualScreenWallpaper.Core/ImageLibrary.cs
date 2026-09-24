using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace DualScreenWallpaper.Core;

public sealed record ImageSize(int Width, int Height);
public sealed record LibraryIndex(string Signature, Dictionary<string, string[]> Pools);

public static class ImageLibrary
{
    private static readonly HashSet<string> Extensions = new(StringComparer.OrdinalIgnoreCase)
        { ".jpg", ".jpeg", ".jfif", ".png", ".bmp", ".gif", ".tif", ".tiff", ".ico", ".wdp", ".jxr", ".webp", ".heic", ".heif", ".avif" };

    public static Dictionary<string, ImageProfile> Profiles(Settings settings)
    {
        var result = new Dictionary<string, ImageProfile>(settings.MonitorProfiles, StringComparer.OrdinalIgnoreCase)
            { ["Primary"] = settings.Primary, ["Secondary"] = settings.Secondary };
        return result;
    }
    public static string Signature(Settings settings) => Convert.ToHexString(SHA256.HashData(
        Encoding.UTF8.GetBytes(JsonSerializer.Serialize(Profiles(settings).OrderBy(x => x.Key, StringComparer.Ordinal)))));

    public static bool IsWithin(string path, string directory)
    {
        string folder = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory));
        string file = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        return file.Equals(folder, StringComparison.OrdinalIgnoreCase) ||
            file.StartsWith(folder + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }
    public static IEnumerable<string> Enumerate(ImageProfile profile, Action<string> log, CancellationToken token)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var pending = new Stack<string>(profile.Roots.Reverse());
        while (pending.TryPop(out string? item))
        {
            token.ThrowIfCancellationRequested();
            string path = Path.GetFullPath(item);
            if (!seen.Add(path) || profile.ExcludeFolders.Any(excluded => IsWithin(path, excluded))) continue;
            if (!File.Exists(path) && !Directory.Exists(path)) { log("Missing source: " + path); continue; }
            FileAttributes attributes;
            try { attributes = File.GetAttributes(path); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { log(ex.Message); continue; }
            if ((attributes & FileAttributes.ReparsePoint) != 0) { log("Skipped linked source: " + path); continue; }
            if ((attributes & FileAttributes.Directory) != 0)
            {
                string[] children;
                try { children = Directory.GetFileSystemEntries(path); }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { log(ex.Message); continue; }
                foreach (string child in children.Reverse()) pending.Push(child);
            }
            else if (Extensions.Contains(Path.GetExtension(path))) yield return path;
        }
    }
    public static bool Accept(ImageProfile profile, ImageSize size) =>
        (!profile.OrientationEnabled || (profile.Orientation == "Portrait" ? size.Height > size.Width : size.Width > size.Height)) &&
        (!profile.MinResolutionEnabled || (size.Width >= profile.MinWidth && size.Height >= profile.MinHeight));

    public static LibraryIndex Scan(Settings settings, Func<string, ImageSize> dimensions, Action<string> log, CancellationToken token)
    {
        var pools = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        var cache = new Dictionary<string, ImageSize>(StringComparer.OrdinalIgnoreCase);
        foreach (var (key, profile) in Profiles(settings))
        {
            var accepted = new List<string>(); int count = 0;
            foreach (string path in Enumerate(profile, log, token))
            {
                token.ThrowIfCancellationRequested();
                try
                {
                    if (!cache.TryGetValue(path, out var size)) cache[path] = size = dimensions(path);
                    if (Accept(profile, size)) accepted.Add(path);
                }
                catch (Exception ex) when (ex is not OperationCanceledException and not OutOfMemoryException) { log($"Skipped {path}: {ex.Message}"); }
                if (++count % 500 == 0) log($"{key}: scanned {count}");
            }
            pools[key] = accepted.ToArray();
            log($"{key}: {accepted.Count} eligible images");
        }
        return new(Signature(settings), pools);
    }
    public static string[] Candidates(IEnumerable<string> images, string? previous, string order)
    {
        var list = images.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        if (order == "Sequential")
        {
            list = list.OrderBy(Path.GetFileName, StringComparer.CurrentCultureIgnoreCase)
                .ThenBy(x => x, StringComparer.CurrentCultureIgnoreCase).ToArray();
            int start = (Array.FindIndex(list, x => x.Equals(previous, StringComparison.OrdinalIgnoreCase)) + 1) % Math.Max(1, list.Length);
            return list.Skip(start).Concat(list.Take(start)).ToArray();
        }
        Random.Shared.Shuffle(list);
        return list.Where(x => !x.Equals(previous, StringComparison.OrdinalIgnoreCase))
            .Concat(list.Where(x => x.Equals(previous, StringComparison.OrdinalIgnoreCase))).ToArray();
    }
}
