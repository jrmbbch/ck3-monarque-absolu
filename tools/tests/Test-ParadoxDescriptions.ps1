#!/usr/bin/env pwsh
# Offline checks: never authenticates or contacts Paradox.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../publish_paradox.ps1"
$description=Get-ParadoxDescription
if ($description -notmatch '<h3>Traits</h3>' -or $description -match '•') { throw 'Expected structured HTML lists and headings' }
$short=(Read-Text (Join-Path $script:RepoRoot 'docs/paradox_mods_short_description.txt')).Trim()
$script:Reads=0; $script:Writes=0
function Get-ParadoxAuth { @{session=@{token='offline-test'}} }
function Get-ParadoxMetadata($Auth) {
    $script:Reads++
    @{actions=@{canEdit=$true};game='ck3';displayName='Monarque Absolu - Absolute Monarch';latestVersion=6;updating=$false;longDescription= $(if ($script:Reads -eq 1) {'old'} else {$description});shortDescription=$short}
}
function Invoke-ParadoxRequest($Method,$Path,$Auth,$Data) {
    if ($Method -cne 'PUT' -or $Path -cne '/mods/161949/versions/6') { throw 'Unexpected metadata request' }
    if ($Data.Count -ne 2 -or $Data.longDescription -cne $description -or $Data.shortDescription -cne $short) { throw 'Unexpected metadata payload' }
    $script:Writes++
    @{}
}
Update-ParadoxDescriptions
if ($script:Writes -ne 1 -or $script:Reads -ne 2) { throw 'Expected one write and read-back verification' }
Update-ParadoxDescriptions
if ($script:Writes -ne 1) { throw 'Matching descriptions must not be rewritten' }
function Get-ParadoxMetadata($Auth) { @{actions=@{canEdit=$false}} }
$denied=$false
try { Update-ParadoxDescriptions } catch { if ($_.Exception.Message -notmatch 'cannot edit') { throw }; $denied=$true }
if (-not $denied -or $script:Writes -ne 1) { throw 'Missing edit-permission guard' }
Write-Host 'PASS Paradox HTML, metadata-only payload, read-back, idempotence and permission guard'
