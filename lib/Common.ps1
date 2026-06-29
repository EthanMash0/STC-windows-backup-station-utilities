function Show-PathHelp {
	param(
		[string]$Title
	)

	Write-Host ""
	Write-Host $Title
	Write-Host ("-" * $Title.Length)
	Write-Host "Enter a local path like:"
	Write-Host "  D:\Users\ethanmash"
	Write-Host ""
	Write-Host "Or a network path like:"
	Write-Host "  \\server\share\folder"
	Write-Host ""
}
