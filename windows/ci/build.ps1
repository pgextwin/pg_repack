[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PgRoot,

    [Parameter(Mandatory = $true)]
    [string]$UpstreamDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
$vswhere = Join-Path $programFilesX86 "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe was not found: $vswhere"
}

$vsRoot = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($vsRoot)) {
    throw "Visual Studio with the C++ x64 toolchain was not found."
}

$vsDevCmd = Join-Path $vsRoot "Common7\Tools\VsDevCmd.bat"
if (-not (Test-Path $vsDevCmd)) {
    throw "VsDevCmd.bat was not found: $vsDevCmd"
}

$meta = Get-Content (Join-Path $UpstreamDir "META.json") -Raw | ConvertFrom-Json
$version = [string]$meta.version
if ($version -ne "1.5.3") {
    throw "Unexpected pg_repack version: $version"
}

$libDir = Join-Path $UpstreamDir "lib"
$binDir = Join-Path $UpstreamDir "bin"
$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }

# pg_repack 1.5.3 predates PostgreSQL 18's extended module-magic support.
# Apply the exact source-level compatibility change introduced upstream by
# reorg/pg_repack commit 82120316e840773e4521314917a97c26b4b5f520.
$repackSource = Join-Path $libDir "repack.c"
$repackText = Get-Content $repackSource -Raw

$versionMacroBlock = @'
#ifdef REPACK_VERSION
/* macro trick to stringify a macro expansion */
#define xstr(s) str(s)
#define str(s) #s
#define LIBRARY_VERSION xstr(REPACK_VERSION)
#else
#define LIBRARY_VERSION "unknown"
#endif
'@

if (-not $repackText.Contains($versionMacroBlock)) {
    throw "Expected pg_repack 1.5.3 version macro block was not found."
}
$repackText = $repackText.Replace($versionMacroBlock, "")

$magicBlock = @'
#ifdef REPACK_VERSION
/* macro trick to stringify a macro expansion */
#define xstr(s) str(s)
#define str(s) #s
#define LIBRARY_VERSION xstr(REPACK_VERSION)
#else
#define LIBRARY_VERSION "unknown"
#endif

#if PG_VERSION_NUM >= 180000
PG_MODULE_MAGIC_EXT(
    .name = "pg_repack",
    .version = LIBRARY_VERSION
);
#else
PG_MODULE_MAGIC;
#endif
'@

$magicMarker = "PG_MODULE_MAGIC;"
$magicIndex = $repackText.IndexOf($magicMarker, [StringComparison]::Ordinal)
if ($magicIndex -lt 0) {
    throw "Expected pg_repack 1.5.3 PG_MODULE_MAGIC marker was not found."
}
if ($repackText.IndexOf($magicMarker, $magicIndex + $magicMarker.Length, [StringComparison]::Ordinal) -ge 0) {
    throw "More than one PG_MODULE_MAGIC marker was found; refusing an ambiguous patch."
}
$repackText = $repackText.Substring(0, $magicIndex) + $magicBlock + $repackText.Substring($magicIndex + $magicMarker.Length)
[IO.File]::WriteAllText($repackSource, $repackText, [Text.UTF8Encoding]::new($false))

# pgut.h is shared by backend and frontend code. On Windows the client side
# must include postgres_fe.h so PostgreSQL's frontend-specific Win32 mappings
# are selected (notably the native Winsock select path rather than the backend
# pgwin32_select wrapper).
$pgutHeader = Join-Path $binDir "pgut\pgut.h"
$pgutHeaderText = Get-Content $pgutHeader -Raw
$plainCHInclude = '#include "c.h"'
$frontendCHInclude = @'
#ifndef WIN32
#include "c.h"
#else
#include "postgres_fe.h"
#endif
'@
if ($pgutHeaderText.Contains($plainCHInclude)) {
    $pgutHeaderText = $pgutHeaderText.Replace($plainCHInclude, $frontendCHInclude.TrimEnd())
    [IO.File]::WriteAllText($pgutHeader, $pgutHeaderText, [Text.UTF8Encoding]::new($false))
}
elseif (-not $pgutHeaderText.Contains('#include "postgres_fe.h"')) {
    throw "Expected pgut.h c.h include was not found; review upstream before continuing."
}

$controlTemplate = Join-Path $libDir "pg_repack.control.in"
$sqlTemplate = Join-Path $libDir "pg_repack.sql.in"
$controlOut = Join-Path $libDir "pg_repack.control"
$sqlOut = Join-Path $libDir "pg_repack--$version.sql"

