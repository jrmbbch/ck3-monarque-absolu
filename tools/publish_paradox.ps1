# LFv1 API adapter, inspected in Paradox Launcher 2026.13. Undocumented API.
. "$PSScriptRoot/Common.ps1"
$script:ParadoxStorage = Join-Path $HOME 'Library/Application Support/Paradox Interactive/launcher-v2/session.js'
function Invoke-ParadoxRequest([string]$Method, [string]$Path, $Auth, $Data, [switch]$Binary) {
    $handler=[Net.Http.HttpClientHandler]::new(); $handler.AllowAutoRedirect=$false
    $client=[Net.Http.HttpClient]::new($handler); $client.Timeout=[TimeSpan]::FromSeconds(60)
    $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), 'https://api.paradox-interactive.com' + $Path)
    $response=$null
    try {
        [void]$request.Headers.TryAddWithoutValidation('Accept','application/json')
        [void]$request.Headers.TryAddWithoutValidation('User-Agent','MonarqueAbsoluPublisher/1')
        if ($Auth) { [void]$request.Headers.TryAddWithoutValidation('Authorization', ($Auth | ConvertTo-Json -Depth 10 -Compress)) }
        if ($Binary) {
            $request.Content=[Net.Http.ByteArrayContent]::new([byte[]]$Data)
            $request.Content.Headers.ContentType=[Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
        } elseif ($null -ne $Data) { $request.Content=[Net.Http.StringContent]::new(($Data | ConvertTo-Json -Depth 20 -Compress), [Text.Encoding]::UTF8, 'application/json') }
        try { $response=$client.SendAsync($request).GetAwaiter().GetResult() } catch { throw 'Paradox network request failed; publication status may be unknown' }
        if (-not $response.IsSuccessStatusCode) { throw "Paradox $Method $($Path.Split('?')[0]) returned HTTP $([int]$response.StatusCode)" }
        $text=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        try { $result=$text ? (ConvertFrom-Json -AsHashtable $text) : @{} } catch { throw 'Unexpected Paradox response format; check the item before retrying' }
        if ($result.ContainsKey('result') -and $result.result -cnotin @('OK','ok',$true,$null)) { throw 'Paradox returned a non-success result; check the item before retrying' }
        $result
    } finally {
        if ($response) { $response.Dispose() }; $request.Dispose(); $client.Dispose()
    }
}
function Get-LauncherStorageKey([string]$RootPath = (Join-Path $HOME 'Library/Application Support/Paradox Interactive')) {
    $versions=@(Get-ChildItem -LiteralPath $RootPath -Directory -Filter 'launcher-v2*' | Where-Object { $_.Name -match '^launcher-v2\.\d+\.\d+(?:\.\d+)*$' } | Sort-Object { [version]($_.Name -replace '^launcher-v2\.','') } -Descending)
    foreach ($directory in $versions) {
        $archive=Join-Path $directory.FullName 'Paradox Launcher.app/Contents/Resources/app.asar'
        if (-not (Test-Path -LiteralPath $archive)) { continue }
        $reader=[IO.BinaryReader]::new([IO.File]::OpenRead($archive))
        try {
            $null=$reader.ReadUInt32(); $headerSize=$reader.ReadUInt32(); $null=$reader.ReadUInt32(); $jsonSize=$reader.ReadUInt32()
            if ($jsonSize -gt 67108864 -or 8L+$headerSize -gt $reader.BaseStream.Length) { throw 'Invalid launcher ASAR header' }
            $header=ConvertFrom-Json -AsHashtable ([Text.Encoding]::UTF8.GetString($reader.ReadBytes($jsonSize)))
            $entry=$header.files.dist.files.main.files['index.mjs']
            if (-not $entry) { continue }
            if ([long]$entry.size -gt 67108864) { throw 'Invalid launcher source size' }
            [void]$reader.BaseStream.Seek(8L + $headerSize + [long]$entry.offset, [IO.SeekOrigin]::Begin)
            $source=[Text.Encoding]::UTF8.GetString($reader.ReadBytes([int]$entry.size))
            $match=[regex]::Match($source, '\w+="session\.js",\w+="([A-Fa-f0-9]{64})"')
            if ($match.Success -and $source.Contains('aes-256-cbc')) { return $match.Groups[1].Value }
        } finally { $reader.Dispose() }
    }
    throw 'Unsupported launcher storage format. Supply PDX_SESSION_TOKEN instead.'
}
function Convert-SessionCipher([byte[]]$Data, [string]$Key, [byte[]]$IV, [switch]$Decrypt) {
    $aes=[Security.Cryptography.Aes]::Create()
    try {
        $aes.Key=[Convert]::FromHexString($Key); $aes.IV=$IV
        $aes.Mode=[Security.Cryptography.CipherMode]::CBC; $aes.Padding=[Security.Cryptography.PaddingMode]::PKCS7
        $transform=$Decrypt ? $aes.CreateDecryptor() : $aes.CreateEncryptor()
        try { return ,$transform.TransformFinalBlock($Data,0,$Data.Length) } finally { $transform.Dispose() }
    } finally { $aes.Dispose() }
}
function Get-ParadoxAuth {
    if ($env:PDX_SESSION_TOKEN) { return @{ session=@{ token=$env:PDX_SESSION_TOKEN } } }
    if (-not (Test-Path -LiteralPath $script:ParadoxStorage)) { throw 'No saved Paradox session. Sign in with Remember me in the launcher.' }
    $key=Get-LauncherStorageKey
    try {
        $encrypted=[Convert]::FromHexString((Read-Text $script:ParadoxStorage).Trim())
        $saved=ConvertFrom-Json -AsHashtable ([Text.Encoding]::UTF8.GetString((Convert-SessionCipher $encrypted[16..($encrypted.Length-1)] $key $encrypted[0..15] -Decrypt)))
    } catch { throw 'Unable to read the launcher session; sign in through the launcher again' }
    if (-not $saved.refresh_token) { throw 'No saved renewal token; sign in with Remember me in the launcher.' }
    $result=Invoke-ParadoxRequest PUT '/accounts/sessions/launcher-v2' @{ renewal=@{ token=$saved.refresh_token } }
    $session=$result.session
    if (-not $session.token) { throw 'Paradox session renewal failed' }
    if ($session.refresh_token -and $session.refresh_token -cne $saved.refresh_token) {
        $saved.refresh_token=$session.refresh_token
        $iv=[Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
        $cipher=Convert-SessionCipher ([Text.Encoding]::UTF8.GetBytes(($saved | ConvertTo-Json -Compress -Depth 10))) $key $iv
        # Preserve the existing encrypted launcher file and its permissions on rotation.
        [IO.File]::WriteAllText($script:ParadoxStorage, [Convert]::ToHexString([byte[]]($iv + $cipher)).ToLowerInvariant())
    }
    @{ session=@{ token=$session.token } }
}
function Get-ParadoxMetadata($Auth) { (Invoke-ParadoxRequest GET '/mods?modId=161949' $Auth).modDetail }
function Test-ParadoxNotes($Detail, [string]$Notes) {
    foreach ($entry in $Detail.changelog) { if (([string]$entry.details).Trim() -ceq $Notes.Trim() -and [string]$entry.modVersion -ceq [string]$Detail.latestVersion) { return $true } }
    return $false
}
function Publish-Paradox([string]$Content, $Info, [int]$TimeoutSeconds=300) {
    $auth=Get-ParadoxAuth; $before=Get-ParadoxMetadata $auth
    if ($before.actions.canPublish -ne $true) { throw 'The signed-in Paradox account cannot publish mod 161949; refusing to upload' }
    if ($before.updating) { throw 'Paradox is processing an update; refusing a concurrent publication' }
    if ($before.displayName -cne $Info.Name -or $before.game -cne 'ck3') { throw 'Unexpected Paradox mod identity; refusing to upload' }
    if (Test-ParadoxNotes $before $Info.Notes) { Write-Host 'Paradox: this version and its notes are already published; no upload performed.'; return }
    $remoteName=$before.name; $filename="monarqueabsolu$($Info.Version.Replace('.','')).zip"
    $archive=Join-Path (Split-Path $Content -Parent) $filename
    [IO.Compression.ZipFile]::CreateFromDirectory($Content, $archive, [IO.Compression.CompressionLevel]::Optimal, $false)
    $payload=@{ modId='161949'; modName=$remoteName; gameName='ck3'; contentFileName=$filename; os='Any'; arch='Any'; longDescription=Read-Text (Join-Path $script:RepoRoot 'docs/paradox_mods_description.txt'); shortDescription=(Read-Text (Join-Path $script:RepoRoot 'docs/paradox_mods_short_description.txt')).Trim(); displayName=$Info.Name; tags=$Info.Tags; recommendedGameVersion=$Info.Required; changelogEntry=$Info.Notes }
    Write-Host 'Paradox: uploading the mod archive.'
    Invoke-ParadoxRequest PUT "/mods/content/ck3/$([uri]::EscapeDataString($remoteName))/content/$filename" $auth ([IO.File]::ReadAllBytes($archive)) -Binary > $null
    $result=Invoke-ParadoxRequest POST '/mods/publishUpdate' $auth $payload
    if ($result.modId -and [string]$result.modId -cne '161949') { throw 'Unexpected Paradox publication response; check the item before retrying' }
    Write-Host 'Paradox: update accepted; waiting for processing.'
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $after=Get-ParadoxMetadata $auth
        if (-not $after.updating -and $after.state -ceq 'published' -and $after.latestUpdate -cne $before.latestUpdate -and (Test-ParadoxNotes $after $Info.Notes)) { Write-Host 'Paradox: publication confirmed. https://mods.paradoxplaza.com/mods/161949/Any'; return }
        Start-Sleep -Seconds 5
    }
    throw 'Paradox processing timed out; check the item before retrying'
}
