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
	$choice = Read-MenuChoice -Title 'Copy Tool (Robocopy based)' -Options @(
		@{ Key = '1'; Label = 'Slow (1 Thread)'; Description = '1 copy thread, or 1 file at a time' }
		@{ Key = '2'; Label = 'Standard (16 Threads)'; Description = '16 copy threads, or up to 16 files at a time' }
		@{ Key = '3'; Label = 'Fast (64 Threads)'; Description = '64 copy threads, or up to 64 files at a time' }
		@{ Key = '4'; Label = 'Back' }
	)

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
	$layout = New-BoxLayout
	$layout | Add-Member -NotePropertyMembers @{
		BarWidth = 40
		OverallStr = " Overall Progress"
		ItemStr = " Current File"
		DataStr = " Data: "
		FilesStr = " Files: "
		PathStr = " Path: "
		SepStr = " / "
		DataUnitStr = " MB"
	} -PassThru
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

function Parse-RobocopyProgressLine {
	param(
		[string]$Line
	)

	# File rows: "New File|Newer|Older|Changed" + byte size + path
	#   e.g. "	    New File  		   12345	C:\folder\file.txt"
	if ($Line -match "^\s*(New File|Newer|Older|Changed)\s+(\d+)\s+(.+)$") {
		return [pscustomobject]@{
			Kind = 'File'
			ItemBytes = [long]$matches[2]
			FileName = $matches[3]
		}
	}

	# Percent rows: 3-character padded percent, then "%"
	#   e.g. "  0%", " 10%", "100%"
	if ($Line -match "^(  \d| \d{2}|\d{3})%\s*$") {
		return [pscustomobject]@{
			Kind = 'Percent'
			ItemPercent = [int]$matches[1].Trim()
		}
	}

	return [pscustomobject]@{
		Kind = 'Other'
	}
}

function New-OverallProgressBox {
	param(
		$Layout,
		$Estimate,
		[long]$CurrentBytes,
		[double]$CurrentMB,
		[long]$CurrentFiles
	)

	$dataPercent = Get-ClampedPercent -Current $CurrentBytes -Total $Estimate.TotalBytes
	$filesPercent = Get-ClampedPercent -Current $CurrentFiles -Total $Estimate.TotalFiles

	$overallData = $Layout.DataStr + $CurrentMB + $Layout.SepStr + $Estimate.TotalMB + $Layout.DataUnitStr
	$dataProgressBar = New-ProgressBar -Percent $dataPercent -BarWidth $Layout.BarWidth

	$overallFiles = $Layout.FilesStr + $CurrentFiles + $Layout.SepStr + $Estimate.TotalFiles
	$filesProgressBar = New-ProgressBar -Percent $filesPercent -BarWidth $Layout.BarWidth

	return Format-Box -Layout $Layout -Title $Layout.OverallStr -TrailingBlank -Rows @(
		''
		$overallData
		$dataProgressBar
		''
		$overallFiles
		$filesProgressBar
		''
	)
}

function New-ItemProgressBox {
	param(
		$Layout,
		[string]$FileName,
		[double]$ItemMB,
		[double]$ItemPercent
	)

	if (($Layout.PathStr.Length + $FileName.Length + 4) -gt $Layout.InnerWidth) {
		$availableSpace = $Layout.InnerWidth - $Layout.PathStr.Length - 4
		$FileName = "..." + $FileName.Substring($FileName.Length - $availableSpace)
	}

	$itemPath = $Layout.PathStr + $FileName
	$currentItemMB = [Math]::Round(($ItemPercent / 100) * $ItemMB, 2)
	$itemData = $Layout.DataStr + $currentItemMB + $Layout.SepStr + $ItemMB + $Layout.DataUnitStr
	$itemProgressBar = New-ProgressBar -Percent $ItemPercent -BarWidth $Layout.BarWidth

	return Format-Box -Layout $Layout -Title $Layout.ItemStr -Rows @(
		''
		$itemPath
		''
		$itemData
		$itemProgressBar
		''
	)
}

function Complete-CopyProgress {
	param(
		$Layout,
		$Estimate,
		[long]$CurrentBytes,
		[double]$CurrentMB,
		[long]$CurrentFiles,
		[int]$ProgressTop,
		[int]$OverallProgressEnd,
		[int]$ItemProgressEnd,
		[bool]$Initiated
	)

	if ($Initiated -eq $true) {
		$overallStatus = New-OverallProgressBox `
			-Layout $Layout `
			-Estimate $Estimate `
			-CurrentBytes $CurrentBytes `
			-CurrentMB $CurrentMB `
			-CurrentFiles $CurrentFiles

		$progressEnds = Write-CopyProgress -OverallLines $overallStatus -CursorTop $ProgressTop
		$OverallProgressEnd = $progressEnds.OverallEnd
	}

	[Console]::SetCursorPosition(0, $OverallProgressEnd)

	for ($i = 0; $i -lt ($ItemProgressEnd - $OverallProgressEnd); $i++) {
		Write-Host "".PadRight($Layout.ConsoleWidth)
	}

	[Console]::SetCursorPosition(0, $OverallProgressEnd)
	[Console]::CursorVisible = $true
	Write-Host "Backup Complete!"
	Write-Host ""
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

			$parsed = Parse-RobocopyProgressLine -Line $_.ToString()

			if ($parsed.Kind -eq 'File') {
				$initiated = $true
				$newItem = $true
				$makeProgress = $true

				$itemBytes = $parsed.ItemBytes
				$itemMB = [Math]::Round($itemBytes / 1MB, 2)
				$fileName = $parsed.FileName
				$itemPercent = 0
			}
			elseif ($parsed.Kind -eq 'Percent') {
				$initiated = $true
				$newItem = $false
				$makeProgress = $true

				$itemPercent = $parsed.ItemPercent
			}
			else {
				$newItem = $false
				$makeProgress = $false
			}

			if ($makeProgress -eq $true) {
				$overallStatus = New-OverallProgressBox `
					-Layout $layout `
					-Estimate $estimate `
					-CurrentBytes $currentBytes `
					-CurrentMB $currentMB `
					-CurrentFiles $currentFiles

				$itemStatus = New-ItemProgressBox `
					-Layout $layout `
					-FileName $fileName `
					-ItemMB $itemMB `
					-ItemPercent $itemPercent

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
		Complete-CopyProgress `
			-Layout $layout `
			-Estimate $estimate `
			-CurrentBytes $currentBytes `
			-CurrentMB $currentMB `
			-CurrentFiles $currentFiles `
			-ProgressTop $progressTop `
			-OverallProgressEnd $overallProgressEnd `
			-ItemProgressEnd $itemProgressEnd `
			-Initiated $initiated
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
