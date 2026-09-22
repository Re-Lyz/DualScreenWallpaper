# DualScreenWallpaper

[简体中文](README.md) | English | [Roadmap / TODO](TODO.md)

A Windows wallpaper slideshow with Primary and Secondary profiles, folder exclusions and independent image filters. See `VERSION` and `CHANGELOG.md` for version history.

## Getting started

Requires Windows 11, Windows PowerShell 5.1, Windows Script Host (VBScript) and Task Scheduler. No PowerShell modules need to be downloaded.

1. Download or clone this repository to a writable, permanent local folder.
2. Open `00-settings.cmd` or `Open-Settings.vbs`.
3. Select **English** from **语言 / Language** at the top. The interface changes immediately and remembers your choice without discarding unsaved edits.
4. Add image folders in the **Primary** and **Secondary** tabs. Use one absolute path per line. Subfolders are scanned recursively. Add folders to skip in each tab's exclusion list.
5. Configure filters and the interval, then click **Save and apply**.

The first launch creates `config.json` from `config.example.json`. Settings without a language preference default to Simplified Chinese. Language changes do not rebuild the index or change wallpapers. Native dialogs and operating-system errors follow Windows settings; diagnostic logs keep their original language. Translations are maintained in `Language.ps1`.

## Screens and filters

The Windows primary display uses Primary. All other displays share Secondary, regardless of rotation. Each profile needs an image folder with eligible images. Both have independent orientation and minimum-resolution switches. Disabled filters retain their values. Orientation filtering excludes square images; zero minimum width or height leaves that dimension unrestricted. Both enabled thresholds must be met.

Exclusions accept absolute paths, including folders that do not exist yet; wildcards are not supported. Excluding `D:\Pictures\Private` excludes its entire tree but not `D:\Pictures\Private2`. Exclusions affect only their own profile. Junctions and symbolic links are skipped. If no eligible images remain, indexing fails and keeps the previous index.

Legacy settings load Landscape as Primary and Portrait as Secondary. If your Windows primary screen was portrait, review and swap folders and rules as needed. The first save of migrated settings creates a backup in `data/config-v1-*.json`. Apply rebuilds legacy indexes automatically.

## Slideshow

The current mode is Fill: wallpapers cover each screen and may be cropped. Random selection tries to avoid consecutive repeats. JPEG EXIF orientation is respected. Multi-frame images use their first frame. JPG and PNG headers are read during indexing; other formats such as WebP and HEIC depend on Windows decoders. Source images remain unchanged. Two JPEG caches are reused per monitor.

Refresh the index after adding, moving or deleting images. Changing only the interval or language reuses the index. Disabling automatic slideshow and choosing Save and apply changes wallpapers once and removes the scheduled task. Stop and restore attempts to restore the original static wallpapers; it cannot restore dynamic wallpapers, Spotlight or another slideshow's configuration.

The task name is `DualScreenWallpaper-1Minute`; its actual interval comes from your settings. Multiple installations share this task. To move the installation, stop the slideshow, move the whole folder, then save and apply from the new location. Closing Settings does not stop the slideshow. Other wallpaper software may override it.

## Shortcuts

| File | Action |
| --- | --- |
| `00-settings.cmd` | Settings |
| `01-install.cmd` | Apply and install slideshow |
| `02-refresh-index.cmd` | Rebuild image index |
| `03-change-now.cmd` | Change wallpapers now |
| `04-stop-and-restore.cmd` | Stop and restore static wallpapers |
| `05-show-monitors.cmd` | Inspect monitors |

## Checks and releases

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Settings.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Settings.ps1 -SmokeTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Release.ps1
```

Tests use isolated fixtures without changing wallpapers or installing tasks. To release a new version, add its `CHANGELOG.md` entry, then run `Release.ps1 -NewVersion X.Y.Z`. Versions must increase; existing archives cannot be overwritten. Review and commit changes before creating a Git tag. Preserve `config.json` and `data/` during upgrades.

The application makes no network requests and uploads no images. `config.json`, `data/` and `dist/` are ignored by Git. Release packages include only an explicit list of application files. Do not upload personal paths, indexes, logs or backups when sharing the project.

See [TODO.md](TODO.md) for future features.
