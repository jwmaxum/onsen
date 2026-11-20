[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9_]{0,62}$')][string]$SourceDatabase,
    [Parameter(Mandatory)][string]$BackupDirectory,
    [ValidateSet('127.0.0.1','::1')][string]$DbHost = '127.0.0.1',
    [ValidateRange(1,65535)][int]$DbPort = 54322,
    [ValidatePattern('^[a-z][a-z0-9_]{0,62}$')][string]$DbUser = 'postgres',
    [switch]$RestoreDrill
)

$ErrorActionPreference = 'Stop'
if ($env:PGHOSTADDR -or $env:PGSERVICE) {
    throw 'Unset PGHOSTADDR and PGSERVICE so the connection stays on the explicit loopback endpoint.'
}
$destination = Get-Item -LiteralPath $BackupDirectory
if (!$destination.PSIsContainer -or $destination.PSProvider.Name -ne 'FileSystem') {
    throw 'BackupDirectory must be an existing private filesystem directory.'
}

function Invoke-Postgres([string]$Tool, [string[]]$ToolArgs) {
    & $Tool @ToolArgs
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE." }
}

$conn = @('--host', $DbHost, '--port', "$DbPort", '--username', $DbUser, '--no-password')
$psql = $conn + @('--no-psqlrc', '--quiet', '--tuples-only', '--no-align', '--set', 'ON_ERROR_STOP=1')
$contract = Join-Path $PSScriptRoot '../tests/db/restore-contract.sql'
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$backup = Join-Path $destination.FullName "onsen-$stamp-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
$null = New-Item -ItemType Directory -Path $backup
$partial = Join-Path $backup 'onsen.dump.partial'
$archive = Join-Path $backup 'onsen.dump'

$backupTimer = [Diagnostics.Stopwatch]::StartNew()
Invoke-Postgres 'pg_dump' ($conn + @('--dbname', $SourceDatabase, '--format=custom', '--strict-names',
    '--schema=core', '--schema=ingest', '--schema=api', '--file', $partial))
$backupTimer.Stop()
Move-Item -LiteralPath $partial -Destination $archive
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
$manifest = [ordered]@{
    captured_utc = $stamp
    scopes = @('core','ingest','api')
    archive_sha256 = $hash
    archive_bytes = (Get-Item -LiteralPath $archive).Length
    dump_seconds = [math]::Round($backupTimer.Elapsed.TotalSeconds, 2)
}
$manifestPath = Join-Path $backup 'manifest.json'
$manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8

if ($RestoreDrill) {
    $restoreDatabase = 'onsen_drill_' + [Guid]::NewGuid().ToString('N')
    $created = $false
    $restoreTimer = [Diagnostics.Stopwatch]::StartNew()
    try {
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -cne $hash) {
            throw 'Archive SHA-256 check failed.'
        }
        Invoke-Postgres 'createdb' ($conn + @('--maintenance-db', $SourceDatabase, '--template', 'template0', $restoreDatabase))
        $created = $true
        Invoke-Postgres 'psql' ($psql + @('--dbname', $restoreDatabase, '--command',
            'create schema extensions; create extension postgis with schema extensions;'))
        Invoke-Postgres 'pg_restore' ($conn + @('--dbname', $restoreDatabase, '--no-owner',
            '--single-transaction', '--exit-on-error', $archive))
        $expected = @(Invoke-Postgres 'psql' ($psql + @('--dbname', $SourceDatabase, '--file', $contract)))
        $restored = @(Invoke-Postgres 'psql' ($psql + @('--dbname', $restoreDatabase, '--file', $contract)))
        if (!$expected.Count -or (($expected -join "`n") -cne ($restored -join "`n"))) {
            throw 'Restored DB fingerprints differ from the source. Use a quiescent staging source for the rehearsal.'
        }
        $restoreTimer.Stop()
        $manifest.restore_verified = $true
        $manifest.restore_seconds = [math]::Round($restoreTimer.Elapsed.TotalSeconds, 2)
        $manifest.verified_groups = $restored.Count
        $manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8
        'PASS archive SHA-256, clean restore, database fingerprints and anonymous privileges'
    } finally {
        if ($created) { Invoke-Postgres 'dropdb' ($conn + @('--maintenance-db', $SourceDatabase, $restoreDatabase)) }
    }
}
Get-Item -LiteralPath $manifestPath | Select-Object -ExpandProperty FullName
