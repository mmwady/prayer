$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../mobile/coaching'))
# Flutter's offline renderer requests this fallback even when the app uses Arabic fonts.
# Package the exact requested WOFF2 on the same origin; no runtime Google font request.
$fontPath = Join-Path $project 'build/web/assets/assets/fonts/roboto/v32'
New-Item -ItemType Directory -Force $fontPath | Out-Null
Invoke-WebRequest 'https://fonts.gstatic.com/s/roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2' -OutFile (Join-Path $fontPath 'KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2')
$flutterBin = Split-Path (Get-Command flutter).Source
Copy-Item (Join-Path $flutterBin 'cache/artifacts/material_fonts/roboto_license.txt') (Join-Path $fontPath 'LICENSE.txt')
Push-Location $project
try {
    node browser/scripts/build-offline.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Offline packaging failed' }
} finally { Pop-Location }
