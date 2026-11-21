[CmdletBinding(DefaultParameterSetName = 'Sync')]
param(
    [Parameter(ParameterSetName = 'Initialize', Mandatory)] [switch]$InitializePublisher,
    [Parameter(ParameterSetName = 'Install', Mandatory)] [switch]$RegisterTask
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Split-Path -Parent $PSScriptRoot
$node = (Get-Command node.exe -CommandType Application | Select-Object -First 1).Source
$dataDirectory = Join-Path $repoRoot '.wrangler/firebase-publisher'
$credentialPath = Join-Path $dataDirectory 'session.xml'
$statePath = Join-Path $dataDirectory 'state.json'
$logPath = Join-Path $dataDirectory 'last-run.json'
$workerConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'wrangler.jsonc') -Raw | ConvertFrom-Json
$environment = Get-Content -LiteralPath (Join-Path $repoRoot '.env.local')

function Read-Setting([string]$Name) {
    foreach ($line in $environment) {
        if ($line -match ('^' + [regex]::Escape($Name) + '=([^\r\n]+)$')) {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
}

function Write-AtomicJson([string]$Path, $Value) {
    $temporary = "$Path.tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 12 -Compress))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Save-Session([string]$Uid, [string]$Token) {
    if ($Uid -notmatch '^[a-zA-Z0-9_-]{1,128}$' -or !$Token) { throw 'Invalid Firebase publisher session' }
    $secret = ConvertTo-SecureString $Token -AsPlainText -Force
    $credential = [pscredential]::new($Uid, $secret)
    $temporary = "$credentialPath.tmp"
    $credential | Export-Clixml -LiteralPath $temporary
    Move-Item -LiteralPath $temporary -Destination $credentialPath -Force
}

New-Item -Path $dataDirectory -ItemType Directory -Force | Out-Null
if ($RegisterTask) {
    if (!(Test-Path -LiteralPath $credentialPath)) { throw 'Initialize the Firebase publisher first' }
    $taskName = 'Onsen Firebase Catalog Publisher'
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
    $powershell = (Get-Command powershell.exe -CommandType Application | Select-Object -First 1).Source
    $scriptArgument = '-WindowStyle Hidden -File "' + $PSCommandPath + '"'
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned ' + $scriptArgument
    $action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $repoRoot
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        $previousArguments = '-NoProfile -NonInteractive ' + $scriptArgument
        $sameCommand = @($existing.Actions).Count -eq 1 -and $existing.Actions.Execute -eq $powershell -and
            $existing.Actions.Arguments -in @($arguments, $previousArguments)
        $sameDirectory = $existing.Actions.WorkingDirectory -eq $repoRoot
        $taskUser = $existing.Principal.UserId
        if ($taskUser -notmatch '^S-\d-') {
            if ($taskUser -notlike '*\*') { $taskUser = "$env:COMPUTERNAME\$taskUser" }
            $taskUser = [Security.Principal.NTAccount]::new($taskUser).Translate([Security.Principal.SecurityIdentifier]).Value
        }
        $sameUser = $taskUser -eq $identity.User.Value
        if (!($sameCommand -and $sameDirectory -and $sameUser)) {
            throw 'A scheduled task with the same name is configured differently'
        }
        if ($existing.Actions.Arguments -eq $previousArguments) {
            Set-ScheduledTask -TaskName $taskName -Action $action | Out-Null
        }
        Start-ScheduledTask -TaskName $taskName
        return
    }
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Publish reviewed Onsen catalog releases to Firebase.' | Out-Null
    Start-ScheduledTask -TaskName $taskName
    return
}

$lock = [IO.File]::Open((Join-Path $dataDirectory 'publisher.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $request = @{
        source = Read-Setting 'ONSEN_POSTGREST_URL'
        database = $workerConfig.vars.ONSEN_FIREBASE_DATABASE_URL
        apiKey = Read-Setting 'NEXT_PUBLIC_FIREBASE_API_KEY'
        initialize = [bool]$InitializePublisher
    }
    if (!$request.apiKey -or !$request.source -or !$request.database) { throw 'Publisher environment is incomplete' }
    if ($InitializePublisher) {
        if (Test-Path -LiteralPath $credentialPath) { throw 'A Firebase publisher session already exists' }
    } else {
        $credential = Import-Clixml -LiteralPath $credentialPath
        $request.credential = @{ uid = $credential.UserName; refreshToken = $credential.GetNetworkCredential().Password }
        if (Test-Path -LiteralPath $statePath) { $request.state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
    }

    $responseText = ($request | ConvertTo-Json -Depth 10 -Compress) | & $node (Join-Path $PSScriptRoot 'sync-firebase-catalog.mjs') --windows-publisher-pipe
    $exitCode = $LASTEXITCODE
    $result = $responseText | ConvertFrom-Json
    if ($result.refreshToken) {
        $uid = if ($InitializePublisher) { $result.uid } else { $request.credential.uid }
        Save-Session -Uid $uid -Token $result.refreshToken
    }
    if ($InitializePublisher -and $exitCode -eq 0 -and $result.status -eq 'created') {
        [pscustomobject]@{ status = 'created'; uid = $result.uid } | ConvertTo-Json -Compress
        return
    }
    if ($exitCode -eq 0 -and $result.state) { Write-AtomicJson -Path $statePath -Value $result.state }
    $log = @{ finishedAt = [DateTimeOffset]::UtcNow.ToString('o'); status = $result.status; summary = $result.summary; error = $result.error }
    Write-AtomicJson -Path $logPath -Value $log
    $log | ConvertTo-Json -Depth 12 -Compress
    if ($exitCode -ne 0) { exit $exitCode }
} finally {
    $lock.Dispose()
}
