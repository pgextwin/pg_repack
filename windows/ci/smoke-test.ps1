[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PgRoot,

    [Parameter(Mandatory = $true)]
    [int]$PgPort,

    [Parameter(Mandatory = $true)]
    [int]$PostgreSqlMajor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$initdb = Join-Path $PgRoot "bin\initdb.exe"
$pgCtl = Join-Path $PgRoot "bin\pg_ctl.exe"
$pgIsReady = Join-Path $PgRoot "bin\pg_isready.exe"
$psql = Join-Path $PgRoot "bin\psql.exe"
$repack = Join-Path $PgRoot "bin\pg_repack.exe"

$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$dataDir = Join-Path $tempRoot "pg_repack-pg$PostgreSqlMajor-data"
$logFile = Join-Path $tempRoot "pg_repack-pg$PostgreSqlMajor.log"
$setupSql = Join-Path $tempRoot "pg_repack-pg$PostgreSqlMajor-setup.sql"

if (Test-Path $dataDir) {
    Remove-Item $dataDir -Recurse -Force
}

& $initdb -D $dataDir -U postgres -A trust --encoding=UTF8 --no-locale
if ($LASTEXITCODE -ne 0) {
    throw "initdb failed."
}

function Show-PostgresLog {
    if (Test-Path $logFile) {
        Write-Host "----- PostgreSQL log -----"
        Get-Content $logFile -Tail 300
        Write-Host "--------------------------"
    }
}

function Wait-Postgres {
    for ($i = 0; $i -lt 45; $i++) {
        & $pgIsReady -h 127.0.0.1 -p $PgPort -q
        if ($LASTEXITCODE -eq 0) {
            return
        }
        Start-Sleep -Seconds 2
    }
    Show-PostgresLog
    throw "Temporary PostgreSQL cluster did not become ready."
}

try {
    & $pgCtl -D $dataDir -l $logFile -o "-p $PgPort" start
    if ($LASTEXITCODE -ne 0) {
        Show-PostgresLog
        throw "Failed to start PostgreSQL."
    }

    Wait-Postgres

    @'
CREATE EXTENSION pg_repack;
DROP TABLE IF EXISTS public.pgextwin_repack_probe;
CREATE TABLE public.pgextwin_repack_probe (
    id integer PRIMARY KEY,
    payload text NOT NULL
);
INSERT INTO public.pgextwin_repack_probe
SELECT g, repeat(md5(g::text), 4)
FROM generate_series(1, 20000) AS g;
UPDATE public.pgextwin_repack_probe
SET payload = payload || '-updated'
WHERE id % 3 = 0;
DELETE FROM public.pgextwin_repack_probe
WHERE id % 7 = 0;
ANALYZE public.pgextwin_repack_probe;
'@ | Set-Content -Path $setupSql -Encoding utf8

    & $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -v ON_ERROR_STOP=1 -f $setupSql
    if ($LASTEXITCODE -ne 0) {
        throw "pg_repack setup SQL failed."
    }

    $beforeCount = (& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT count(*) FROM public.pgextwin_repack_probe;") | Select-Object -Last 1
    $beforeNode = (& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT pg_relation_filenode('public.pgextwin_repack_probe'::regclass);") | Select-Object -Last 1

    & $repack -h 127.0.0.1 -p $PgPort -U postgres -d postgres --table public.pgextwin_repack_probe --no-order
    if ($LASTEXITCODE -ne 0) {
        Show-PostgresLog
        throw "pg_repack.exe failed to repack the probe table."
    }

    $afterCount = (& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT count(*) FROM public.pgextwin_repack_probe;") | Select-Object -Last 1
    $afterNode = (& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT pg_relation_filenode('public.pgextwin_repack_probe'::regclass);") | Select-Object -Last 1
    $version = (& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT repack.version();") | Select-Object -Last 1

    if (([string]$beforeCount).Trim() -ne ([string]$afterCount).Trim()) {
        throw "Row count changed during pg_repack: before=$beforeCount after=$afterCount"
    }

    if (([string]$beforeNode).Trim() -eq ([string]$afterNode).Trim()) {
        throw "Relation filenode did not change; the probe table was not physically repacked."
    }

    if (([string]$version).Trim() -notmatch '^pg_repack 1\.5\.3$') {
        throw "Unexpected extension version output: $version"
    }

    & $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -v ON_ERROR_STOP=1 -c "DROP TABLE public.pgextwin_repack_probe; DROP EXTENSION pg_repack;"
    if ($LASTEXITCODE -ne 0) {
        throw "pg_repack smoke-test cleanup failed."
    }
}
catch {
    Show-PostgresLog
    throw
}
finally {
    if (Test-Path (Join-Path $dataDir "postmaster.pid")) {
        & $pgCtl -D $dataDir -m fast stop
    }
}
