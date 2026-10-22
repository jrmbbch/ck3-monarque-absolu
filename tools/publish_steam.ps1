# Official Steamworks API through a small C# ABI bridge loaded by Add-Type.
function Initialize-SteamTypes {
    if (-not ('MonarqueAbsolu.SteamApi' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'SteamNative.cs') }
}
function Confirm-SteamResult([byte[]]$Bytes) {
    if ($Bytes.Length -lt 5) { throw 'Unexpected Steam submission callback size' }
    $result=[BitConverter]::ToInt32($Bytes, 0)
    if ($result -ne 1) { throw "Steam rejected publication (EResult=$result)" }
    if ($Bytes[4]) { throw 'Uploaded, but Steam requires the owner to accept the Workshop agreement on the item page' }
}
function Publish-Steam([string]$Content, $Info, [string]$Library, [int]$TimeoutSeconds=300) {
    Initialize-SteamTypes
    $oldApp=$env:SteamAppId; $oldGame=$env:SteamGameId
    $env:SteamAppId='1158310'; $env:SteamGameId='1158310'; $api=$null
    try {
        $api=[MonarqueAbsolu.SteamApi]::new($Library)
        $handle=$api.Start.Invoke($api.Ugc, 1158310, 3813333986)
        if ($handle -eq 0 -or $handle -eq [ulong]::MaxValue) { throw 'Steam rejected the item update handle' }
        $settings=@{ Title=$Info.Name; Description=Read-Text (Join-Path $script:RepoRoot 'docs/workshop_description.bbcode'); Content=$Content; Preview=Join-Path $Content 'thumbnail.png' }
        foreach ($key in $settings.Keys) { if (-not $api.$key.Invoke($api.Ugc, $handle, $settings[$key])) { throw "Steam rejected $key" } }
        $call=$api.Submit.Invoke($api.Ugc, $handle, $Info.Notes)
        if (-not $call) { throw 'Steam did not start the submission' }
        Write-Host 'Steam: update submitted; waiting for the server result.'
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $message=[MonarqueAbsolu.CallbackMessage]::new()
        while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            $api.Frame.Invoke($api.Pipe)
            while ($api.Next.Invoke($api.Pipe, [ref]$message)) {
                $ready=$null
                try {
                    if ($message.Callback -eq 703 -and $message.Size -eq [Runtime.InteropServices.Marshal]::SizeOf([type][MonarqueAbsolu.CallCompleted])) {
                        $completed=[Runtime.InteropServices.Marshal]::PtrToStructure($message.Data, [type][MonarqueAbsolu.CallCompleted])
                        if ($completed.Handle -eq $call) { $ready=$completed }
                    }
                } finally { $api.Free.Invoke($api.Pipe) }
                if ($null -eq $ready) { continue }
                if ($ready.Callback -ne 3404 -or $ready.Size -lt 5 -or $ready.Size -gt 1048576) { throw 'Unexpected Steam submission callback' }
                $buffer=[Runtime.InteropServices.Marshal]::AllocHGlobal([int]$ready.Size)
                try {
                    $failed=$false
                    if (-not $api.Result.Invoke($api.Pipe, $call, $buffer, [int]$ready.Size, 3404, [ref]$failed) -or $failed) { throw 'Steam callback failed; check the item before retrying' }
                    $bytes=[byte[]]::new($ready.Size); [Runtime.InteropServices.Marshal]::Copy($buffer, $bytes, 0, $bytes.Length)
                    Confirm-SteamResult $bytes
                } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer) }
                Write-Host 'Steam: publication confirmed. https://steamcommunity.com/sharedfiles/filedetails/?id=3813333986'
                return
            }
            Start-Sleep -Milliseconds 250
        }
        throw 'Steam submission timed out; status unknown. Check the item before retrying.'
    } finally {
        if ($api) { $api.Dispose() }
        $env:SteamAppId=$oldApp; $env:SteamGameId=$oldGame
    }
}
