#!/usr/bin/env pwsh
#Requires -Version 7.4
param([Alias('GamePath')][string]$MandalaGamePath, [Alias('OutputPath')][string]$MandalaOutputPath = (Join-Path $PSScriptRoot '../common/buildings'), [Alias('RewardOutputPath')][string]$MandalaRewardOutputPath)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/Common.ps1"

function Get-MandalaCompletionPatch([string]$Source, [string[]]$ExpectedKeys) {
    # Replace the native file at its exact path: duplicate building IDs in a late
    # filename have no documented event-style override priority. Keep every other
    # definition/field byte-for-byte after normalizing source BOM and newlines.
    $patched=$Source
    $edits=[Collections.Generic.List[object]]::new()
    $blocks=@(Get-ScriptBlocks $Source)
    foreach ($key in $ExpectedKeys) {
        $matches=@($blocks | Where-Object Key -ceq $key)
        if ($matches.Count -ne 1) { throw "Expected one $key definition; review the vanilla update" }
        $original="$key = {$($matches[0].Body)}"
        $completion=Get-InnerBlock $matches[0].Body 'on_complete'
        $scope=[regex]::Matches($completion,'(?m)^\t\tscope:character = \{')
        if ($scope.Count -ne 1 -or $completion -notmatch '(creator_mandala_upgraded_regular_holding_piety_effect|mandala_upgraded_temple_holding_effect) = yes') {
            throw "Expected one mandala reward callback in $key; review the vanilla update"
        }
        $start=$scope[0].Index
        $open=$completion.IndexOf('{',$start); $depth=0; $end=$open
        for(;$end -lt $completion.Length;$end++) {
            if($completion[$end] -eq '{') { $depth++ }
            elseif($completion[$end] -eq '}') { $depth--; if($depth -eq 0) { break } }
        }
        if($depth -ne 0) { throw "Unclosed character callback in $key" }
        $callback=$completion.Substring($start,$end-$start+1)
        $indented=($callback -split '\n' | ForEach-Object { "`t$_" }) -join "`n"
        $guard=@"
		# MQA: instant construction has no payer in the engine's callback context.
		# Match the vanilla mandala fallback, while preserving a real payer.
		if = {
			limit = {
				NOT = { exists = scope:character }
				exists = county.holder
				county.holder = { is_alive = yes }
			}
			county.holder = { save_scope_as = character }
		}
		if = {
			limit = { exists = scope:character scope:character = { is_alive = yes } }
			debug_log = "MQA_REWARD CALLBACK $key"
$indented
		}
		else = { debug_log = "MQA_REWARD SKIPPED no_living_builder $key" }
"@
        $newCompletion=$completion.Replace($callback,$guard)
        $replacement=$original.Replace($completion,$newCompletion)
        if (-not $patched.Contains($original)) { throw "Cannot safely replace $key; review the vanilla update" }
        $patched=$patched.Replace($original,$replacement)
        $edits.Add([pscustomobject]@{Key=$key; Original=$callback; Patched=$guard})
    }
    # Reject a changed source shape/new unguarded callbacks instead of silently
    # ignoring a new level introduced by a game update.
    foreach ($block in $blocks) {
        $completion=Get-InnerBlock $block.Body 'on_complete'
        if ($completion -match '(?m)^\t\tscope:character = \{' -and $block.Key -cnotin $ExpectedKeys) {
            throw "Unexpected character callback in $($block.Key); review the vanilla update"
        }
    }
    [pscustomobject]@{Original=$Source; Patched=$patched; Edits=$edits.ToArray()}
}

