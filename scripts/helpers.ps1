#Requires -Version 5.1
# helpers.ps1 - Shared functions for PowerShell mod scripts
#
# Usage: dot-source from other scripts:
#   . "$ScriptDir\helpers.ps1"

function Import-DotEnv {
    param([string]$Path = '.env')
    if (-not (Test-Path $Path)) { return $false }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()
            # Strip surrounding quotes
            if (($val.StartsWith('"') -and $val.EndsWith('"')) -or
                ($val.StartsWith("'") -and $val.EndsWith("'"))) {
                $val = $val.Substring(1, $val.Length - 2)
            }
            [System.Environment]::SetEnvironmentVariable($key, $val, 'Process')
        }
    }
    return $true
}

function Get-XmlTagValue {
    param(
        [string]$FilePath,
        [string]$TagName
    )
    if (-not (Test-Path $FilePath)) { return $null }
    [xml]$doc = Get-Content $FilePath
    $node = $doc.SelectSingleNode("//$TagName")
    if ($node) { return $node.InnerText }
    return $null
}

function Set-XmlTagValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$FilePath,
        [string]$TagName,
        [string]$Value
    )
    if (-not (Test-Path $FilePath)) { return $false }
    [xml]$doc = Get-Content $FilePath
    $node = $doc.SelectSingleNode("//$TagName")
    if (-not $node) { return $false }
    if ($PSCmdlet.ShouldProcess($FilePath, "Set <$TagName> to '$Value'")) {
        $node.InnerText = $Value
        $doc.Save((Resolve-Path $FilePath).Path)
    }
    return $true
}

function Invoke-CSharpBuild {
    param(
        [string]$CsprojPath,
        [string]$OldWorldPath
    )
    if (-not $OldWorldPath) {
        Write-Error "OLDWORLD_PATH not set in .env (required for C# build)"
        return
    }
    Write-Host ""
    Write-Host "=== Building C# mod ==="
    & dotnet build $CsprojPath -c Release -p:OldWorldPath="$OldWorldPath"
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed with exit code $LASTEXITCODE" }
}

function Get-ChangelogForVersion {
    param(
        [string]$Version,
        [string]$ChangelogPath = 'CHANGELOG.md'
    )
    if (-not (Test-Path $ChangelogPath)) { return '' }
    $lines = Get-Content $ChangelogPath
    $found = $false
    $result = @()
    foreach ($line in $lines) {
        if ($line -match '^## \[') {
            if ($found) { break }
            if ($line -match [regex]::Escape("[$Version]")) {
                $found = $true
                continue
            }
        }
        if ($found -and $line.Trim() -ne '') {
            $result += $line
        }
    }
    if ($result.Count -gt 20) {
        $result = $result[0..19]
    }
    return ($result -join "`n")
}

function Invoke-ModioApi {
    param(
        [string]$Method,
        [string]$Uri,
        [string]$Token,
        [hashtable]$FormFields = @{},
        [string]$FilePath = $null,
        [string]$FileFieldName = $null
    )

    Add-Type -AssemblyName System.Net.Http

    $client = [System.Net.Http.HttpClient]::new()
    $client.DefaultRequestHeaders.Add('Authorization', "Bearer $Token")
    $client.DefaultRequestHeaders.Add('Accept', 'application/json')

    try {
        if ($FilePath) {
            # Multipart form data with file upload
            $content = [System.Net.Http.MultipartFormDataContent]::new()
            foreach ($field in $FormFields.GetEnumerator()) {
                $content.Add([System.Net.Http.StringContent]::new($field.Value), $field.Key)
            }
            $fileStream = [System.IO.File]::OpenRead((Resolve-Path $FilePath).Path)
            $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
            $content.Add($fileContent, $FileFieldName, [System.IO.Path]::GetFileName($FilePath))

            $response = $client.PostAsync($Uri, $content).Result
            $body = $response.Content.ReadAsStringAsync().Result
            $fileStream.Dispose()
            $content.Dispose()

            return @{
                StatusCode = [int]$response.StatusCode
                Body       = $body | ConvertFrom-Json
                RawBody    = $body
            }
        }
        elseif ($Method -eq 'PUT') {
            # URL-encoded form data
            $formEncoded = ($FormFields.GetEnumerator() | ForEach-Object {
                "$($_.Key)=$([System.Uri]::EscapeDataString($_.Value))"
            }) -join '&'

            $httpContent = [System.Net.Http.StringContent]::new(
                $formEncoded,
                [System.Text.Encoding]::UTF8,
                'application/x-www-form-urlencoded'
            )

            $response = $client.PutAsync($Uri, $httpContent).Result
            $body = $response.Content.ReadAsStringAsync().Result
            $httpContent.Dispose()

            return @{
                StatusCode = [int]$response.StatusCode
                Body       = $body | ConvertFrom-Json
                RawBody    = $body
            }
        }
        else {
            # Simple POST without file
            $content = [System.Net.Http.MultipartFormDataContent]::new()
            foreach ($field in $FormFields.GetEnumerator()) {
                $content.Add([System.Net.Http.StringContent]::new($field.Value), $field.Key)
            }

            $response = $client.PostAsync($Uri, $content).Result
            $body = $response.Content.ReadAsStringAsync().Result
            $content.Dispose()

            return @{
                StatusCode = [int]$response.StatusCode
                Body       = $body | ConvertFrom-Json
                RawBody    = $body
            }
        }
    }
    finally {
        $client.Dispose()
    }
}
