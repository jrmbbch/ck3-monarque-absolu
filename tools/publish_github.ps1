# GitHub tag/release adapter. Dot-source from publish_release.ps1 or tests.
. "$PSScriptRoot/Common.ps1"
$script:GitHubRepository = 'jrmbbch/ck3-monarque-absolu'
function Get-RemoteRefs([string]$Tag) {
    $result = Invoke-Tool git @('ls-remote','origin','refs/heads/main',"refs/tags/$Tag","refs/tags/$Tag^{}")
    $refs=@{}
    foreach ($line in ($result.Output.Trim() -split '\n')) { if ($line.Trim()) { $parts=$line.Trim() -split '\s+'; $refs[$parts[1]]=$parts[0] } }
    $refs
}
function Get-GitHubRelease([string]$Tag) {
    $result = Invoke-Tool gh @('api','--hostname','github.com',"repos/$script:GitHubRepository/releases/tags/$Tag") -AllowFailure
    if ($result.Code) { if ($result.Error.Contains('(HTTP 404)')) { return $null }; throw "Cannot inspect GitHub release: $($result.Error.Trim())" }
    ConvertFrom-Json -AsHashtable $result.Output
}
function Confirm-GitHubRelease($Release, [string]$Tag, [string]$Notes) {
    if ($Release.tag_name -cne $Tag -or $Release.draft -or $Release.prerelease -or ([string]$Release.body).Trim() -cne $Notes.Trim()) { throw "Existing GitHub release $Tag differs; refusing to overwrite it" }
}
function Confirm-GitHubTag($Refs, [string]$Tag, [string]$Commit) {
    $remote = $Refs["refs/tags/$Tag^{}"] ?? $Refs["refs/tags/$Tag"]
    if ($remote -and $remote -cne $Commit) { throw "Remote tag $Tag points to another commit; refusing to move it" }
    $remote
}
function Publish-GitHub($Info) {
    $tag='v' + $Info.Version
    if ((Invoke-Tool git @('status','--porcelain','--untracked-files=normal')).Output.Trim()) { throw 'GitHub publication requires a clean working tree; commit and push the release changes first' }
    $origin=(Invoke-Tool git @('remote','get-url','origin')).Output.Trim()
    if ($origin -cnotin @("https://github.com/$script:GitHubRepository.git","https://github.com/$script:GitHubRepository","git@github.com:$script:GitHubRepository.git")) { throw 'Unexpected origin repository; refusing to publish' }
    $commit=(Invoke-Tool git @('rev-parse','HEAD')).Output.Trim()
    $refs=Get-RemoteRefs $tag; $remoteTag=Confirm-GitHubTag $refs $tag $commit
    if ($refs['refs/heads/main'] -cne $commit) { throw 'HEAD must match origin/main on GitHub; push the release commit before publishing' }
    $local=Invoke-Tool git @('rev-parse','--verify',"refs/tags/$tag^{commit}") -AllowFailure
    if (-not $local.Code -and $local.Output.Trim() -cne $commit) { throw "Local tag $tag points to another commit; refusing to move it" }
    $existing=Get-GitHubRelease $tag
    if ($null -ne $existing) {
        if (-not $remoteTag) { throw 'GitHub release exists without the expected remote tag' }
        Confirm-GitHubRelease $existing $tag $Info.Notes
        Write-Host "GitHub: $tag and its notes are already published; no changes made."
        return
    }
    if (-not $remoteTag) {
        if ($local.Code) { Invoke-Tool git @('tag','-a',$tag,$commit,'-m',"Release $($Info.Version)") > $null }
        Invoke-Tool git @('push','origin',"refs/tags/${tag}:refs/tags/$tag") > $null
    }
    if (-not (Confirm-GitHubTag (Get-RemoteRefs $tag) $tag $commit)) { throw 'The pushed tag is not visible on GitHub; check before retrying' }
    $notesPath=Join-Path $script:RepoRoot "docs/patch_notes/$($Info.Version).txt"
    Invoke-Tool gh @('release','create',$tag,'--repo',$script:GitHubRepository,'--verify-tag','--title',$tag,'--notes-file',$notesPath) > $null
    $created=Get-GitHubRelease $tag
    if ($null -eq $created) { throw 'GitHub release not visible; check before retrying' }
    Confirm-GitHubRelease $created $tag $Info.Notes
    Write-Host "GitHub: publication confirmed. https://github.com/$script:GitHubRepository/releases/tag/$tag"
}
