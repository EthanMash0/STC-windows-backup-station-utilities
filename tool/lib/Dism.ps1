$LibRoot = $PSScriptRoot

function dism-tool {
	Write-Host ""
	Write-Host "DISM CLI Tool"
	Write-Host "-------------"
	Write-Host "Options:"
	Write-Host "1. No compression"
	Write-Host "2. Fast compression (XPRESS)"
	Write-Host "3. Max Compression (LZX)"
	Write-Host "4. Exit"
	Write-Host ""

	do {
		$tool = Read-Host "Enter choice (1-4)"
		$tool = $tool.Trim().Trim('"')

		if ($tool -notin '1', '2', '3', '4') {
			Write-Host "Invalid choice. Enter a number in the range 1-4."
		}
	} while ($tool -notin '1', '2', '3', '4')

	switch ($tool) {
		'1' {
			$compression = "none"
		}
		'2' {
			$compression = "fast"
		}
		'3' {
			$compression = "max"
		}
		'4' {
			Write-Host "Exiting."
			return
		}
	}

	$title = "DISM Compress $compression"
	$name = "STC"

	$log = "C:\Temp\backup_bench_logs\dism_compress_${compression}\dism-wim.log"
	$timeLog = "C:\Temp\backup_bench_logs\dism_compress_${compression}\dism-wim-time.txt"
	$scratchDir = "C:\Temp\dism_scratch"

	. "$LibRoot\Common.ps1"
	Show-PathHelp -Title $title

	$source = Read-Host "Source"
	$source = $source.Trim().Trim('"')

	if ([string]::IsNullOrWhiteSpace($source)) {
			Write-Host "No source entered. Exiting."
			Pause
			return
	}

	if (-not (Test-Path -LiteralPath $source -PathType Container)) {
			Write-Host "Source folder does not exist. Exiting."
			Write-Host $source
			Pause
			return
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
			return
	}

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
		/Compress:$compression `
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

}
