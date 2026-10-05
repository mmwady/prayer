param([int]$Port = 8011)
# Explicit opt-in; no production accounts or external notifications.
$ErrorActionPreference = 'Stop'
$previousEnabled = $env:MOSQUE_DEMO_ENABLED
$previousDatabase = $env:MOSQUE_DEMO_DB
Push-Location $PSScriptRoot
try {
    $env:MOSQUE_DEMO_ENABLED = 'true'
    $env:MOSQUE_DEMO_DB = 'data/mosque_companion.sqlite3'
    & .\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port $Port
} finally {
    $env:MOSQUE_DEMO_ENABLED = $previousEnabled
    $env:MOSQUE_DEMO_DB = $previousDatabase
    Pop-Location
}
