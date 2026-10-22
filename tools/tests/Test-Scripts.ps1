#!/usr/bin/env pwsh
#Requires -Version 7.4
# Self-contained offline regression suite; no Pester install or network is required.
param([string]$GamePath, [switch]$TestInstalledGame)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../publish_release.ps1"
. "$PSScriptRoot/../generate_building_effects.ps1"
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
    if ($TestInstalledGame) {
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
