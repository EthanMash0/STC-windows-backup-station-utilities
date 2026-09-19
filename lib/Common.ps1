function Show-PathHelp {
	param(
		[string]$Title
	)

	Write-Host ""
	Write-Host $Title
	Write-Host ("-" * $Title.Length)
	Write-Host "Enter a local path like:"
	Write-Host "  D:\Users\STC"
	Write-Host ""
	Write-Host "Or a network path like:"
	Write-Host "  \\server\share\folder"
	Write-Host ""
}

function New-BoxLayout {
	# Code points so Windows PowerShell 5.1 can parse this file without a UTF-8 BOM.
	$boxH = [char]0x2500
	$boxV = [char]0x2502
	$boxTL = [char]0x250C
	$boxTR = [char]0x2510
	$boxBL = [char]0x2514
	$boxBR = [char]0x2518
	$boxVL = [char]0x251C
	$boxVR = [char]0x2524

	$consoleWidth = [Console]::WindowWidth - 1
	$innerWidth = $consoleWidth - 2

	$borderFill = [String]::new($boxH, $innerWidth)
	$emptyFill = [String]::new(' ', $innerWidth)

	return [pscustomobject]@{
		ConsoleWidth = $consoleWidth
		InnerWidth = $innerWidth
		Bar = $boxV
		Top = $boxTL + $borderFill + $boxTR
		Bottom = $boxBL + $borderFill + $boxBR
		Cross = $boxVL + $borderFill + $boxVR
		Middle = $boxV + $emptyFill + $boxV
	}
}

function Format-Box {
	param(
		$Layout,
		[string]$Title,
		[string[]]$Rows,
		[switch]$TrailingBlank
	)

	$box = @(
		$Layout.Top
		$Layout.Bar + $Title.PadRight($Layout.InnerWidth) + $Layout.Bar
		$Layout.Cross
	)

	foreach ($row in $Rows) {
		if ([string]::IsNullOrEmpty($row)) {
			$box += $Layout.Middle
		} else {
			$box += $Layout.Bar + $row.PadRight($Layout.InnerWidth) + $Layout.Bar
		}
	}

	$box += $Layout.Bottom

	if ($TrailingBlank) {
		$box += ""
	}

	return $box
}

function Format-ByteSize {
	param(
		[Parameter(Mandatory = $true)]
		[double]$Bytes
	)

	if ($Bytes -ge 1GB) {
		return ('{0:N2} GB' -f ($Bytes / 1GB))
	}

	if ($Bytes -ge 1MB) {
		return ('{0:N2} MB' -f ($Bytes / 1MB))
	}

	return ('{0:N2} KB' -f ($Bytes / 1KB))
}

function Read-MenuChoice {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Title,

		[Parameter(Mandatory = $true)]
		[hashtable[]]$Options,

		[string]$Prompt
	)

	$keys = foreach ($option in $Options) {
		[string]$option.Key
	}

	if ([string]::IsNullOrWhiteSpace($Prompt)) {
		$Prompt = "Enter choice ($($keys[0])-$($keys[-1]))"
	}

	$rows = foreach ($option in $Options) {
		"  [$($option.Key)]  $($option.Label)"
		if (-not [string]::IsNullOrWhiteSpace($option.Description)) {
			"       $($option.Description)"
		}
	}

	$layout = New-BoxLayout
	$box = Format-Box -Layout $layout -Title "  $Title" -Rows $rows

	Clear-Host
	Write-Host ""
	foreach ($line in $box) {
		Write-Host $line
	}
	Write-Host ""

	do {
		$choice = Read-Host $Prompt
		$choice = $choice.Trim().Trim('"')

		if ($choice -notin $keys) {
			Write-Host "Invalid choice. Enter a number in the range $($keys[0])-$($keys[-1])."
		}
	} while ($choice -notin $keys)

	return $choice
}
