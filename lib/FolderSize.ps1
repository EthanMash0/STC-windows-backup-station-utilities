$LibRoot = $PSScriptRoot

# import
. "$LibRoot\Common.ps1"

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
	Write-Host ""
	Write-UiText -Text "Scanning:" -Style Progress
	Write-Host $path
	Write-Host ""

	$files = 0
	$folders = 0
	$bytes = [uint64]0

	try {
		Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction Continue | ForEach-Object {
			if ($_.PSIsContainer) {
				$folders++
			}
			else {
				$files++
				$bytes += $_.Length
			}
		}

		Write-Host ""
		Write-UiText -Text "Done." -Style Success
		Write-Host ("Total size: {0} ({1:N0} bytes)" -f (Format-ByteSize $bytes), $bytes)
		Write-Host ("Files:      {0:N0}" -f $files)
		Write-Host ("Folders:    {0:N0}" -f $folders)
	}
	catch {
		Write-Host ""
		Write-UiText -Text "Fatal error:" -Style Error
		Write-UiText -Text $_.Exception.Message -Style Error
	}

	Write-Host ""
}
