#requires -version 5.1

<#
.SYNOPSIS
Scans an Allegro project and removes selected log, cache, and temporary files.

.DESCRIPTION
On first use, the script scans the project, presents cleanup categories, and
saves the selection in .allegro-clean.json. Later runs reuse that selection.

.PARAMETER Root
Project directory to scan. Defaults to the current directory.

.PARAMETER Reconfigure
Ignore the saved selection and ask for cleanup categories again.

.PARAMETER Preview
Show what would be removed without deleting anything.

.PARAMETER Force
Skip the final deletion confirmation. This does not change category selection.

.PARAMETER Forget
Delete the saved selection and exit.

.EXAMPLE
.\scripts\Clean-AllegroProject.ps1

.EXAMPLE
.\scripts\Clean-AllegroProject.ps1 -Preview

.EXAMPLE
.\scripts\Clean-AllegroProject.ps1 -Reconfigure

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Clean-AllegroProject.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Root = (Get-Location).Path,

    [switch]$Reconfigure,
    [switch]$Preview,
    [switch]$Force,
    [switch]$Forget
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ConfigFileName = '.allegro-clean.json'
$script:ConfigVersion = 1
$script:ExcludedDirectoryNames = @('.git', '.svn', '.hg', 'node_modules')

$script:Categories = @(
    [pscustomobject]@{
        Id          = 'logs'
        Number      = 1
        Name        = '日志与崩溃信息'
        Description = '*.log, *.jrl, *.err, *.dmp, *.stackdump'
        Recommended = $true
        Risk        = ''
    },
    [pscustomobject]@{
        Id          = 'temporary'
        Number      = 2
        Name        = '临时文件与锁文件'
        Description = '*.tmp, *.temp, *.lck, *.swp, *~, ~$*'
        Recommended = $true
        Risk        = '运行前请先关闭 Allegro，避免删除仍在使用的锁文件。'
    },
    [pscustomobject]@{
        Id          = 'cache'
        Number      = 3
        Name        = '缓存目录'
        Description = '.cache, cache, allegro_cache, .allegro_cache'
        Recommended = $true
        Risk        = ''
    },
    [pscustomobject]@{
        Id          = 'backups'
        Number      = 4
        Name        = '备份版本'
        Description = '*.bak, *.old, *.orig, 文件名末尾的 ,数字'
        Recommended = $false
        Risk        = '这些文件可能是唯一可用的历史版本。'
    },
    [pscustomobject]@{
        Id          = 'autosave'
        Number      = 5
        Name        = '自动保存与恢复文件'
        Description = '*.sav, *.autosave'
        Recommended = $false
        Risk        = '发生崩溃后可能需要这些文件恢复设计。'
    }
)

function Resolve-ProjectRoot {
    param([string]$Path)

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $resolved.Path -PathType Container)) {
        throw "项目路径不是目录: $Path"
    }

    $fullPath = [IO.Path]::GetFullPath($resolved.Path)
    $pathRoot = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -gt $pathRoot.Length) {
        return $fullPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $fullPath
}

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $base = $BasePath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $baseUri = [Uri]$base
    $pathUri = [Uri]$FullPath
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', [IO.Path]::DirectorySeparatorChar)
}

function Get-FileCategoryId {
    param([IO.FileInfo]$File)

    $name = $File.Name
    $extension = $File.Extension.ToLowerInvariant()

    if ($extension -in @('.log', '.jrl', '.err', '.dmp', '.stackdump')) {
        return 'logs'
    }
    if ($name -match '(?i)\.(log|jrl|err|dmp|stackdump),\d+$') {
        return 'logs'
    }
    if (($extension -in @('.tmp', '.temp', '.lck', '.swp')) -or
        $name.EndsWith('~') -or $name.StartsWith('~$')) {
        return 'temporary'
    }
    if (($extension -in @('.bak', '.old', '.orig')) -or $name -match ',\d+$') {
        return 'backups'
    }
    if ($extension -in @('.sav', '.autosave')) {
        return 'autosave'
    }

    return $null
}

function Get-DirectorySize {
    param([string]$Path)

    $total = [long]0
    try {
        foreach ($file in [IO.Directory]::EnumerateFiles($Path, '*', [IO.SearchOption]::AllDirectories)) {
            try { $total += ([IO.FileInfo]$file).Length } catch { }
        }
    }
    catch { }
    return $total
}

