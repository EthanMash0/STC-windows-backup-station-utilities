$LibRoot = $PSScriptRoot

function robocopy-tool {
	Write-Host ""
	Write-Host "Robocopy CLI Tool"
	Write-Host "-----------------"
	Write-Host "Options:"
	Write-Host "1. 1 Thread"
	Write-Host "2. 8 Threads"
	Write-Host "3. 16 Threads"
	Write-Host "4. 32 Threads"
	Write-Host "5. 64 Threads"
	Write-Host "6. 128 Threads"
	Write-Host "7. Exit"
	Write-Host ""

	do {
		$tool = Read-Host "Enter choice (1-7)"
		$tool = $tool.Trim().Trim('"')

		if ($tool -notin '1', '2', '3', '4', '5', '6', '7') {
			Write-Host "Invalid choice. Enter a number in the range 1-7."
		}
	} while ($tool -notin '1', '2', '3', '4', '5', '6', '7')

	switch ($tool) {
		'1' {
			$mt = 1
		}
		'2' {
			$mt = 8
		}
		'3' {
			$mt = 16
		}
		'4' {
			$mt = 32
		}
		'5' {
			$mt = 64
		}
		'6' {
			$mt = 128
		}
		'7' {
			Write-Host "Exiting."
			return
		}
	}

	$padded = $mt.ToString("D3")
	$title = "Robocopy $padded Thread"
	$log = "C:\Temp\backup_bench_logs\robocopy_${padded}_thread\robocopy.log"
	$timeLog = "C:\Temp\backup_bench_logs\robocopy_${padded}_thread\robocopy-time.txt"

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
	$dest = Read-Host "Destination"
	$dest = $dest.Trim().Trim('"')

	if ([string]::IsNullOrWhiteSpace($dest)) {
			Write-Host "No destination entered. Exiting."
			Pause
			return
	}

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
		/MT:$mt `
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
}
