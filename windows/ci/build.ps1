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

$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$cmdFile = Join-Path $tempRoot "pg_repack-build.cmd"

$clientLibs = @(
    (Join-Path $PgRoot "lib\libpq.lib"),
    (Join-Path $PgRoot "lib\libpgport.lib"),
    (Join-Path $PgRoot "lib\libpgcommon.lib"),
    (Join-Path $PgRoot "lib\libintl.lib")
) | Where-Object { Test-Path $_ }

$clientLibArgs = (($clientLibs | ForEach-Object { '"{0}"' -f $_ }) + @("advapi32.lib", "ws2_32.lib")) -join " "

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

cl /nologo /O2 /MD /DWIN32 /DWIN32_NO_STATUS /D_CRT_SECURE_NO_WARNINGS /DREPACK_VERSION=$version ^
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
