#!/usr/bin/env pwsh
#Requires -Version 7.4
# Regenerate province and domicile effects after a game update. Requirements, priorities
# and upgrade choices follow the original generator; output is UTF-8 with BOM and LF.
param([string]$GamePath, [string]$OutputPath = (Join-Path $PSScriptRoot '../common/scripted_effects/mqa_building_effects.txt'))
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Common.ps1"
$script:RegularFiles = @('00_common_buildings.txt','00_standard_economy_buildings.txt','00_standard_fortification_buildings.txt','00_standard_military_buildings.txt','00_temple_buildings.txt','00_tribal_buildings.txt','00_city_buildings.txt','temple_citadel_buildings.txt')
$script:HoldingMain = @('castle','city','temple','tribe','temple_citadel')
$script:Fortifications = @('ramparts','curtain_walls','watchtowers','hill_forts','palisades','idjang_forts','citadel_shrine')
$script:NotUpgraded = @('tgp_great_project_buildings.txt','pam_buildings.txt','99_ach_buildings.txt')
function Get-BuildingValues([string]$Game) {
    $model = @{ Constants = @{}; Values = @{} }
    foreach ($folder in @('common/script_values','common/buildings')) {
        # Preserve file enumeration order for overriding definitions, as in the old generator.
        foreach ($path in (Get-ChildItem -LiteralPath "$Game/$folder" -Filter '*.txt' -File)) {
            $text = Remove-ScriptComments (Read-Text $path.FullName)
            foreach ($match in [regex]::Matches($text, '^\s*@([A-Za-z0-9_]+)\s*=\s*([^\n]+?)\s*$', 'Multiline')) { $model.Constants[$match.Groups[1].Value] = $match.Groups[2].Value }
            if ($folder -eq 'common/script_values') {
                foreach ($match in [regex]::Matches($text, '^([A-Za-z0-9_]+)\s*=\s*(@\[[^\]\n]*\]|@[A-Za-z0-9_]+|-?[0-9.]+)\s*$', 'Multiline')) { $model.Values[$match.Groups[1].Value] = $match.Groups[2].Value }
            }
        }
    }
    $model
}
function Invoke-NumericExpression([string]$Expression) {
    # Small arithmetic parser, including Python-style exponent/floor/modulo semantics.
    # Never execute game content as PowerShell or permit method/property access.
    $tokens=[Collections.Generic.List[string]]::new(); $offset=0
    $pattern=[regex]::new('\G\s*(?:(\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|\*\*|//|[+*/%()\-])')
    while ($offset -lt $Expression.Length) {
        if (-not $Expression.Substring($offset).Trim()) { break }
        $m=$pattern.Match($Expression,$offset)
        if (-not $m.Success) { throw 'Invalid arithmetic token' }
        $tokens.Add($m.Value.Trim()); $offset=$m.Index+$m.Length
    }
    $state=@{Index=0}
    function Parse-Number([int]$Minimum=0) {
        if ($state.Index -ge $tokens.Count) { throw 'Missing operand' }
        $token=$tokens[$state.Index]; $state.Index++
        if ($token -in @('+','-')) { $left=Parse-Number 25; if ($token -eq '-') { $left=-$left } }
        elseif ($token -eq '(') {
            $left=Parse-Number 0
            if ($state.Index -ge $tokens.Count -or $tokens[$state.Index] -ne ')') { throw 'Missing parenthesis' }
            $state.Index++
        } else { $left=[double]::Parse($token,[Globalization.CultureInfo]::InvariantCulture) }
        while ($state.Index -lt $tokens.Count) {
            $op=$tokens[$state.Index]
            $precedence=switch ($op) { '+' {10};'-' {10};'*' {20};'/' {20};'//' {20};'%' {20};'**' {30};default {-1} }
            if ($precedence -lt $Minimum) { break }
            $state.Index++
            $right=Parse-Number ($op -eq '**' ? $precedence : ($precedence+1))
            $left=switch ($op) {
                '+' { $left+$right }; '-' { $left-$right }; '*' { $left*$right }
                '/' { if ($right -eq 0) { throw 'Division by zero' }; $left/$right }
                '//' { if ($right -eq 0) { throw 'Division by zero' }; [Math]::Floor($left/$right) }
                '%' { if ($right -eq 0) { throw 'Division by zero' }; $left-[Math]::Floor($left/$right)*$right }
                '**' { [Math]::Pow($left,$right) }
            }
        }
        return [double]$left
    }
    $value=Parse-Number 0
    if ($state.Index -ne $tokens.Count -or -not [double]::IsFinite($value)) { throw 'Invalid arithmetic expression' }
    $value
}
function Resolve-BuildingValue($Model, [string]$Token, [int]$Depth = 0) {
    if (-not $Token -or $Depth -gt 30) { return 0.0 }
    $token = $Token.Trim(); $numeric = 0.0
    if ([double]::TryParse($token, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$numeric)) { return $numeric }
    if ($token.StartsWith('@[')) {
        $expression = [regex]::Replace($token.Substring(2, $token.Length - 3), '[A-Za-z_][A-Za-z0-9_]*', [Text.RegularExpressions.MatchEvaluator]{ param($m) (Resolve-BuildingValue $Model ('@' + $m.Value) ($Depth + 1)).ToString('R', [Globalization.CultureInfo]::InvariantCulture) })
        # Parse arithmetic as data. No PowerShell evaluation of game file content.
        try { return Invoke-NumericExpression $expression } catch { return 0.0 }
    }
    if ($token.StartsWith('@')) { return Resolve-BuildingValue $Model $Model.Constants[$token.Substring(1)] ($Depth + 1) }
    Resolve-BuildingValue $Model $Model.Values[$token] ($Depth + 1)
}
function Get-ProvinceBuildings([string]$Game) {
    $buildings = New-OrdinalMap
    foreach ($path in (Get-OrdinalSorted @(Get-ChildItem -LiteralPath "$Game/common/buildings" -Filter '*.txt' -File | ForEach-Object FullName))) {
        $file = [IO.Path]::GetFileName($path)
        if ($file -eq '99_background_graphics_buildings.txt') { continue }
        foreach ($block in (Get-ScriptBlocks (Remove-ScriptComments (Read-Text $path)))) {
            $income = [regex]::Match((Get-InnerBlock $block.Body 'province_modifier'), 'monthly_income\s*=\s*(\S+)')
            $buildings[$block.Key] = @{ File=$file; Type=(Get-ScriptField $block.Body 'type') ? (Get-ScriptField $block.Body 'type') : 'regular'; Next=Get-ScriptField $block.Body 'next_building'; Potential=Get-InnerBlock $block.Body 'can_construct_potential'; CanConstruct=Get-InnerBlock $block.Body 'can_construct'; FailuresOnly=Get-InnerBlock $block.Body 'can_construct_showing_failures_only'; LevyToken=Get-ScriptField $block.Body 'levy'; GoldToken=$income.Success ? $income.Groups[1].Value : '' }
        }
    }
    ,$buildings
}
function Get-ProvinceChains($Buildings) {
    $previous = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($b in $Buildings.Values) { if ($b.Next) { [void]$previous.Add($b.Next) } }
    $chains = New-OrdinalMap
    foreach ($key in $Buildings.Keys) {
        if ($previous.Contains($key)) { continue }
        $chain = [Collections.Generic.List[string]]::new(); $chain.Add($key)
        while ($Buildings[$chain[-1]].Next -and $Buildings.Contains($Buildings[$chain[-1]].Next)) {
            $next = $Buildings[$chain[-1]].Next
            if ($chain.Contains($next)) { throw "Building cycle at $next" }
            $chain.Add($next)
        }
        $chains[$key] = $chain.ToArray()
    }
    ,$chains
}
function Get-Requirements($Building) { (@($Building.Potential, $Building.CanConstruct, $Building.FailuresOnly) | Where-Object { $_ -and $_.Trim() }) -join "`n" }
function Get-RegularFamilies($Buildings, $Chains, $Values) {
    foreach ($root in $Chains.Keys) {
        $family = $root -replace '_01$', ''; $building = $Buildings[$root]; $chain = $Chains[$root]
        if ($building.File -notin $script:RegularFiles -or $family -in $script:HoldingMain -or -not $root.EndsWith('_01')) { continue }
        $requirement = Get-Requirements $building
        if (-not $requirement) { continue }
        $top = $Buildings[$chain[-1]]
        @{ Name=$family; Chain=$chain; Requirement=$requirement; Levy=Resolve-BuildingValue $Values $top.LevyToken; Gold=Resolve-BuildingValue $Values $top.GoldToken }
    }
}
function Get-DomicileBuildings([string]$Game) {
    $buildings = New-OrdinalMap
    foreach ($path in (Get-OrdinalSorted @(Get-ChildItem -LiteralPath "$Game/common/domiciles/buildings" -Filter '*.txt' -File | ForEach-Object FullName))) {
        foreach ($block in (Get-ScriptBlocks (Remove-ScriptComments (Read-Text $path)))) {
            $allowed = [regex]::Match($block.Body, 'allowed_domicile_types\s*=\s*\{([^}]*)\}')
            $slot = Get-ScriptField $block.Body 'slot_type'
            $buildings[$block.Key] = @{ Previous=Get-ScriptField $block.Body 'previous_building'; Slot=$slot ? $slot : 'external'; Types=@(($allowed.Success ? $allowed.Groups[1].Value.Trim() : '') -split '\s+' | Where-Object { $_ }); Modifiers=(Get-InnerBlock $block.Body 'character_modifier') + (Get-InnerBlock $block.Body 'province_modifier'); CanConstruct=Get-InnerBlock $block.Body 'can_construct' }
        }
    }
    ,$buildings
}
function Get-SameSlot($Model, [string]$Key) {
    foreach ($next in $Model.Successors[$Key]) { if ($Model.Buildings[$next].Slot -eq $Model.Buildings[$Key].Slot) { $next } }
}
function Get-LinearNext($Model, [string]$Key) {
    $same = @(Get-SameSlot $Model $Key)
    if ($same.Count -eq 1 -and ($same[0] -replace '_\d+$','') -ceq ($Key -replace '_\d+$','')) { $same[0] }
}
function Get-DomicileTrack($Model, [string]$Start) {
    $track = [Collections.Generic.List[string]]::new(); $track.Add($Start)
    while ($next = Get-LinearNext $Model $track[-1]) {
        if ($track.Contains($next)) { throw "Domicile cycle at $next" }
        $track.Add($next)
    }
    $track.ToArray()
}
function Get-DomicileScore($Model, [string]$Start) {
    $modifiers = (@(Get-DomicileTrack $Model $Start) | ForEach-Object { $Model.Buildings[$_].Modifiers }) -join ''
    $army = 0; $resources = 0
    foreach ($match in [regex]::Matches($modifiers, '([a-z_]+)\s*=')) {
        $key = $match.Groups[1].Value
        if ($key -match 'men_at_arms|maa_|knight|levy|garrison|stationed|army_|prowess|advantage|_damage_(mult|add)|_toughness_(mult|add)|_pursuit_|_screen_|_siege_value_|movement_speed|supply') { $army++ }
        if ($key -match 'gold|income|tax|herd|provision|influence|merit|treasury|prestige|piety|renown') { $resources++ }
    }
    @{ Name=$Start; Category=$army ? 0 : ($resources ? 1 : 2); Army=-$army; Resources=-$resources }
}
function Sort-DomicileCandidates($Model, [string[]]$Candidates) {
    # Assign ordinal indices for the final name tiebreaker; Sort-Object's culture must not affect output.
    $order = @{}; $index=0
    foreach ($key in (Get-OrdinalSorted $Candidates)) { $order[$key]=$index; $index++ }
    @($Candidates | ForEach-Object { Get-DomicileScore $Model $_ } | Sort-Object { $_.Category }, { $_.Army }, { $_.Resources }, { $order[$_.Name] } | ForEach-Object { $_.Name })
}
function Get-DomicileModel($Buildings) {
    $model = @{ Buildings=$Buildings; Successors=@{}; RootTracks=[Collections.Generic.List[object]]::new(); Choices=[Collections.Generic.List[object]]::new(); BranchTracks=[Collections.Generic.List[object]]::new(); External=@{}; Internal=@{} }
    foreach ($key in $Buildings.Keys) {
        $previous = $Buildings[$key].Previous
        if ($previous -and $Buildings.Contains($previous)) {
            if (-not $model.Successors.ContainsKey($previous)) { $model.Successors[$previous]=[Collections.Generic.List[string]]::new() }
            $model.Successors[$previous].Add($key)
        }
    }
    $roots = @($Buildings.Keys | Where-Object { $p=$Buildings[$_].Previous; -not $p -or -not $Buildings.Contains($p) -or $Buildings[$p].Slot -ne $Buildings[$_].Slot })
    $branches = @($Buildings.Keys | Where-Object { $same=@(Get-SameSlot $model $_); $same.Count -gt 1 -or ($same.Count -eq 1 -and -not (Get-LinearNext $model $_)) })
    $order=@{main=0;external=1;internal=2}; $indices=@{}; $i=0
    foreach ($key in (Get-OrdinalSorted $roots)) { $indices[$key]=$i; $i++ }
    foreach ($key in ($roots | Sort-Object { $slot=$Buildings[$_].Slot; $order.ContainsKey($slot) ? $order[$slot] : 3 }, { $indices[$_] })) {
        $track=@(Get-DomicileTrack $model $key); if ($track.Count -gt 1) { $model.RootTracks.Add($track) }
    }
    $specializations=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($node in (Get-OrdinalSorted $branches)) {
        $candidates=@(Sort-DomicileCandidates $model @(Get-SameSlot $model $node))
        $model.Choices.Add(@{ Node=$node; Candidates=$candidates })
        foreach ($key in $candidates) { [void]$specializations.Add($key) }
    }
    foreach ($key in (Get-OrdinalSorted @($specializations))) { $track=@(Get-DomicileTrack $model $key); if ($track.Count -gt 1) { $model.BranchTracks.Add($track) } }
    foreach ($root in $roots) {
        $b=$Buildings[$root]; $p=$b.Previous
        if ($b.Slot -eq 'external' -and (-not $p -or -not $Buildings.Contains($p))) {
            foreach ($type in $b.Types) {
                if (-not $model.External.ContainsKey($type)) { $model.External[$type]=[Collections.Generic.List[string]]::new() }
                $model.External[$type].Add($root)
            }
        } elseif ($b.Slot -eq 'internal' -and $p -and $Buildings.Contains($p)) {
            if (-not $model.Internal.ContainsKey($p)) { $model.Internal[$p]=[Collections.Generic.List[string]]::new() }
            $model.Internal[$p].Add($root)
        }
    }
    foreach ($group in @($model.External, $model.Internal)) { foreach ($key in @($group.Keys)) { $group[$key]=@(Sort-DomicileCandidates $model @($group[$key])) } }
    $model
}
function Write-BuildingEffects([string]$Game, [string]$Output) {
    $version='unknown'; $settings=Join-Path (Split-Path $Game -Parent) 'launcher/launcher-settings.json'
    if (Test-Path -LiteralPath $settings) { $m=[regex]::Match((Read-Text $settings), '"rawVersion":\s*"([^"]+)"'); if ($m.Success) { $version=$m.Groups[1].Value } }
    $buildings=Get-ProvinceBuildings $Game; $chains=Get-ProvinceChains $buildings
    $families=@(Get-RegularFamilies $buildings $chains (Get-BuildingValues $Game))
    $forts=@(foreach ($name in $script:Fortifications) { $families | Where-Object { $_.Name -ceq $name } })
    $others=@($families | Where-Object { $_.Name -notin $script:Fortifications })
    $indices=@{}; $i=0; foreach ($key in (Get-OrdinalSorted @($others | ForEach-Object { $_.Name }))) { $indices[$key]=$i; $i++ }
    $ranked=@($forts) + @($others | Where-Object { $_.Levy -gt 0 -or $_.Gold -gt 0 } | Sort-Object { -$_.Levy }, { -$_.Gold }, { $indices[$_.Name] })
    $dropped=@($others | Where-Object { $_.Levy -le 0 -and $_.Gold -le 0 } | Sort-Object { $indices[$_.Name] })
    $out=[Collections.Generic.List[string]]::new()
    function Emit([string[]]$Lines) { $out.AddRange($Lines) }
    Emit @('# GENERATED FILE, DO NOT EDIT BY HAND.', "# Built from the game files of CK3 $version by tools/generate_building_effects.ps1.", '# Run the script again after a game update to pick up new buildings.', '', '# Priority used by mqa_b_priority_fill_province_effect (yields at maximum level,', '# before culture, terrain and holding bonuses):', '#   rank  building                levies  gold/month')
    $rank=1
    foreach ($family in $ranked) { $out.Add([string]::Format([Globalization.CultureInfo]::InvariantCulture, '#   {0,4}  {1,-22}{2,8:F0}{3,12:F2}', $rank, $family.Name, $family.Levy, $family.Gold)); $rank++ }
    Emit @(('#   never built, replaced first: ' + (($dropped | ForEach-Object { $_.Name }) -join ', ')), '')
    Emit @('# Province scope, scope:holder must be the holder of the barony.', '# Upgrades every existing building straight to the highest level whose own', '# requirements are met, as when building it by hand, holding main buildings first', '# (other buildings need their level).', 'mqa_b_upgrade_province_buildings_effect = {')
    $indices=@{}; $i=0; foreach ($key in (Get-OrdinalSorted @($chains.Keys))) { $indices[$key]=$i; $i++ }
    $upgradable=0
    foreach ($root in ($chains.Keys | Sort-Object { ($_ -replace '_01$','') -notin $script:HoldingMain }, { $indices[$_] })) {
        $chain=$chains[$root]
        if ($chain.Count -lt 2 -or $buildings[$root].File -in $script:NotUpgraded) { continue }
        $upgradable++
        for ($index=$chain.Count-1; $index -ge 1; $index--) {
            $keyword=($index -eq $chain.Count-1) ? 'if' : 'else_if'
            Emit @("`t$keyword = {", "`t`tlimit = {", "`t`t`tOR = {")
            for ($j=0; $j -lt $index; $j++) { $out.Add("`t`t`t`thas_building = $($chain[$j])") }
            Emit @("`t`t`t}")
            Emit @(Format-ScriptIndent (Get-Requirements $buildings[$chain[$index]]) 3)
            $place=$buildings[$chain[$index]].Type -eq 'regular' ? 'add_building' : 'replace_building_effect'
            Emit @("`t`t}", "`t`t$place = $($chain[$index])", "`t}")
        }
    }
    Emit @('}', '', '# Province scope. Remove a regular building, whatever its level.')
    foreach ($family in ($ranked + $dropped)) {
        $out.Add("mqa_b_remove_$($family.Name)_effect = {")
        foreach ($level in $family.Chain) { Emit @("`tif = {", "`t`tlimit = { has_building = $level }", "`t`tremove_building = $level", "`t}") }
        $out.Add('}')
    }
    Emit @('', '# Province scope, scope:holder must be the holder of the barony.', '# Goes down the priority list. Each missing building the holder could build here', "# by hand (all of its first level's requirements, copied from the game) is built", '# in a free slot, straight at the highest level whose requirements are met; when no', '# slot is free, the worst-ranked building below it is removed to make room. No slot', '# is ever added.', 'mqa_b_priority_fill_province_effect = {')
    for ($rank=0; $rank -lt $ranked.Count; $rank++) {
        $family=$ranked[$rank]; $victims=@($dropped)
        for ($j=$ranked.Count-1; $j -gt $rank; $j--) { $victims+=,$ranked[$j] }
        Emit @("`tif = {", "`t`tlimit = {", "`t`t`tNOT = { has_building_or_higher = $($family.Chain[0]) }")
        Emit @(Format-ScriptIndent $family.Requirement 3); Emit @("`t`t}")
        if ($victims.Count) {
            Emit @("`t`tif = {", "`t`t`tlimit = { free_building_slots < 1 }")
            for ($i=0; $i -lt $victims.Count; $i++) {
                $v=$victims[$i]; $keyword=$i -eq 0 ? 'if' : 'else_if'
                Emit @("`t`t`t$keyword = {", "`t`t`t`tlimit = { has_building_or_higher = $($v.Chain[0]) }", "`t`t`t`tmqa_b_remove_$($v.Name)_effect = yes", "`t`t`t}")
            }
            Emit @("`t`t}")
        }
        $chain=$family.Chain; Emit @("`t`tif = {", "`t`t`tlimit = { free_building_slots > 0 }")
        for ($i=$chain.Count-1; $i -ge 1; $i--) {
            $keyword=$i -eq $chain.Count-1 ? 'if' : 'else_if'
            Emit @("`t`t`t$keyword = {", "`t`t`t`tlimit = {")
            Emit @(Format-ScriptIndent (Get-Requirements $buildings[$chain[$i]]) 5)
            Emit @("`t`t`t`t}", "`t`t`t`tadd_building = $($chain[$i])", "`t`t`t}")
        }
        if ($chain.Count -gt 1) { Emit @("`t`t`telse = {", "`t`t`t`tadd_building = $($chain[0])", "`t`t`t}") } else { Emit @("`t`t`tadd_building = $($chain[0])") }
        Emit @("`t`t}", "`t}")
    }
    Emit @('}', '')
    $model=Get-DomicileModel (Get-DomicileBuildings $Game)
    function Attempt([string[]]$Conditions, [string]$Building, [int]$Indent, [string]$Keyword='if') {
        $tab="`t" * $Indent
        Emit @("$tab$Keyword = {", "$tab`tlimit = {", "$tab`t`tdomicile ?= {")
        foreach ($condition in $Conditions) { Emit @("$tab`t`t`t$condition") }
        Emit @("$tab`t`t}")
        Emit @(Format-ScriptIndent $model.Buildings[$Building].CanConstruct ($Indent+2))
        Emit @("$tab`t}", "$tab`tdomicile = { add_domicile_building = $Building }", "$tab}")
    }
    Emit @("# Character scope (the domicile owner). Cancels the domicile's ongoing construction, with", "# the game's own refund, so that its slot can be filled and upgraded right away.", 'mqa_b_cancel_domicile_construction_effect = {', "`tif = {", "`t`tlimit = { domicile ?= { has_ongoing_domicile_construction = yes } }", "`t`tdomicile = {")
    foreach ($building in (Get-OrdinalSorted @($model.Buildings.Keys))) { Emit @("`t`t`tif = {", "`t`t`t`tlimit = { has_domicile_construction = $building }", "`t`t`t`tremove_domicile_building = $building", "`t`t`t}") }
    Emit @("`t`t}", "`t}", '}', '', '# Character scope (the domicile owner). Builds missing buildings in free slots, by priority:', '# buildings with army bonuses first, then gold and resources, then the rest. External', "# buildings go in the domicile's external slots, internal ones in the internal slots of their", '# parent building. Each building is only attempted when the character meets its own', '# can_construct, copied from the game.', 'mqa_b_construct_domicile_effect = {')
    foreach ($type in (Get-OrdinalSorted @($model.External.Keys))) {
        Emit @("`tif = {", "`t`tlimit = { domicile ?= { is_domicile_type = $type } }")
        foreach ($root in $model.External[$type]) { Attempt @('free_external_domicile_building_slots >= 1', "NOT = { has_domicile_building_or_higher = $root }") $root 2 }
        Emit @("`t}")
    }
    foreach ($parent in (Get-OrdinalSorted @($model.Internal.Keys))) {
        foreach ($root in $model.Internal[$parent]) { Attempt @("has_domicile_building_or_higher = $parent", "domicile_building_has_free_internal_slot = $parent", "NOT = { has_domicile_building_or_higher = $root }") $root 1 }
    }
    Emit @('}', '', '# Character scope (the domicile owner). Upgrades every domicile building one level at a', "# time, main building first, when the character meets the next level's can_construct.", '# Where a building can specialize, the best allowed specialization is picked by the same', '# priority, then upgraded in turn.', 'mqa_b_upgrade_domicile_effect = {')
    foreach ($track in $model.RootTracks) { for ($i=0; $i -lt $track.Count-1; $i++) { Attempt @("has_domicile_building = $($track[$i])") $track[$i+1] 1 } }
    foreach ($choice in $model.Choices) { for ($i=0; $i -lt $choice.Candidates.Count; $i++) { Attempt @("has_domicile_building = $($choice.Node)") $choice.Candidates[$i] 1 ($i -eq 0 ? 'if' : 'else_if') } }
    foreach ($track in $model.BranchTracks) { for ($i=0; $i -lt $track.Count-1; $i++) { Attempt @("has_domicile_building = $($track[$i])") $track[$i+1] 1 } }
    Emit @('}', '')
    Write-Text $Output ($out -join "`n") -Bom
    Write-Host "CK3 ${version}: $upgradable upgradable building chains, $($ranked.Count) ranked and $($dropped.Count) dropped building families, $($model.RootTracks.Count + $model.BranchTracks.Count) domicile tracks -> $Output"
    $rank=1; foreach ($family in $ranked) { Write-Host ([string]::Format([Globalization.CultureInfo]::InvariantCulture, '  {0,3}. {1,-22} levies {2,5:F0}  gold {3:F2}', $rank, $family.Name, $family.Levy, $family.Gold)); $rank++ }
    Write-Host ('  dropped: ' + (($dropped | ForEach-Object { $_.Name }) -join ', '))
}
if ($MyInvocation.InvocationName -ne '.') { Write-BuildingEffects ($GamePath ? $GamePath : $script:DefaultGame) $OutputPath }
