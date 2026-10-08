# LEGIONFORGE 7.3.5 - получение полных дампов игрового мира (world + hotfixes).
# Файл хранится в UTF-8 с BOM (кириллица в PowerShell 5.1).
#
# Источник по умолчанию: официальный релиз AshamaneCore "ADB_735.10 Final before BfA"
#   https://github.com/AshamaneProject/AshamaneCore/releases/tag/ADB_735.10
#   ADB_735.10.rar (88 МБ) -> ADB_735.10_world.sql (367 МБ) + ADB_735.10_hotfix.sql (126 МБ)
# Ядро LEGIONFORGE основано на AshamaneCore, setup.bat ожидает именно эти файлы.
#
# Порядок поиска: setup_tmp\*.sql -> databases.zip / ADB_735.10.rar (setup_tmp или корень)
#                 -> LEGIONFORGE_DATABASES_URL -> официальный релиз AshamaneCore.
[CmdletBinding()]
param(
    [string]$TargetDir = ''
)

. (Join-Path $PSScriptRoot 'lf_common.ps1')

$Root = $PSScriptRoot
if (-not $TargetDir) { $TargetDir = Join-Path $Root 'setup_tmp' }
$WorldSql = Join-Path $TargetDir 'ADB_735.10_world.sql'
$HotfixSql = Join-Path $TargetDir 'ADB_735.10_hotfix.sql'
$AdbUrl = 'https://github.com/AshamaneProject/AshamaneCore/releases/download/ADB_735.10/ADB_735.10.rar'
$AdbSha256 = 'e3f0f90db8940f3a1201188fafdf740b8734e2d3e893e1cebbd14c2b9917154a'

function Test-Dumps {
    return (Test-Path -LiteralPath $WorldSql) -and (Test-Path -LiteralPath $HotfixSql) -and
        ((Get-Item -LiteralPath $WorldSql).Length -gt 100MB) -and ((Get-Item -LiteralPath $HotfixSql).Length -gt 30MB)
}

function Expand-Dumps([string]$Archive) {
    Write-LfStep "Распаковка $(Split-Path -Leaf $Archive)..."
    $tmp = Join-Path $TargetDir 'adb_extract'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    Expand-LfArchive -Archive $Archive -Destination $tmp
    foreach ($name in @('ADB_735.10_world.sql', 'ADB_735.10_hotfix.sql')) {
        $found = Get-ChildItem -LiteralPath $tmp -Recurse -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) { throw "В архиве $(Split-Path -Leaf $Archive) нет файла $name" }
        Move-Item -LiteralPath $found.FullName -Destination (Join-Path $TargetDir $name) -Force
    }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$exitCode = 0
try {
    Open-LfLog (Join-Path $Root 'logs\get_databases.log')
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

    if (Test-Dumps) { Write-LfOk 'Дампы ADB_735.10 уже на месте.'; exit 0 }

    $free = Get-LfFreeSpaceGB $TargetDir
    if ($free -ge 0 -and $free -lt 3) { throw "Для дампов нужно около 3 ГБ, свободно $free ГБ." }

    $local = @(
        (Join-Path $TargetDir 'databases.zip'), (Join-Path $Root 'databases.zip'),
        (Join-Path $TargetDir 'ADB_735.10.rar'), (Join-Path $Root 'ADB_735.10.rar')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if ($local) {
        Write-LfOk "Найден локальный архив: $local"
        Expand-Dumps $local
    }
    elseif ($env:LEGIONFORGE_DATABASES_URL) {
        $archive = Join-Path $TargetDir 'databases.zip'
        Invoke-LfDownload -Urls @($env:LEGIONFORGE_DATABASES_URL) -Destination $archive -MinBytes 10MB
        Expand-Dumps $archive
    }
    else {
        Write-LfStep 'Загрузка базы мира ADB_735.10 (официальный релиз AshamaneCore, 88 МБ)...'
        $archive = Join-Path $TargetDir 'ADB_735.10.rar'
        Invoke-LfDownload -Urls @($AdbUrl) -Destination $archive -Sha256 $AdbSha256 -MinBytes 50MB
        Expand-Dumps $archive
    }

    if (-not (Test-Dumps)) { throw 'После распаковки дампы world/hotfix не найдены или повреждены.' }
    Write-LfOk ("Дампы готовы: world {0}, hotfix {1}" -f (Format-LfSize (Get-Item -LiteralPath $WorldSql).Length), (Format-LfSize (Get-Item -LiteralPath $HotfixSql).Length))
}
catch {
    $exitCode = 1
    Write-LfErr $_.Exception.Message
}
finally { Close-LfLog }
exit $exitCode
