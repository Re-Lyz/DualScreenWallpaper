using System.Text.Json.Nodes;
using DualScreenWallpaper.Core;

// Dependency-free regression runner: fail the process on a broken migration contract.
var legacy = """
{"LandscapeRoots":["D:\\Pictures"],"PortraitRoots":["D:\\Portraits"],
 "PortraitMinWidth":1440,"PortraitMinHeight":2560,"OnlyPortrait":true,"IntervalMinutes":3}
""";
int assertions = 0;
void Check(bool condition, string message)
{
    assertions++;
    if (!condition) throw new Exception(message);
}
void Reject(string input)
{
    try { SettingsReader.Parse(input); }
    catch (FormatException) { assertions++; return; }
    catch (System.Text.Json.JsonException) { assertions++; return; }
    throw new Exception("Invalid configuration accepted: " + input);
}
var old = SettingsReader.Parse(legacy);
Check(old.Primary.Roots.SequenceEqual([@"D:\Pictures"]), "Legacy folders lost");
Check(old.Secondary.MinResolutionEnabled && old.Secondary.MinWidth == 1440, "Legacy filter lost");
Check(old.AutoStart && old.SetupCompleted && old.TransitionEffect == "Instant", "Legacy defaults differ");
Check(old.DisplayMode == "Fill" && old.PlaybackOrder == "Random" && old.Language == "zh-CN", "Playback defaults differ");
var current = JsonNode.Parse(SettingsReader.Serialize(old))!.AsObject();
current["TransitionEffect"] = "CrossFade";
current["PlaybackOrder"] = "Sequential";
current["Language"] = "en-US";
current["AutoStart"] = false;
current["Primary"]!["ExcludeFolders"] = new JsonArray(@"D:\Pictures\private");
string encoded = current.ToJsonString();
var read = SettingsReader.Parse(encoded);
Check(read.TransitionEffect == "CrossFade" && read.PlaybackOrder == "Sequential", "Independent playback preferences lost");
Check(read.Primary.ExcludeFolders.SequenceEqual([@"D:\Pictures\private"]), "Exclusions lost");
Check(!read.AutoStart && read.Language == "en-US", "User preferences lost");
Check(SettingsReader.Serialize(SettingsReader.Parse(SettingsReader.Serialize(read))) == SettingsReader.Serialize(read), "Round trip changed values");
foreach (var field in new[] { "DisplayMode", "PlaybackOrder", "TransitionEffect", "Language", "SetupCompleted" }) current.Remove(field);
Check(SettingsReader.Parse(current.ToJsonString()).TransitionEffect == "Instant", "v1.2 default missing");
foreach (var (key, value) in new (string, JsonNode?)[] {
    ("SchemaVersion", 4), ("IntervalMinutes", 0), ("IntervalMinutes", 1441),
    ("IntervalMinutes", 1.5), ("AutoStart", "true"), ("AutoStart", null),
    ("PlaybackOrder", "random"), ("DisplayMode", "Span"), ("TransitionEffect", "Fade"),
    ("Primary", null), ("Language", "invalid"), ("SetupCompleted", 1) })
{
    var invalid = JsonNode.Parse(encoded)!.AsObject(); invalid[key] = value; Reject(invalid.ToJsonString());
}
foreach (var invalidPaths in new JsonNode[] { new JsonArray("relative"), new JsonArray("C:relative"), new JsonArray(""), JsonValue.Create("D:\\Pictures")! })
{
    var invalid = JsonNode.Parse(encoded)!; invalid["Primary"]!["Roots"] = invalidPaths; Reject(invalid.ToJsonString());
}
Reject("null"); Reject("[]"); Reject("{}"); Reject("{");
var invalidLegacy = JsonNode.Parse(legacy)!; invalidLegacy["PortraitMinWidth"] = -1; Reject(invalidLegacy.ToJsonString());
var temp = Path.Combine(Path.GetTempPath(), "dsw-config-" + Guid.NewGuid() + ".json");
try
{
    File.WriteAllText(temp, legacy, new System.Text.UTF8Encoding(true));
    var before = File.ReadAllBytes(temp);
    _ = SettingsReader.Load(temp);
    Check(before.SequenceEqual(File.ReadAllBytes(temp)), "Loading rewrote legacy file");
}
finally { File.Delete(temp); }
Console.WriteLine($"PASS: {assertions} migration, validation and non-mutating read assertions.");
