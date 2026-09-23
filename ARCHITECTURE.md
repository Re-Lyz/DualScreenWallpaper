# Architecture and refactoring decision

The application remains a Windows PowerShell 5.1 / WinForms utility using IDesktopWallpaper and Task Scheduler. A full rewrite is not justified by the current feature set: it would replace working OS integration, configuration migration and image handling without a demonstrated user benefit.

This release separates the responsibilities that were growing together:

| File | Responsibility |
| --- | --- |
| `Settings.ps1` | Main window, localization events and background-worker orchestration |
| `Settings.Controls.ps1` | Shared folder/filter controls used by Settings and the wizard |
| `Settings.Persistence.ps1` | Form-to-config mapping, staged import/export and saving |
| `SetupWizard.ps1` | First-run prerequisites, monitor confirmation and guided setup |
| `Config.ps1` | Configuration migration/validation, filtering and playback ordering |
| `ImageProcessing.ps1` | Monitor geometry, image decoding, EXIF orientation and conversion |
| `Preview.ps1` | Read-only layout and rendering preview |
| `Wallpaper.ps1` | Indexing, applying wallpapers and registering the slideshow |
| `Lifecycle.ps1` / `Uninstall.ps1` | Task ownership, maintenance coordination and uninstall cleanup |
| `Package.ps1` | Single explicit release-file allowlist |
| `Release.ps1` / `Build-Installer.ps1` / `Installer.iss` | ZIP and per-user Windows installer builds |
| `Test-*.ps1` | Isolated regression, UI, feature and setup checks |

The UI helper files are dot-sourced, not independent modules: they deliberately share the active form's controls and language. This is an incremental boundary, not a dependency-injection framework. Extract a typed application service or move to compiled C# only if future work (tray process, transitions, many independent monitor profiles) makes long-lived state and UI concurrency significantly more complex.

## Installation invariants

- Install per user into a writable directory. Upgrade in place; keep `config.json` and `data/` unchanged.
- Stage only allowlisted files. Never include personal paths, caches or downloaded build tools.
- Installer maintenance prevents new workers/settings windows from starting; existing operations must close before changing program files.
- Uninstall removes only the scheduled task pointing to this installation's `Run-Wallpaper.vbs`. A different installation's task is left alone.
- Uninstall attempts wallpaper restoration, but keeps configuration, backups and caches. It never recursively deletes the installation directory.
- Uninstall cleanup does not parse `config.json`, so damaged settings do not strand the scheduled task.
- Setup wizard edits are staged until Finish and apply; cancel does not save settings or change wallpapers/tasks. Existing configured installations do not automatically repeat the wizard.

## Validation

Run `Test-Settings.ps1`, `Test-Features.ps1`, `Settings.ps1 -SmokeTest`, and `Test-Setup.ps1` with Windows PowerShell. These use isolated files and mocked task/wallpaper mutation boundaries. Installer integration testing additionally covers actual extraction, repeat installation and removal in a disposable installation directory; it must not point at the user's working installation.