(Get-Content $controlTemplate -Raw).Replace("REPACK_VERSION", $version) |
    Set-Content -Path $controlOut -Encoding utf8

$sql = (Get-Content $sqlTemplate -Raw).Replace("REPACK_VERSION", $version)
$sql = $sql.Replace("relhasoids", "false")
$sql | Set-Content -Path $sqlOut -Encoding utf8

$exports = @()
foreach ($line in Get-Content (Join-Path $libDir "exports.txt")) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0) { continue }
    $symbol = ($trimmed -split '\s+')[0]
    if (-not [string]::IsNullOrWhiteSpace($symbol)) {
        $exports += $symbol
    }
}
if ($exports.Count -eq 0) {
    throw "No DLL exports were found in upstream lib/exports.txt."
}

$defPath = Join-Path $libDir "pg_repack.pgextwin.def"
(@("LIBRARY pg_repack", "EXPORTS") + @($exports | ForEach-Object { "    $_" })) |
    Set-Content -Path $defPath -Encoding ascii

$includeArgs = @(
    ('/I"{0}\include\server\port\win32_msvc"' -f $PgRoot),
    ('/I"{0}\include\server\port\win32"' -f $PgRoot),
    ('/I"{0}\include\server"' -f $PgRoot),
    ('/I"{0}\include\internal"' -f $PgRoot),
    ('/I"{0}\include"' -f $PgRoot)
) -join " "

$libpq = Join-Path $PgRoot "lib\libpq.lib"
if (-not (Test-Path $libpq)) {
    throw "Required PostgreSQL libpq import library was not found: $libpq"
}

$pgport = Join-Path $PgRoot "lib\libpgport.lib"
$pgcommon = Join-Path $PgRoot "lib\libpgcommon.lib"

# Resolve the exact installed PostgreSQL minor for license provenance and,
# when needed, for rebuilding internal frontend support archives.
$pgConfig = Join-Path $PgRoot "bin\pg_config.exe"
if (-not (Test-Path $pgConfig)) {
    throw "pg_config.exe was not found: $pgConfig"
}

$pgVersionText = (& $pgConfig --version).Trim()
if ($LASTEXITCODE -ne 0 -or $pgVersionText -notmatch '^PostgreSQL\s+(\d+)\.(\d+)') {
    throw "Could not parse PostgreSQL version from pg_config.exe: '$pgVersionText'"
}

$pgMajor = [int]$Matches[1]
$pgMinor = [int]$Matches[2]
$pgSourceTag = "REL_{0}_{1}" -f $pgMajor, $pgMinor
$pgSourceDir = Join-Path $tempRoot ("postgresql-{0}.{1}-source" -f $pgMajor, $pgMinor)
$pgSupportBuildDir = Join-Path $tempRoot ("postgresql-{0}.{1}-frontend-support" -f $pgMajor, $pgMinor)

foreach ($dir in @($pgSourceDir, $pgSupportBuildDir)) {
    if (Test-Path $dir) {
        Remove-Item $dir -Recurse -Force
    }
}

Write-Host "Resolving official PostgreSQL source $pgMajor.$pgMinor ($pgSourceTag)."
& git clone --quiet --depth 1 --branch $pgSourceTag https://github.com/postgres/postgres.git $pgSourceDir
if ($LASTEXITCODE -ne 0) {
    throw "Failed to clone official PostgreSQL source tag $pgSourceTag."
}

$pgSourceSha = (& git -C $pgSourceDir rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($pgSourceSha)) {
    throw "Failed to resolve PostgreSQL source commit for $pgSourceTag."
}
Write-Host "PostgreSQL source provenance: postgres/postgres $pgSourceTag @ $pgSourceSha"

# pg_repack.exe statically links PostgreSQL frontend support code either from
# the EDB installation or from the matching official source build. Preserve
# the PostgreSQL license notice in every package in both cases.
$postgresCopyright = Join-Path $pgSourceDir "COPYRIGHT"
if (-not (Test-Path $postgresCopyright)) {
    throw "PostgreSQL COPYRIGHT was not found in the official source checkout."
}
Copy-Item $postgresCopyright (Join-Path $UpstreamDir "POSTGRESQL-COPYRIGHT") -Force

