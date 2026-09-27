$script:FolderSizeProgressIntervalMs = 100

# =============================================================================
#  Helpers
# =============================================================================

function New-FolderSizeProgressLayout {
	param([int]$WindowWidth)

	$layout = New-BoxLayout -WindowWidth $WindowWidth
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

	$availableSpace = $Layout.InnerWidth - (Get-VisibleTextLength $Layout.PathStr) - 1
	$ItemPath = Format-UiPath -Path $ItemPath -Width $availableSpace

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

function New-FolderSizeScreenLines {
	param([int]$WindowWidth, $Progress)

	$layout = New-FolderSizeProgressLayout -WindowWidth $WindowWidth
	return @('') + @(New-FolderSizeProgressBox -Layout $layout -ItemPath $Progress.CurrentPath -Files $Progress.Files -Folders $Progress.Folders -Bytes $Progress.Bytes)
}

function Start-FolderSizeScan {
	param([string]$Path, [hashtable]$Shared)

	$worker = [PowerShell]::Create()
	try {
		[void]$worker.AddScript({
			param($ScanPath, $Shared, $Interval)
			$files = 0
			$folders = 0
			$bytes = [uint64]0
			$currentPath = $ScanPath
			$clock = [System.Diagnostics.Stopwatch]::StartNew()
			# Enumeration and counting remain the same. Ignore access errors
			# without retaining an unbounded error stream in the worker.
			Get-ChildItem -LiteralPath $ScanPath -Recurse -Force -ErrorAction Ignore | ForEach-Object {
				$currentPath = $_.FullName
				if ($_.PSIsContainer) { $folders++ }
				else { $files++; $bytes += $_.Length }
				if ($clock.ElapsedMilliseconds -ge $Interval) {
					# Publish one complete snapshot, never independently changing
					# fields while the UI reads them. Nothing writes to the console.
					$Shared.Snapshot = @{ Files = $files; Folders = $folders; Bytes = $bytes; CurrentPath = $currentPath }
					$clock.Restart()
				}
			}
			$Shared.Snapshot = @{ Files = $files; Folders = $folders; Bytes = $bytes; CurrentPath = $currentPath }
		}).AddArgument($Path).AddArgument($Shared).AddArgument($script:FolderSizeProgressIntervalMs)
		return @{ Worker = $worker; Pending = $worker.BeginInvoke() }
	}
	catch {
		$worker.Dispose()
		throw
	}
}

# =============================================================================
#  Orchestrator
# =============================================================================

function Invoke-FolderSizeTool {
	Reset-UiScreen

	$title = "Folder Size Counter"
	Show-PathHelp -Title $title

	$inputPath = Read-FolderPath -Prompt 'Path' -MustExist -RetryDraw {
		Reset-UiScreen
		Show-PathHelp -Title $title
	}
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

	Reset-UiScreen
	$state = @{ Files = 0; Folders = 0; Bytes = [uint64]0; CurrentPath = $path }
	$shared = [hashtable]::Synchronized(@{ Snapshot = $state })
	$block = @{ Kind = 'Custom'; Builder = ${function:New-FolderSizeScreenLines}; Data = $state }
	Add-UiBlock $block
	$scan = $null

	try {
		Set-UiCursorVisible -Visible $false
		Update-UiScreen
		$scan = Start-FolderSizeScan -Path $path -Shared $shared
		while (-not $scan.Pending.IsCompleted) {
			$snapshot = $shared.Snapshot
			if (-not [object]::ReferenceEquals($state, $snapshot)) {
				$state = $snapshot
				$block.Data = $state
				$script:UiScreen.Dirty = $true
			}
			# Check for resizing even if a directory/network read is waiting.
			Update-UiScreen
			Start-Sleep -Milliseconds $script:FolderSizeProgressIntervalMs
		}
		[void]$scan.Worker.EndInvoke($scan.Pending)
		$state = $shared.Snapshot
		$block.Data = $state
		Update-UiScreen -Force
		Set-UiCursorVisible -Visible $true
		Write-UiLine
		Show-InfoBox -Title "Folder Size" -Rows @(
			("  Path:        {0}" -f $inputPath)
			("  Total size:  {0} ({1:N0} bytes)" -f (Format-ByteSize $state.Bytes), $state.Bytes)
			("  Files:       {0:N0}" -f $state.Files)
			("  Folders:     {0:N0}" -f $state.Folders)
		)
	}
	catch [System.Management.Automation.PipelineStoppedException] { throw }
	catch {
		Write-UiLine
		Write-ErrorMessage "Fatal error:"
		Write-ErrorMessage $_.Exception.Message
	}
	finally {
		try {
			if ($null -ne $scan) {
				try { if (-not $scan.Pending.IsCompleted) { $scan.Worker.Stop() } }
				finally { $scan.Worker.Dispose() }
			}
		}
		finally { Set-UiCursorVisible -Visible $true }
	}

	return 'Completed'
}
