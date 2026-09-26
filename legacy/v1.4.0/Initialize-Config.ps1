# Each installation keeps its own untracked configuration.
$localConfig = Join-Path $PSScriptRoot 'config.json'
if (!(Test-Path -LiteralPath $localConfig)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'config.example.json') -Destination $localConfig -ErrorAction Stop
}
