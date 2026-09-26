# STC Windows Backup Station Utilities

Menu-driven PowerShell tools for Yale Student Technology Collaborative (STC) Windows backup stations. Use them to copy a client's data with Robocopy and to check folder size before or after a backup.

There are no command-line arguments. Source, destination, and options are entered in the console.

## Requirements

- Windows
- Windows PowerShell 5.1 or later
- Built-in `robocopy.exe`
- Write access so the copy tool can create `C:\Temp\backup_logs`
- Administrator rights (`run.bat` always requests elevation via UAC)

Use a normal `powershell.exe` window. Some hosts (PowerShell ISE, remoting) cannot resize the window or set colors; the tools still run, but the UI may look wrong.

## How to run

Double-click `run.bat`. That opens an elevated PowerShell window in this folder and starts `BackupTool.ps1`. Approve the UAC prompt.

To run the menu yourself (this command does not elevate; right-click PowerShell and run as administrator if you need that):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\STC-windows-backup-station-utilities\BackupTool.ps1"
```

The console title is `STC Backup Station`. When the host allows it, the window is set to a black background, UTF-8 output, and a minimum width of 80 columns.

The main menu is **Copy Data**, **Folder Size**, and **Exit**. After a copy or folder-size run finishes, you can return to the main menu or exit. Canceling before a run starts (empty path, **Back**) returns to the main menu without that prompt.

## Tools

### Copy Data

Robocopy-based folder copy. Choose a speed preset, or **Back** to the main menu:

| Option | Threads | Meaning |
|--------|---------|---------|
| Slow | 1 | One file at a time |
| Standard | 16 | Up to 16 files at a time |
| Fast | 64 | Up to 64 files at a time |

Enter a source folder (must already exist) and a destination (local, mapped drive, or UNC). Surrounding quotes and a trailing backslash are stripped. Invalid paths can be re-entered. Enter with an empty source or destination cancels and returns to the main menu.

The destination does not have to exist yet. It is accepted when an ancestor folder exists so Robocopy can create the final directory. If no ancestor exists, the tool rejects the path.

You then get a **Confirm Copy** summary (source, destination, preset):

1. Start copy
2. Change source
3. Change destination
4. Change both paths
5. Back to main menu

When changing one path, Enter keeps the current value. Changing both paths and then canceling leaves the previous pair unchanged.

After you start, the tool does a dry run to estimate total size and file count, then copies with live overall progress (data and files) and per-file progress. When it finishes, it shows a summary (paths, size, file count, timing, Robocopy exit code, status, and log path) and writes the same timing summary next to the Robocopy log. The summary's size and file count come from the initial estimate.

Robocopy runs as a separate process and writes directly to its log. Like the Folder Size tool, the copy tool processes available activity continuously and limits only screen refreshes to once every 100 milliseconds. It waits for new data only after catching up with the log, so the read-buffer size does not limit processing to one chunk per refresh. Console rendering cannot block Robocopy through an output pipe.

The original progress display is approximate: file listings do not confirm completed writes, and multithreaded percentage messages do not identify which file they belong to. The Current File box retains the original association with the most recently listed file. Completion is determined by the process exiting, not by a percentage reaching 100%. Log buffering can delay updates. As before, parsing estimates and file activity expects English Robocopy output.

#### What is copied

Copies use:

- `/E` — subfolders, including empty ones
- `/COPY:DAT` and `/DCOPY:DAT` — data, attributes, and timestamps for files and directories (not NTFS ACLs, owner, or auditing)
- `/XJ` — junctions excluded (important on user profiles)
- `/R:3 /W:5` — 3 retries, 5 seconds between retries
- `/MT:<threads>` — the Slow / Standard / Fast preset
- `/UNILOG:` — Unicode log file, read by the progress display; no `/TEE`
- `/FP` — log full file paths; per-file percentages remain enabled

This is a copy, not a mirror. Extra files already in the destination are left alone. Hidden and system files are included. Junctions are not followed.

#### Logs

Logs and a timing summary are written under `C:\Temp\backup_logs`. The thread count in the folder name is padded to two digits:

| Preset | Folder |
|--------|--------|
| Slow (1) | `C:\Temp\backup_logs\robocopy_01_thread\` |
| Standard (16) | `C:\Temp\backup_logs\robocopy_16_thread\` |
| Fast (64) | `C:\Temp\backup_logs\robocopy_64_thread\` |

Each run writes:

- `robocopy-yyyyMMdd-HHmmss-<id>.log` — Robocopy log in UTF-16, including file activity, errors, and the final summary
- `robocopy-time-yyyyMMdd-HHmmss-<id>.txt` — timing and status summary

The eight-character run ID keeps simultaneous runs from sharing a log. Example: `C:\Temp\backup_logs\robocopy_16_thread\robocopy-20260914-184600-a13b4c5d.log`

The log reader uses 64 KB buffers and immediately reads another chunk when more data is available. On process exit, it reads the final summary without replaying a backlog of activity and uses its copied totals for the final overall progress update when available. Reported duration uses the process start and exit times and excludes the initial estimate and UI cleanup. Ctrl+C or a monitoring error triggers cleanup that stops an active child process and closes the log reader.

#### Robocopy exit codes

Exit codes **0 through 7** are treated as success (no fatal failure). **8 or higher**, or a negative process exit code, means the copy failed; check the log.

Robocopy returns a bit mask. The base flags are **1** (files copied), **2** (extra files or directories on the destination), **4** (mismatched files or directories), **8** (copy failures after retries), and **16** (serious error). Combined values are the sum of those flags:

| Code | Flags | Meaning |
|------|-------|---------|
| 0 | | No files were copied. No failure. No mismatches. The trees already match. |
| 1 | 1 | Files were copied successfully. |
| 2 | 2 | Extra files or directories on the destination. No files were copied. |
| 3 | 1+2 | Files were copied. Extra files were present. No failure. |
| 4 | 4 | Mismatched files or directories. No files were copied. |
| 5 | 1+4 | Files were copied. Some files were mismatched. No failure. |
| 6 | 2+4 | Extra files and mismatched files. No files were copied. No failure. |
| 7 | 1+2+4 | Files were copied. Mismatches and extra files were present. No failure. |
| 8 | 8 | Some files or directories could not be copied (retry limit exceeded). |
| 9 | 1+8 | Files were copied, but some copy failures occurred. |
| 10 | 2+8 | Extra files present, and some copy failures. |
| 11 | 1+2+8 | Files were copied, extra files were present, and some copy failures. |
| 12 | 4+8 | Mismatches present, and some copy failures. |
| 13 | 1+4+8 | Files were copied, mismatches were present, and some copy failures. |
| 14 | 2+4+8 | Extra files, mismatches, and some copy failures. |
| 15 | 1+2+4+8 | Files were copied; extra files, mismatches, and copy failures. |
| 16 | 16 | Serious error. Robocopy did not copy any files (usage error or insufficient access). |

### Folder Size

Recursively counts files, subfolders, and total bytes at a path you enter (must already exist). Hidden and system items are included.

While it scans, it shows live size, file count, folder count, and the path currently being read. The final summary repeats the path you typed, the total size (human-readable and bytes), and the file and folder counts.

Long paths are supported via the `\\?\` prefix:

- Local: `C:\folder` → `\\?\C:\folder`
- UNC: `\\server\share\folder` → `\\?\UNC\server\share\folder`

Access-denied items are skipped silently so the progress display stays in place. Counts only include readable items, so a locked or permission-denied tree can under-report.

Enter with an empty path cancels and returns to the main menu.

## Paths

You can enter a local path, a mapped drive letter, or a UNC share. Surrounding quotes are stripped. A trailing backslash is removed.

```
D:\Users\STC
Z:\Backups\jdoe
\\server\share\folder
```

Source (Copy Data) and Path (Folder Size) must already exist. Destination (Copy Data) may be created if a parent folder exists.

## Troubleshooting

### Mapped drives missing in the elevated window (`Z:`, `X:`, and similar)

`run.bat` always starts an **elevated** PowerShell session. Windows gives your normal desktop session and that elevated session separate logon tokens. Drive letters mapped in the normal user session (for example `Z:` to a backup share) often do **not** appear in the admin window.

Symptoms:

- `net use Z:` in the elevated window reports that the drive is not there
- The tool says the source or destination folder does not exist when you enter `Z:\...`
- The same path works in a non-admin Explorer or PowerShell window

#### Longer-term fix: `EnableLinkedConnections`

This registry value tells Windows to share those mapped drives between the filtered (standard) token and the elevated token.

Run this from an **elevated** PowerShell, then **restart Windows**:

```powershell
New-ItemProperty `
  -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
  -Name 'EnableLinkedConnections' `
  -PropertyType DWord `
  -Value 1 `
  -Force
```

Verify after the reboot:

```powershell
Get-ItemProperty `
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
  -Name EnableLinkedConnections
```

You should see:

```
EnableLinkedConnections : 1
```

If `Z:` (or `X:`, or any other mapped letter) is mapped in the same user's normal session, an elevated PowerShell launched by that user should then accept:

```powershell
net use Z:
```

and paths like `Z:\Backups\jdoe` in this tool.

This is a machine-wide setting. Apply it once on each backup station.

#### Workaround without a reboot

Type the **UNC path** instead of the drive letter:

```
\\server\share\folder
```

A UNC path does not depend on the mapped letter being visible in the elevated session. You still need permission to that share from the elevated token.

## Project layout

```
BackupTool.ps1     Main menu
run.bat            Elevated launcher (UAC)
lib/
  Ui.ps1           Headers, boxes, menus, colors
  Common.ps1       Shared path prompt and size formatting
  Robocopy.ps1     Copy tool
  FolderSize.ps1   Folder size tool
```
