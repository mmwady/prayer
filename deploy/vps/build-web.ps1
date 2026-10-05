$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../mobile/coaching'))
Push-Location (Join-Path $project 'browser')
try {
    npm.cmd run build
    if ($LASTEXITCODE -ne 0) { throw 'Browser build failed' }
} finally { Pop-Location }
Push-Location $project
try {
    flutter build web --release --no-pub --pwa-strategy=none --no-web-resources-cdn
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Web build failed' }
    & (Join-Path $PSScriptRoot 'package-web.ps1')
} finally { Pop-Location }
