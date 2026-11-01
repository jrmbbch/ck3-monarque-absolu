#!/usr/bin/env pwsh
#Requires -Version 7.4
# Offline only: all HTTP, authentication, writes and waiting are mocked.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../publish_paradox.ps1"
$script:PublicationFixture=Join-Path $PSScriptRoot 'fixtures/paradox_publication.json'
function Read-Fixture { ConvertFrom-Json -AsHashtable (Read-Text $script:PublicationFixture) }
function Assert($Condition,[string]$Message='Assertion failed') { if(-not $Condition){throw $Message} }
function Assert-Fails([scriptblock]$Action,[string]$Pattern) {
    try { & $Action } catch { Assert ($_.Exception.Message -match $Pattern) "Unexpected failure: $($_.Exception.Message)"; return }
    throw "Expected failure: $Pattern"
}
function Invoke-ParadoxRequest { throw 'Unexpected HTTP request in offline test' }
function Get-ParadoxAuth { throw 'Unexpected authentication in offline test' }
function Start-Sleep { }
$script:PublicationPassed=0
function Test([string]$Name,[scriptblock]$Action) { & $Action; $script:PublicationPassed++; Write-Host "PASS $Name" }

Test 'Metadata URLs are unique and GET requests explicitly bypass cache' {
    $script:ReadPaths=[Collections.Generic.List[string]]::new()
    function Invoke-ParadoxRequest($Method,$Path,$Auth) {
        Assert ($Method -ceq 'GET' -and $null -eq $Auth)
        $script:ReadPaths.Add($Path)
        @{modDetail=(Read-Fixture).confirmed}
    }
    $null=Get-ParadoxMetadata $null; $null=Get-ParadoxMetadata $null
    Assert ($script:ReadPaths[0] -cne $script:ReadPaths[1])
    Assert ($script:ReadPaths[0] -match '^/mods\?modId=161949&_mqa_check=[0-9a-f]{32}$')
    $request=New-ParadoxHttpRequest GET $script:ReadPaths[0] $null
    try {
        Assert $request.Headers.CacheControl.NoCache
        Assert $request.Headers.CacheControl.NoStore
        Assert ($request.Headers.CacheControl.MaxAge -eq [TimeSpan]::Zero)
        Assert ($request.Headers.Pragma.ToString() -eq 'no-cache')
        Assert (-not $request.Headers.Contains('Authorization'))
    } finally { $request.Dispose() }
    $post=New-ParadoxHttpRequest POST '/mods/publishUpdate' @{session=@{token='offline'}} @{modId='161949'}
    try {
        Assert ($post.Headers.Contains('Authorization'))
        Assert ($null -eq $post.Headers.CacheControl)
        Assert ((ConvertFrom-Json ($post.Content.ReadAsStringAsync().GetAwaiter().GetResult())).modId -eq '161949')
    } finally { $post.Dispose() }
}
Test 'Public latest notes confirm publication despite lagging flag or unchanged timestamp' {
    $f=Read-Fixture
    Assert ($f.confirmed.latestUpdate -ceq $f.pending.latestUpdate)
    Assert ((Get-ParadoxPublicationStatus $f.confirmed $f.notes) -ceq 'Confirmed')
    $f.confirmed.changelog[0].details=$f.confirmed.changelog[0].details.Replace("`n","`r`n")
    Assert ((Get-ParadoxPublicationStatus $f.confirmed $f.notes) -ceq 'Confirmed')
    $f.confirmed.updating=$true
    Assert ((Get-ParadoxPublicationStatus $f.confirmed $f.notes) -ceq 'Confirmed')
    $f.confirmed.state='draft'
    Assert ((Get-ParadoxPublicationStatus $f.confirmed $f.notes) -cne 'Confirmed')
}
Test 'Old or edited notes, history-only matches and wrong identities cannot confirm' {
    $f=Read-Fixture
    Assert ((Get-ParadoxPublicationStatus $f.pending $f.notes) -ceq 'Pending')
    $f.pending.updating=$false
    Assert ((Get-ParadoxPublicationStatus $f.pending $f.notes) -ceq 'Unknown')
    $f.confirmed.latestVersion=8
    Assert ((Get-ParadoxPublicationStatus $f.confirmed $f.notes) -ceq 'Unknown')
    $f=Read-Fixture; $f.confirmed.changelog[0].details+=' edited'
    Assert ((Get-ParadoxPublicationStatus $f.confirmed $f.notes) -ceq 'Unknown')
    $f.confirmed.game='other'
    Assert-Fails { Get-ParadoxPublicationStatus $f.confirmed $f.notes } 'Unexpected Paradox mod identity'
    Assert (-not (Test-ParadoxNotes @{latestVersion='';changelog=@(@{modVersion='';details=$f.notes})} $f.notes))
    Assert (-not (Test-ParadoxNotes (Read-Fixture).confirmed ''))
}
Test 'Verification retries stale public snapshots without authenticating or writing' {
    $f=Read-Fixture; $script:PublicationReads=0
    function Get-ParadoxMetadata($Auth) {
        Assert ($null -eq $Auth)
        $script:PublicationReads++
        if($script:PublicationReads -lt 3) { return (Read-Fixture).pending }
        (Read-Fixture).confirmed
    }
    $result=Wait-ParadoxPublication $f.notes 2
    Assert ($result.Status -ceq 'Confirmed' -and $result.LatestVersion -eq 7)
    Assert ($script:PublicationReads -eq 3)
}
Test 'Expired verification reports uncertainty, not non-publication, and does not resubmit' {
    function Get-ParadoxMetadata { (Read-Fixture).pending }
    Assert-Fails { Wait-ParadoxPublication (Read-Fixture).notes 0 } 'publication not confirmed.*Status is unknown.*check_paradox_publication.ps1.*Do not automatically resubmit'
}
Test 'A public read error stays unknown and a transient read error can recover' {
    function Get-ParadoxMetadata { throw 'offline simulated network failure' }
    Assert-Fails { Wait-ParadoxPublication (Read-Fixture).notes 0 } 'Unknown \(public read unavailable\)'
    $script:PublicationReads=0
    function Get-ParadoxMetadata {
        $script:PublicationReads++
        if($script:PublicationReads -eq 1){throw 'offline simulated network failure'}
        (Read-Fixture).confirmed
    }
    Assert ((Wait-ParadoxPublication (Read-Fixture).notes 2).Status -ceq 'Confirmed')
}
Test 'An existing public release with a lagging flag never uploads or edits descriptions' {
    function Get-ParadoxAuth { @{session=@{token='offline'}} }
    function Get-ParadoxMetadata($Auth) {
        $f=Read-Fixture
        if($Auth){return $f.pending}
        $f.confirmed.updating=$true
        $f.confirmed
    }
    function Update-ParadoxDescriptions { throw 'Unexpected edit while updating' }
    $f=Read-Fixture
    Publish-Paradox '/unused' @{Name=$f.confirmed.displayName;Notes=$f.notes} 0
}
Test 'A pending submission can finish without sending another archive' {
    function Get-ParadoxAuth { @{session=@{token='offline'}} }
    $script:PublicReads=0
    function Get-ParadoxMetadata($Auth) {
        if($Auth){return (Read-Fixture).pending}
        $script:PublicReads++
        if($script:PublicReads -eq 1){return (Read-Fixture).pending}
        (Read-Fixture).confirmed
    }
    $f=Read-Fixture
    Publish-Paradox '/unused' @{Name=$f.confirmed.displayName;Notes=$f.notes} 2
    Assert ($script:PublicReads -eq 2)
}
Test 'Fresh upload is sent once; success or uncertain timeout never repeats the write' {
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('mqa-paradox-publication-'+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory("$temporary/content") > $null
    try {
        Write-Text "$temporary/content/descriptor.mod" 'version="1.0.6"'
        function Get-ParadoxAuth { @{session=@{token='offline'}} }
        $script:PublicReads=0; $script:PublicationWrites=[Collections.Generic.List[string]]::new()
        function Get-ParadoxMetadata($Auth) {
            $f=Read-Fixture
            if($Auth){$f.pending.updating=$false; return $f.pending}
            $script:PublicReads++
            if($script:PublicReads -lt 3){$f.pending.updating=$false; return $f.pending}
            $f.confirmed.updating=$true; $f.confirmed
        }
        function Invoke-ParadoxRequest($Method,$Path,$Auth,$Data,[switch]$Binary) {
            Assert ([bool]$Auth)
            $script:PublicationWrites.Add("$Method $Path")
            if($Method -ceq 'PUT'){Assert $Binary; return @{}}
            Assert ($Method -ceq 'POST' -and $Path -ceq '/mods/publishUpdate')
            Assert ($Data.changelogEntry -ceq (Read-Fixture).notes)
            @{modId='161949'}
        }
        $f=Read-Fixture
        Publish-Paradox "$temporary/content" @{Name=$f.confirmed.displayName;Notes=$f.notes;Version='1.0.6';Tags=@();Required='1.20.*'} 2
        Assert ($script:PublicationWrites.Count -eq 2)
        Assert ($script:PublicReads -eq 3)
        Remove-Item -LiteralPath "$temporary/monarqueabsolu106.zip"
        $script:PublicReads=0; $script:PublicationWrites.Clear()
        Assert-Fails { Publish-Paradox "$temporary/content" @{Name=$f.confirmed.displayName;Notes=$f.notes;Version='1.0.6';Tags=@();Required='1.20.*'} 0 } 'publication not confirmed.*Status is unknown'
        Assert ($script:PublicationWrites.Count -eq 2)
        Assert ($script:PublicReads -eq 2)
    } finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
Write-Host "$script:PublicationPassed Paradox publication checks passed. No network requests performed."
