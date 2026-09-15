Write-Host ""
Write-Host "STC Windows Backup Station Tool"
Write-Host "-------------------------------"
Write-Host "Options:"
Write-Host ""
Write-Host "1. Copy Data"
Write-Host ""
Write-Host "2. Folder Size"
Write-Host ""
Write-Host "3. Exit"
Write-Host ""

do {
	$tool = Read-Host "Enter choice (1-3)"
	$tool = $tool.Trim().Trim('"')

	if ($tool -notin '1', '2', '3') {
		Write-Host "Invalid choice. Enter a number in the range 1-4."
	}
} while ($tool -notin '1', '2', '3')

switch ($tool) {
	'1' {
		. "$PSScriptRoot\lib\Robocopy.ps1"
		Invoke-RobocopyTool
	}
	'2' {
		. "$PSScriptRoot\lib\FolderSize.ps1"
		Invoke-FolderSizeTool
	}
	'3' {
		Write-Host "Exiting."
		exit 0
	}
}

Pause
