<#
.SYNOPSIS
    Builds the .NET worker and the PowerBuilder app, and assembles a runnable folder.

.DESCRIPTION
    1. Builds PbBackground (dotnet build).
    2. Builds MultiThreadingDemo.pbproj with PBAutoBuild (PBC approach).
    3. Moves the PBD next to the exe and copies the worker DLL there.
    4. Copies the worker DLL to the solution folder too, for running from the IDE.

.EXAMPLE
    pwsh -File build.ps1
.EXAMPLE
    pwsh -File build.ps1 -Platform 64
#>
param(
    # Build a 32-bit (the default) or 64-bit exe.
    [ValidateSet("32", "64")]
    [string]$Platform = "32",
    [string]$PBAutoBuild = "C:\Program Files (x86)\Appeon\PowerBuilder 25.0\pbautobuild250.exe"
)

$ErrorActionPreference = "Stop"

$root    = $PSScriptRoot
$project = Join-Path $root "MultiThreadingDemo.pbproj"
$outDir  = Join-Path $root "build\multithreadingdemo"
if ($Platform -eq "64") { $outDir += "-x64" }
New-Item -ItemType Directory -Force $outDir | Out-Null
$exe      = Join-Path $outDir "multithreadingdemo.exe"
$buildLog = Join-Path $outDir "build.log"

# --- .NET worker -----------------------------------------------------------
dotnet build (Join-Path $root "PbBackground\PbBackground.csproj") -c Release --nologo -v quiet
if ($LASTEXITCODE -ne 0) { Write-Host "dotnet build failed"; exit 1 }

# --- PowerBuilder ----------------------------------------------------------
$build = Start-Process -FilePath $PBAutoBuild -NoNewWindow -Wait -PassThru -RedirectStandardOutput $buildLog `
    -ArgumentList '/pbc', '/d', "`"$project`"", '/o', "`"$exe`"", '/x', $Platform
if ($build.ExitCode -ne 0 -or -not (Test-Path $exe)) {
    Write-Host "PowerBuilder build failed; see $buildLog"
    exit 1
}

# PBC writes the PBD beside its library folder; move it next to the exe.
Move-Item -Force (Join-Path $root "PowerBuilder\multithreadingdemo.pbd") $outDir

# --- Worker DLL ------------------------------------------------------------
$worker = Join-Path $root "PbBackground\bin\Release\net8.0"
foreach ($file in "PbBackground.dll", "PbBackground.deps.json") {
    Copy-Item (Join-Path $worker $file) $outDir
    Copy-Item (Join-Path $worker $file) $root
}

Write-Host "Built $exe"