function Get-CleanupCandidates {
    param([string]$ProjectRoot)

    $results = New-Object System.Collections.Generic.List[object]
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($ProjectRoot)
    $cacheDirectoryNames = @('.cache', 'cache', 'allegro_cache', '.allegro_cache')

    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()

        try {
            $childDirectories = Get-ChildItem -LiteralPath $directory -Directory -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "无法读取目录，已跳过: $directory"
            continue
        }

        foreach ($childDirectory in $childDirectories) {
            if ($childDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                continue
            }
            if ($script:ExcludedDirectoryNames -contains $childDirectory.Name) {
                continue
            }
            if ($cacheDirectoryNames -contains $childDirectory.Name.ToLowerInvariant()) {
                $results.Add([pscustomobject]@{
                    CategoryId  = 'cache'
                    FullPath    = $childDirectory.FullName
                    RelativePath = Get-RelativePath -BasePath $ProjectRoot -FullPath $childDirectory.FullName
                    ItemType    = '目录'
                    Size        = Get-DirectorySize -Path $childDirectory.FullName
                })
                continue
            }
            $pending.Push($childDirectory.FullName)
        }

        try {
            $files = Get-ChildItem -LiteralPath $directory -File -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "无法读取文件列表，已跳过: $directory"
            continue
        }

        foreach ($file in $files) {
            if ($file.Name -eq $script:ConfigFileName) {
                continue
            }
            $categoryId = Get-FileCategoryId -File $file
            if ($null -ne $categoryId) {
                $results.Add([pscustomobject]@{
                    CategoryId   = $categoryId
                    FullPath     = $file.FullName
                    RelativePath = Get-RelativePath -BasePath $ProjectRoot -FullPath $file.FullName
                    ItemType     = '文件'
                    Size         = [long]$file.Length
                })
            }
        }
    }

    return @($results | ForEach-Object { $_ })
}

function Get-SavedSelection {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return $null
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.version -ne $script:ConfigVersion) {
            Write-Warning '已保存配置的版本不兼容，将重新选择。'
            return $null
        }

        $validIds = @($script:Categories | ForEach-Object { $_.Id })
        $selection = @($config.selectedCategories | Where-Object { $validIds -contains $_ })
        if ($selection.Count -eq 0) {
            return $null
        }
        return $selection
    }
    catch {
        Write-Warning "无法读取配置文件，将重新选择: $ConfigPath"
        return $null
    }
}

