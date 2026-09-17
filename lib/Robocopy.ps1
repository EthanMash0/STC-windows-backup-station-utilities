$LibRoot = $PSScriptRoot

# import
. "$LibRoot\Common.ps1"

# shared flags
$script:RobocopyCopyFlags = @(
	'/E',
	'/COPY:DAT',
	'/DCOPY:DAT',
	'/BYTES',
	'/XJ',
	'/R:3',
	'/W:5'
)

# =============================================================================
#  Helpers
# =============================================================================

function Read-RobocopyThreadCount {
	Clear-Host
	Write-Host ""
	Write-Host "Copy Tool (Robocopy based)"
	Write-Host "--------------------------"
	Write-Host "Options:"
	Write-Host ""
	Write-Host "1. Slow (1 Thread)"
	Write-Host "   * 1 copy thread, or 1 file at a time" -ForegroundColor Gray
	Write-Host "2. Standard (16 Threads)"
	Write-Host "   * 16 copy threads, or up to 16 files at a time" -ForegroundColor Gray
	Write-Host "3. Fast (64 Threads)"
	Write-Host "   * 64 copy threads, or up to 64 files at a time" -ForegroundColor Gray
	Write-Host "4. Back"
	Write-Host ""

	do {
		$choice = Read-Host "Enter choice (1-4)"
		$choice = $choice.Trim().Trim('"')

		if ($choice -notin '1', '2', '3', '4') {
			Write-Host "Invalid choice. Enter a number in the range 1-4."
		}
	} while ($choice -notin '1', '2', '3', '4')

	switch ($choice) {
		'1' {
			return 1
		}
		'2' {
			return 16
		}
		'3' {
			return 64
		}
		'4' {
			Write-Host "Exiting."
			return $null
		}
	}
}

function New-RobocopyLogPaths {
	param(
		[int]$ThreadCount
	)

	$padded = $ThreadCount.ToString("D2")
	$title = "Robocopy $padded Thread"
	$runId = Get-Date -Format "yyyyMMdd-HHmmss"
	$log = "C:\Temp\backup_logs\robocopy_${padded}_thread\robocopy-$runId.log"
	$timeLog = "C:\Temp\backup_logs\robocopy_${padded}_thread\robocopy-time-$runId.txt"
	$logFolder = Split-Path -Parent $log

	New-Item -ItemType Directory -Force -Path $logFolder | Out-Null

	return [pscustomobject]@{
		Title = $title
		Log = $log
		TimeLog = $timeLog
	}
}

