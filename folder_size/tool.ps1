Write-Host ""
Write-Host "Folder Size Counter"
Write-Host "-------------------"
Write-Host "Enter a local path like:"
Write-Host "  C:\Users\ethanmash"
Write-Host ""
Write-Host "Or a network path like:"
Write-Host "  \\server\share\folder"
Write-Host ""

$inputPath = Read-Host "Path"

# Remove surrounding quotes if the user entered a quoted path
$inputPath = $inputPath.Trim().Trim('"')

if ([string]::IsNullOrWhiteSpace($inputPath)) {
    Write-Host "No path entered. Exiting."
    Pause
    exit 1
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

Write-Host ""
Write-Host "Scanning:"
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
    Write-Host "Done."
    Write-Host "-------------------"
    Write-Host ("Total size: {0:N2} GB ({1:N0} bytes)" -f ($bytes / 1GB), $bytes)
    Write-Host ("Files:      {0:N0}" -f $files)
    Write-Host ("Folders:    {0:N0}" -f $folders)
}
catch {
    Write-Host ""
    Write-Host "Fatal error:"
    Write-Host $_.Exception.Message
}

Write-Host ""
Pause
