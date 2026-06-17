Write-Host ""
Write-Host "Backup Station Benchmark Tool"
Write-Host "-----------------------------"
Write-Host "Options:"
Write-Host "1. Robocopy"
Write-Host "2. Dism"
Write-Host "3. Folder Size"
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
		. "$PSScriptRoot\lib\Robocopy.ps1"
		# Consider renaming these tools to Invoke-<tool name> due to powershell typical Verb-Noun naming convention
		robocopy-tool
	}
	'2' {
		. "$PSScriptRoot\lib\Dism.ps1"
		dism-tool
	}
	'3' {
		. "$PSScriptRoot\lib\FolderSize.ps1"
		folder-size-tool
	}
	'4' {
		Write-Host "Exiting."
		exit 0
	}
}

Pause
