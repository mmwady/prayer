param(
  [string]$Python = (Join-Path $PSScriptRoot '..\..\..\backend\.venv\Scripts\python.exe'),
  [switch]$SkipInstall
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
  if (-not $SkipInstall) { npm.cmd ci --cache .cache; if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' } }
  & $Python tools/prepare_parity.py --pixels-only
  if ($LASTEXITCODE -ne 0) { throw 'Pixel fixtures failed' }
  & $Python tools/decode_fixtures.py
  if ($LASTEXITCODE -ne 0) { throw 'Decode fixtures failed' }
  & $Python tools/sequence_fixtures.py
  if ($LASTEXITCODE -ne 0) { throw 'Sequence fixtures failed' }
  & $Python tools/local_report_fixtures.py
  if ($LASTEXITCODE -ne 0) { throw 'Local report fixtures failed' }
  & $Python tools/export_models.py
  if ($LASTEXITCODE -ne 0) { throw 'ONNX export validation failed' }
  npm.cmd test
  if ($LASTEXITCODE -ne 0) { throw 'Browser unit tests failed' }
  npm.cmd run build
  if ($LASTEXITCODE -ne 0) { throw 'Static build failed' }
  Push-Location ..
  try {
    $taskAnalysis = flutter analyze --no-pub 2>&1
    $taskAnalysis | Write-Output
    if ($LASTEXITCODE -ne 0 -and (($taskAnalysis -join "`n") -match '(error|warning) -' -or ($taskAnalysis -join "`n") -notmatch 'info -')) {
      throw 'Flutter analyzer reported an error/warning or failed to run'
    }
    flutter build web --release --no-pub --pwa-strategy=none --no-web-resources-cdn
    if ($LASTEXITCODE -ne 0) { throw 'Flutter production build failed' }
    node browser/scripts/build-offline.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Offline production manifest failed' }
  } finally { Pop-Location }
} finally { Pop-Location }
