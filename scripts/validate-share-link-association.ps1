[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [uri]$BaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$AppleTeamId,

    [Parameter(Mandatory = $true)]
    [string]$AndroidSha256,

    [string]$IosBundleId = 'com.rigley.supanotes',
    [string]$AndroidPackage = 'com.example.supanotes'
)

$ErrorActionPreference = 'Stop'
$origin = $BaseUrl.AbsoluteUri.TrimEnd('/')

function Get-AssociationJson {
    param([Parameter(Mandatory = $true)][string]$Path)

    $uri = "$origin$Path"
    $response = Invoke-WebRequest -Uri $uri -MaximumRedirection 0
    if ($response.StatusCode -ne 200) {
        throw "$uri returned HTTP $($response.StatusCode)"
    }

    try {
        return $response.Content | ConvertFrom-Json
    } catch {
        throw "$uri did not return valid JSON: $($_.Exception.Message)"
    }
}

function Normalize-Fingerprint {
    param([Parameter(Mandatory = $true)][string]$Value)

    return ($Value -replace '[:\-\s]', '').ToUpperInvariant()
}

$aasa = Get-AssociationJson '/.well-known/apple-app-site-association'
$expectedAppId = "$AppleTeamId.$IosBundleId"
$aasaDetail = @($aasa.applinks.details) | Where-Object {
    $componentMatch = @($_.components) | Where-Object { $_.'/' -eq '/s/*' }
    $_.appIDs -contains $expectedAppId -and $componentMatch.Count -gt 0
}
if (@($aasaDetail).Count -eq 0) {
    throw "AASA does not claim $expectedAppId for /s/*"
}

$assetlinks = @(Get-AssociationJson '/.well-known/assetlinks.json')
$expectedFingerprint = Normalize-Fingerprint $AndroidSha256
$assetLink = $assetlinks | Where-Object {
    $_.target.namespace -eq 'android_app' -and
        $_.target.package_name -eq $AndroidPackage -and
        (@($_.target.sha256_cert_fingerprints) | ForEach-Object {
            (Normalize-Fingerprint $_) -eq $expectedFingerprint
        }) -contains $true -and
        $_.relation -contains 'delegate_permission/common.handle_all_urls'
}
if (-not $assetLink) {
    throw "assetlinks.json does not claim $AndroidPackage with $AndroidSha256"
}

Write-Output "Share Link association is valid for $origin"
