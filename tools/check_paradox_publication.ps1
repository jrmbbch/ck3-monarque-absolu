#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Verify the current release's public Paradox notes without authentication/upload.
.EXAMPLE
pwsh -File tools/check_paradox_publication.ps1 -TimeoutSeconds 60
#>
param([Alias('TimeoutSeconds')][ValidateRange(0,86400)][int]$VerificationTimeoutSeconds=30)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/publish_release.ps1"
function Confirm-PublicParadoxRelease([int]$Timeout=30) {
    $info=Get-ReleaseInfo
    $status=Wait-ParadoxPublication $info.Notes $Timeout
    Write-Host "Paradox: $($info.Version) and its exact notes are publicly confirmed (internal version $($status.LatestVersion); backend updating: $($status.Updating)). https://mods.paradoxplaza.com/mods/161949/Any"
}
if ($MyInvocation.InvocationName -ne '.') { Confirm-PublicParadoxRelease $VerificationTimeoutSeconds }