function Save-Selection {
    param(
        [string]$ConfigPath,
        [string[]]$Selection
    )

    $config = [ordered]@{
        version            = $script:ConfigVersion
        selectedCategories = @($Selection)
        updatedAt          = (Get-Date).ToString('o')
    }
    $json = $config | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText($ConfigPath, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Show-ScanSummary {
    param([object[]]$Candidates)

    Write-Host ''
    Write-Host '扫描结果:' -ForegroundColor Cyan
    foreach ($category in $script:Categories) {
        $items = @($Candidates | Where-Object { $_.CategoryId -eq $category.Id })
        $size = [long]0
        if ($items.Count -gt 0) {
            $size = [long](($items | Measure-Object -Property Size -Sum).Sum)
        }

        $recommended = if ($category.Recommended) { ' [建议]' } else { ' [谨慎]' }
        Write-Host ("  {0}. {1}{2}: {3} 项, {4}" -f $category.Number, $category.Name, $recommended, $items.Count, (Format-FileSize $size))
        Write-Host ("     {0}" -f $category.Description) -ForegroundColor DarkGray
        if ($category.Risk) {
            Write-Host ("     注意: {0}" -f $category.Risk) -ForegroundColor Yellow
        }
    }
}

function Read-CategorySelection {
    param([object[]]$Candidates)

    $availableNumbers = @(
        foreach ($category in $script:Categories) {
            $matchingItems = @($Candidates | Where-Object { $_.CategoryId -eq $category.Id })
            if ($matchingItems.Count -gt 0) {
                $category.Number
            }
        }
    )
    if ($availableNumbers.Count -eq 0) {
        return @()
    }

    $recommendedNumbers = @(
        $script:Categories |
            Where-Object { $_.Recommended -and ($availableNumbers -contains $_.Number) } |
            ForEach-Object { $_.Number }
    )
    $defaultText = $recommendedNumbers -join ','

    while ($true) {
        $answer = Read-Host "选择要清理的类别编号（逗号分隔；直接回车使用建议项: $defaultText；输入 0 取消）"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            $numbers = $recommendedNumbers
        }
        elseif ($answer.Trim() -eq '0') {
            return @()
        }
        else {
            $parts = @($answer -split '[,，\s]+' | Where-Object { $_ })
            $numbers = New-Object System.Collections.Generic.List[int]
            $valid = $true
            foreach ($part in $parts) {
                $number = 0
                if (-not [int]::TryParse($part, [ref]$number) -or -not ($availableNumbers -contains $number)) {
                    $valid = $false
                    break
                }
                if (-not $numbers.Contains($number)) {
                    $numbers.Add($number)
                }
            }
            if (-not $valid -or $numbers.Count -eq 0) {
                Write-Host '输入无效，请只填写扫描结果中存在内容的类别编号。' -ForegroundColor Yellow
                continue
            }
        }

        return @(
            $script:Categories |
                Where-Object { $numbers -contains $_.Number } |
                ForEach-Object { $_.Id }
        )
    }
}

function Show-SelectedItems {
    param([object[]]$Items)

    Write-Host ''
    Write-Host '将处理以下内容:' -ForegroundColor Cyan
    foreach ($item in ($Items | Sort-Object CategoryId, RelativePath)) {
        Write-Host ("  [{0}] {1} ({2})" -f $item.ItemType, $item.RelativePath, (Format-FileSize $item.Size))
    }
    $totalSize = [long](($Items | Measure-Object -Property Size -Sum).Sum)
    Write-Host ("合计: {0} 项, {1}" -f $Items.Count, (Format-FileSize $totalSize)) -ForegroundColor Cyan
}

function Remove-CleanupItems {
    param([object[]]$Items)

    $removedCount = 0
    $removedBytes = [long]0
    $failed = New-Object System.Collections.Generic.List[object]

    foreach ($item in $Items) {
        try {
            if ($item.ItemType -eq '目录') {
                Remove-Item -LiteralPath $item.FullPath -Recurse -Force -ErrorAction Stop
            }
            else {
                Remove-Item -LiteralPath $item.FullPath -Force -ErrorAction Stop
            }
            $removedCount++
            $removedBytes += $item.Size
        }
        catch {
            $failed.Add([pscustomobject]@{
                Path  = $item.RelativePath
                Error = $_.Exception.Message
            })
        }
    }

    Write-Host ''
    Write-Host ("已清理 {0} 项，释放约 {1}。" -f $removedCount, (Format-FileSize $removedBytes)) -ForegroundColor Green
    if ($failed.Count -gt 0) {
        Write-Warning ("有 {0} 项清理失败:" -f $failed.Count)
        foreach ($failure in $failed) {
            Write-Warning ("{0}: {1}" -f $failure.Path, $failure.Error)
        }
        return $false
    }
    return $true
}

try {
    $projectRoot = Resolve-ProjectRoot -Path $Root
    $configPath = Join-Path $projectRoot $script:ConfigFileName

    if ($Forget) {
        if (Test-Path -LiteralPath $configPath -PathType Leaf) {
            Remove-Item -LiteralPath $configPath -Force
            Write-Host "已删除清理配置: $configPath"
        }
        else {
            Write-Host '没有已保存的清理配置。'
        }
        exit 0
    }

    Write-Host "Allegro 项目清理器" -ForegroundColor Cyan
    Write-Host "项目目录: $projectRoot"
    Write-Host '正在扫描项目文件...'

    $candidates = @(Get-CleanupCandidates -ProjectRoot $projectRoot)
    Show-ScanSummary -Candidates $candidates

    if ($candidates.Count -eq 0) {
        Write-Host ''
        Write-Host '未发现可清理内容。' -ForegroundColor Green
        exit 0
    }

    $selection = $null
    if (-not $Reconfigure) {
        $selection = Get-SavedSelection -ConfigPath $configPath
    }

    if ($null -ne $selection -and @($selection).Count -gt 0) {
        $selectedNames = @(
            $script:Categories |
                Where-Object { @($selection) -contains $_.Id } |
                ForEach-Object { $_.Name }
        )
        Write-Host ''
        Write-Host ("使用已保存的选择: {0}" -f ($selectedNames -join '、')) -ForegroundColor Green
        Write-Host '如需修改，请使用 -Reconfigure。' -ForegroundColor DarkGray
    }
    else {
        $selection = @(Read-CategorySelection -Candidates $candidates)
        if ($selection.Count -eq 0) {
            Write-Host '已取消。'
            exit 0
        }
        Save-Selection -ConfigPath $configPath -Selection $selection
        Write-Host "选择已保存到: $configPath" -ForegroundColor Green
    }

    $selectedItems = @($candidates | Where-Object { @($selection) -contains $_.CategoryId })
    if ($selectedItems.Count -eq 0) {
        Write-Host ''
        Write-Host '已选类别中没有可清理内容。' -ForegroundColor Green
        exit 0
    }

    Show-SelectedItems -Items $selectedItems

    if ($Preview) {
        Write-Host ''
        Write-Host '预览完成，未删除任何内容。' -ForegroundColor Yellow
        exit 0
    }

    if (-not $Force) {
        $confirmation = Read-Host '确认清理以上内容？输入 Y 继续'
        if ($confirmation -notmatch '^(?i)y(es)?$') {
            Write-Host '已取消，未删除任何内容。'
            exit 0
        }
    }

    $success = Remove-CleanupItems -Items $selectedItems
    if (-not $success) { exit 1 }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
