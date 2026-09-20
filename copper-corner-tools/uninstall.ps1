[CmdletBinding()]
param(
    [string]$UserProfilePath = [Environment]::GetFolderPath('UserProfile')
)

$ErrorActionPreference = 'Stop'

$ilinitPath = Join-Path (Join-Path $UserProfilePath 'pcbenv') 'allegro.ilinit'
$beginMarker = '; BEGIN COPPER CORNER TOOLS'
$endMarker = '; END COPPER CORNER TOOLS'

if (Test-Path -LiteralPath $ilinitPath) {
    $content = Get-Content -LiteralPath $ilinitPath -Raw
    $pattern = '(?ms)^' + [regex]::Escape($beginMarker) + '.*?^' + [regex]::Escape($endMarker) + '\s*'
    $updated = [regex]::Replace($content, $pattern, '')
    if ($updated -ne $content) {
        Set-Content -LiteralPath $ilinitPath -Value $updated.TrimEnd() -Encoding Default
        Write-Host "Removed Copper Corner Tools startup block from: $ilinitPath"
    } else {
        Write-Host 'Copper Corner Tools startup block was not present.'
    }
} else {
    Write-Host "Allegro startup file does not exist: $ilinitPath"
}

Write-Host 'The plugin source directory was not deleted.'
