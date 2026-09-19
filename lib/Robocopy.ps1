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
			Write-UiText -Text "Back." -Style Secondary
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

	Clear-Host
	Show-PathHelp -Title $Title

	$source = Read-FolderPath -Prompt 'Source' -MustExist
	if ($null -eq $source) {
		return $null
	}

	$dest = Read-FolderPath -Prompt 'Destination'
	if ($null -eq $dest) {
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
		TotalSize = Format-ByteSize $totalBytes
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
		[string]$Log,
		$Estimate
	)

	$duration = $End - $Start
	$succeeded = $ExitCode -le 7
	$status = if ($succeeded) {
		"Completed without fatal failure"
	} else {
		"Failed"
	}
	$statusStyle = if ($succeeded) { 'Success' } else { 'Error' }

	$summary = @"
Source:      $Source
Destination: $Dest
Size:        $($Estimate.TotalSize)
Files:       $($Estimate.TotalFiles)
Start:       $Start
End:         $End
Duration:    $duration
Seconds:     $([math]::Round($duration.TotalSeconds, 2))
Minutes:     $([math]::Round($duration.TotalMinutes, 2))
ExitCode:    $ExitCode
Status:      $status
"@
	$summary | Tee-Object -FilePath $TimeLog | Out-Null

	$fields = @(
		@{ Label = 'Source:      '; Value = $Source }
		@{ Label = 'Destination: '; Value = $Dest }
		@{ Label = 'Size:        '; Value = $Estimate.TotalSize }
		@{ Label = 'Files:       '; Value = $Estimate.TotalFiles }
		@{ Label = 'Start:       '; Value = $Start }
		@{ Label = 'End:         '; Value = $End }
		@{ Label = 'Duration:    '; Value = $duration }
		@{ Label = 'Seconds:     '; Value = [math]::Round($duration.TotalSeconds, 2) }
		@{ Label = 'Minutes:     '; Value = [math]::Round($duration.TotalMinutes, 2) }
		@{ Label = 'ExitCode:    '; Value = $ExitCode; Style = $statusStyle }
		@{ Label = 'Status:      '; Value = $status; Style = $statusStyle }
	)

	Write-Host ""
	foreach ($field in $fields) {
		Write-Host $field.Label -NoNewline
		if ($field.Style) {
			Write-UiText -Text "$($field.Value)" -Style $field.Style
		} else {
			Write-Host $field.Value
		}
	}

	Write-Host ""
	if ($succeeded) {
		Write-UiText -Text "Robocopy completed without fatal failure." -Style Success
	} else {
		Write-UiText -Text "Robocopy failed. Check $Log" -Style Error
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

	$fillLen = [int][Math]::Round(($Percent / 100) * $BarWidth)
	if ($fillLen -lt 0) {
		$fillLen = 0
	}
	elseif ($fillLen -gt $BarWidth) {
		$fillLen = $BarWidth
	}

	$emptyLen = $BarWidth - $fillLen

	# Block fill + box horizontal empty, via code points so Windows PowerShell 5.1
	# can parse this file without a UTF-8 BOM.
	$fillChar = [char]0x2588
	$emptyChar = [char]0x2500
	$fillStr = [String]::new($fillChar, $fillLen)
	$emptyStr = [String]::new($emptyChar, $emptyLen)

	if ($fillLen -gt 0) {
		$fillStr = Format-UiText -Text $fillStr -Style Success
	}
	if ($emptyLen -gt 0) {
		$emptyStr = Format-UiText -Text $emptyStr -Style Secondary
	}

	return ' [' + $fillStr + $emptyStr + '] ' + $Percent + '%'
}

function New-ProgressLayout {
	$layout = New-BoxLayout
	# ' [' + bar + '] ' + '100.00%'
	$layout | Add-Member -NotePropertyMembers @{
		BarWidth = [Math]::Max(1, $layout.InnerWidth - 11)
		OverallStr = " Overall Progress"
		ItemStr = " Current File"
		DataStr = " Data: "
		FilesStr = " Files: "
		PathStr = " Path: "
		SepStr = " / "
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
		[long]$CurrentFiles
	)

	$dataPercent = Get-ClampedPercent -Current $CurrentBytes -Total $Estimate.TotalBytes
	$filesPercent = Get-ClampedPercent -Current $CurrentFiles -Total $Estimate.TotalFiles

	$overallData = $Layout.DataStr + (Format-ByteSize $CurrentBytes) + $Layout.SepStr + $Estimate.TotalSize
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
		[long]$ItemBytes,
		[double]$ItemPercent
	)

	if (($Layout.PathStr.Length + $FileName.Length + 4) -gt $Layout.InnerWidth) {
		$availableSpace = $Layout.InnerWidth - $Layout.PathStr.Length - 4
		$FileName = "..." + $FileName.Substring($FileName.Length - $availableSpace)
	}

	$itemPath = $Layout.PathStr + $FileName
	$currentItemBytes = ($ItemPercent / 100) * $ItemBytes
	$itemData = $Layout.DataStr + (Format-ByteSize $currentItemBytes) + $Layout.SepStr + (Format-ByteSize $ItemBytes)
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
	Write-UiText -Text "Backup Complete!" -Style Success
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
	Clear-Host
	Write-Host ""
	Write-UiText -Text "Copying:" -Style Header
	Write-Host "  Source:      $($copyPaths.Source)"
	Write-Host "  Destination: $($copyPaths.Dest)"
	Write-Host ""

	$estimate = Get-RobocopyEstimate -Source $copyPaths.Source -Dest $copyPaths.Dest

	$currentBytes = 0
	$currentFiles = 0

	$layout = New-ProgressLayout

	$newItem = $false
	$makeProgress = $false
	$initiated = $false

	Write-UiText -Text "Making Backup..." -Style Progress
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
					-CurrentFiles $currentFiles

				$itemStatus = New-ItemProgressBox `
					-Layout $layout `
					-FileName $fileName `
					-ItemBytes $itemBytes `
					-ItemPercent $itemPercent

				$progressEnds = Write-CopyProgress -OverallLines $overallStatus -ItemLines $itemStatus -CursorTop $progressTop
				$overallProgressEnd = $progressEnds.OverallEnd
				$itemProgressEnd = $progressEnds.ItemEnd
			}

			if ($newItem -eq $true) {
				$currentBytes += $itemBytes
				$currentFiles += 1
			}
		}
	}
	finally {
		Complete-CopyProgress `
			-Layout $layout `
			-Estimate $estimate `
			-CurrentBytes $currentBytes `
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
		-Log $logPaths.Log `
		-Estimate $estimate
}
