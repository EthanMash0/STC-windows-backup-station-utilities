function Enable-VirtualTerminal {
	try {
		if (-not ([System.Management.Automation.PSTypeName]'Win32.VtConsole').Type) {
			$signature = @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
			Add-Type -MemberDefinition $signature -Name VtConsole -Namespace Win32 -ErrorAction Stop
		}

		$handle = [Win32.VtConsole]::GetStdHandle(-11)
		if ($handle -eq [IntPtr]::Zero -or $handle.ToInt64() -eq -1) {
			return $false
		}

		[uint32]$mode = 0
		if (-not [Win32.VtConsole]::GetConsoleMode($handle, [ref]$mode)) {
			return $false
		}

		$enableVt = [uint32]4
		if (($mode -band $enableVt) -ne $enableVt) {
			if (-not [Win32.VtConsole]::SetConsoleMode($handle, ($mode -bor $enableVt))) {
				return $false
			}
		}

		return $true
	}
	catch {
		return $false
	}
}

function Initialize-Ui {
	if ($global:StcUi -and $global:StcUi.Initialized) {
		return
	}

	$global:StcUi = @{
		Initialized = $true
		UseVt = Enable-VirtualTerminal
		Esc = [char]27
		Theme = @{
			Header = @(126, 182, 255)
			Secondary = @(154, 154, 154)
			Success = @(110, 170, 88)
			Error = @(255, 107, 107)
			Progress = @(230, 180, 80)
		}
		Fallback = @{
			Header = $null
			Secondary = 'DarkGray'
			Success = 'Green'
			Error = 'Red'
			Progress = 'Yellow'
		}
	}
}

function Format-UiText {
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Text,

		[Parameter(Mandatory = $true)]
		[ValidateSet('Header', 'Secondary', 'Success', 'Error', 'Progress')]
		[string]$Style
	)

	Initialize-Ui

	if (-not $global:StcUi.UseVt) {
		return $Text
	}

	$rgb = $global:StcUi.Theme[$Style]
	$esc = $global:StcUi.Esc
	# Keep black behind the text. SGR 0 resets to the console default, which
	# is dark blue in powershell.exe — not the Black we set on RawUI.
	return "$esc[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m$esc[48;2;0;0;0m$Text$esc[38;2;255;255;255m$esc[48;2;0;0;0m"
}

function Get-VisibleTextLength {
	param(
		[AllowEmptyString()]
		[string]$Text
	)

	if ([string]::IsNullOrEmpty($Text)) {
		return 0
	}

	# Strip CSI color/style sequences so padding matches what the console draws.
	return [regex]::Replace($Text, '\x1b\[[0-9;]*m', '').Length
}

function Write-UiText {
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Text,

		[Parameter(Mandatory = $true)]
		[ValidateSet('Header', 'Secondary', 'Success', 'Error', 'Progress')]
		[string]$Style,

		[switch]$NoNewline
	)

	Initialize-Ui

	if ($global:StcUi.UseVt) {
		$line = Format-UiText -Text $Text -Style $Style
		if ($NoNewline) {
			Write-Host $line -NoNewline
		} else {
			Write-Host $line
		}
		return
	}

	$color = $global:StcUi.Fallback[$Style]
	if ($color) {
		if ($NoNewline) {
			Write-Host $Text -NoNewline -ForegroundColor $color
		} else {
			Write-Host $Text -ForegroundColor $color
		}
	}
	elseif ($NoNewline) {
		Write-Host $Text -NoNewline
	}
	else {
		Write-Host $Text
	}
}

function Write-Success {
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Message
	)

	Write-UiText -Text $Message -Style Success
}

function Write-ErrorMessage {
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Message
	)

	Write-UiText -Text $Message -Style Error
}

function Show-Header {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Title,

		[ValidateSet('Header', 'Secondary', 'Success', 'Error', 'Progress')]
		[string]$Style = 'Header'
	)

	Write-Host ""
	Write-UiText -Text $Title -Style $Style
	Write-UiText -Text ("-" * $Title.Length) -Style $Style
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

	$titlePad = [Math]::Max(0, $Layout.InnerWidth - (Get-VisibleTextLength $Title))
	$box = @(
		$Layout.Top
		$Layout.Bar + $Title + [String]::new(' ', $titlePad) + $Layout.Bar
		$Layout.Cross
	)

	foreach ($row in $Rows) {
		if ([string]::IsNullOrEmpty($row)) {
			$box += $Layout.Middle
		} else {
			$pad = [Math]::Max(0, $Layout.InnerWidth - (Get-VisibleTextLength $row))
			$box += $Layout.Bar + $row + [String]::new(' ', $pad) + $Layout.Bar
		}
	}

	$box += $Layout.Bottom

	if ($TrailingBlank) {
		$box += ""
	}

	return $box
}

function Write-BoxLine {
	param(
		$Layout,
		[string]$Text,
		[string]$Style
	)

	Write-Host $Layout.Bar -NoNewline

	$visibleLength = Get-VisibleTextLength $Text
	$pad = [Math]::Max(0, $Layout.InnerWidth - $visibleLength)
	$padded = $Text + [String]::new(' ', $pad)
	if (-not [string]::IsNullOrWhiteSpace($Style)) {
		Write-UiText -Text $padded -Style $Style -NoNewline
	} else {
		Write-Host $padded -NoNewline
	}

	Write-Host $Layout.Bar
}

function Show-InfoBox {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Title,

		[string[]]$Rows,

		[switch]$TrailingBlank
	)

	$layout = New-BoxLayout
	$titleText = Format-UiText -Text "  $Title" -Style Header
	$lines = Format-Box -Layout $layout -Title $titleText -Rows $Rows -TrailingBlank:$TrailingBlank
	foreach ($line in $lines) {
		Write-Host $line
	}
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

	$layout = New-BoxLayout

	Clear-Host
	Write-Host ""
	Write-Host $layout.Top
	Write-BoxLine -Layout $layout -Text "  $Title" -Style Header
	Write-Host $layout.Cross

	foreach ($option in $Options) {
		Write-BoxLine -Layout $layout -Text "  [$($option.Key)]  $($option.Label)"
		if (-not [string]::IsNullOrWhiteSpace($option.Description)) {
			Write-BoxLine -Layout $layout -Text "       $($option.Description)" -Style Secondary
		}
	}

	Write-Host $layout.Bottom
	Write-Host ""

	do {
		$choice = Read-Host $Prompt
		$choice = $choice.Trim().Trim('"')

		if ($choice -notin $keys) {
			Write-ErrorMessage "Invalid choice. Enter a number in the range $($keys[0])-$($keys[-1])."
		}
	} while ($choice -notin $keys)

	return $choice
}

Initialize-Ui
