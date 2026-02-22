#Requires -Version 5.1
# validate.ps1 - Validate mod content before deployment
#
# Checks:
#   - text-*-add.xml files have UTF-8 BOM (ef bb bf)
#   - All XML files in Infos/ are well-formed
#   - ModInfo.xml is well-formed and has a <modversion> tag
#
# Usage: .\scripts\validate.ps1 [-ProjectDir path]
# Exit code: 0 on success, 1 on failure

param(
    [string]$ProjectDir = ''
)

Set-StrictMode -Version Latest

if (-not $ProjectDir) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectDir = Split-Path -Parent $ScriptDir
}
Push-Location $ProjectDir

$Errors = 0

[Console]::Error.WriteLine("=== Validating mod content ===")

# Check ModInfo.xml exists and is well-formed
if (-not (Test-Path 'ModInfo.xml')) {
    [Console]::Error.WriteLine("FAIL: ModInfo.xml not found")
    $Errors++
} else {
    try {
        [xml]$modInfo = Get-Content 'ModInfo.xml'
    } catch {
        [Console]::Error.WriteLine("FAIL: ModInfo.xml is not well-formed XML")
        $Errors++
        $modInfo = $null
    }

    if ($modInfo) {
        $version = $modInfo.SelectSingleNode('//modversion')
        if (-not $version) {
            [Console]::Error.WriteLine("FAIL: ModInfo.xml missing <modversion> tag")
            $Errors++
        }
    }
}

# Check Infos/ directory exists
if (-not (Test-Path 'Infos' -PathType Container)) {
    [Console]::Error.WriteLine("FAIL: Infos/ directory not found")
    $Errors++
} else {
    # Check all XML files in Infos/ are well-formed
    foreach ($xmlFile in Get-ChildItem 'Infos\*.xml' -ErrorAction SilentlyContinue) {
        try {
            [xml](Get-Content $xmlFile.FullName) | Out-Null
        } catch {
            [Console]::Error.WriteLine("FAIL: $($xmlFile.Name) is not well-formed XML")
            $Errors++
        }
    }

    # Check text XML files have UTF-8 BOM
    foreach ($textFile in Get-ChildItem 'Infos\text*-add.xml' -ErrorAction SilentlyContinue) {
        $bytes = [System.IO.File]::ReadAllBytes($textFile.FullName)
        if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
            if ($bytes.Length -ge 3) {
                $bomHex = '{0:x2}{1:x2}{2:x2}' -f $bytes[0], $bytes[1], $bytes[2]
            } else {
                $bomHex = '(empty)'
            }
            [Console]::Error.WriteLine("FAIL: $($textFile.Name) missing UTF-8 BOM (found: $bomHex)")
            [Console]::Error.WriteLine("  Fix: Use a text editor that saves with UTF-8 BOM, or run:")
            [Console]::Error.WriteLine("  `$bom = [byte[]](0xEF,0xBB,0xBF); `$content = [System.IO.File]::ReadAllBytes('$($textFile.Name)'); [System.IO.File]::WriteAllBytes('$($textFile.Name)', `$bom + `$content)")
            $Errors++
        }
    }
}

Pop-Location

if ($Errors -gt 0) {
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("Validation failed with $Errors error(s)")
    exit 1
} else {
    [Console]::Error.WriteLine("All checks passed")
    exit 0
}
