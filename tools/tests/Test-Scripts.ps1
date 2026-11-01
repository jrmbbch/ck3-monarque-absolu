#!/usr/bin/env pwsh
#Requires -Version 7.4
# Self-contained offline regression suite; no Pester install or network is required.
param([string]$GamePath, [switch]$TestInstalledGame)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../publish_release.ps1"
. "$PSScriptRoot/../generate_building_effects.ps1"
. "$PSScriptRoot/../generate_holding_requirements.ps1"
. "$PSScriptRoot/../generate_epidemic_fix.ps1"
. "$PSScriptRoot/../generate_mandala_completion_fix.ps1"
. "$PSScriptRoot/../generate_lifestyle_effects.ps1"
. "$PSScriptRoot/../build_release.ps1"
$repository=$script:RepoRoot
$script:Passed=0
function Assert-True($Condition, [string]$Message='Assertion failed') { if (-not $Condition) { throw $Message } }
function Assert-Equal($Actual, $Expected) { if ($Actual -cne $Expected) { throw "Expected '$Expected', got '$Actual'" } }
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    $caught=$false
    try { & $Action } catch { $caught=$true; if ($_.Exception.Message -notmatch $Pattern) { throw "Unexpected error: $($_.Exception.Message)" } }
    if (-not $caught) { throw "Expected an error matching $Pattern" }
}
function Test-Case([string]$Name, [scriptblock]$Action) {
    $root=$script:RepoRoot
    try { & $Action; $script:Passed++; Write-Host "PASS $Name" }
    finally { $script:RepoRoot=$root }
}
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('mqa-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporary) > $null
try {
    Test-Case 'Localization accepts all nine languages' { Test-Localization "$repository/localization" }
    Test-Case 'Release notes match semantic version' {
        $info=Get-ReleaseInfo
        Assert-True $info.Notes.StartsWith($info.Version + "`n")
        Assert-Equal $info.Name 'Monarque Absolu - Absolute Monarch'
    }
    Test-Case 'Staging includes only game files and preserves BOM' {
        $target=Join-Path $temporary 'stage'; New-ReleaseStage $target
        Assert-Equal ((Get-ChildItem $target | Sort-Object Name | ForEach-Object Name) -join ',') 'common,descriptor.mod,events,localization,thumbnail.png'
        $bytes=[IO.File]::ReadAllBytes("$target/localization/french/monarque_absolu_l_french.yml")
        Assert-Equal ([Convert]::ToHexString($bytes[0..2])) 'EFBBBF'
    }
    Test-Case 'Symlinks rejected before staging' {
        $fixture=Join-Path $temporary 'links'; [IO.Directory]::CreateDirectory($fixture) > $null
        Copy-Item "$repository/localization" $fixture -Recurse
        foreach ($name in @('common','events')) { [IO.Directory]::CreateDirectory("$fixture/$name") > $null }
        [IO.File]::CreateSymbolicLink("$fixture/common/external", "$repository/README.md") > $null
        $script:RepoRoot=$fixture
        Assert-Throws { New-ReleaseStage "$fixture/output" } 'Symlink'
        Assert-True (-not (Test-Path "$fixture/output"))
    }
    Test-Case 'Bad localization detects BOM, quotes and missing keys' {
        $fixture=Join-Path $temporary 'bad-localization'; Copy-Item "$repository/localization" $fixture -Recurse
        Write-Text "$fixture/french/monarque_absolu_l_french.yml" "l_french:`n broken:0 `"unclosed`n"
        Assert-Throws { Test-Localization $fixture 6>$null } 'validation failed'
    }
    Test-Case 'Build preserves Workshop ID and launcher entry and copies only mod data' {
        $target=Join-Path $temporary 'installed'; [IO.Directory]::CreateDirectory("$target/monarque_absolu") > $null
        Write-Text "$target/monarque_absolu/descriptor.mod" "remote_file_id=`"3813333986`"`n"
        Build-Release $target
        Assert-True ((Read-Text "$target/monarque_absolu.mod").Contains('remote_file_id="3813333986"'))
        Assert-True ((Read-Text "$target/monarque_absolu.mod").Contains("path=`"$target/monarque_absolu`""))
        Assert-True (-not (Test-Path "$target/monarque_absolu/tools"))
    }
    Test-Case 'Paradox notes must belong to latest version' {
        $detail=@{latestVersion=6;changelog=@(@{modVersion=5;details="1.0.5`nnotes"})}
        Assert-True (-not (Test-ParadoxNotes $detail "1.0.5`nnotes"))
        $detail.changelog+=@{modVersion=6;details="1.0.5`nnotes`n"}
        Assert-True (Test-ParadoxNotes $detail "1.0.5`nnotes")
    }
    Test-Case 'Session AES-CBC roundtrip and invalid padding' {
        $key='01' * 32; $iv=[byte[]](0..15); $data=[Text.Encoding]::UTF8.GetBytes('{"refresh_token":"test-token"}')
        $cipher=Convert-SessionCipher $data $key $iv
        Assert-Equal ([Text.Encoding]::UTF8.GetString((Convert-SessionCipher $cipher $key $iv -Decrypt))) ([Text.Encoding]::UTF8.GetString($data))
        Assert-Throws { Convert-SessionCipher ([byte[]](1,2,3)) $key $iv -Decrypt } '.'
    }
    Test-Case 'Paradox publication verification handles delayed metadata and uncertain status without re-upload' {
        $result=Invoke-Tool 'pwsh' @('-NoProfile','-File',"$repository/tools/tests/Test-ParadoxPublication.ps1")
        Assert-True ($result.Output.Contains('Paradox publication checks passed. No network requests performed.'))
    }
    Test-Case 'ASAR storage format is read without executing launcher code' {
        $root=Join-Path $temporary 'asar'; $folder="$root/launcher-v2.2026.13/Paradox Launcher.app/Contents/Resources"
        [IO.Directory]::CreateDirectory($folder) > $null
        [IO.Directory]::CreateDirectory("$root/launcher-v2") > $null
        $source='x="session.js",y="' + ('AB' * 32) + '"; aes-256-cbc'
        $header=@{files=@{dist=@{files=@{main=@{files=@{'index.mjs'=@{offset='0';size=$source.Length}}}}}}} | ConvertTo-Json -Depth 20 -Compress
        $json=[Text.Encoding]::UTF8.GetBytes($header)
        $writer=[IO.BinaryWriter]::new([IO.File]::Create("$folder/app.asar"))
        try { $writer.Write([uint32]4);$writer.Write([uint32]($json.Length+8));$writer.Write([uint32]($json.Length+4));$writer.Write([uint32]$json.Length);$writer.Write($json);$writer.Write([Text.Encoding]::UTF8.GetBytes($source)) } finally { $writer.Dispose() }
        Assert-Equal (Get-LauncherStorageKey $root) ('AB' * 32)
    }
    Test-Case 'Native Steam interop compiles with correct callback sizes' {
        Initialize-SteamTypes
        Assert-Equal ([Runtime.InteropServices.Marshal]::SizeOf([type][MonarqueAbsolu.CallbackMessage])) 24
        Assert-Equal ([Runtime.InteropServices.Marshal]::SizeOf([type][MonarqueAbsolu.CallCompleted])) 16
    }
    Test-Case 'Steam rejects server failure and required agreement' {
        Assert-Throws { Confirm-SteamResult ([byte[]](15,0,0,0,0,0,0,0)) } 'EResult=15'
        Assert-Throws { Confirm-SteamResult ([byte[]](1,0,0,0,1,0,0,0)) } 'Workshop agreement'
        Assert-Throws { Confirm-SteamResult ([byte[]](1,0)) } 'callback size'
        Confirm-SteamResult ([byte[]](1,0,0,0,0,0,0,0))
    }
    Test-Case 'GitHub rejects moved tags and edited release notes' {
        Assert-Throws { Confirm-GitHubTag @{'refs/tags/v1.2.3^{}'='wrong'} 'v1.2.3' 'right' } 'refusing to move'
        Assert-Equal (Confirm-GitHubTag @{'refs/tags/v1.2.3'='right'} 'v1.2.3' 'right') 'right'
        Assert-Throws { Confirm-GitHubRelease @{tag_name='v1.2.3';body='wrong'} 'v1.2.3' 'notes' } 'refusing to overwrite'
        Assert-Throws { Confirm-GitHubRelease @{tag_name='v1.2.3';body='notes';draft=$true} 'v1.2.3' 'notes' } 'refusing to overwrite'
    }
    Test-Case 'GitHub auth failure is not mistaken for missing release' {
        function Invoke-Tool { @{Code=1;Error='HTTP 401 unauthorized';Output=''} }
        Assert-Throws { Get-GitHubRelease 'v1.2.3' } 'Cannot inspect'
    }
    # GitHub orchestration mocks are scoped to each test; no global command replacement.
    $info=@{Version='1.2.3';Notes="1.2.3`nnotes"}; $sha='a'*40
    $release=@{tag_name='v1.2.3';body=$info.Notes;draft=$false;prerelease=$false}
    Test-Case 'GitHub new tag is annotated and release uses notes file' {
        $calls=[Collections.Generic.List[object]]::new(); $reads=0
        function Invoke-Tool($File,$Arguments,[switch]$AllowFailure) {
            $calls.Add(@{File=$File;Args=$Arguments}); $output='';$code=0
            switch ($Arguments -join ' ') {
                'remote get-url origin' { $output="https://github.com/$script:GitHubRepository.git" }
                'rev-parse HEAD' { $output=$sha }
                'rev-parse --verify refs/tags/v1.2.3^{commit}' { $code=128 }
            }
            @{Code=$code;Output=$output;Error=''}
        }
        function Get-RemoteRefs { if ($calls | Where-Object { $_.Args[0] -eq 'push' }) { @{'refs/heads/main'=$sha;'refs/tags/v1.2.3^{}'=$sha} } else { @{'refs/heads/main'=$sha} } }
        function Get-GitHubRelease { if ($calls | Where-Object { $_.Args[0] -eq 'release' }) { $release } }
        Publish-GitHub $info
        Assert-True ([bool]($calls | Where-Object { ($_.Args -join ' ') -eq "tag -a v1.2.3 $sha -m Release 1.2.3" }))
        Assert-True ([bool]($calls | Where-Object { $_.Args -contains '--verify-tag' -and $_.Args -contains '--notes-file' }))
    }
    Test-Case 'GitHub reuses exact published release without mutation' {
        $calls=[Collections.Generic.List[string]]::new()
        function Invoke-Tool($File,$Arguments,[switch]$AllowFailure) {
            $calls.Add($Arguments -join ' ')
            $output=switch ($Arguments -join ' ') { 'remote get-url origin' { "https://github.com/$script:GitHubRepository.git" };'rev-parse HEAD' { $sha };'rev-parse --verify refs/tags/v1.2.3^{commit}' { $sha };default { '' } }
            @{Code=0;Output=[string]$output;Error=''}
        }
        function Get-RemoteRefs { @{'refs/heads/main'=$sha;'refs/tags/v1.2.3^{}'=$sha} }
        function Get-GitHubRelease { $release }
        Publish-GitHub $info
        Assert-True (-not ($calls | Where-Object { $_ -match '^(tag|push|release create) ' }))
    }
    Test-Case 'GitHub resumes after tag was pushed but release is absent' {
        $calls=[Collections.Generic.List[string]]::new()
        function Invoke-Tool($File,$Arguments,[switch]$AllowFailure) {
            $calls.Add($Arguments -join ' ')
            $output=switch ($Arguments -join ' ') { 'remote get-url origin' { "https://github.com/$script:GitHubRepository.git" };'rev-parse HEAD' { $sha };'rev-parse --verify refs/tags/v1.2.3^{commit}' { $sha };default { '' } }
            @{Code=0;Output=[string]$output;Error=''}
        }
        function Get-RemoteRefs { @{'refs/heads/main'=$sha;'refs/tags/v1.2.3^{}'=$sha} }
        function Get-GitHubRelease { if ($calls | Where-Object { $_ -like 'release create*' }) { $release } }
        Publish-GitHub $info
        Assert-True (-not ($calls | Where-Object { $_ -match '^(tag|push) ' }))
        Assert-True ([bool]($calls | Where-Object { $_ -like 'release create*' }))
    }
    Test-Case 'GitHub stops on dirty worktree before network' {
        function Invoke-Tool { @{Code=0;Output=' M descriptor.mod';Error=''} }
        function Get-RemoteRefs { throw 'Network must not be called' }
        Assert-Throws { Publish-GitHub $info } 'clean working tree'
    }
    Test-Case 'GitHub rejects unpushed commits' {
        function Invoke-Tool($File,$Arguments) { @{Code=0;Output=($Arguments[0] -eq 'remote' ? "https://github.com/$script:GitHubRepository.git" : ($Arguments[0] -eq 'status' ? '' : $sha));Error=''} }
        function Get-RemoteRefs { @{'refs/heads/main'='other'} }
        Assert-Throws { Publish-GitHub $info } 'push the release commit'
    }
    Test-Case 'GitHub failure prevents Steam and Paradox publication' {
        function New-ReleaseStage($Destination) { [IO.Directory]::CreateDirectory($Destination) > $null }
        function Publish-GitHub { throw 'GitHub failed' }
        function Publish-Steam { throw 'Steam must not be called' }
        function Publish-Paradox { throw 'Paradox must not be called' }
        Assert-Throws { Invoke-ReleasePublication all $true '' } 'GitHub failed'
    }
    Test-Case 'Dry run performs no authentication or publication' {
        function Publish-GitHub { throw 'Unexpected GitHub request' }
        function Publish-Steam { throw 'Unexpected Steam request' }
        function Publish-Paradox { throw 'Unexpected Paradox request' }
        Invoke-ReleasePublication all $false ''
    }
    Test-Case 'Script parser preserves nested blocks and numeric constants' {
        $blocks=@(Get-ScriptBlocks "first = {`n`tinner = { a = 1 }`n}`nsecond = { value = 2 }")
        Assert-Equal $blocks.Count 2
        Assert-Equal (Get-InnerBlock $blocks[0].Body 'inner').Trim() 'a = 1'
        $values=@{Constants=@{base='4';complex='@[ base * 2 + 1 ]'};Values=@{yield='@complex'}}
        Assert-Equal (Resolve-BuildingValue $values 'yield') 9
        Assert-Equal (Resolve-BuildingValue $values '@missing') 0
        Assert-Equal (Invoke-NumericExpression '-2**2 + 2**3**2') 508
        Assert-Equal (Invoke-NumericExpression '-7//3') -3
        Assert-Equal (Invoke-NumericExpression '-7%3') 2
        Assert-Throws { Invoke-NumericExpression '[IO.File]::Delete(1)' } 'Invalid arithmetic'
    }
    Test-Case 'Domicile choices prioritize army and preserve level order' {
        $buildings=New-OrdinalMap
        $buildings['base_01']=@{Previous='';Slot='external';Types=@('camp');Modifiers='';CanConstruct=''}
        $buildings['base_02']=@{Previous='base_01';Slot='external';Types=@();Modifiers='';CanConstruct=''}
        $buildings['gold_01']=@{Previous='base_02';Slot='external';Types=@();Modifiers='monthly_income = 1';CanConstruct=''}
        $buildings['army_01']=@{Previous='base_02';Slot='external';Types=@();Modifiers='levy = 100';CanConstruct=''}
        $model=Get-DomicileModel $buildings
        Assert-Equal ($model.RootTracks[0] -join ',') 'base_01,base_02'
        Assert-Equal ($model.Choices[0].Candidates -join ',') 'army_01,gold_01'
    }
    Test-Case 'Both generators match golden files from the original Python implementation' {
        foreach ($kind in @('building','lifestyle')) {
            $output=Join-Path $temporary "$kind-fixture.txt"
            if ($kind -eq 'building') { Write-BuildingEffects "$PSScriptRoot/fixtures/game" $output } else { Write-LifestyleEffects "$PSScriptRoot/fixtures/game" $output }
            $actual=[IO.File]::ReadAllBytes($output)
            $expected=[IO.File]::ReadAllBytes("$PSScriptRoot/fixtures/expected_${kind}_effects.txt")
            Assert-True ([Linq.Enumerable]::SequenceEqual[byte]($actual,$expected)) "$kind generator differs from its golden file"
        }
    }
    Test-Case 'Every domain traversal branch and holding foundation exclude active construction' {
        $source=Remove-ScriptComments (Read-Text "$repository/common/scripted_effects/mqa_building_scope_effects.txt")
        $blocks=@{}; foreach ($b in (Get-ScriptBlocks $source)) { $blocks[$b.Key]=$b.Body }
        $walk=$blocks.mqa_b_every_domain_holding_effect
        Assert-Equal ([regex]::Matches($walk,'has_ongoing_construction = no').Count) 2
        Assert-True ($walk -match '(?s)tier = tier_barony.*?title_province = \{\s*has_holding = yes\s*exists = barony.holder\s*has_ongoing_construction = no')
        Assert-True ($blocks.mqa_b_run_in_holding_effect -match '(?s)if = \{\s*limit = \{\s*has_ongoing_construction = no\s*exists = barony.holder\s*\}.*?\$EFFECT\$ = yes')
        Assert-True ($blocks.mqa_b_found_domain_holdings_effect -match 'has_holding = no\s*has_ongoing_construction = no')
        Assert-True ($blocks.mqa_b_feudalize_domain_holdings_effect -match 'has_ongoing_construction = no')
    }
    Test-Case 'Foundation chooses the missing temple then city before castles and checks each prerequisite' {
        $blocks=@{}; foreach ($block in Get-ScriptBlocks (Remove-ScriptComments (Read-Text "$repository/common/scripted_effects/mqa_building_scope_effects.txt"))) { $blocks[$block.Key]=$block.Body }
        $foundation=$blocks.mqa_b_found_domain_holdings_effect
        Assert-True ($foundation -match 'has_holding = no\s*has_ongoing_construction = no\s*barony_cannot_construct_holding = no\s*is_county_capital = no')
        Assert-True ($foundation -match '(?s)NOT = \{\s*scope:mqa_county = \{\s*mqa_b_county_has_required_temple_trigger = yes.*?mqa_b_can_found_temple_citadel_trigger = yes.*?TYPE = temple_citadel_holding.*?mqa_b_can_found_temple_trigger = yes.*?TYPE = church_holding.*?else_if.*?NOT = \{\s*scope:mqa_county = \{\s*any_county_province = \{ has_holding_type = city_holding \}.*?mqa_b_can_found_city_trigger = yes.*?TYPE = city_holding.*?else_if.*?mqa_b_can_found_castle_trigger = yes.*?TYPE = castle_holding')
        Assert-Equal ([regex]::Matches($foundation,'mqa_b_found_holding_effect =').Count) 4
        Assert-True ($foundation -match '(?s)scope:mqa_b_founder = \{ save_scope_as = holder \}.*?government_has_flag = government_is_mandala')
        Assert-True ($blocks.mqa_b_found_holding_effect -match 'set_holding_type = \$TYPE\$.*\n\s*mqa_b_trace_change_effect')
        Assert-True ($blocks.mqa_b_found_holding_effect -notmatch 'grant|create_character|resolve_title')
    }
    Test-Case 'Mandala requires a temple-citadel while other rulers require a church holding' {
        $source=Remove-ScriptComments (Read-Text "$repository/common/scripted_triggers/mqa_building_triggers.txt")
        Assert-True ($source -match '(?s)trigger_if = \{\s*limit = \{ holder = \{ government_has_flag = government_is_mandala \} \}\s*any_county_province = \{ has_holding_type = temple_citadel_holding \}\s*\}\s*trigger_else = \{\s*any_county_province = \{ has_holding_type = church_holding \}')
        $requirements=Read-Text "$repository/common/scripted_triggers/mqa_holding_requirements_triggers.txt"
        $blocks=@{}; foreach($block in Get-ScriptBlocks $requirements) { $blocks[$block.Key]=$block.Body }
        Assert-True ($blocks.mqa_b_can_found_temple_trigger -match 'NOT = \{ government_has_flag = government_is_mandala \}')
        Assert-True ($blocks.mqa_b_can_found_temple_citadel_trigger -match 'scope:holder = \{ government_has_flag = government_is_mandala \}')
    }
    Test-Case 'Existing personal holdings share one protected grant transaction with new and converted holdings' {
        $blocks=@{}; foreach ($block in Get-ScriptBlocks (Remove-ScriptComments (Read-Text "$repository/common/scripted_effects/mqa_building_scope_effects.txt"))) { $blocks[$block.Key]=$block.Body }
        $grant=$blocks.mqa_b_queue_holding_grant_effect
        $batch=$blocks.mqa_b_grant_personal_baronies_effect
        $protection=Read-Text "$repository/common/scripted_triggers/mqa_building_triggers.txt"
        Assert-True ($protection -match '(?s)mqa_b_can_grant_holding_trigger = \{\s*has_holding = yes\s*is_county_capital = no\s*has_ongoing_construction = no')
        Assert-True ($protection -match 'holder = scope:mqa_b_founder\s*is_leased_out = no')
        Assert-True ($protection -match '(?s)NOT = \{\s*AND = \{\s*has_holding_type = church_holding.*?rite_has_parameter = theocracy_temple_lease')
        foreach($type in @('castle','city','church','temple_citadel')) { Assert-True ($protection.Contains("has_holding_type = ${type}_holding")) }
        foreach ($identity in @('culture','faith','rite')) { Assert-True ($grant.Contains("$identity = scope:mqa_b_founder.$identity")) }
        Assert-True ($grant -match 'dynasty = generate\s*random_traits = yes')
        Assert-True ($grant -match '(?s)barony = \{\s*change_title_holder = \{\s*holder = scope:mqa_b_new_baron')
        Assert-True ($grant -match '(?s)change_liege = \{\s*liege = scope:mqa_b_founder')
        Assert-True ($grant -notmatch 'resolve_title_and_vassal_change|create_title_and_vassal_change')
        Assert-Equal ([regex]::Matches($batch,'create_title_and_vassal_change =').Count) 1
        Assert-Equal ([regex]::Matches($batch,'resolve_title_and_vassal_change =').Count) 1
        Assert-True ($batch -match '(?s)every_held_title = .*?add_to_list = mqa_b_grant_titles.*?limit = \{ var:mqa_b_grant_candidates > 0 \}.*?create_title_and_vassal_change.*?list = mqa_b_grant_titles.*?mqa_b_queue_holding_grant_effect.*?resolve_title_and_vassal_change.*?list = mqa_b_new_grantees.*?var:mqa_b_expected_title = \{ holder = prev \}.*?liege = scope:mqa_b_founder.*?COUNTER = mqa_b_granted.*?COUNTER = mqa_b_grant_failed.*?remove_variable = mqa_b_expected_title')
        Assert-True ($batch -notmatch 'has_variable = mqa_b_founded|has_variable = mqa_b_feudalized')
        Assert-True ($blocks.mqa_b_feudalize_domain_holdings_effect -notmatch 'grant|create_character|resolve_title')
        Assert-True ($blocks.mqa_b_every_domain_holding_effect -notmatch 'grant|create_character|change_title_holder')
        $event=Read-Text "$repository/events/mqa_building_events.txt"
        Assert-True ($event -match '(?s)MQA_BUILD BEGIN grants.*?grants prepare_grants.*?mqa_b_grant_personal_baronies_effect = yes.*?MQA_BUILD END grants')
        $trace=Read-Text "$repository/common/scripted_effects/mqa_building_diagnostics_effects.txt"
        Assert-True ($trace.Contains('set_variable = { name = mqa_b_granted value = 0 }'))
        Assert-True ($trace.Contains('set_variable = { name = mqa_b_grant_candidates value = 0 }'))
    }
    Test-Case 'Expired-epidemic fix guards the whole county loop and preserves other event behavior' {
        $fixture=@'
epidemic_events.1110 = {
	type = character_event
	option = {
		name = epidemic_events.1110.a
		add_gold = 10
	}
	option = {
		name = epidemic_events.1110.b
		add_prestige = medium_prestige_gain
		every_sub_realm_county = {
			custom = every_infected_county
			limit = {
				any_county_province = { any_province_epidemic = { this = scope:epidemic_scope } }
			}
			add_county_modifier = { modifier = ce1_bodies_in_the_street years = 15 }
		}
		ai_chance = { base = 100 }
	}
}
'@
        $patch=Get-EpidemicEventPatch $fixture
        Assert-True ($patch.GuardedLoop -match '^\t\tif = \{\n\t\t\tlimit = \{ exists = scope:epidemic_scope \}\n\t\t\tevery_sub_realm_county')
        Assert-Equal ($patch.Patched.Replace($patch.GuardedLoop,'LOOP').Replace($patch.PriorityInsertion,'')) ($patch.Original.Replace($patch.OriginalLoop,'LOOP'))
        Assert-Equal ([regex]::Matches($patch.Patched,'(?m)^\tid_override_priority = 1$').Count) 1
        Assert-Equal ([regex]::Matches($patch.Patched,'exists = scope:epidemic_scope').Count) 1
        Assert-True ($patch.Patched.Contains('ai_chance = { base = 100 }'))
        Assert-Throws { Get-EpidemicEventPatch ($fixture.Replace('custom = every_infected_county','custom = changed_by_game_update')) } 'review the vanilla update'
        Assert-Throws { Get-EpidemicEventPatch ($fixture.Replace('type = character_event','id_override_priority = 2')) } 'review the vanilla update'
        $output=Read-Text "$repository/events/zz_mqa_epidemic_events.txt"
        Assert-Equal (@(Get-ScriptBlocks $output).Count) 1
        Assert-True ($output -match '(?s)name = epidemic_events.1110.b.*?if = \{\s*limit = \{ exists = scope:epidemic_scope \}\s*every_sub_realm_county =')
        Assert-True ($output -match '(?m)^\tid_override_priority = 1$')
    }
    Test-Case 'Mandala callback repair preserves native effects and only supplies a missing payer' {
        $fixture=@'
castle_03 = {
	levy = 100
	on_complete = {
		barony.holder = { add_prestige = 10 }
		scope:character = {
			# Native reward must remain exactly once, with its original conditions.
			creator_mandala_upgraded_regular_holding_piety_effect = yes
		}
	}
	ai_value = { base = 8 }
}
castle_unrelated = {
	levy = 10
	on_complete = { add_province_modifier = example }
}
'@
        $patch=Get-MandalaCompletionPatch $fixture @('castle_03')
        Assert-Equal $patch.Edits.Count 1
        $edit=$patch.Edits[0]
        Assert-Equal ($patch.Patched.Replace($edit.Patched,$edit.Original)) $fixture
        Assert-True ($edit.Patched -match '(?s)NOT = \{ exists = scope:character \}\s*exists = county.holder\s*county.holder = \{ is_alive = yes \}.*?county.holder = \{ save_scope_as = character \}.*?limit = \{ exists = scope:character scope:character = \{ is_alive = yes \} \}.*?scope:character = \{')
        Assert-True ($edit.Patched.Contains('MQA_REWARD SKIPPED no_living_builder castle_03'))
        Assert-Equal ([regex]::Matches($patch.Patched,'creator_mandala_upgraded_regular_holding_piety_effect = yes').Count) 1
        Assert-True ($patch.Patched -notmatch 'add_piety|mqa_b_trace_actor|set_variable|trigger_event')
        # Both pre-existing payer and ownerless cases retain the exists guards.
        # Offline validation cannot execute CK3 callbacks: test these in game too.
        Assert-Throws { Get-MandalaCompletionPatch $fixture @('castle_04') } 'review the vanilla update'
        Assert-Throws { Get-MandalaCompletionPatch ($fixture.Replace('creator_mandala_upgraded_regular_holding_piety_effect','new_game_reward_effect')) @('castle_03') } 'review the vanilla update'
        Assert-Throws { Get-MandalaCompletionPatch ($fixture.Replace('castle_unrelated = {', "castle_unrelated = {`n`ton_complete = {`n`t`tscope:character = { add_piety = 1 }`n`t}")) @('castle_03') } 'review the vanilla update'
    }
    Test-Case 'Reward repair guards both recipients, preserves native allocations and audits only actual payments' {
        $fixture=Read-Text "$repository/tools/tests/fixtures/mandala_reward_effects.txt"
        $patch=Get-MandalaRewardPatch $fixture
        Assert-Equal $patch.Definitions.Count 2
        foreach($definition in $patch.Definitions) {
            $restored=$definition.Patched
            $edits=@($definition.Edits)
            [array]::Reverse($edits)
            foreach($edit in $edits) { $restored=$restored.Replace($edit.Patched,$edit.Original) }
            Assert-Equal $restored $definition.Original
            Assert-True ($definition.Patched -match 'exists = scope:character scope:character = \{ is_alive = yes \}')
            Assert-True ($definition.Patched -match 'exists = county.holder\s*county.holder = \{ is_alive = yes \}')
            $expected=$definition.Key -eq 'mandala_upgraded_temple_holding_effect' ? 3 : 1
            Assert-Equal ([regex]::Matches($definition.Patched,'add_piety =').Count) $expected
            Assert-Equal ([regex]::Matches($definition.Patched,'MQA_REWARD PAYMENT').Count) $expected
            Assert-Equal ([regex]::Matches($definition.Patched,'mqa_b_reward_payment_begin_effect = yes').Count) $expected
            Assert-Equal ([regex]::Matches($definition.Patched,'mqa_b_reward_payment_end_effect = yes').Count) $expected
            foreach($payment in @($definition.Edits | Where-Object Index -ge 0)) {
                Assert-True ($payment.Patched -match '(?s)^\s*if = \{\s*limit = \{ is_alive = yes \}\s*mqa_b_reward_payment_begin_effect = yes\s*add_piety = .*?MQA_REWARD PAYMENT.*?mqa_b_reward_payment_end_effect = yes\s*\}\s*else = \{ debug_log = "MQA_REWARD SKIPPED dead_recipient')
            }
        }
        # The two identical primary allocations must be patched independently,
        # leaving the secondary holder payment at its own native location.
        foreach($number in 1..3) { Assert-Equal ([regex]::Matches($patch.Definitions[0].Patched,"PAYMENT mandala_upgraded_temple_holding_effect allocation=$number").Count) 1 }
        Assert-Throws { Get-MandalaRewardPatch ($fixture.Replace('add_piety =','add_prestige =')) } 'review the vanilla update'
        Assert-Throws { Get-MandalaRewardPatch ($fixture.Replace('county.holder = { save_scope_as = character }','save_scope_as = changed_fallback')) } 'review the vanilla update'
    }
    Test-Case 'Repeat audit reports mutations and actor piety without issuing rewards' {
        $source=Read-Text "$repository/common/scripted_effects/mqa_building_diagnostics_effects.txt"
        $effects=@{}; foreach($b in Get-ScriptBlocks $source) { $effects[$b.Key]=$b.Body }
        Assert-True ($effects.mqa_b_trace_begin_effect.Contains('name = mqa_b_piety_before value = piety'))
        $summary=$effects.mqa_b_trace_improvement_result_effect
        Assert-True ($summary -match 'var:mqa_b_added = 0 var:mqa_b_upgraded = 0 var:mqa_b_removed = 0')
        foreach($marker in @('no_building_changes','building_changes','actor_piety_increased','actor_piety_decreased','actor_piety_unchanged','actor_reward_payments','actor_no_reward_payments')) { Assert-True ($summary.Contains("MQA_BUILD RESULT $marker")) }
        Assert-True ($effects.mqa_b_reward_payment_end_effect -match '(?s)change_variable = \{ name = mqa_reward_payments_total add = 1 \}.*?var:mqa_reward_last_gain > 0.*?MQA_REWARD PIETY_INCREASED.*?save_scope_as = mqa_reward_recipient.*?debug_log_scopes = yes')
        Assert-True ($source -notmatch '\badd_piety\s*=')
        $events=Read-Text "$repository/events/mqa_building_events.txt"
        Assert-Equal ([regex]::Matches($events,'mqa_b_trace_improvement_result_effect = yes').Count) 1
        Assert-True ($events -match '(?s)domain final_upgrade.*?mqa_b_upgrade_province_buildings_effect.*?mqa_b_trace_improvement_result_effect = yes.*?MQA_BUILD END domain')
    }
    Test-Case 'Diagnostic warning sources are removed or consumed by a useful result marker' {
        $source=Read-Text "$repository/common/scripted_effects/mqa_building_diagnostics_effects.txt"
        Assert-True ($source -notmatch '\bmqa_b_domain_before\b|\bmqa_b_domain_limit_before\b')
        Assert-True ($source -match '(?s)limit = \{ var:mqa_b_skipped > 0 \}\s*debug_log = "MQA_BUILD RESULT active_constructions_skipped"')
        # Keep last-measurement comparisons: dropping unused initial snapshots
        # must not remove detection of changes in owned holdings or domain limit.
        Assert-True ($source.Contains('domain_size != var:mqa_b_domain_after'))
        Assert-True ($source.Contains('domain_limit != var:mqa_b_domain_limit_after'))
    }
    Test-Case 'Holding requirement generator copies all requirement categories and does not touch building effects' {
        $game=Join-Path $temporary 'holding-fixture'
        [IO.Directory]::CreateDirectory("$game/common/buildings") > $null
        $fixture=@'
temple_01 = {
	can_construct_potential = { exists = scope:holder }
	can_construct = { culture = { has_innovation = innovation_city_planning } }
	can_construct_showing_failures_only = { building_requirement_tribal = no }
}
temple_citadel_01 = {
	can_construct_potential = { scope:holder = { government_has_flag = government_is_mandala } }
	can_construct = { scope:holder = { government_has_flag = government_is_mandala } }
}
city_01 = {
	can_construct_potential = { barony_cannot_construct_holding = no }
	can_construct = { culture = { has_innovation = innovation_city_planning } }
}
castle_01 = {
	can_construct = { culture = { has_innovation = innovation_motte } }
	can_construct_showing_failures_only = { japan_castle_construction_trigger = yes }
}
'@
        Write-Text "$game/common/buildings/holdings.txt" $fixture
        $before=(Get-FileHash "$repository/common/scripted_effects/mqa_building_effects.txt").Hash
        $output=Join-Path $temporary 'holding-triggers.txt'
        # Exercise the CLI too: a dot-sourced generator must not overwrite its output parameter.
        Invoke-Tool 'pwsh' @('-NoProfile','-File',"$repository/tools/generate_holding_requirements.ps1",'-GamePath',$game,'-OutputPath',$output) > $null
        Assert-Equal (Get-FileHash "$repository/common/scripted_effects/mqa_building_effects.txt").Hash $before
        $triggers=@{}; foreach ($block in Get-ScriptBlocks (Read-Text $output)) { $triggers[$block.Key]=$block.Body }
        Assert-Equal $triggers.Count 4
        Assert-True ($triggers.mqa_b_can_found_temple_citadel_trigger -match 'government_has_flag = government_is_mandala')
        Assert-True ($triggers.mqa_b_can_found_temple_trigger -match '(?s)exists = scope:holder.*?innovation_city_planning.*?building_requirement_tribal = no')
        Assert-True ($triggers.mqa_b_can_found_city_trigger -match 'barony_cannot_construct_holding = no')
        Assert-True ($triggers.mqa_b_can_found_castle_trigger -match '(?s)innovation_motte.*?japan_castle_construction_trigger')
    }
    Test-Case 'Decision tooltips cannot traverse holdings or expand construction effects' {
        $source=Remove-ScriptComments (Read-Text "$repository/common/decisions/mqa_building_decisions.txt")
        $decisions=@{}; foreach ($b in (Get-ScriptBlocks $source)) { $decisions[$b.Key]=$b.Body }
        $index=0
        foreach ($name in @('mqa_b_lucky_7_sub_realm_decision','mqa_b_max_domicile_decision','mqa_b_found_holdings_decision','mqa_b_convert_holdings_decision','mqa_b_grant_baronies_decision')) {
            $index++
            $effect=Get-InnerBlock $decisions[$name] 'effect'
            Assert-True ($effect -match 'custom_tooltip = mqa_b_(domain|domicile|found_holdings|convert_holdings|grant_baronies)_effect_tt')
            $hidden=@(Get-ScriptBlocks ($effect -replace '(?m)^\t\t','') | Where-Object { $_.Key -eq 'hidden_effect' })
            Assert-Equal $hidden.Count 1
            Assert-True ($hidden[0].Body.Trim() -ceq "trigger_event = mqa_building.$index")
            Assert-True ($effect -notmatch '\b(mqa_b_\w+_effect|mqa_b_ongoing_constructions_value|every_\w+|debug_log|set_variable)\s*[=>]')
        }
    }
    Test-Case 'Every decision action is isolated and all decision text is static in every language' {
        $events=@{}
        foreach ($path in @('mqa_decision_events.txt','mqa_building_events.txt')) {
            foreach ($event in Get-ScriptBlocks (Remove-ScriptComments (Read-Text "$repository/events/$path"))) {
                $events[$event.Key]=$event.Body
            }
        }
        $keys=[Collections.Generic.HashSet[string]]::new()
        $targets=[Collections.Generic.HashSet[string]]::new()
        foreach ($path in Get-ChildItem "$repository/common/decisions/*.txt") {
            $source=(Remove-ScriptComments (Read-Text $path.FullName)) -replace '(?m)^ {4}', "`t"
            foreach ($decision in Get-ScriptBlocks $source) {
                foreach ($field in @('title','desc','selection_tooltip','confirm_text')) {
                    $key=Get-ScriptField $decision.Body $field
                    Assert-True ([bool]$key) "Missing $field in $($decision.Key)"
                    [void]$keys.Add($key)
                }
                $effect=Get-InnerBlock $decision.Body 'effect'
                if ($decision.Key -match '^mqa_(b_)?(show|hide)_decision$') {
                    Assert-True ($effect -match '^\s*(add|remove)_character_flag = \w+\s*$')
                } else {
                    $match=[regex]::Match($effect,'^\s*custom_tooltip = (\w+)\s+hidden_effect = \{ trigger_event = (mqa_(?:decision|building)\.\d+) \}\s*$')
                    Assert-True $match.Success "Tooltip can still reach action code: $($decision.Key)"
                    [void]$keys.Add($match.Groups[1].Value)
                    $target=$match.Groups[2].Value
                    Assert-True ($events.ContainsKey($target)) "Missing target event: $target"
                    Assert-True ($targets.Add($target)) "Two actions share an event: $target"
                }
            }
        }
        Assert-Equal $targets.Count 13
        foreach ($file in Get-ChildItem "$repository/localization/*/*.yml") {
            $loc=@{}
            foreach ($line in (Read-Text $file.FullName) -split '\n') {
                $match=[regex]::Match($line,'^ (\w+):\d* "(.*)"$')
                if ($match.Success) { $loc[$match.Groups[1].Value]=$match.Groups[2].Value }
            }
            $pending=[Collections.Generic.Queue[string]]::new([string[]]@($keys))
            $seen=[Collections.Generic.HashSet[string]]::new()
            while ($pending.Count) {
                $key=$pending.Dequeue()
                if (-not $seen.Add($key)) { continue }
                Assert-True ($loc.ContainsKey($key)) "Missing static text $key in $($file.Name)"
                Assert-True (-not $loc[$key].Contains('[')) "Dynamic decision text $key in $($file.Name)"
                foreach ($alias in [regex]::Matches($loc[$key],'\$(\w+)\$')) { $pending.Enqueue($alias.Groups[1].Value) }
            }
        }
    }
    Test-Case 'Saint site lookup filters local provinces before native realm membership' {
        $source=Remove-ScriptComments (Read-Text "$repository/common/scripted_triggers/zz_mqa_pam_saint_performance_triggers.txt")
        $blocks=@(Get-ScriptBlocks $source)
        Assert-Equal $blocks.Count 1
        Assert-Equal $blocks[0].Key 'pam_county_has_actor_primary_site_trigger'
        Assert-Equal ([regex]::Matches($source,'any_county_province =').Count) 2
        Assert-Equal ([regex]::Matches($source,'any_realm_province = \{ this = scope:mqa_primary_site_province \}').Count) 2
        Assert-True ($source -match '(?s)any_county_province = \{\s*any_province_domicile = \{ owner = \{ pam_character_has_cathedral_trigger = yes \} \}\s*save_temporary_scope_as = mqa_primary_site_province\s*\$ACTOR\$ = \{\s*any_realm_province')
        Assert-True ($source -match '(?s)any_county_province = \{\s*barony \?= \{ is_holy_site_of = \$ACTOR\$.faith \}\s*save_temporary_scope_as = mqa_primary_site_province\s*\$ACTOR\$ = \{\s*any_realm_province')
        # Keep the native actor-cathedral exception and intrinsic site rules.
        Assert-True ($source -match 'domicile \?= \{ domicile_location \?= \{ county = scope:pam_primary_site_county \} \}')
        Assert-True ($source -notmatch 'pam_site_free_trigger|poi_buried_saint|is_county_capital|target_is_liege|change_|set_variable|create_')
    }
    Test-Case 'Migrated decision events preserve the realm, council and cure actions without repeating dispatch' {
        $source=Remove-ScriptComments (Read-Text "$repository/events/mqa_decision_events.txt")
        $events=@{}; foreach ($event in Get-ScriptBlocks $source) { $events[$event.Key]=$event.Body }
        Assert-Equal $events.Count 8
        foreach ($event in $events.Values) {
            Assert-True ($event -match 'type = character_event\s+hidden = yes')
            Assert-True ($event -notmatch '\b(trigger_event|take_decision|while|on_action)\s*=')
            Assert-Equal ([regex]::Matches($event,'MQA_DECISION BEGIN').Count) 1
            Assert-Equal ([regex]::Matches($event,'MQA_DECISION END').Count) 1
        }
        Assert-True ($events['mqa_decision.1'] -match 'add_gold = 100000')
        Assert-True ($events['mqa_decision.2'] -match 'every_sub_realm_county')
        Assert-True ($events['mqa_decision.3'] -match 'mqa_convert_county_to_root_faith_effect')
        Assert-True ($events['mqa_decision.4'] -match 'resolve_title_and_vassal_change = scope:change')
        Assert-True ($events['mqa_decision.5'] -match 'mqa_council_start_check_effect = yes')
        Assert-True ($events['mqa_decision.6'] -match 'every_councillor = \{ mqa_council_clear_effect = yes \}')
        Assert-True ($events['mqa_decision.7'] -match 'mqa_every_realm_character_effect = \{ EFFECT = mqa_cure_diseases_effect \}')
        Assert-True ($events['mqa_decision.8'] -match 'mqa_every_close_family_effect = \{ EFFECT = mqa_cure_genetic_flaws_effect \}')
    }
    Test-Case 'Construction events run once without scheduling or calling decisions' {
        $source=Remove-ScriptComments (Read-Text "$repository/events/mqa_building_events.txt")
        $events=@(Get-ScriptBlocks $source)
        Assert-Equal $events.Count 5
        foreach ($event in $events) {
            Assert-True ($event.Body -match 'type = character_event')
            Assert-True ($event.Body -match 'hidden = yes')
            $body=Get-InnerBlock $event.Body 'immediate'
            Assert-Equal ([regex]::Matches($body,'mqa_b_trace_begin_effect = yes').Count) 1
            Assert-True ($body -match 'debug_log = "MQA_BUILD BEGIN (domain|domicile|foundation|conversion|grants)"')
            Assert-True ($body -match 'debug_log = "MQA_BUILD END (domain|domicile|foundation|conversion|grants)"')
            Assert-True ($body -notmatch '\b(trigger_event|while|on_action|take_decision)\s*=')
        }
        Assert-Equal ([regex]::Matches($source,'EFFECT = mqa_b_upgrade_province_buildings_effect').Count) 4
        Assert-Equal ([regex]::Matches($source,'EFFECT = mqa_b_priority_fill_province_effect').Count) 3
        Assert-Equal ([regex]::Matches($source,'mqa_b_trace_domain_size_effect = yes').Count) 5
        foreach ($file in Get-ChildItem "$repository/localization/*/*.yml") {
            Assert-True ((Read-Text $file.FullName) -notmatch 'mqa_b_trace_\w+_(begin|end):')
        }
    }
    Test-Case 'Four domain actions cannot invoke another action or share its event' {
        $events=@{}; foreach ($event in Get-ScriptBlocks (Remove-ScriptComments (Read-Text "$repository/events/mqa_building_events.txt"))) { $events[$event.Key]=$event.Body }
        $actions=@{
            'mqa_building.1'=@('mqa_b_upgrade_province_buildings_effect','mqa_b_priority_fill_province_effect')
            'mqa_building.3'=@('mqa_b_found_domain_holdings_effect')
            'mqa_building.4'=@('mqa_b_feudalize_domain_holdings_effect')
            'mqa_building.5'=@('mqa_b_grant_personal_baronies_effect')
        }
        $all=@($actions.Values | ForEach-Object { $_ })
        foreach ($id in $actions.Keys) {
            foreach ($effect in $all) {
                Assert-Equal ($events[$id].Contains($effect)) ($actions[$id] -contains $effect) "Unexpected action $effect in $id"
            }
        }
        $decisions=@{}; foreach ($decision in Get-ScriptBlocks (Remove-ScriptComments (Read-Text "$repository/common/decisions/mqa_building_decisions.txt"))) { $decisions[$decision.Key]=$decision.Body }
        foreach ($key in @('found_holdings','convert_holdings','grant_baronies')) {
            $body=$decisions["mqa_b_${key}_decision"]
            Assert-True ($body -match 'is_ai = no\s+has_character_flag = mqa_b_show_decision_flag')
            Assert-True ($body -notmatch 'is_valid|any_\w+|every_\w+|script_value') 'Decision visibility must not scan the realm'
        }
        # Foundation/conversion can trigger native callbacks, but must not explicitly
        # call the custom grant helper or generate its recipients.
        $helpers=@{}; foreach ($block in Get-ScriptBlocks (Remove-ScriptComments (Read-Text "$repository/common/scripted_effects/mqa_building_scope_effects.txt"))) { $helpers[$block.Key]=$block.Body }
        foreach ($key in @('mqa_b_found_domain_holdings_effect','mqa_b_found_holding_effect','mqa_b_feudalize_domain_holdings_effect')) {
            Assert-True ($helpers[$key] -notmatch 'mqa_b_(grant|queue_holding_grant)|create_character|change_title_holder|resolve_title_and_vassal_change')
        }
    }
    Test-Case 'All generated mutation calls have exactly one guarded actor counter' {
        $source=Read-Text "$repository/common/scripted_effects/mqa_building_effects.txt"
        Assert-Equal (Add-BuildingDiagnostics $source) $source
        $primitives=[regex]::Matches($source,'(?m)^\t+(?:(?:add_building|replace_building_effect|remove_building|remove_domicile_building) = \w+|domicile = \{ add_domicile_building = \w+ \})$')
        $counters=[regex]::Matches($source,'mqa_b_trace_change_effect = \{ COUNTER = (\w+) \}')
        Assert-True ($primitives.Count -gt 0)
        Assert-Equal $primitives.Count $counters.Count
        $trace=Read-Text "$repository/common/scripted_effects/mqa_building_diagnostics_effects.txt"
        Assert-True ($trace -match '(?s)exists = scope:mqa_b_trace_actor.*?scope:mqa_b_trace_actor = \{\s*change_variable')
        foreach ($counter in @($counters | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)) {
            Assert-True ($trace.Contains("set_variable = { name = $counter value = 0 }")) "Missing reset: $counter"
        }
        Assert-Equal ([regex]::Matches($source,'debug_log').Count) 0
    }
    Test-Case 'CK3 building scripts have balanced braces and no timed repeat loop' {
        $paths=@("$repository/common/decisions/mqa_building_decisions.txt", "$repository/common/decisions/mqa_decisions.txt", "$repository/events/mqa_building_events.txt", "$repository/events/mqa_decision_events.txt", "$repository/events/zz_mqa_epidemic_events.txt", "$repository/common/scripted_effects/zz_mqa_mandala_reward_effects.txt", "$repository/common/scripted_triggers/mqa_building_triggers.txt", "$repository/common/scripted_triggers/mqa_holding_requirements_triggers.txt", "$repository/common/scripted_triggers/zz_mqa_pam_saint_performance_triggers.txt") + @(Get-ChildItem "$repository/common/scripted_effects/mqa_building*txt" | ForEach-Object FullName) + @(Get-ChildItem "$repository/common/buildings/*.txt" | ForEach-Object FullName)
        foreach ($path in $paths) {
            $bytes=[IO.File]::ReadAllBytes($path)
            Assert-Equal ([Convert]::ToHexString($bytes[0..2])) 'EFBBBF'
            $text=Remove-ScriptComments (Read-Text $path)
            $text=[regex]::Replace($text,'"[^"\n]*"','')
            $depth=0
            foreach ($char in $text.ToCharArray()) { if ($char -eq '{') { $depth++ }; if ($char -eq '}') { $depth-- }; Assert-True ($depth -ge 0) "Unexpected closing brace: $path" }
            Assert-Equal $depth 0
            Assert-True ($text -notmatch '\b(while|on_action)\s*=') "Unexpected repeating work: $path"
        }
    }
    if ($TestInstalledGame) {
        Test-Case 'Epidemic override matches the installed event except for the expired-scope guard' {
            $game=$GamePath ? $GamePath : $script:DefaultGame
            $patch=Get-EpidemicEventPatch (Read-Text "$game/events/dlc/ce1/epidemic_events.txt")
            $output=Join-Path $temporary 'epidemic-override.txt'
            Write-EpidemicFix $game $output
            Assert-Equal (Read-Text $output) (Read-Text "$repository/events/zz_mqa_epidemic_events.txt")
            Assert-Equal ($patch.Patched.Replace($patch.GuardedLoop,'LOOP').Replace($patch.PriorityInsertion,'')) ($patch.Original.Replace($patch.OriginalLoop,'LOOP'))
        }
        Test-Case 'Installed mandala replacements preserve eight callbacks and original reward allocations' {
            $game=$GamePath ? $GamePath : $script:DefaultGame
            $output=Join-Path $temporary 'mandala-buildings'
            Invoke-Tool 'pwsh' @('-NoProfile','-File',"$repository/tools/generate_mandala_completion_fix.ps1",'-GamePath',$game,'-OutputPath',$output) > $null
            $files=@{'00_castle_buildings.txt'=@('castle_03','castle_04'); '00_temple_buildings.txt'=@('temple_02','temple_03','temple_04'); 'temple_citadel_buildings.txt'=@('temple_citadel_02','temple_citadel_03','temple_citadel_04')}
            foreach ($name in $files.Keys) {
                $original=Read-Text "$game/common/buildings/$name"
                $patch=Get-MandalaCompletionPatch $original $files[$name]
                $actual=Read-Text "$repository/common/buildings/$name"
                Assert-Equal $actual $patch.Patched
                Assert-Equal (Read-Text "$output/$name") $actual
                Assert-Equal $patch.Edits.Count $files[$name].Count
                foreach ($edit in $patch.Edits) { $actual=$actual.Replace($edit.Patched,$edit.Original) }
                Assert-Equal $actual $original
                Assert-Equal ([regex]::Matches($patch.Patched,'(?m)^\t\tscope:character = \{').Count) 0
                Assert-True (-not ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes("$output/$name")).Contains("`r")))
            }
            $rewards=Get-MandalaRewardPatch (Read-Text "$game/common/scripted_effects/tgp_mandala_scripted_effects.txt")
            $generated=Read-Text (Join-Path $temporary 'scripted_effects/zz_mqa_mandala_reward_effects.txt')
            Assert-Equal $generated (Read-Text "$repository/common/scripted_effects/zz_mqa_mandala_reward_effects.txt")
            Assert-True ($generated.EndsWith($rewards.Patched))
            foreach($definition in $rewards.Definitions) {
                $restored=$definition.Patched; $edits=@($definition.Edits); [array]::Reverse($edits)
                foreach($edit in $edits) { $restored=$restored.Replace($edit.Patched,$edit.Original) }
                Assert-Equal $restored $definition.Original
            }
        }
        Test-Case 'Installed game generators produce BOM, LF and balanced effects' {
            $game=$GamePath ? $GamePath : $script:DefaultGame
            foreach ($kind in @('building','lifestyle')) {
                $output=Join-Path $temporary "$kind-installed.txt"
                if ($kind -eq 'building') { Write-BuildingEffects $game $output } else { Write-LifestyleEffects $game $output }
                $bytes=[IO.File]::ReadAllBytes($output); $text=Read-Text $output
                Assert-Equal ([Convert]::ToHexString($bytes[0..2])) 'EFBBBF'
                Assert-True (-not ([Text.Encoding]::UTF8.GetString($bytes).Contains("`r")))
                Assert-Equal ([regex]::Matches($text,'\{').Count) ([regex]::Matches($text,'\}').Count)
            }
        }
    }
    Write-Host "$script:Passed tests passed."
} finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
