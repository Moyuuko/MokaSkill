[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $PSScriptRoot 'build'
$outputDir = Join-Path $projectRoot 'dist'
$configSource = Join-Path $PSScriptRoot 'MokaSkillConfig.cs'
$configExe = Join-Path $buildDir 'MokaSkillConfig.exe'
$setupScript = Join-Path $PSScriptRoot 'MokaSkillSetup.iss'

New-Item -ItemType Directory -Force -Path $buildDir, $outputDir | Out-Null

$cscCandidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) {
    throw '找不到 .NET Framework C# 编译器 (csc.exe)。'
}

Write-Host 'Building Moka Skill configuration helper...'
& $csc /nologo /target:exe /optimize+ "/out:$configExe" $configSource
if ($LASTEXITCODE -ne 0) { throw 'MokaSkillConfig.exe 编译失败。' }

Write-Host 'Running configuration self-test...'
& $configExe self-test
if ($LASTEXITCODE -ne 0) { throw 'MokaSkillConfig.exe 自检失败。' }

$isccCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe')
)
$iscc = $isccCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $iscc) {
    $isccCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($isccCommand) { $iscc = $isccCommand.Source }
}
if (-not $iscc) {
    throw '找不到 Inno Setup。请先运行：winget install --id JRSoftware.InnoSetup.7 -e'
}

Write-Host 'Building modern installer...'
& $iscc $setupScript
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup 编译失败。' }

$installer = Join-Path $outputDir 'MokaSkill_Setup_v1.0.exe'
if (-not (Test-Path -LiteralPath $installer)) { throw "未生成安装程序：$installer" }
Write-Host "Done: $installer"
