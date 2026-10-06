param(
    [int]$Port = 8020,
    [string]$Database = "data/accounts.rich.v2.demo.sqlite3"
)

$ErrorActionPreference = "Stop"
$backendDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$databasePath = [System.IO.Path]::GetFullPath((Join-Path $backendDir $Database))
$dataDir = [System.IO.Path]::GetFullPath((Join-Path $backendDir "data")) +
    [System.IO.Path]::DirectorySeparatorChar

if (-not $databasePath.StartsWith(
        $dataDir,
        [System.StringComparison]::OrdinalIgnoreCase
    ) -or -not $databasePath.EndsWith(".demo.sqlite3")) {
    throw "The demo database must be a .demo.sqlite3 file inside backend/data."
}

$python = Join-Path $backendDir ".venv/Scripts/python.exe"
if (-not (Test-Path -LiteralPath $python)) {
    throw "Create backend/.venv and install backend/requirements.txt first."
}

$envFile = Join-Path $backendDir ".env"
function Get-AccountSetting([string]$Name) {
    $processValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($processValue)) {
        return $processValue
    }
    if (Test-Path -LiteralPath $envFile) {
        $line = Get-Content -LiteralPath $envFile -Encoding utf8 |
            Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
            Select-Object -Last 1
        if ($null -ne $line) {
            return (($line -split "=", 2)[1]).Trim().Trim('"').Trim("'")
        }
    }
    return ""
}

$mailMode = (Get-AccountSetting "ACCOUNT_MAIL_MODE").ToLowerInvariant()
if ($mailMode -eq "resend") {
    if ([string]::IsNullOrWhiteSpace((Get-AccountSetting "ACCOUNT_RESEND_API_KEY")) -or
        [string]::IsNullOrWhiteSpace((Get-AccountSetting "ACCOUNT_MAIL_FROM"))) {
        throw "Resend requires ACCOUNT_RESEND_API_KEY and ACCOUNT_MAIL_FROM in backend/.env."
    }
}
elseif ($mailMode -eq "smtp") {
    if ([string]::IsNullOrWhiteSpace((Get-AccountSetting "ACCOUNT_SMTP_HOST"))) {
        throw "SMTP requires ACCOUNT_SMTP_HOST in backend/.env."
    }
}
elseif ($mailMode -eq "development") {
    Write-Warning "Development mode writes local .eml files; it does not send real email."
}
else {
    throw "Set ACCOUNT_MAIL_MODE to resend, smtp, or development in backend/.env."
}

if (-not (Test-Path -LiteralPath $databasePath)) {
    & $python -m tools.seed_account_demo --db $databasePath
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create the isolated demo database."
    }
}

$wifi = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -notlike "127.*" -and
        $_.IPAddress -notlike "169.254.*" -and
        $_.AddressState -eq "Preferred"
    } |
    Sort-Object InterfaceMetric |
    Select-Object -First 1

if ($null -eq $wifi) {
    throw "No active private IPv4 address was found. Connect the PC to Wi-Fi first."
}

$lanOrigin = "http://$($wifi.IPAddress):$Port"
$env:ACCOUNT_DB = $databasePath
$env:ACCOUNT_SECURE_COOKIES = "false"
$env:ACCOUNT_PUBLIC_URL = $lanOrigin
$env:ACCOUNT_ALLOWED_ORIGINS = @(
    $lanOrigin,
    "http://127.0.0.1:$Port",
    "http://localhost:$Port"
) | ConvertTo-Json -Compress

Write-Host "Iqtadi local account demo"
Write-Host "Computer: http://127.0.0.1:$Port"
Write-Host "Phone on the same Wi-Fi: $lanOrigin"
Write-Host "Email uses ACCOUNT_MAIL_MODE from backend/.env; verification is mandatory."
Write-Host "Press Ctrl+C to stop."

Push-Location $backendDir
try {
    & $python -m uvicorn tools.account_demo_server:app --host 0.0.0.0 --port $Port
}
finally {
    Pop-Location
}
