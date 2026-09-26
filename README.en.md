# DualScreenWallpaper

[简体中文](README.md) | English | [Roadmap](TODO.md)

A Windows wallpaper slideshow with independent monitor profiles, mixed folder/file sources, resizable settings, previews, installers and updates.

The current C# / .NET 10 implementation is in `src/`, with its version in `src/VERSION`. Version 2.0 is a locally installed candidate, not a published GitHub Release. Real-desktop crossfade acceptance remains pending. Legacy indexes are not yet migrated, so first use requires a new scan.

- [Current usage, build instructions and validation](src/README.md)
- [Architecture](ARCHITECTURE.md)
- [Archived PowerShell 1.4.0 project](legacy/v1.4.0/README.en.md)

`legacy/v1.4.0/` contains the old application, packaging scripts and historical documentation. The current application builds without legacy sources. Do not run the archived scripts against an active installation.

`data/` holds local tools, test results and backups; `dist/` holds build artifacts. Both are excluded from Git and remain in place. Personal settings and the installed application are unaffected by this source reorganization.
