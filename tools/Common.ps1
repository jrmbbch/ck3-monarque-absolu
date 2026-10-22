# Shared helpers for PowerShell 7.4+; no third-party modules required.
$script:RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:DefaultGame = Join-Path $HOME 'Library/Application Support/Steam/steamapps/common/Crusader Kings III/game'
function New-OrdinalMap { ,([Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)) }
function Get-OrdinalSorted([string[]]$Items) {
    $copy = [string[]]@($Items); [Array]::Sort($copy, [StringComparer]::Ordinal); $copy
}
function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path).Replace("`r`n", "`n") }
function Write-Text([string]$Path, [string]$Text, [switch]$Bom) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))) > $null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($Bom.IsPresent))
}
function Invoke-Tool([string]$File, [string[]]$Arguments, [string]$WorkingDirectory = $script:RepoRoot, [switch]$AllowFailure) {
    $start = [Diagnostics.ProcessStartInfo]::new($File)
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    try {
        [void]$process.Start()
        $output = $process.StandardOutput.ReadToEndAsync(); $errorText = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) { $process.Kill($true); throw "$File timed out; check the remote state before retrying" }
        $result = @{ Code = $process.ExitCode; Output = $output.GetAwaiter().GetResult(); Error = $errorText.GetAwaiter().GetResult() }
        if ($result.Code -ne 0 -and -not $AllowFailure) { throw "$File failed: $($result.Error.Trim())" }
        $result
    } finally { $process.Dispose() }
}
function Remove-ScriptComments([string]$Text) { [regex]::Replace($Text, '#[^\n]*', '') }
function Get-ScriptBlocks([string]$Text) {
    $pattern = [regex]::new('^([A-Za-z0-9_]+)\s*=\s*\{', 'Multiline')
    $position = 0
    while (($match = $pattern.Match($Text, $position)).Success) {
        $depth = 0; $index = $match.Index + $match.Length - 1
        for (; $index -lt $Text.Length; $index++) {
            if ($Text[$index] -eq '{') { $depth++ }
            elseif ($Text[$index] -eq '}') { $depth--; if ($depth -eq 0) { break } }
        }
        if ($depth -ne 0) { throw "Unclosed script block: $($match.Groups[1].Value)" }
        $start = $match.Index + $match.Length
        @{ Key = $match.Groups[1].Value; Body = $Text.Substring($start, $index - $start) }
        $position = $index + 1
    }
}
function Get-InnerBlock([string]$Body, [string]$Key) {
    $match = [regex]::Match($Body, '(?m)^\t' + [regex]::Escape($Key) + '\s*=\s*\{')
    if (-not $match.Success) { return '' }
    $depth = 0
    for ($index = $match.Index + $match.Length - 1; $index -lt $Body.Length; $index++) {
        if ($Body[$index] -eq '{') { $depth++ }
        elseif ($Body[$index] -eq '}') {
            $depth--; if ($depth -eq 0) { return $Body.Substring($match.Index + $match.Length, $index - $match.Index - $match.Length) }
        }
    }
    throw "Unclosed inner block: $Key"
}
function Get-ScriptField([string]$Body, [string]$Key) {
    $match = [regex]::Match($Body, '(?m)^\t' + [regex]::Escape($Key) + '\s*=\s*([A-Za-z0-9_@.\-]+)')
    if ($match.Success) { return $match.Groups[1].Value }; return ''
}
function Format-ScriptIndent([string]$Block, [int]$Depth) {
    $level = $Depth
    foreach ($line in ($Block.Trim() -split '\r?\n')) {
        $line = $line.Trim(); if (-not $line) { continue }
        if ($line.StartsWith('}')) { $level-- }
        ("`t" * $level) + $line
        $level += ([regex]::Matches($line, '\{').Count - [regex]::Matches($line, '\}').Count)
        if ($line.StartsWith('}')) { $level++ }
    }
}
