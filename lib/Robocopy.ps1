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
	$runId = Get-Date -Format "yyyyMMdd-HHmmss"
	$log = "C:\Temp\backup_logs\robocopy_${padded}_thread\robocopy-$runId.log"
	$timeLog = "C:\Temp\backup_logs\robocopy_${padded}_thread\robocopy-time-$runId.txt"
	$logFolder = Split-Path -Parent $log

	New-Item -ItemType Directory -Force -Path $logFolder | Out-Null
	
	. "$LibRoot\Common.ps1"
	Show-PathHelp -Title $title

	$source = Read-Host "Source"
	$source = $source.Trim().Trim('"').TrimEnd('\')

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

	Write-Host ""
	Write-Host "Copying:"
	Write-Host "  Source:      $source"
	Write-Host "  Destination: $dest"
	Write-Host ""

	$start = Get-Date

	$dryRun = robocopy `
		$source `
		$dest `
		/L `
		/NFL `
		/NDL `
		/NJH `
		/NP `
		/E `
		/COPY:DAT `
		/DCOPY:DAT `
		/BYTES `
		/XJ `
		/R:3 `
		/W:5

	$totalBytes = ($dryRun	-match 'Bytes :' -split '[\t ]+')[3]
	$totalFiles = ($dryRun	-match 'Files :' -split '[\t ]+')[3]

	$totalMB = [Math]::Round($totalBytes / 1MB, 2)

	$currentBytes = 0
	$currentFiles = 0

	$barWidth = 40

	$overallStr = " Overall Progress"
	$itemStr = " Current File"
	$dataStr = " Data: "
	$filesStr = " Files: "
	$pathStr = " Path: "
	$sepStr = " / "
	$dataUnitStr = " MB"

	$consoleWidth = [Console]::WindowWidth - 1
	$innerWidth = $consoleWidth - 2

	$borderFill = [String]::new('─', $innerWidth)
	$emptyFill = [String]::new(' ', $innerWidth)
	$emptyBarFill = [String]::new(' ', $barWidth)

	$topStr = "┌" + $borderFill + "┐"
	$bottomStr = "└" + $borderFill + "┘"
	$crossStr = "├" + $borderFill + "┤"
	$middleStr = "│" + $emptyFill + "│"

	$newItem = $false
	$makeProgress = $false
	$initiated = $false

	Write-Host "Making Backup..."
	Write-Host ""

	$progressTop = [Console]::CursorTop
	$overallProgressEnd = $progressTop
	$itemProgressEnd = $progressTop

	try {
		[Console]::CursorVisible = $false
		robocopy $source $dest `
			/E `
			/COPY:DAT `
			/DCOPY:DAT `
			/BYTES `
			/XJ `
			/MT:$mt `
			/R:3 `
			/W:5 `
			/TEE `
			/LOG:$log | ForEach-Object {

			$line = $_.ToString()

			if ($line -match "^\s*(New File|Newer|Older|Changed)\s+(\d+)\s+(.+)$") {
				$initiated = $true
				$newItem = $true
				$makeProgress = $true

				$itemBytes = [long]$matches[2]
				$itemMB = [Math]::Round($itemBytes / 1MB, 2)

				$fileName = $matches[3]
				if (($pathStr.Length + $fileName.Length + 4) -gt $innerWidth) {
					$availableSpace = $innerWidth - $pathStr.Length - 4
					$fileName = "..." + $fileName.Substring($fileName.Length - $availableSpace)
				}

				if ($totalBytes -gt 0) {
					$dataPercent = [Math]::Round(($currentBytes / $totalBytes) * 100, 2)
				} else {
					$dataPercent = 100
				}
				$dataPercent = [Math]::Min($dataPercent, 100)

				if ($totalFiles -gt 0) {
					$filesPercent = [Math]::Round(($currentFiles / $totalFiles) * 100, 2)
				} else {
					$filesPercent = 100
				}
				$filesPercent = [Math]::Min($filesPercent, 100)

				$itemPercent = 0

				$overallData = $dataStr + $currentMB + $sepStr + $totalMB + $dataUnitStr

				$dataFillLen = [Math]::Round(($dataPercent / 100) * $barWidth)
				$dataEmptyLen = $barWidth - $dataFillLen
				$dataFillStr = [String]::new('=', $dataFillLen)
				$dataEmptyStr = [String]::new(' ', $dataEmptyLen) 
				$dataProgressBar = ' [' + $dataFillStr + $dataEmptyStr + '] ' + $dataPercent + '%'

				$overallFiles = $filesStr + $currentFiles + $sepStr + $totalFiles

				$filesFillLen = [Math]::Round(($filesPercent / 100) * $barWidth)
				$filesEmptyLen = $barWidth - $filesFillLen
				$filesFillStr = [String]::new('=', $filesFillLen)
				$filesEmptyStr = [String]::new(' ', $filesEmptyLen) 
				$filesProgressBar = ' [' + $filesFillStr + $filesEmptyStr + '] ' + $filesPercent + '%'

				$itemPath = $pathStr + $fileName

				$itemData = $dataStr + "0" + $sepStr + $itemMB + $dataUnitStr

				$itemProgressBar = ' [' + $emptyBarFill + '] ' + $itemPercent + '%'
			}
			elseif ($line -match "^(  \d| \d{2}|\d{3})%\s*$") {
				$initiated = $true
				$newItem = $false
				$makeProgress = $true

				$itemPercent = [int]$matches[1].Trim()

				$currentItemMB = [Math]::Round(($itemPercent / 100) * $itemMB, 2)

				$itemData = $dataStr + $currentItemMB + $sepStr + $itemMB + $dataUnitStr

				$itemFillLen = [Math]::Round(($itemPercent / 100) * $barWidth)
				$itemEmptyLen = $barWidth - $itemFillLen
				$itemFillStr = [String]::new('=', $itemFillLen)
				$itemEmptyStr = [String]::new(' ', $itemEmptyLen) 
				$itemProgressBar = ' [' + $itemFillStr + $itemEmptyStr + '] ' + $itemPercent + '%'
			}
			else {
				$newItem = $false
				$makeProgress = $false
			}

			if ($makeProgress -eq $true) {
				$overallStatus = @(
					$topStr
					"│" + $overallStr.PadRight($innerWidth) + "│"
					$crossStr
					$middleStr
					"│" + $overallData.PadRight($innerWidth) + "│"
					"│" + $dataProgressBar.PadRight($innerWidth) + "│"
					$middleStr
					"│" + $overallFiles.PadRight($innerWidth) + "│"
					"│" + $filesProgressBar.PadRight($innerWidth) + "│"
					$middleStr
					$bottomStr
					""
				)

				$itemStatus = @(
					$topStr
					"│" + $itemStr.PadRight($innerWidth) + "│"
					$crossStr
					$middleStr
					"│" + $itemPath.PadRight($innerWidth) + "│"
					$middleStr
					"│" + $itemData.PadRight($innerWidth) + "│"
					"│" + $itemProgressBar.PadRight($innerWidth) + "│"
					$middleStr
					$bottomStr
				)

				[Console]::SetCursorPosition(0, $progressTop)

				for ($i = 0; $i -lt $overallStatus.Count; $i++) {
					Write-Host $overallStatus[$i]
				}

				$overallProgressEnd = [Console]::CursorTop

				for ($i = 0; $i -lt $itemStatus.Count; $i++) {
					Write-Host $itemStatus[$i]
				}

				$itemProgressEnd = [Console]::CursorTop
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
			if ($totalBytes -gt 0) {
				$dataPercent = [Math]::Round(($currentBytes / $totalBytes) * 100, 2)
			} else {
				$dataPercent = 100
			}
			$dataPercent = [Math]::Min($dataPercent, 100)

			if ($totalFiles -gt 0) {
				$filesPercent = [Math]::Round(($currentFiles / $totalFiles) * 100, 2)
			} else {
				$filesPercent = 100
			}
			$filesPercent = [Math]::Min($filesPercent, 100)

			$itemPercent = 0

			$overallData = $dataStr + $currentMB + $sepStr + $totalMB + $dataUnitStr

			$dataFillLen = [Math]::Round(($dataPercent / 100) * $barWidth)
			$dataEmptyLen = $barWidth - $dataFillLen
			$dataFillStr = [String]::new('=', $dataFillLen)
			$dataEmptyStr = [String]::new(' ', $dataEmptyLen) 
			$dataProgressBar = ' [' + $dataFillStr + $dataEmptyStr + '] ' + $dataPercent + '%'

			$overallFiles = $filesStr + $currentFiles + $sepStr + $totalFiles

			$filesFillLen = [Math]::Round(($filesPercent / 100) * $barWidth)
			$filesEmptyLen = $barWidth - $filesFillLen
			$filesFillStr = [String]::new('=', $filesFillLen)
			$filesEmptyStr = [String]::new(' ', $filesEmptyLen) 
			$filesProgressBar = ' [' + $filesFillStr + $filesEmptyStr + '] ' + $filesPercent + '%'

			$overallStatus = @(
				$topStr
				"│" + $overallStr.PadRight($innerWidth) + "│"
				$crossStr
				$middleStr
				"│" + $overallData.PadRight($innerWidth) + "│"
				"│" + $dataProgressBar.PadRight($innerWidth) + "│"
				$middleStr
				"│" + $overallFiles.PadRight($innerWidth) + "│"
				"│" + $filesProgressBar.PadRight($innerWidth) + "│"
				$middleStr
				$bottomStr
				""
			)

			[Console]::SetCursorPosition(0, $progressTop)

			for ($i = 0; $i -lt $overallStatus.Count; $i++) {
				Write-Host $overallStatus[$i]
			}

			$overallProgressEnd = [Console]::CursorTop
		}

		[Console]::SetCursorPosition(0, $overallProgressEnd)

		for ($i = 0; $i -lt ($itemProgressEnd - $overallProgressEnd); $i++) {
			Write-Host "".PadRight($consoleWidth)
		}

		[Console]::SetCursorPosition(0, $overallProgressEnd)
		[Console]::CursorVisible = $true
		Write-Host "Backup Complete!"
		Write-Host ""
	}

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

	Write-Host ""
	if ($exitCode -le 7) {
			Write-Host "Robocopy completed without fatal failure."
	} else {
			Write-Host "Robocopy failed. Check $log"
	}

	Write-Host ""
}
