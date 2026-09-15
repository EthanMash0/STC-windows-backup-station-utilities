# STC Windows Backup Station Utilities

Menu-driven PowerShell tools for Yale Student Technology Collaborative (STC) Windows backup stations. Use them to copy a user's data with Robocopy and to check folder size before or after a backup.

## Requirements

- Windows
- PowerShell (Windows PowerShell 5.1 or later)
- Built-in `robocopy.exe`
- Writable `C:\Temp` for copy logs
- Administrator rights (recommended; `run.bat` always requests elevation)

## How to run

Double-click `run.bat`. That opens an elevated PowerShell window in this folder and starts `BackupBench.ps1`.

To run the menu yourself:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\STC-windows-backup-station-utilities\BackupBench.ps1"
```

There are no command-line arguments. Source, destination, and options are entered in the console.

## Tools

### Copy Data

Robocopy-based folder copy with three presets:

| Option | Threads |
|--------|---------|
| Slow | 1 |
| Standard | 16 |
| Fast | 64 |

Enter a source folder and a destination (local or UNC). The tool does a dry run to estimate totals, then copies with live overall and per-file progress.

Copies use `/E` (subfolders, including empty), data/attributes/timestamps, and retries (`/R:3 /W:5`). Junctions are excluded (`/XJ`).

Logs and a timing summary are written to:

```
C:\Temp\backup_logs\robocopy_<threads>_thread\
```

Example: `C:\Temp\backup_logs\robocopy_016_thread\robocopy-20260914-184600.log`

A Robocopy exit code of 7 or lower is treated as success (no fatal failure). Higher codes mean the copy failed; check the log.

### Calculate Folder Size

Recursively counts files, folders, and total bytes at a path you enter. Long paths are supported via the `\\?\` prefix (including UNC).

## Paths

You can enter a local path or a network share. Surrounding quotes are stripped.

```
D:\Users\STC
\\server\share\folder
```

## Project layout

```
BackupBench.ps1    Main menu
run.bat            Elevated launcher
lib/
  Common.ps1       Shared path prompt
  Robocopy.ps1     Copy tool
  FolderSize.ps1   Folder size tool
```
