$script:FolderSizeProgressIntervalMs = 100
$script:FolderSizeLastProgressTick = 0

# =============================================================================
#  Helpers
# =============================================================================

function New-FolderSizeProgressLayout {
	$layout = New-BoxLayout
	$layout | Add-Member -NotePropertyMembers @{
		SizeStr = " Size:    "
		FilesStr = " Files:   "
		FoldersStr = " Folders: "
		PathStr = " Path:    "
	} -PassThru
}

function New-FolderSizeProgressBox {
	param(
		$Layout,
		[string]$ItemPath,
		[int]$Files,
		[int]$Folders,
		[uint64]$Bytes
	)

	if (($Layout.PathStr.Length + $ItemPath.Length + 4) -gt $Layout.InnerWidth) {
		$availableSpace = $Layout.InnerWidth - $Layout.PathStr.Length - 4
		if ($availableSpace -lt 1) {
			$ItemPath = ''
		}
		else {
			$ItemPath = "..." + $ItemPath.Substring($ItemPath.Length - $availableSpace)
		}
	}

	$title = Format-UiText -Text " Scanning" -Style Progress

	return Format-Box -Layout $Layout -Title $title -Rows @(
		''
		($Layout.SizeStr + (Format-ByteSize $Bytes))
		($Layout.FilesStr + ('{0:N0}' -f $Files))
		($Layout.FoldersStr + ('{0:N0}' -f $Folders))
		''
		($Layout.PathStr + $ItemPath)
		''
	)
}

function Write-FolderSizeProgress {
	param(
		$Layout,
		[string]$ItemPath,
		[int]$Files,
		[int]$Folders,
		[uint64]$Bytes,
		[int]$CursorTop,
		[switch]$Force
	)

	$now = [Environment]::TickCount
	if (-not $Force -and ($now - $script:FolderSizeLastProgressTick) -lt $script:FolderSizeProgressIntervalMs) {
		return
	}

	$script:FolderSizeLastProgressTick = $now

	$lines = New-FolderSizeProgressBox `
		-Layout $Layout `
		-ItemPath $ItemPath `
		-Files $Files `
		-Folders $Folders `
		-Bytes $Bytes

	[Console]::SetCursorPosition(0, $CursorTop)
	foreach ($line in $lines) {
		Write-Host $line
	}
}

function Complete-FolderSizeProgress {
	param(
		$Layout,
		[string]$ItemPath,
		[int]$Files,
		[int]$Folders,
		[uint64]$Bytes,
		[int]$CursorTop
	)

	Write-FolderSizeProgress `
		-Layout $Layout `
		-ItemPath $ItemPath `
		-Files $Files `
		-Folders $Folders `
		-Bytes $Bytes `
		-CursorTop $CursorTop `
		-Force

	[Console]::CursorVisible = $true
	Write-Success "Done."
}

# =============================================================================
#  Orchestrator
# =============================================================================

function Invoke-FolderSizeTool {
	Clear-Host

	$title = "Folder Size Counter"
	Show-PathHelp -Title $title

	$inputPath = Read-FolderPath -Prompt 'Path' -MustExist
	if ($null -eq $inputPath) {
		return
	}

	# Convert to long-path form when possible
	if ($inputPath -like "\\?\*") {
		$path = $inputPath
	}
	elseif ($inputPath -like "\\*") {
		# UNC path: \\server\share\folder -> \\?\UNC\server\share\folder
		$path = "\\?\UNC\" + $inputPath.TrimStart("\")
	}
	else {
		# Local path: C:\folder -> \\?\C:\folder
		$path = "\\?\" + $inputPath
	}

	Clear-Host
	Show-Header -Title "Scanning:" -Style Progress
	Write-Host $path
	Write-Host ""

	# Hashtable so ForEach-Object mutations stay visible to the caller.
	$state = @{
		Files = 0
		Folders = 0
		Bytes = [uint64]0
		CurrentPath = $path
	}
	$layout = New-FolderSizeProgressLayout
	$script:FolderSizeLastProgressTick = 0

	try {
		[Console]::CursorVisible = $false
		$progressTop = [Console]::CursorTop

		Write-FolderSizeProgress `
			-Layout $layout `
			-ItemPath $state.CurrentPath `
			-Files $state.Files `
			-Folders $state.Folders `
			-Bytes $state.Bytes `
			-CursorTop $progressTop `
			-Force

		# SilentlyContinue keeps access-denied noise from jumping the
		# in-place progress box. Counts still include every readable item.
		Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
			$state.CurrentPath = $_.FullName

			if ($_.PSIsContainer) {
				$state.Folders++
			}
			else {
				$state.Files++
				$state.Bytes += $_.Length
			}

			Write-FolderSizeProgress `
				-Layout $layout `
				-ItemPath $state.CurrentPath `
				-Files $state.Files `
				-Folders $state.Folders `
				-Bytes $state.Bytes `
				-CursorTop $progressTop
		}

		Complete-FolderSizeProgress `
			-Layout $layout `
			-ItemPath $state.CurrentPath `
			-Files $state.Files `
			-Folders $state.Folders `
			-Bytes $state.Bytes `
			-CursorTop $progressTop

		Write-Host ""
		Show-InfoBox -Title "Folder Size" -Rows @(
			("  Total size: {0} ({1:N0} bytes)" -f (Format-ByteSize $state.Bytes), $state.Bytes)
			("  Files:      {0:N0}" -f $state.Files)
			("  Folders:    {0:N0}" -f $state.Folders)
		)
	}
	catch {
		Write-Host ""
		Write-ErrorMessage "Fatal error:"
		Write-ErrorMessage $_.Exception.Message
	}
	finally {
		[Console]::CursorVisible = $true
	}

	Write-Host ""
}