function Read-CopyPaths {
	param(
		[string]$Title
	)

	Show-PathHelp -Title $Title

	$source = Read-Host "Source"
	$source = $source.Trim().Trim('"').TrimEnd('\')

	if ([string]::IsNullOrWhiteSpace($source)) {
		Write-Host "No source entered. Exiting."
		Pause
		return $null
	}

	if (-not (Test-Path -LiteralPath $source -PathType Container)) {
		Write-Host "Source folder does not exist. Exiting."
		Write-Host $source
		Pause
		return $null
	}

	# Write-Host ""
	# Show-PathHelp

	$dest = Read-Host "Destination"
	$dest = $dest.Trim().Trim('"')

	if ([string]::IsNullOrWhiteSpace($dest)) {
		Write-Host "No destination entered. Exiting."
		Pause
		return $null
	}

	return [pscustomobject]@{
		Source = $source
		Dest = $dest
	}
}

function Get-RobocopyEstimate {
	param(
		[string]$Source,
		[string]$Dest
	)

	$dryRun = robocopy `
		$Source `
		$Dest `
		/L `
		/NFL `
		/NDL `
		/NJH `
		/NP `
		@script:RobocopyCopyFlags

	$totalBytes = [long]($dryRun -match 'Bytes :' -split '[\t ]+')[3]
	$totalFiles = [long]($dryRun -match 'Files :' -split '[\t ]+')[3]

	return [pscustomobject]@{
		TotalBytes = $totalBytes
		TotalFiles = $totalFiles
		TotalMB = [Math]::Round($totalBytes / 1MB, 2)
	}
}

function Write-RobocopySummary {
	param(
		[string]$Source,
		[string]$Dest,
		[datetime]$Start,
		[datetime]$End,
		[int]$ExitCode,
		[string]$TimeLog,
		[string]$Log
	)

	$duration = $End - $Start
	$status = if ($ExitCode -le 7) {
		"Completed without fatal failure"
	} else {
		"Failed"
	}

@"
Source:      $Source
Destination: $Dest
Start:       $Start
End:         $End
Duration:    $duration
Seconds:     $([math]::Round($duration.TotalSeconds, 2))
Minutes:     $([math]::Round($duration.TotalMinutes, 2))
ExitCode:    $ExitCode
Status:      $status
"@ | Tee-Object -FilePath $TimeLog

	Write-Host ""
	if ($ExitCode -le 7) {
		Write-Host "Robocopy completed without fatal failure."
	} else {
		Write-Host "Robocopy failed. Check $Log"
	}
	Write-Host ""
}

function Get-ClampedPercent {
	param(
		[double]$Current,
		[double]$Total
	)

	if ($Total -le 0) {
		return 100
	}

	return [Math]::Min([Math]::Round(($Current / $Total) * 100, 2), 100)
}

function New-ProgressBar {
	param(
		[double]$Percent,
		[int]$BarWidth
	)
	$fillLen = [Math]::Round(($Percent / 100) * $BarWidth)
	$emptyLen = $BarWidth - $fillLen
	$fillStr = [String]::new('=', $fillLen)
	$emptyStr = [String]::new(' ', $emptyLen)

	return ' [' + $fillStr + $emptyStr + '] ' + $Percent + '%'
}

function New-ProgressLayout {
	$barWidth = 40
	$consoleWidth = [Console]::WindowWidth - 1
	$innerWidth = $consoleWidth - 2

	$borderFill = [String]::new('─', $innerWidth)
	$emptyFill = [String]::new(' ', $innerWidth)

	return [pscustomobject]@{
		BarWidth = $barWidth
		ConsoleWidth = $consoleWidth
		InnerWidth = $innerWidth
		OverallStr = " Overall Progress"
		ItemStr = " Current File"
		DataStr = " Data: "
		FilesStr = " Files: "
		PathStr = " Path: "
		SepStr = " / "
		DataUnitStr = " MB"
		Top = "┌" + $borderFill + "┐"
		Bottom = "└" + $borderFill + "┘"
		Cross = "├" + $borderFill + "┤"
		Middle = "│" + $emptyFill + "│"
	}
}

function Format-ProgressBox {
	param(
		$Layout,
		[string]$Title,
		[string[]]$Rows,
		[switch]$TrailingBlank
	)

	$box = @(
		$Layout.Top
		"│" + $Title.PadRight($Layout.InnerWidth) + "│"
		$Layout.Cross
	)

	foreach ($row in $Rows) {
		if ([string]::IsNullOrEmpty($row)) {
			$box += $Layout.Middle
		} else {
			$box += "│" + $row.PadRight($Layout.InnerWidth) + "│"
		}
	}

	$box += $Layout.Bottom

	if ($TrailingBlank) {
		$box += ""
	}

	return $box
}

function Write-CopyProgress {
	param(
		[string[]]$OverallLines,
		[string[]]$ItemLines,
		[int]$CursorTop
	)

	[Console]::SetCursorPosition(0, $CursorTop)
	foreach ($line in $OverallLines) {
		Write-Host $line
	}

	$overallEnd = [Console]::CursorTop
	$itemEnd = $overallEnd

	if ($null -ne $ItemLines) {
		foreach ($line in $ItemLines) {
			Write-Host $line
		}

		$itemEnd = [Console]::CursorTop
	}

	return [pscustomobject]@{
		OverallEnd = $overallEnd
		ItemEnd = $itemEnd
	}
}

# =============================================================================
#  Orchestrator
# =============================================================================

function Invoke-RobocopyTool {
	$threadCount = Read-RobocopyThreadCount
	if ($null -eq $threadCount) {
		return
	}

	$logPaths = New-RobocopyLogPaths -ThreadCount $threadCount

	$copyPaths = Read-CopyPaths -Title $logPaths.Title
	if ($null -eq $copyPaths) {
		return
	}

	# echo paths back to user
	Write-Host ""
	Write-Host "Copying:"
	Write-Host "  Source:      $($copyPaths.Source)"
	Write-Host "  Destination: $($copyPaths.Dest)"
	Write-Host ""

	$estimate = Get-RobocopyEstimate -Source $copyPaths.Source -Dest $copyPaths.Dest

	$currentBytes = 0
	$currentMB = 0
	$currentFiles = 0

	$layout = New-ProgressLayout

	$newItem = $false
	$makeProgress = $false
	$initiated = $false

	Write-Host "Making Backup..."
	Write-Host ""

	$progressTop = [Console]::CursorTop
	$overallProgressEnd = $progressTop
	$itemProgressEnd = $progressTop

	# start timer
	$start = Get-Date

	try {
		[Console]::CursorVisible = $false
		robocopy $copyPaths.Source $copyPaths.Dest `
			@script:RobocopyCopyFlags `
			/MT:$threadCount `
			/TEE `
			/LOG:$($logPaths.Log) | ForEach-Object {

			$line = $_.ToString()

			if ($line -match "^\s*(New File|Newer|Older|Changed)\s+(\d+)\s+(.+)$") {
				$initiated = $true
				$newItem = $true
				$makeProgress = $true

				$itemBytes = [long]$matches[2]
				$itemMB = [Math]::Round($itemBytes / 1MB, 2)

				$fileName = $matches[3]
				if (($layout.PathStr.Length + $fileName.Length + 4) -gt $layout.InnerWidth) {
					$availableSpace = $layout.InnerWidth - $layout.PathStr.Length - 4
					$fileName = "..." + $fileName.Substring($fileName.Length - $availableSpace)
				}

				$dataPercent = Get-ClampedPercent -Current $currentBytes -Total $estimate.TotalBytes
				$filesPercent = Get-ClampedPercent -Current $currentFiles -Total $estimate.TotalFiles

				$overallData = $layout.DataStr + $currentMB + $layout.SepStr + $estimate.TotalMB + $layout.DataUnitStr
				$dataProgressBar = New-ProgressBar -Percent $dataPercent -BarWidth $layout.BarWidth

				$overallFiles = $layout.FilesStr + $currentFiles + $layout.SepStr + $estimate.TotalFiles
				$filesProgressBar = New-ProgressBar -Percent $filesPercent -BarWidth $layout.BarWidth

				$itemPath = $layout.PathStr + $fileName

				$itemData = $layout.DataStr + "0" + $layout.SepStr + $itemMB + $layout.DataUnitStr

				$itemProgressBar = New-ProgressBar -Percent 0 -BarWidth $layout.BarWidth
			}
			elseif ($line -match "^(  \d| \d{2}|\d{3})%\s*$") {
				$initiated = $true
				$newItem = $false
				$makeProgress = $true

				$itemPercent = [int]$matches[1].Trim()

				$currentItemMB = [Math]::Round(($itemPercent / 100) * $itemMB, 2)

				$itemData = $layout.DataStr + $currentItemMB + $layout.SepStr + $itemMB + $layout.DataUnitStr

				$itemProgressBar = New-ProgressBar -Percent $itemPercent -BarWidth $layout.BarWidth
			}
			else {
				$newItem = $false
				$makeProgress = $false
			}

			if ($makeProgress -eq $true) {
				$overallStatus = Format-ProgressBox -Layout $layout -Title $layout.OverallStr -TrailingBlank -Rows @(
					''
					$overallData
					$dataProgressBar
					''
					$overallFiles
					$filesProgressBar
					''
				)

				$itemStatus = Format-ProgressBox -Layout $layout -Title $layout.ItemStr -Rows @(
					''
					$itemPath
					''
					$itemData
					$itemProgressBar
					''
				)

				$progressEnds = Write-CopyProgress -OverallLines $overallStatus -ItemLines $itemStatus -CursorTop $progressTop
				$overallProgressEnd = $progressEnds.OverallEnd
				$itemProgressEnd = $progressEnds.ItemEnd
			}

			if ($newItem -eq $true) {
				$currentBytes += $itemBytes
				$currentMB = [Math]::Round($currentBytes / 1MB, 2)
				$currentFiles += 1
			}
		}
	}
	finally {
		if ($initiated -eq $true) {
			$dataPercent = Get-ClampedPercent -Current $currentBytes -Total $estimate.TotalBytes
			$filesPercent = Get-ClampedPercent -Current $currentFiles -Total $estimate.TotalFiles

			$overallData = $layout.DataStr + $currentMB + $layout.SepStr + $estimate.TotalMB + $layout.DataUnitStr
			$dataProgressBar = New-ProgressBar -Percent $dataPercent -BarWidth $layout.BarWidth

			$overallFiles = $layout.FilesStr + $currentFiles + $layout.SepStr + $estimate.TotalFiles
			$filesProgressBar = New-ProgressBar -Percent $filesPercent -BarWidth $layout.BarWidth

			$overallStatus = Format-ProgressBox -Layout $layout -Title $layout.OverallStr -TrailingBlank -Rows @(
				''
				$overallData
				$dataProgressBar
				''
				$overallFiles
				$filesProgressBar
				''
			)

			$progressEnds = Write-CopyProgress -OverallLines $overallStatus -CursorTop $progressTop
			$overallProgressEnd = $progressEnds.OverallEnd
		}

		[Console]::SetCursorPosition(0, $overallProgressEnd)

		for ($i = 0; $i -lt ($itemProgressEnd - $overallProgressEnd); $i++) {
			Write-Host "".PadRight($layout.ConsoleWidth)
		}

		[Console]::SetCursorPosition(0, $overallProgressEnd)
		[Console]::CursorVisible = $true
		Write-Host "Backup Complete!"
		Write-Host ""
	}

	$exitCode = $LASTEXITCODE
	# end timer
	$end = Get-Date

	Write-RobocopySummary `
		-Source $copyPaths.Source `
		-Dest $copyPaths.Dest `
		-Start $start `
		-End $end `
		-ExitCode $exitCode `
		-TimeLog $logPaths.TimeLog `
		-Log $logPaths.Log
}
