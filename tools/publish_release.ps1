#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Publish the GitHub tag/release, Steam Workshop and Paradox Mods with release notes.
.DESCRIPTION
Without -Publish, validate and stage only: no network or authentication.
.EXAMPLE
pwsh -File tools/publish_release.ps1 all -Publish
#>
param(
    [Parameter(Position=0)][ValidateSet('github','steam','paradox','all')][string]$Platform='all',
    [switch]$Publish,
    [string]$SteamLibrary=(Join-Path $HOME 'Library/Application Support/Steam/steamapps/common/Crusader Kings III/binaries/ck3.app/Contents/Frameworks/libsteam_api.dylib'),
    [ValidateRange(1,86400)][int]$TimeoutSeconds=300
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/Common.ps1"
. "$PSScriptRoot/check_localization.ps1"
. "$PSScriptRoot/publish_github.ps1"
. "$PSScriptRoot/publish_steam.ps1"
. "$PSScriptRoot/publish_paradox.ps1"
function Get-ReleaseInfo {
    $source=Read-Text (Join-Path $script:RepoRoot 'descriptor.mod')
    function Field([string]$Name) {
        $match=[regex]::Match($source, '(?m)^' + [regex]::Escape($Name) + '="([^"\n]+)"$')
        if (-not $match.Success) { throw "Missing descriptor field: $Name" }
        $match.Groups[1].Value
    }
    $version=Field 'version'
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid release version' }
    if ((Field 'remote_file_id') -cne '3813333986') { throw 'Unexpected Steam item ID; refusing to publish' }
    $notes=(Read-Text (Join-Path $script:RepoRoot "docs/patch_notes/$version.txt")).Trim()
    if (-not $notes.StartsWith($version + "`n", [StringComparison]::Ordinal)) { throw 'Release notes do not match descriptor version' }
    $tagBlock=[regex]::Match($source,'(?s)tags=\{(.*?)\}').Groups[1].Value
    @{ Version=$version; Name=Field 'name'; Required=Field 'supported_version'; Notes=$notes; Tags=@([regex]::Matches($tagBlock,'"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }) }
}
function New-ReleaseStage([string]$Destination) {
    Test-Localization (Join-Path $script:RepoRoot 'localization')
    $names=@('common','events','localization','descriptor.mod','thumbnail.png')
    foreach ($name in $names) {
        $source=Join-Path $script:RepoRoot $name
        $items=@(Get-Item -LiteralPath $source -Force)
        if (Test-Path -LiteralPath $source -PathType Container) { $items+=@(Get-ChildItem -LiteralPath $source -Recurse -Force) }
        if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw "Symlink in release sources: $name" }
    }
    if (Test-Path -LiteralPath $Destination) { throw 'Staging destination already exists' }
    [IO.Directory]::CreateDirectory($Destination) > $null
    foreach ($name in $names) { Copy-Item -LiteralPath (Join-Path $script:RepoRoot $name) -Destination $Destination -Recurse }
    Get-ChildItem -LiteralPath $Destination -Recurse -Force -Filter '.DS_Store' | Remove-Item -Force
    Get-ChildItem -LiteralPath $Destination -Recurse -Force -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force
}
function Invoke-ReleasePublication([string]$Target, [bool]$Upload, [string]$Library, [int]$Timeout=300) {
    $info=Get-ReleaseInfo
    Write-Host "Version $($info.Version); platforms: $Target; upload: $Upload"
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('mqa-publish-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($temporary) > $null
    try {
        $content=Join-Path $temporary 'monarque_absolu'; New-ReleaseStage $content
        Write-Host "Validated $(@(Get-ChildItem -LiteralPath $content -Recurse -File).Count) game files; notes: $($info.Notes)"
        if ($Target -in @('github','all')) { Write-Host "GitHub: tag v$($info.Version) and release with matching notes; publication requires a clean, pushed commit." }
        if (-not $Upload) { Write-Host 'Dry run complete; no authentication or network requests performed.'; return }
        if ($Target -in @('github','all')) { Publish-GitHub $info }
        if ($Target -in @('steam','all')) { Publish-Steam $content $info $Library $Timeout }
        if ($Target -in @('paradox','all')) { Publish-Paradox $content $info $Timeout }
    } finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
if ($MyInvocation.InvocationName -ne '.') { Invoke-ReleasePublication $Platform $Publish.IsPresent $SteamLibrary $TimeoutSeconds }
