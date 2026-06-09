Write-Host ""
Write-Host "Robocopy 128 Thread"
Write-Host "-------------------"
Write-Host "Enter a local path like:"
Write-Host "  D:\Users\STC"
Write-Host ""
Write-Host "Or a network path like:"
Write-Host "  \\server\share\folder"
Write-Host ""

$source = Read-Host "Source"
$source = $source.Trim().Trim('"')

if ([string]::IsNullOrWhiteSpace($source)) {
    Write-Host "No source entered. Exiting."
    Pause
    exit 1
}

if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    Write-Host "Source folder does not exist. Exiting."
    Write-Host $source
    Pause
    exit 1
}

Write-Host ""
$dest = Read-Host "Destination"
$dest = $dest.Trim().Trim('"')

if ([string]::IsNullOrWhiteSpace($dest)) {
    Write-Host "No destination entered. Exiting."
    Pause
    exit 1
}

$log = "C:\Temp\backup_bench_logs\robocopy_128_thread\robocopy.log"
$timeLog = "C:\Temp\backup_bench_logs\robocopy_128_thread\robocopy-time.txt"

$logFolder = Split-Path -Parent $log
$timeLogFolder = Split-Path -Parent $timeLog

New-Item -ItemType Directory -Force -Path $logFolder | Out-Null
New-Item -ItemType Directory -Force -Path $timeLogFolder | Out-Null

Write-Host ""
Write-Host "Copying:"
Write-Host "  Source:      $source"
Write-Host "  Destination: $dest"
Write-Host ""

$start = Get-Date

robocopy $source $dest `
  /E `
  /COPY:DAT `
  /DCOPY:DAT `
  /XJ `
  /MT:128 `
  /R:3 `
  /W:5 `
  /LOG:$log

$exitCode = $LASTEXITCODE
$end = Get-Date
$duration = $end - $start

$status = if ($exitCode -le 7) {
    "Completed without fatal failure"
} else {
    "Failed"
}

@"
Source:           $source
Destination:      $dest
Start:            $start
End:              $end
Duration:         $duration
Seconds:          $([math]::Round($duration.TotalSeconds, 2))
Minutes:          $([math]::Round($duration.TotalMinutes, 2))
Robocopy ExitCode: $exitCode
Status:           $status
"@ | Tee-Object -FilePath $timeLog

if ($exitCode -le 7) {
    Write-Host "Robocopy completed without fatal failure."
} else {
    Write-Host "Robocopy failed. Check $log"
}

Write-Host ""
Pause
