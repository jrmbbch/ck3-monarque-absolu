#!/usr/bin/env pwsh
#Requires -Version 7.4
param([string]$ModDirectory = $(if ($env:CK3_MOD_DIR) { $env:CK3_MOD_DIR } else { Join-Path $HOME 'Documents/Paradox Interactive/Crusader Kings III/mod' }))
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Common.ps1"
. "$PSScriptRoot/check_localization.ps1"
function Build-Release([string]$Directory) {
    Test-Localization (Join-Path $script:RepoRoot 'localization')
    $target = [IO.Path]::GetFullPath((Join-Path $Directory 'monarque_absolu'))
    if ($target -eq $script:RepoRoot -or $script:RepoRoot.StartsWith($target + [IO.Path]::DirectorySeparatorChar)) { throw 'Release target overlaps the repository' }
    $remote = ''
    if (Test-Path -LiteralPath "$target/descriptor.mod") { $remote = [regex]::Match((Read-Text "$target/descriptor.mod"), '(?m)^remote_file_id=.*$').Value }
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    [IO.Directory]::CreateDirectory($target) > $null
    foreach ($name in @('common','events','localization','descriptor.mod','thumbnail.png')) { Copy-Item -LiteralPath (Join-Path $script:RepoRoot $name) -Destination $target -Recurse }
    $descriptor = Read-Text "$target/descriptor.mod"
    if ($remote -and $descriptor -notmatch '(?m)^remote_file_id=') { $descriptor = $descriptor.TrimEnd() + "`n$remote`n"; Write-Text "$target/descriptor.mod" $descriptor }
    Get-ChildItem -LiteralPath $target -Recurse -Force -Filter '.DS_Store' | Remove-Item -Force
    $entry = @($descriptor -split '\n' | Where-Object { $_ -and $_ -notmatch '^remote_file_id=' })
    $entry += 'path="' + $target + '"'
    if ($remote) { $entry += $remote }
    Write-Text (Join-Path $Directory 'monarque_absolu.mod') (($entry -join "`n") + "`n")
    Write-Host "Release ready in $target"
}
if ($MyInvocation.InvocationName -ne '.') { Build-Release $ModDirectory }
