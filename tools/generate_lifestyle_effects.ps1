#!/usr/bin/env pwsh
#Requires -Version 7.4
param([string]$GamePath, [string]$OutputPath = (Join-Path $PSScriptRoot '../common/scripted_effects/mqa_lifestyle_effects.txt'))
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Common.ps1"
function Write-LifestyleEffects([string]$Game, [string]$Output) {
    $perks = New-OrdinalMap
    foreach ($path in (Get-OrdinalSorted @(Get-ChildItem -LiteralPath "$Game/common/lifestyle_perks" -Filter '*.txt' -File | ForEach-Object FullName))) {
        foreach ($block in (Get-ScriptBlocks (Remove-ScriptComments (Read-Text $path)))) {
            $perks[$block.Key] = @{ Parents = @([regex]::Matches($block.Body, '(?m)^\tparent\s*=\s*(\w+)') | ForEach-Object { $_.Groups[1].Value }); Lifestyle = Get-ScriptField $block.Body 'lifestyle' }
        }
    }
    $done = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $keys = [Collections.Generic.List[string]]::new()
    function Visit-Perk([string]$Key) {
        if (-not $perks.Contains($Key) -or -not $done.Add($Key)) { return }
        foreach ($parent in $perks[$Key].Parents) { Visit-Perk $parent }
        $keys.Add($Key)
    }
    foreach ($key in $perks.Keys) { Visit-Perk $key }
    $regular = @($keys | Where-Object { $perks[$_].Lifestyle -ne 'wanderer_lifestyle' })
    $wanderer = @($keys | Where-Object { $perks[$_].Lifestyle -eq 'wanderer_lifestyle' })
    $lines = [Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]@('# GENERATED FILE, DO NOT EDIT BY HAND.', '# Built from the game files by tools/generate_lifestyle_effects.ps1.', '', '# Character scope. Unlocks every lifestyle perk, parents first.', 'mqa_unlock_all_perks_effect = {'))
    function Add-Perk([string]$Key, [int]$Depth) {
        $tab = "`t" * $Depth
        $lines.AddRange([string[]]@("${tab}if = {", "$tab`tlimit = { NOT = { has_perk = $Key } }", "$tab`tadd_perk = $Key", "$tab}"))
    }
    foreach ($key in $regular) { Add-Perk $key 1 }
    if ($wanderer.Count) {
        $lines.AddRange([string[]]@("`tif = {", "`t`tlimit = { has_dlc_feature = wandering_nobles }"))
        foreach ($key in $wanderer) { Add-Perk $key 2 }
        $lines.Add("`t}")
    }
    $lines.AddRange([string[]]@('}', ''))
    Write-Text $Output ($lines -join "`n") -Bom
    Write-Host "$($regular.Count) perks, $($wanderer.Count) wanderer perks -> $Output"
}
if ($MyInvocation.InvocationName -ne '.') { Write-LifestyleEffects ($GamePath ? $GamePath : $script:DefaultGame) $OutputPath }
