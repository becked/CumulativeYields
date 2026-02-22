#Requires -Version 5.1
# workshop-upload.ps1 - Upload mod to Steam Workshop via SteamCMD
#
# Prerequisites:
#   1. Install SteamCMD (https://developer.valvesoftware.com/wiki/SteamCMD)
#   2. Have Steam Guard ready (you'll need to authenticate)
#   3. .env file with STEAM_USERNAME and optionally STEAM_WORKSHOP_ID
#   4. workshop.vdf template in project root
#
# Usage: .\scripts\workshop-upload.ps1 [-DryRun] [[-Changelog] "message"]
# Examples:
#   .\scripts\workshop-upload.ps1                         # Upload with changelog from CHANGELOG.md
#   .\scripts\workshop-upload.ps1 -Changelog "Fixed X"    # Upload with custom changelog
#   .\scripts\workshop-upload.ps1 -DryRun                 # Preview without uploading

param(
    [switch]$DryRun,
    [string]$Changelog = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
. "$ScriptDir\helpers.ps1"
Push-Location $ProjectDir

try {
    # Load .env
    if (-not (Import-DotEnv)) {
        Write-Error ".env file not found"
    }

    # Validate mod content (run as subprocess so validate's exit doesn't terminate us)
    $psExe = (Get-Process -Id $PID).Path
    & $psExe -NoProfile -ExecutionPolicy Bypass -File "$ScriptDir\validate.ps1"
    if ($LASTEXITCODE -ne 0) { exit 1 }

    # Build C# mod if project file exists
    $csproj = Get-ChildItem "$ProjectDir\*.csproj" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($csproj) {
        $owPath = [System.Environment]::GetEnvironmentVariable('OLDWORLD_PATH', 'Process')
        Invoke-CSharpBuild $csproj.FullName $owPath
    }

    # Read version from ModInfo.xml (single source of truth)
    $Version = Get-XmlTagValue 'ModInfo.xml' 'modversion'
    if (-not $Version) {
        Write-Error "Could not extract version from ModInfo.xml"
    }
    Write-Host "Version: $Version"

    # Changelog: use parameter if provided, otherwise extract from CHANGELOG.md
    if (-not $Changelog) {
        $Changelog = Get-ChangelogForVersion -Version $Version
    }

    # Format changenote with version prefix
    if ($Changelog) {
        $Changenote = "v$Version`n`n$Changelog"
    } else {
        $Changenote = "v$Version"
    }

    # Prepare workshop content folder
    Write-Host ""
    Write-Host "=== Preparing workshop content ==="
    if (Test-Path 'workshop_content') { Remove-Item 'workshop_content' -Recurse -Force }
    New-Item -ItemType Directory -Path 'workshop_content' -Force | Out-Null

    Copy-Item 'ModInfo.xml' 'workshop_content\'
    if (Test-Path 'logo-512.png') { Copy-Item 'logo-512.png' 'workshop_content\' }
    Copy-Item -Path 'Infos' -Destination 'workshop_content\Infos' -Recurse

    # Copy built DLLs if C# mod
    if ($csproj) {
        Copy-Item "$ProjectDir\bin\*.dll" 'workshop_content\'
    }

    Write-Host "Content staged:"
    Get-ChildItem 'workshop_content' -Recurse | ForEach-Object {
        Write-Host "  $($_.FullName.Substring((Resolve-Path 'workshop_content').Path.Length + 1))"
    }

    if ($DryRun) {
        Write-Host ""
        Write-Host "Changenote:"
        Write-Host $Changenote
        Write-Host ""
        Write-Host "Dry run complete - nothing was uploaded."
        Remove-Item 'workshop_content' -Recurse -Force
        exit 0
    }

    # Get publishedfileid from .env
    $PublishedId = [System.Environment]::GetEnvironmentVariable('STEAM_WORKSHOP_ID', 'Process')
    if (-not $PublishedId) { $PublishedId = '0' }

    # Check for workshop.vdf template
    Write-Host ""
    Write-Host "=== Generating upload VDF ==="

    if (-not (Test-Path 'workshop.vdf')) {
        Write-Error "workshop.vdf template not found. Create a workshop.vdf file in the project root."
    }

    # Convert mod-description.html to BBCode for Steam Workshop
    $Description = ''
    if (Test-Path 'mod-description.html') {
        $Description = (Get-Content 'mod-description.html' -Raw) `
            -replace '<p>(.*?)</p>', '$1' `
            -replace '<h2>(.*?)</h2>', '[h2]$1[/h2]' `
            -replace '<ul>', '[list]' `
            -replace '</ul>', '[/list]' `
            -replace '<li>(.*?)</li>', '[*] $1' `
            -replace '"', "'"
        Write-Host "Description converted from mod-description.html"
    } else {
        Write-Host "Warning: mod-description.html not found, skipping description"
    }

    # Sanitize changenote for VDF format
    $EscapedChangenote = $Changenote -replace '"', "'"

    # Build VDF by processing template line by line
    $ContentFolder = (Resolve-Path 'workshop_content').Path
    $LogoPath = Join-Path $ProjectDir 'logo-512.png'

    $vdfLines = Get-Content 'workshop.vdf' | ForEach-Object {
        switch -Regex ($_) {
            '"contentfolder"' { "`t`"contentfolder`"`t`t`"$ContentFolder`"" }
            '"previewfile"'   { "`t`"previewfile`"`t`t`"$LogoPath`"" }
            '"publishedfileid"' { "`t`"publishedfileid`"`t`t`"$PublishedId`"" }
            '"description"'   { "`t`"description`"`t`t`"$Description`"" }
            '"changenote"'    { "`t`"changenote`"`t`t`"$EscapedChangenote`"" }
            default           { $_ }
        }
    }
    $vdfLines | Set-Content 'workshop_upload.vdf' -Encoding ASCII

    $firstLine = ($Changenote -split "`n")[0]
    Write-Host "Changenote: $firstLine..."

    if ($PublishedId -and $PublishedId -ne '0') {
        Write-Host "Updating existing item: $PublishedId"
    } else {
        Write-Host "Creating new workshop item"
    }

    Write-Host ""
    Write-Host "=== Uploading to Steam Workshop ==="

    # Get Steam username
    $Username = [System.Environment]::GetEnvironmentVariable('STEAM_USERNAME', 'Process')
    if (-not $Username) {
        $Username = Read-Host "Steam username"
    }

    Write-Host "Logging in as: $Username"
    Write-Host "(You may be prompted for password and Steam Guard code)"
    Write-Host ""

    # Run SteamCMD
    $VdfFullPath = (Resolve-Path 'workshop_upload.vdf').Path
    & steamcmd +login $Username +workshop_build_item $VdfFullPath +quit

    # Cleanup temp file
    Remove-Item 'workshop_upload.vdf' -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "=== Upload complete ==="
    Write-Host ""
    Write-Host "If this was a new upload, note the 'publishedfileid' from the output above."
    Write-Host "Add it to your .env file as STEAM_WORKSHOP_ID for future updates."
} finally {
    Pop-Location
}
