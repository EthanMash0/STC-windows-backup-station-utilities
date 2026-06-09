Write-Host ""
Write-Host "DISM Compress None"
Write-Host "------------------"
Write-Host "Enter a source folder like:"
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
Write-Host "Enter a destination image file like:"
Write-Host "  Z:\benchmark\dism_compress_none\STC.wim"
Write-Host ""

$dest = Read-Host "Destination"
$dest = $dest.Trim().Trim('"')

if ([string]::IsNullOrWhiteSpace($dest)) {
    Write-Host "No destination entered. Exiting."
    Pause
    exit 1
}

$name = "STC"

$log = "C:\Temp\backup_bench_logs\dism_compress_none\dism-wim.log"
$timeLog = "C:\Temp\backup_bench_logs\dism_compress_none\dism-wim-time.txt"
$scratchDir = "C:\Temp\dism_scratch"

$destFolder = Split-Path -Parent $dest
$logFolder = Split-Path -Parent $log
$timeLogFolder = Split-Path -Parent $timeLog

if (-not [string]::IsNullOrWhiteSpace($destFolder)) {
    New-Item -ItemType Directory -Force -Path $destFolder | Out-Null
}

New-Item -ItemType Directory -Force -Path $logFolder | Out-Null
New-Item -ItemType Directory -Force -Path $timeLogFolder | Out-Null
New-Item -ItemType Directory -Force -Path $scratchDir | Out-Null

Write-Host ""
Write-Host "Capturing image:"
Write-Host "  Source:      $source"
Write-Host "  Destination: $dest"
Write-Host ""

$start = Get-Date

dism /Capture-Image `
  /ImageFile:$dest `
  /CaptureDir:$source `
  /Name:$name `
  /Compress:none `
  /CheckIntegrity `
  /Verify `
  /ScratchDir:$scratchDir `
  > $log 2>&1

$exitCode = $LASTEXITCODE
$end = Get-Date
$duration = $end - $start

@"
Source:        $source
Destination:   $dest
Start:         $start
End:           $end
Duration:      $duration
Seconds:       $([math]::Round($duration.TotalSeconds, 2))
Minutes:       $([math]::Round($duration.TotalMinutes, 2))
DISM ExitCode: $exitCode
"@ | Tee-Object -FilePath $timeLog

if ($exitCode -eq 0) {
    Write-Host "DISM completed successfully."
} else {
    Write-Host "DISM failed. Check $log"
}

Write-Host ""
Pause
