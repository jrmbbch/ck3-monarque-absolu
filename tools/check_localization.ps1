#!/usr/bin/env pwsh
#Requires -Version 7.4
param([string]$LocalizationRoot = (Join-Path $PSScriptRoot '../localization'))
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Common.ps1"
function Test-Localization([string]$Root = $LocalizationRoot) {
    $problems = [Collections.Generic.List[string]]::new()
    $reference = New-OrdinalMap
    foreach ($language in @('english','french','german','spanish','polish','russian','japanese','korean','simp_chinese')) {
        $folder = Join-Path $Root $language
        $files = if (Test-Path -LiteralPath $folder) { @(Get-ChildItem -LiteralPath $folder -Filter '*.yml' -Recurse -File | Sort-Object FullName) } else { @() }
        if (-not $files.Count) { $problems.Add("${language}: no localization files"); continue }
        $main = New-OrdinalMap
        foreach ($file in $files) {
            if (-not $file.Name.EndsWith("_l_$language.yml")) { $problems.Add("${file}: file name must end with _l_$language.yml") }
            $raw = [IO.File]::ReadAllBytes($file.FullName)
            if ($raw.Length -lt 3 -or $raw[0] -ne 239 -or $raw[1] -ne 187 -or $raw[2] -ne 191) { $problems.Add("${file}: missing UTF-8 BOM") }
            $lines = (Read-Text $file.FullName).TrimStart([char]0xFEFF) -split '\n'
            if (-not $lines.Count -or $lines[0].Trim() -cne "l_${language}:") { $problems.Add("${file}: first line must be 'l_${language}:'") }
            $keys = New-OrdinalMap
            for ($index = 1; $index -lt $lines.Count; $index++) {
                $line = $lines[$index]; $location = "$($file.FullName):$($index + 1)"
                if (-not $line.Trim() -or $line.Trim().StartsWith('#')) { continue }
                $match = [regex]::Match($line, '^ ([A-Za-z0-9_.]+):\d* "(.*)"\s*$')
                if (-not $match.Success) { $problems.Add("${location}: unparsable line"); continue }
                $key = $match.Groups[1].Value; $value = $match.Groups[2].Value
                if ($value.Contains('"')) { $problems.Add("${location}: double quote inside value of $key") }
                if ([regex]::Matches($value,'\[').Count -ne [regex]::Matches($value,'\]').Count) { $problems.Add("${location}: unbalanced [] in $key") }
                if ([regex]::Matches($value,'#').Count -gt 3 * [regex]::Matches($value,'#!').Count) { $problems.Add("${location}: formatting tag not closed with #! in $key") }
                if ($keys.Contains($key)) { $problems.Add("${location}: duplicate key $key") }
                $keys[$key] = $value
            }
            if ($file.FullName -notmatch '[/\\]replace[/\\]') { foreach ($key in $keys.Keys) { $main[$key] = $keys[$key] } }
        }
        if ($language -eq 'english') { $reference = $main; continue }
        $missing = @($reference.Keys | Where-Object { -not $main.Contains($_) })
        $extra = @($main.Keys | Where-Object { -not $reference.Contains($_) })
        if ($missing.Count) { $problems.Add("${language}: missing keys $($missing -join ', ')") }
        if ($extra.Count) { $problems.Add("${language}: unknown keys $($extra -join ', ')") }
    }
    foreach ($problem in $problems) { Write-Host $problem }
    Write-Host "$($problems.Count) problem(s)"
    if ($problems.Count) { throw 'Localization validation failed' }
}
if ($MyInvocation.InvocationName -ne '.') { Test-Localization $LocalizationRoot }
