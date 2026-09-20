[CmdletBinding()]
param(
    [string]$UserProfilePath = [Environment]::GetFolderPath('UserProfile')
)

$ErrorActionPreference = 'Stop'

$pluginDir = (Resolve-Path -LiteralPath $PSScriptRoot).Path.Replace('\', '/')
$loaderPath = "$pluginDir/copper_corner_loader.il"
$pcbenvDir = Join-Path $UserProfilePath 'pcbenv'
$ilinitPath = Join-Path $pcbenvDir 'allegro.ilinit'
$beginMarker = '; BEGIN COPPER CORNER TOOLS'
$endMarker = '; END COPPER CORNER TOOLS'
$block = @"
$beginMarker
axlSetVariable("CCT_INSTALL_DIR" "$pluginDir")
load("$loaderPath")
$endMarker
"@

New-Item -ItemType Directory -Path $pcbenvDir -Force | Out-Null

$content = if (Test-Path -LiteralPath $ilinitPath) {
    Get-Content -LiteralPath $ilinitPath -Raw
} else {
    ''
}

$pattern = '(?ms)^' + [regex]::Escape($beginMarker) + '.*?^' + [regex]::Escape($endMarker) + '\s*'
$content = [regex]::Replace($content, $pattern, '')
$content = $content.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block.Trim() + [Environment]::NewLine

Set-Content -LiteralPath $ilinitPath -Value $content -Encoding Default

Write-Host "Copper Corner Tools installed in: $pluginDir"
Write-Host "Updated Allegro startup file: $ilinitPath"
Write-Host 'Restart Allegro, then run: copper_corner'
