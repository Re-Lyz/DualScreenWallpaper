# DualScreenWallpaper

[简体中文](README.md) | English | [Roadmap](TODO.md) | [Changelog](CHANGELOG.md)

An independent wallpaper slideshow for multiple Windows monitors, built with C# / .NET 10. Combine folders and individual images, configure filters per monitor, preview placement, and choose random or sequential playback independently from Instant or Crossfade transitions. Scheduled tasks keep the slideshow running after Settings closes, without a resident background application.

## Download

**Version 2.0.1 · Windows 11 x64.** Download from [GitHub Releases](https://github.com/Re-Lyz/DualScreenWallpaper/releases/latest).

| Asset | Usage |
| --- | --- |
| `DualScreenWallpaper-2.0.1-Setup.exe` | Recommended installer; includes the runtime, shortcuts and uninstall support |
| `DualScreenWallpaper-2.0.1.zip` | Portable package with runtime; extract to a writable directory |
| `DualScreenWallpaper-2.0.1-FrameworkDependent.zip` | Small portable package; requires .NET Desktop Runtime 10 x64 |
| `*.sha256` | SHA-256 checksum for the matching asset |

Runtime-included packages expand to approximately 154 MiB. Open `DualScreenWallpaper.exe`, select monitor profiles and image sources, then configure playback. Enable **Automatic slideshow and run at logon**, and choose **Save and apply**. This immediately changes the wallpaper; closing Settings afterward does not stop the schedule.

**Stop and restore** persists the disabled state and restores available original static wallpapers. Settings shows the actual task status, last result and next run. The window and log area are resizable. Fill, Fit, Stretch, Center and Tile modes, drag-and-drop sources, and configuration import/export are supported.

## Upgrading and compatibility

- Installed 1.4 copies can upgrade in place while retaining `config.json` and `data/`.
- Portable 1.4 copies require a manual first migration: back up and stop the old slideshow, then transfer configuration and data to the new package. The old updater cannot apply binary packages.
- Old image indexes are not converted automatically; first use of 2.x requires a new scan, then reuses the cache.
- On 2026-10-06, the user confirmed visible crossfade on their actual setup. Incompatible desktop environments fall back to direct switching with a log entry. RDP and broader hardware coverage remain unverified.

The old PowerShell/VBScript application has been removed from the current tree and remains available in [v1.4.0 history](https://github.com/Re-Lyz/DualScreenWallpaper/tree/v1.4.0). PowerShell is still used for build and test scripts.

## Development

Source and version are in `src/` and `src/VERSION`. Use .NET 10 SDK; installer builds additionally require Inno Setup 6.7+. Run `src/Test.ps1` for regressions and `src/Build.ps1 -Installer` for packaging. See [detailed usage/build notes](src/README.md) and [architecture](ARCHITECTURE.md).

Local `data/`, `dist/`, personal configuration, logs and backups are excluded from Git.
