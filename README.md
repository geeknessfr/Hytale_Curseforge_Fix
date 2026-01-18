# Hytale CurseForge Fix (Windows)
- Temporary Fix until CurseForge update - I'll remove this repo when fixed.

This script fixes a CurseForge/Hytale mod setup issue with mods installed at the wrong location on Windows by moving mods/plugins into the game install folder and linking Hytale’s roaming `UserData` folder to that location.

In short: your mods end up where the game expects them, and CurseForge stops writing to the “wrong” place.

## What it does

- Reads Hytale’s install path from the Windows registry:
  - `HKEY_CURRENT_USER\Software\Hypixel Studios\Hytale`
  - value: `GameInstallPath`
- Uses that path to locate the game folder:
  - `<GameInstallPath>\UserData`
- Looks for these folders in your roaming profile:
  - `%APPDATA%\UserData\mods`
  - `%APPDATA%\UserData\earlyplugins`
- Merges their contents into the game’s `UserData` folder.
  - If a file already exists on both sides, it keeps **the most recently modified** version.
  - The “older” version is moved into a backup folder:
    - `<GameInstallPath>\UserData\mods.backup\<timestamp>\...`
    - `<GameInstallPath>\UserData\earlyplugins.backup\<timestamp>\...`
- If `%APPDATA%\UserData` contains unexpected extra files/folders (besides `mods` and `earlyplugins`), they are backed up in AppData before the link is created.
- Removes `%APPDATA%\UserData` (after merging/backup), then creates a **directory symlink**:
  - `%APPDATA%\UserData` → `<GameInstallPath>\UserData`

## Requirements

- Windows 10/11
- PowerShell
- Administrator rights (the script will request UAC elevation automatically)

## How to use

1. Close Hytale and CurseForge (recommended).
2. Download `Hytale_CurseForge_Fix.ps1`. (You can download it directly or in the [Releases](https://github.com/geeknessfr/Hytale_Curseforge_Fix/releases))
3. Right click the script and run it with PowerShell (or run it from a PowerShell window).
4. Accept the UAC prompt (admin permission).
5. Read the output log. The script pauses at the end so you can see the result.

That’s it. After this, Hytale and CurseForge should both use the game’s `UserData` folder.

## Where are backups?

- Conflicting mod/plugin files (only when needed):
  - `<GameInstallPath>\UserData\mods.backup\<timestamp>\`
  - `<GameInstallPath>\UserData\earlyplugins.backup\<timestamp>\`
- Unexpected extra AppData content (rare):
  - `%APPDATA%\UserData.root.backup.<timestamp>\`

## Notes

- The script is designed to be safe: it never deletes conflicting files, it moves the “losing” version to backups.
- If `%APPDATA%\UserData` is already a link, the script will detect it and do nothing.

## License

Choose whatever you want (MIT is common). 🙂
