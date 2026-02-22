#Requires -Version 5.1
# bump-version.ps1 - Bump the mod version in ModInfo.xml and scaffold CHANGELOG.md
#
# Usage:
#   .\scripts\bump-version.ps1 patch    # 0.1.0 -> 0.1.1
#   .\scripts\bump-version.ps1 minor    # 0.1.0 -> 0.2.0
#   .\scripts\bump-version.ps1 major    # 0.1.0 -> 1.0.0
#   .\scripts\bump-version.ps1 1.2.3    # Set explicit version

param(
    [Parameter(Position = 0)]
    [string]$BumpType = '',
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
    if (-not (Test-Path 'ModInfo.xml')) {
        Write-Error "ModInfo.xml not found"
    }

    # Extract current version
    $Current = Get-XmlTagValue 'ModInfo.xml' 'modversion'
    if (-not $Current) {
        Write-Error "Could not extract version from ModInfo.xml"
    }

    Write-Host "Current version: $Current"

    # Parse version components
    $parts = $Current -split '\.'
    if ($parts.Count -ne 3) {
        Write-Error "Current version '$Current' is not valid semver (expected X.Y.Z)"
    }
    [int]$Major = $parts[0]
    [int]$Minor = $parts[1]
    [int]$Patch = $parts[2]

    # Determine new version
    switch ($BumpType) {
        'major' {
            $Major++
            $Minor = 0
            $Patch = 0
        }
        'minor' {
            $Minor++
            $Patch = 0
        }
        'patch' {
            $Patch++
        }
        '' {
            Write-Host "Usage: bump-version.ps1 <major|minor|patch|X.Y.Z>"
            Write-Host ""
            Write-Host "Examples:"
            Write-Host "  .\scripts\bump-version.ps1 patch    # $Current -> $Major.$Minor.$($Patch + 1)"
            Write-Host "  .\scripts\bump-version.ps1 minor    # $Current -> $Major.$($Minor + 1).0"
            Write-Host "  .\scripts\bump-version.ps1 major    # $Current -> $($Major + 1).0.0"
            Write-Host "  .\scripts\bump-version.ps1 1.2.3    # Set explicit version"
            exit 1
        }
        default {
            if ($BumpType -match '^\d+\.\d+\.\d+$') {
                $explicit = $BumpType -split '\.'
                [int]$Major = $explicit[0]
                [int]$Minor = $explicit[1]
                [int]$Patch = $explicit[2]
            } else {
                Write-Error "Invalid version format '$BumpType'. Expected major, minor, patch, or X.Y.Z"
            }
        }
    }

    $NewVersion = "$Major.$Minor.$Patch"
    Write-Host "New version: $NewVersion"

    # Update ModInfo.xml
    if (-not (Set-XmlTagValue 'ModInfo.xml' 'modversion' $NewVersion)) {
        Write-Error "Failed to update modversion in ModInfo.xml"
    }
    Write-Host "Updated ModInfo.xml: $Current -> $NewVersion"

    # Scaffold CHANGELOG.md entry
    if (Test-Path 'CHANGELOG.md') {
        $Today = Get-Date -Format 'yyyy-MM-dd'
        $NewEntry = "## [$NewVersion] - $Today"

        $lines = Get-Content 'CHANGELOG.md'
        $inserted = $false
        $result = @()
        foreach ($line in $lines) {
            if (-not $inserted -and $line -match '^## \[') {
                $result += $NewEntry
                $result += ''
                $result += '- '
                $result += ''
                $inserted = $true
            }
            $result += $line
        }
        $result | Set-Content 'CHANGELOG.md'

        Write-Host "Scaffolded CHANGELOG.md entry: $NewEntry"
    } else {
        Write-Host ""
        Write-Host "Note: CHANGELOG.md not found. Remember to document changes for $NewVersion"
    }

    # Sync modbuild from game installation (optional)
    # Only runs when OLDWORLD_PATH is set and ModInfo.xml has a <modbuild> tag
    if (Test-Path '.env') {
        Import-DotEnv | Out-Null
    }

    $OldWorldPath = [System.Environment]::GetEnvironmentVariable('OLDWORLD_PATH', 'Process')
    $OldBuild = Get-XmlTagValue 'ModInfo.xml' 'modbuild'

    if ($OldWorldPath -and $OldBuild) {
        $GameBuild = $null

        $Plist = Join-Path $OldWorldPath 'OldWorld.app/Contents/Info.plist'
        if (Test-Path $Plist) {
            try {
                $raw = & defaults read $Plist CFBundleShortVersionString 2>$null
                if ($raw) {
                    $GameBuild = ($raw -split '\s')[0]
                }
            } catch {
                Write-Verbose "defaults command not available (e.g., Windows) - skip"
            }
        }

        if ($GameBuild) {
            if ($OldBuild -ne $GameBuild) {
                if (Set-XmlTagValue 'ModInfo.xml' 'modbuild' $GameBuild) {
                    Write-Host "Updated modbuild: $OldBuild -> $GameBuild"
                }
            } else {
                Write-Host "modbuild already current: $GameBuild"
            }
        } else {
            Write-Host "Warning: Could not detect game build version"
        }
    }

    Write-Host ""
    Write-Host "Done. Review changes before committing."
} finally {
    Pop-Location
}
