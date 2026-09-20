[CmdletBinding()]
param(
    [string]$UserProfilePath = [Environment]::GetFolderPath('UserProfile')
)

$ErrorActionPreference = 'Stop'

$ilinitPath = Join-Path (Join-Path $UserProfilePath 'pcbenv') 'allegro.ilinit'
$beginMarker = '; BEGIN MOORETRONICS SYMBOL PLACER'
$endMarker = '; END MOORETRONICS SYMBOL PLACER'

if (Test-Path -LiteralPath $ilinitPath) {
    $content = Get-Content -LiteralPath $ilinitPath -Raw
    $pattern = '(?ms)^' + [regex]::Escape($beginMarker) + '.*?^' + [regex]::Escape($endMarker) + '\s*'
    $updated = [regex]::Replace($content, $pattern, '')
    if ($updated -ne $content) {
        Set-Content -LiteralPath $ilinitPath -Value $updated.TrimEnd() -Encoding Default
        Write-Host "Removed the Mooretronics startup block from: $ilinitPath"
    } else {
        Write-Host 'The Mooretronics startup block was not present.'
    }
} else {
    Write-Host "Allegro startup file does not exist: $ilinitPath"
}

Write-Host 'The plugin source directory and font resource were not deleted.'
