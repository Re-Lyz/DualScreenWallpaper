# DualScreenWallpaper

[简体中文](README.md) | English | [Roadmap / TODO](TODO.md)

A Windows wallpaper slideshow with Primary and Secondary profiles, folder exclusions and independent image filters. See `VERSION` and `CHANGELOG.md` for version history.

## Getting started

Requires Windows 11, Windows PowerShell 5.1, Windows Script Host (VBScript) and Task Scheduler. No PowerShell modules need to be downloaded.

1. Run `DualScreenWallpaper-1.4.0-Setup.exe`, or extract the ZIP / clone this repository to a writable, permanent local folder.
2. Open Settings from the Start Menu, or run `00-settings.cmd` / `Open-Settings.vbs`. Fresh configurations open the setup wizard; existing configured libraries skip it.
3. Select **English** from **语言 / Language** at the top. The interface changes immediately and remembers your choice without discarding unsaved edits.
4. Add image folders in the **Primary** and **Secondary** tabs. Use one absolute path per line. Subfolders are scanned recursively. Add folders to skip in each tab's exclusion list.
5. Configure filters and the interval, then click **Save and apply**.

The first launch creates `config.json` from `config.example.json`. Settings without a language preference default to Simplified Chinese. Language changes do not rebuild the index or change wallpapers. Native dialogs and operating-system errors follow Windows settings; diagnostic logs keep their original language. Translations are maintained in `Language.ps1`.

## Screens and filters

The Windows primary display uses Primary. All other displays share Secondary, regardless of rotation. Each profile needs an image folder with eligible images. Both have independent orientation and minimum-resolution switches. Disabled filters retain their values. Orientation filtering excludes square images; zero minimum width or height leaves that dimension unrestricted. Both enabled thresholds must be met.

Exclusions accept absolute paths, including folders that do not exist yet; wildcards are not supported. Excluding `D:\Pictures\Private` excludes its entire tree but not `D:\Pictures\Private2`. Exclusions affect only their own profile. Junctions and symbolic links are skipped. If no eligible images remain, indexing fails and keeps the previous index.

Legacy settings load Landscape as Primary and Portrait as Secondary. If your Windows primary screen was portrait, review and swap folders and rules as needed. The first save of migrated settings creates a backup in `data/config-v1-*.json`. Apply rebuilds legacy indexes automatically.

## Slideshow

The display mode applies to all screens: Fill keeps aspect ratio and crops edges; Fit shows the whole image with possible borders; Stretch covers the screen with possible distortion; Center uses original size and may crop; Tile repeats at original size. Existing settings default to Fill. Choose Random to avoid consecutive repeats, or Sequential to loop in filename order. JPEG EXIF orientation is respected. Multi-frame images use their first frame. JPG and PNG headers are read during indexing; other formats such as WebP and HEIC depend on Windows decoders. Source images remain unchanged. Two JPEG caches are reused per monitor.

Refresh the index after adding, moving or deleting images. Changing only the interval, display mode, playback order or language reuses the index. Disabling automatic slideshow and choosing Save and apply changes wallpapers once and removes the scheduled task. Stop and restore attempts to restore the original static wallpapers; it cannot restore dynamic wallpapers, Spotlight or another slideshow's configuration.

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

The application contacts GitHub and its release download services only when you manually check for or download updates. Version comparison happens locally; no images, library paths or settings are uploaded, and there is no telemetry. `config.json`, `data/` and `dist/` are ignored by Git. Release packages include only an explicit list of application files. Do not upload personal paths, indexes, logs or backups when sharing the project.

See [TODO.md](TODO.md) for future features.

## Folder drops and resolution presets

Drop multiple folders into either image or exclusion lists; paths are deduplicated and invalid items reported. Both profiles offer landscape and portrait minimum-resolution presets. Selecting one fills width and height without enabling filtering or changing orientation rules. Custom dimensions remain editable.

## Playback order, settings transfer and previews

