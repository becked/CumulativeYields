#Requires -Version 5.1
# deploy.ps1 - Deploy mod to local Old World mods folder for testing
#
# Prerequisites:
#   .env file with OLDWORLD_MODS_PATH set (and OLDWORLD_PATH for C# mods)
#
# Usage: .\scripts\deploy.ps1

param(
    [string]$ProjectDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ProjectDir) {
    $ProjectDir = Split-Path -Parent $ScriptDir
}
. "$ScriptDir\helpers.ps1"
Push-Location $ProjectDir

try {
    # Load .env
    if (-not (Import-DotEnv)) {
        Write-Error ".env file not found. Create a .env file with OLDWORLD_MODS_PATH set."
    }

    $ModsPath = [System.Environment]::GetEnvironmentVariable('OLDWORLD_MODS_PATH', 'Process')
    if (-not $ModsPath) {
        Write-Error "OLDWORLD_MODS_PATH not set in .env"
    }

    # Read mod name from ModInfo.xml
    $ModName = Get-XmlTagValue 'ModInfo.xml' 'displayName'
    if (-not $ModName) {
        Write-Error "Could not extract mod name from ModInfo.xml"
    }

    $ModFolder = Join-Path $ModsPath $ModName

    # Validate mod content (run as subprocess so validate's exit doesn't terminate us)
    $psExe = (Get-Process -Id $PID).Path
    & $psExe -NoProfile -ExecutionPolicy Bypass -File "$ScriptDir\validate.ps1" -ProjectDir $ProjectDir
    if ($LASTEXITCODE -ne 0) { exit 1 }

    # Build C# mod if project file exists
    $csproj = Get-ChildItem "$ProjectDir\*.csproj" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($csproj) {
        $owPath = [System.Environment]::GetEnvironmentVariable('OLDWORLD_PATH', 'Process')
        Invoke-CSharpBuild $csproj.FullName $owPath
    }

    Write-Host ""
    Write-Host "=== Deploying to mods folder ==="
    Write-Host "Target: $ModFolder"

    if (Test-Path $ModFolder) {
        Remove-Item $ModFolder -Recurse -Force
    }
    New-Item -ItemType Directory -Path $ModFolder -Force | Out-Null

    Copy-Item 'ModInfo.xml' $ModFolder
    if (Test-Path 'logo-512.png') {
        Copy-Item 'logo-512.png' $ModFolder
    }
    Copy-Item -Path 'Infos' -Destination (Join-Path $ModFolder 'Infos') -Recurse

    # Copy built DLLs if C# mod
    if ($csproj) {
        Copy-Item "$ProjectDir\bin\*.dll" $ModFolder
    }

    Write-Host ""
    Write-Host "=== Deployment complete ==="
    Write-Host "Deployed files:"
    Get-ChildItem $ModFolder -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($ModFolder.Length + 1)
        Write-Host "  $relativePath"
    }
} finally {
    Pop-Location
}
