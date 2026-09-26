param([ValidateSet('Check','Download')][string]$Mode,[Parameter(Mandatory=$true)][string]$Job,[Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'UpdateCore.ps1')
$result=Join-Path $Job 'result.json'
try {
    if($Mode -eq 'Check') {
        $metadata=Join-Path $Job 'release.json'
        Save-UpdateHttpFile 'https://api.github.com/repos/Re-Lyz/DualScreenWallpaper/releases/latest' $metadata 2MB
        $release=Get-Content -LiteralPath $metadata -Raw -Encoding UTF8 | ConvertFrom-Json
        $info=Convert-ReleaseInfo $release ((Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()) (Get-DistributionKind $Root)
        $info | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Job 'release-info.json') -Encoding UTF8
    } else {
        $info=Get-Content -LiteralPath (Join-Path $Job 'release-info.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if(!$info.Available){throw 'No newer release is available.'}
        $path=Join-Path $Job 'download.part'
        Save-UpdateHttpFile $info.Url $path ([long]$info.Size)
        Assert-UpdatePackage $info $path
        Move-Item -LiteralPath $path -Destination (Join-Path $Job $info.Name) -Force
    }
    @{Success=$true;Mode=$Mode} | ConvertTo-Json | Set-Content -LiteralPath ($result+'.tmp') -Encoding UTF8
    Move-Item -LiteralPath ($result+'.tmp') -Destination $result -Force
} catch {
    @{Success=$false;Error=[string]$_;Mode=$Mode} | ConvertTo-Json | Set-Content -LiteralPath ($result+'.tmp') -Encoding UTF8
    Move-Item -LiteralPath ($result+'.tmp') -Destination $result -Force
    exit 1
}