# Modern EDB Windows installers do not ship the internal libpgport/libpgcommon
# archives. PostgreSQL 16+ has the official Meson Windows build path, so build
# only those two frontend support archives when needed. PostgreSQL 14/15 are
# first tested against the libraries supplied by their EDB installations.
if (-not (Test-Path $pgport) -or -not (Test-Path $pgcommon)) {
    if ($pgMajor -lt 16) {
        throw "EDB PostgreSQL $pgMajor does not provide libpgport/libpgcommon; a legacy MSVC frontend-support fallback is required."
    }

    Write-Host "EDB install does not contain libpgport/libpgcommon; building frontend support from PostgreSQL $pgMajor.$pgMinor."

    $python = (Get-Command python.exe -ErrorAction Stop).Source
    & $python -m pip install --disable-pip-version-check --quiet "meson==1.8.3" "ninja==1.11.1.4"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install pinned Meson/Ninja build tooling."
    }

    if (-not (Get-Command win_bison.exe -ErrorAction SilentlyContinue) -or
        -not (Get-Command win_flex.exe -ErrorAction SilentlyContinue)) {
        # Chocolatey package availability can vary by runner/source. Fetch the exact
        # upstream archive used by the approved winflexbison3 2.5.24.20210105
        # package and verify its immutable SHA256 BEFORE extracting/executing.
        $winFlexVersion = "2.5.24"
        $winFlexArchive = Join-Path $tempRoot "win_flex_bison-$winFlexVersion.zip"
        $winFlexRoot = Join-Path $tempRoot "winflexbison-$winFlexVersion"
        $winFlexUrl = "https://github.com/lexxmark/winflexbison/releases/download/v$winFlexVersion/win_flex_bison-$winFlexVersion.zip"
        $winFlexSha256 = "39C6086CE211D5415500ACC5ED2D8939861CA1696AEE48909C7F6DAF5122B505"
        Invoke-WebRequest -Uri $winFlexUrl -OutFile $winFlexArchive -ErrorAction Stop
        $actualWinFlexSha = (Get-FileHash -Path $winFlexArchive -Algorithm SHA256).Hash
        if ($actualWinFlexSha -ne $winFlexSha256) {
            throw "WinFlexBison upstream ZIP SHA-256 mismatch: $actualWinFlexSha"
        }
        Expand-Archive -Path $winFlexArchive -DestinationPath $winFlexRoot -Force
        $winBison = Get-ChildItem $winFlexRoot -Recurse -Filter win_bison.exe -File | Select-Object -First 1
        $winFlex = Get-ChildItem $winFlexRoot -Recurse -Filter win_flex.exe -File | Select-Object -First 1
        if ($null -eq $winBison -or $null -eq $winFlex -or $winBison.DirectoryName -ne $winFlex.DirectoryName) {
            throw "Pinned WinFlexBison executables were not found together after verified extraction."
        }
        $env:PATH = "$($winBison.DirectoryName);$env:PATH"
        Write-Host "Using checksum-verified WinFlexBison $winFlexVersion from its original release archive."
    }

    $supportCmd = Join-Path $tempRoot "postgresql-frontend-support-build.cmd"
    @"
@echo off
call "$vsDevCmd" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%
"$python" -m mesonbuild.mesonmain setup "$pgSupportBuildDir" "$pgSourceDir" --buildtype=release -Dssl=none -Dnls=disabled -Dicu=disabled -Dldap=disabled -Dgssapi=disabled -Dlibxml=disabled -Dlibxslt=disabled -Dlz4=disabled -Dzstd=disabled -Dzlib=disabled -Dreadline=disabled -Dllvm=disabled -Dplperl=disabled -Dplpython=disabled -Dpltcl=disabled -Ddocs=disabled -Ddtrace=disabled
if errorlevel 1 exit /b %errorlevel%
"$python" -m mesonbuild.mesonmain compile -C "$pgSupportBuildDir" libpgport libpgcommon
if errorlevel 1 exit /b %errorlevel%
"@ | Set-Content -Path $supportCmd -Encoding ascii

    & cmd.exe /d /c $supportCmd
    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL frontend support library build failed with exit code $LASTEXITCODE."
    }

    # PostgreSQL's Meson targets may use .a names even with the MSVC toolchain.
    # Both .a and .lib outputs here are COFF static archives.
    $pgportItem = Get-ChildItem -Path $pgSupportBuildDir -Recurse -File |
        Where-Object { $_.Name -in @("libpgport.a", "libpgport.lib") } |
        Select-Object -First 1
    $pgcommonItem = Get-ChildItem -Path $pgSupportBuildDir -Recurse -File |
        Where-Object { $_.Name -in @("libpgcommon.a", "libpgcommon.lib") } |
        Select-Object -First 1
    if ($null -eq $pgportItem -or $null -eq $pgcommonItem) {
        throw "Meson completed but libpgport/libpgcommon static archives were not found in the PostgreSQL build tree."
    }

    $pgport = $pgportItem.FullName
    $pgcommon = $pgcommonItem.FullName
    Write-Host "Built PostgreSQL frontend support archives: $pgport ; $pgcommon"
}
else {
    Write-Host "Using PostgreSQL frontend support libraries supplied by the installation: $pgport ; $pgcommon"
}