- **Playback order:** Sequential sorts by filename, then full path for ties, and loops. This is text sorting rather than natural numeric sorting; use prefixes such as 01 and 02. Each monitor resumes after its last successfully displayed image, including after restarting. If that image is absent from a refreshed index, playback starts at the first image. Missing or unreadable images are skipped. Older settings default to Random.
- **Export settings:** Exports the current form, including unsaved edits, without images, indexes or playback state. Review local paths before sharing.
- **Import settings:** Validates current or legacy JSON, loads it into the form, and reports missing folders in the log. This replaces unsaved form edits. Save and apply (or Refresh index) writes the settings, backing up the original to `data/config-before-import-*.json` first. Language changes after import also remain staged until saving. Images are not copied; adjust paths when moving to another computer.
- **Preview:** Shows connected monitor positions and current wallpapers. Choose a sample for each display and compare all five display modes. The dialog starts with the unsaved display mode; Use this display mode only updates the form until saving and applying. Samples are not added to the library and do not represent the next slideshow image. Tile is illustrated per screen; Windows multi-monitor tiling may differ.

Run feature tests with isolated images and a simulated desktop (no real wallpaper changes):

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-Features.ps1
```
## Installer and first-run setup

The installer defaults to `%LOCALAPPDATA%\Programs\DualScreenWallpaper`, requires no administrator privileges, and supports another writable folder, Start Menu group and optional desktop shortcut. The installer is in English; Settings and the wizard support Chinese and English. For a fresh Chinese-default configuration, cancel the wizard, choose English in Settings, then reopen Setup wizard.

The four-step wizard checks prerequisites and directory access, displays actual monitor assignments, configures both libraries and filters, then slideshow/display preferences with preview. With one monitor, an empty Secondary library inherits Primary folders and disables its initial filters. Finish and apply saves, scans and applies; Cancel does not save or affect wallpapers/tasks. Setup wizard is also available from the top of Settings. Scan errors remain visible for correction.

Close Settings before upgrading in the same directory. Upgrades preserve `config.json` and `data/`; downgrades and relocating an existing installation through an upgrade are rejected. Uninstall through Windows Installed apps or the Start Menu shortcut. Removal stops only the slideshow task pointing to this installation and attempts to restore original static wallpapers. Another copy's task is left untouched. Configuration, caches and backups remain in the installation folder for manual removal when no longer needed.

Building requires [Inno Setup 6.7 or later](https://jrsoftware.org/isdl.php); running the application does not. Release artifacts are not code signed.

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-Setup.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Installer.ps1
# Optional explicit compiler path:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Installer.ps1 -CompilerPath 'C:\Tools\Inno Setup 6\ISCC.exe'
```

`Test-Installer.ps1` performs a real temporary installation, upgrade, downgrade rejection and uninstall, including shortcut and configuration checks. It refuses to run if an installed copy is already registered; use a test account or VM. It does not create slideshow tasks or change wallpapers. Logs and retained test data remain under ignored `data/installer-test-*` directories.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the focused refactor and why a full rewrite is not currently warranted.

## Transition effects and online updates

Playback order and transition effect are separate settings. Choose Instant (the legacy default) or Crossfade. Crossfade renders eight intermediate frames per monitor, targeting about 0.8 seconds; Windows wallpaper application latency can extend this and affect smoothness. Tile, screens over 16 million pixels, unreadable previous wallpapers and transition failures use direct switching. Two extra transition caches are reused per monitor.

Check for updates manually reads the latest stable GitHub release and displays its notes. Download update selects EXE for an installed copy or ZIP for a portable copy, verifying size and SHA-256. Update and restart closes Settings, backs up files and updates while preserving saved configuration and data. Save pending edits first. Installed copies run the installer; portable copies replace program files. There are no automatic startup checks or automatic installations.

Downloads, logs and backups remain under `data/updates/<update-job>/`. Portable copy failures attempt automatic rollback. For manual recovery, close Settings and run that job's `Restore.cmd` to restore backed-up programs and configuration. Installed-copy file recovery does not rewrite installation registration. Backups are not automatically deleted; remove old job directories once recovery is no longer needed.

Both distributions have the same features. The installer adds Start Menu shortcuts, an optional desktop shortcut and Windows uninstall registration; the portable ZIP runs after extraction. Both create a scheduled task when automatic slideshow is enabled; stop it before moving the folder. Version 1.3.0 and earlier require a manual upgrade to obtain the built-in updater.

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-Updates.ps1
# Optional live GitHub query, download and verification:
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-Updates.ps1 -LiveCheck
```