function Get-MandalaRewardPatch([string]$Source) {
    $keys=@('mandala_upgraded_temple_holding_effect','creator_mandala_upgraded_regular_holding_piety_effect')
    $blocks=@(Get-ScriptBlocks $Source)
    $definitions=[Collections.Generic.List[object]]::new()
    foreach ($key in $keys) {
        $found=@($blocks | Where-Object Key -ceq $key)
        if($found.Count -ne 1) { throw "Expected one $key; review the vanilla update" }
        $original="$key = {$($found[0].Body)}"
        $patched=$original
        $edits=[Collections.Generic.List[object]]::new()
        $payments=[regex]::Matches($original,'(?m)^(\t+)add_piety = \{')
        $expected=$key -eq 'mandala_upgraded_temple_holding_effect' ? 3 : 1
        if($payments.Count -ne $expected) { throw "Changed reward payments in $key; review the vanilla update" }
        $index=0
        foreach($payment in $payments) {
            $index++
            $start=$payment.Index; $open=$original.IndexOf('{',$start); $depth=0; $end=$open
            for(;$end -lt $original.Length;$end++) {
                if($original[$end] -eq '{') { $depth++ }
                elseif($original[$end] -eq '}') { $depth--; if($depth -eq 0) { break } }
            }
            if($depth -ne 0) { throw "Unclosed reward payment in $key" }
            $old=$original.Substring($start,$end-$start+1)
            $indent=$payment.Groups[1].Value
            $indented=($old -split '\n' | ForEach-Object { "`t$_" }) -join "`n"
            # Distinguish the two native temple allocations (payer and county
            # holder) rather than mistaking them for a duplicate upgrade.
            $new=@(
                "${indent}if = {",
                "${indent}`tlimit = { is_alive = yes }",
                "${indent}`tmqa_b_reward_payment_begin_effect = yes",
                $indented,
                "${indent}`tdebug_log = `"MQA_REWARD PAYMENT $key allocation=$index`"",
                "${indent}`tmqa_b_reward_payment_end_effect = yes",
                "${indent}}",
                "${indent}else = { debug_log = `"MQA_REWARD SKIPPED dead_recipient $key allocation=$index`" }") -join "`n"
            # Identical primary-payment text can occur twice. Replace the
            # original spans from right to left after collecting all edits.
            $edits.Add([pscustomobject]@{Index=$start;Original=$old;Patched=$new})
        }
        foreach($edit in @($edits | Sort-Object Index -Descending)) {
            $patched=$patched.Remove($edit.Index,$edit.Original.Length).Insert($edit.Index,$edit.Patched)
        }
        $fallback=[regex]::Match($patched,'(?s)\A[^\n]+\n\tif = \{\n\t\tlimit = \{\n\t\t\tNOT = \{ exists = scope:character \}\n\t\t\}\n\t\tcounty.holder = \{ save_scope_as = character \}\n\t\}')
        if(-not $fallback.Success) { throw "Changed payer fallback in $key; review the vanilla update" }
        $oldFallback=$fallback.Value.Substring($fallback.Value.IndexOf("`n")+1)
        $newFallback=$oldFallback.Replace('NOT = { exists = scope:character }', "NOT = { exists = scope:character }`n`t`t`texists = county.holder`n`t`t`tcounty.holder = { is_alive = yes }")
        $patched=$patched.Replace($oldFallback,$newFallback)
        $edits.Add([pscustomobject]@{Index=-1;Original=$oldFallback;Patched=$newFallback})
        # Guard the helper entry as well: castle level 2 and ordinary engine
        # construction may call this helper outside our patched callbacks.
        $entry=[regex]::Matches($patched,'(?m)^\tscope:character = \{')
        if($entry.Count -ne 1) { throw "Changed payer scope in $key; review the vanilla update" }
        $entryStart=$entry[0].Index
        $open=$patched.IndexOf('{',$entryStart); $depth=0; $end=$open
        for(;$end -lt $patched.Length;$end++) {
            if($patched[$end] -eq '{') { $depth++ }
            elseif($patched[$end] -eq '}') { $depth--; if($depth -eq 0) { break } }
        }
        if($depth -ne 0) { throw "Unclosed payer scope in $key" }
        $oldEntry=$patched.Substring($entryStart,$end-$entryStart+1)
        $indented=($oldEntry -split '\n' | ForEach-Object { "`t$_" }) -join "`n"
        $newEntry="`tif = {`n`t`tlimit = { exists = scope:character scope:character = { is_alive = yes } }`n$indented`n`t}`n`telse = { debug_log = `"MQA_REWARD SKIPPED no_living_builder $key`" }"
        $patched=$patched.Remove($entryStart,$oldEntry.Length).Insert($entryStart,$newEntry)
        $edits.Add([pscustomobject]@{Index=-2;Original=$oldEntry;Patched=$newEntry})
        $definitions.Add([pscustomobject]@{Key=$key;Original=$original;Patched=$patched;Edits=$edits.ToArray()})
    }
    [pscustomobject]@{Definitions=$definitions.ToArray();Patched=($definitions.Patched -join "`n`n")+"`n"}
}

function Write-MandalaCompletionFix([string]$Game,[string]$Output,[string]$RewardOutput='') {
    $files=@{
        '00_castle_buildings.txt'=@('castle_03','castle_04')
        '00_temple_buildings.txt'=@('temple_02','temple_03','temple_04')
        'temple_citadel_buildings.txt'=@('temple_citadel_02','temple_citadel_03','temple_citadel_04')
    }
    # Validate all sources before writing any replacement.
    $patches=@{}
    foreach ($name in $files.Keys) {
        $patches[$name]=Get-MandalaCompletionPatch (Read-Text "$Game/common/buildings/$name") $files[$name]
    }
    $rewards=Get-MandalaRewardPatch (Read-Text "$Game/common/scripted_effects/tgp_mandala_scripted_effects.txt")
    if(-not $RewardOutput) { $RewardOutput=Join-Path (Split-Path ([IO.Path]::GetFullPath($Output)) -Parent) 'scripted_effects/zz_mqa_mandala_reward_effects.txt' }
    foreach ($name in $files.Keys) {
        Write-Text (Join-Path $Output $name) $patches[$name].Patched -Bom
    }
    Write-Text $RewardOutput ("# GENERATED by tools/generate_mandala_completion_fix.ps1.`n# Preserve native reward conditions/amounts; guard living recipients and audit actual payments.`n`n"+$rewards.Patched) -Bom
}
if ($MyInvocation.InvocationName -ne '.') { Write-MandalaCompletionFix ($MandalaGamePath ? $MandalaGamePath : $script:DefaultGame) $MandalaOutputPath $MandalaRewardOutputPath }