$optionalClientLibs = @(
    (Join-Path $PgRoot "lib\libintl.lib")
) | Where-Object { Test-Path $_ }

$clientLibs = @($libpq, $pgport, $pgcommon) + @($optionalClientLibs)
Write-Host ("PostgreSQL frontend link libraries: " + ($clientLibs -join ", "))
$clientLibArgs = (($clientLibs | ForEach-Object { '"{0}"' -f $_ }) + @("advapi32.lib", "ws2_32.lib")) -join " "

$cmdFile = Join-Path $tempRoot "pg_repack-build.cmd"
$cmd = @"
@echo off
call "$vsDevCmd" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%
cd /d "$UpstreamDir"

cl /nologo /O2 /MD /DWIN32 /DWIN32_NO_STATUS /D_CRT_SECURE_NO_WARNINGS /DREPACK_VERSION=$version ^
  $includeArgs /I"$libDir" /I"$libDir\pgut" ^
  /c "$libDir\repack.c" /Fo"$libDir\repack.obj"
if errorlevel 1 exit /b %errorlevel%

cl /nologo /O2 /MD /DWIN32 /DWIN32_NO_STATUS /D_CRT_SECURE_NO_WARNINGS ^
  $includeArgs /I"$libDir" /I"$libDir\pgut" ^
  /c "$libDir\pgut\pgut-spi.c" /Fo"$libDir\pgut-spi.obj"
if errorlevel 1 exit /b %errorlevel%

link /nologo /DLL /OUT:"$libDir\pg_repack.dll" /DEF:"$defPath" ^
  "$libDir\repack.obj" "$libDir\pgut-spi.obj" ^
  "$PgRoot\lib\postgres.lib"
if errorlevel 1 exit /b %errorlevel%

cl /nologo /O2 /MD /DWIN32 /DWIN32_NO_STATUS /D_CRT_SECURE_NO_WARNINGS /DFRONTEND /DREPACK_VERSION=$version ^
  $includeArgs /I"$binDir" /I"$binDir\pgut" ^
  /c "$binDir\pg_repack.c" /Fo"$binDir\pg_repack.obj"
if errorlevel 1 exit /b %errorlevel%

cl /nologo /O2 /MD /DWIN32 /DWIN32_NO_STATUS /D_CRT_SECURE_NO_WARNINGS ^
  $includeArgs /I"$binDir" /I"$binDir\pgut" ^
  /c "$binDir\pgut\pgut.c" /Fo"$binDir\pgut.obj"
if errorlevel 1 exit /b %errorlevel%

cl /nologo /O2 /MD /DWIN32 /DWIN32_NO_STATUS /D_CRT_SECURE_NO_WARNINGS ^
  $includeArgs /I"$binDir" /I"$binDir\pgut" ^
  /c "$binDir\pgut\pgut-fe.c" /Fo"$binDir\pgut-fe.obj"
if errorlevel 1 exit /b %errorlevel%

link /nologo /OUT:"$binDir\pg_repack.exe" ^
  "$binDir\pg_repack.obj" "$binDir\pgut.obj" "$binDir\pgut-fe.obj" ^
  $clientLibArgs
if errorlevel 1 exit /b %errorlevel%
"@

$cmd | Set-Content -Path $cmdFile -Encoding ascii

& cmd.exe /d /c $cmdFile
if ($LASTEXITCODE -ne 0) {
    throw "pg_repack MSVC build failed with exit code $LASTEXITCODE."
}

foreach ($path in @(
    (Join-Path $libDir "pg_repack.dll"),
    (Join-Path $binDir "pg_repack.exe"),
    $controlOut,
    $sqlOut
)) {
    if (-not (Test-Path $path)) {
        throw "Expected pg_repack build output was not produced: $path"
    }
}

& (Join-Path $binDir "pg_repack.exe") --version
if ($LASTEXITCODE -ne 0) {
    throw "Built pg_repack.exe failed its --version check."
}
