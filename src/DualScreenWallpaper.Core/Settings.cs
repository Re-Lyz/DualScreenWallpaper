using System.Text.Json;
using System.Text.Json.Nodes;

namespace DualScreenWallpaper.Core;

public sealed record ImageProfile(string[] Roots, string[] ExcludeFolders,
    bool OrientationEnabled, string Orientation, bool MinResolutionEnabled, int MinWidth, int MinHeight);

public sealed record Settings(int SchemaVersion, string Language, string DisplayMode,
    string PlaybackOrder, string TransitionEffect, bool SetupCompleted,
    ImageProfile Primary, ImageProfile Secondary, int IntervalMinutes, bool AutoStart)
{
    public Dictionary<string, ImageProfile> MonitorProfiles { get; init; } = new(StringComparer.OrdinalIgnoreCase);
    public ImageProfile ForMonitor(string id, bool primary) => MonitorProfiles.TryGetValue(id, out var value)
        ? value : primary ? Primary : Secondary;
}

/// <summary>Read-only migration boundary. Loading never rewrites a user's configuration.</summary>
public static class SettingsReader
{
    public static Settings Load(string path) => Parse(File.ReadAllText(path));

    public static Settings Parse(string json)
    {
        // File.ReadAllText consumes BOMs; permit one when parsing a fixture directly too.
        var root = JsonNode.Parse(json.TrimStart('\uFEFF')) as JsonObject
            ?? throw new FormatException("Configuration must be a JSON object.");
        bool legacy = !root.ContainsKey("SchemaVersion");
        if (!legacy) _ = Integer(root, "SchemaVersion", 2, 3);
        ImageProfile primary, secondary;
        if (legacy)
        {
            primary = new(Paths(root, "LandscapeRoots"), [], false, "Landscape", false, 1920, 1080);
            int width = Integer(root, "PortraitMinWidth", 0, 100000);
            int height = Integer(root, "PortraitMinHeight", 0, 100000);
            secondary = new(Paths(root, "PortraitRoots"), [], Boolean(root, "OnlyPortrait"),
                "Portrait", width > 0 || height > 0, width, height);
        }
        else
        {
            primary = Profile(root["Primary"] as JsonObject, "Primary");
            secondary = Profile(root["Secondary"] as JsonObject, "Secondary");
        }
        var profiles = new Dictionary<string, ImageProfile>(StringComparer.OrdinalIgnoreCase);
        if (root.ContainsKey("MonitorProfiles"))
        {
            if (root["MonitorProfiles"] is not JsonObject map) throw new FormatException("Invalid MonitorProfiles.");
            foreach (var entry in map)
            {
                if (string.IsNullOrWhiteSpace(entry.Key) || entry.Key.Equals("Primary", StringComparison.OrdinalIgnoreCase) || entry.Key.Equals("Secondary", StringComparison.OrdinalIgnoreCase)) throw new FormatException("Invalid monitor ID.");
                profiles.Add(entry.Key, Profile(entry.Value as JsonObject, entry.Key));
            }
        }
        return new Settings(3,
            Choice(root, "Language", "zh-CN", "zh-CN", "en-US"),
            Choice(root, "DisplayMode", "Fill", "Fill", "Fit", "Stretch", "Center", "Tile"),
            Choice(root, "PlaybackOrder", "Random", "Random", "Sequential"),
            Choice(root, "TransitionEffect", "Instant", "Instant", "CrossFade"),
            OptionalBoolean(root, "SetupCompleted", primary.Roots.Length > 0 && secondary.Roots.Length > 0),
            primary, secondary, Integer(root, "IntervalMinutes", 1, 1440),
            legacy ? OptionalBoolean(root, "AutoStart", true) : Boolean(root, "AutoStart")) { MonitorProfiles = profiles };
    }

    public static string Serialize(Settings settings) => JsonSerializer.Serialize(settings,
        new JsonSerializerOptions { WriteIndented = true });

    public static Settings Defaults => new(3, "zh-CN", "Fill", "Random", "Instant", false,
        new([], [], false, "Landscape", false, 1920, 1080),
        new([], [], true, "Portrait", true, 1440, 2560), 1, true);

    private static ImageProfile Profile(JsonObject? value, string name)
    {
        if (value is null) throw new FormatException($"Missing profile: {name}");
        return new(Paths(value, "Roots"), Paths(value, "ExcludeFolders"),
            Boolean(value, "OrientationEnabled"), RequiredChoice(value, "Orientation", "Landscape", "Portrait"),
            Boolean(value, "MinResolutionEnabled"), Integer(value, "MinWidth", 0, 100000),
            Integer(value, "MinHeight", 0, 100000));
    }

    private static T Value<T>(JsonObject obj, string name)
    {
        if (obj[name] is JsonValue value && value.TryGetValue<T>(out var result)) return result;
        throw new FormatException($"Invalid or missing setting: {name}");
    }
    private static bool Boolean(JsonObject obj, string name) => Value<bool>(obj, name);
    private static bool OptionalBoolean(JsonObject obj, string name, bool fallback) =>
        obj.ContainsKey(name) ? Boolean(obj, name) : fallback;
    private static int Integer(JsonObject obj, string name, int min, int max)
    {
        int value = Value<int>(obj, name);
        if (value < min || value > max) throw new FormatException($"Out of range: {name}");
        return value;
    }
    private static string Choice(JsonObject obj, string name, string fallback, params string[] allowed) =>
        obj.ContainsKey(name) ? RequiredChoice(obj, name, allowed) : fallback;
    private static string RequiredChoice(JsonObject obj, string name, params string[] allowed)
    {
        string value = Value<string>(obj, name);
        if (!allowed.Contains(value, StringComparer.Ordinal)) throw new FormatException($"Unsupported {name}: {value}");
        return value;
    }
    private static string[] Paths(JsonObject obj, string name)
    {
        if (obj[name] is not JsonArray values) throw new FormatException($"{name} must be an array.");
        return values.Select(value =>
        {
            if (value is not JsonValue node || !node.TryGetValue<string>(out var path) ||
                string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path))
                throw new FormatException($"{name} requires absolute paths.");
            _ = Path.GetFullPath(path);
            return path;
        }).ToArray();
    }
}
