param(
    [string]$Cloudflared = 'cloudflared',
    [int]$Port = 8000
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (!(Test-Path -LiteralPath $python)) { throw 'Create the backend .venv and install requirements first.' }
$bundled = Join-Path $PSScriptRoot 'tools\cloudflared.exe'
if ($Cloudflared -eq 'cloudflared' -and (Test-Path -LiteralPath $bundled)) { $Cloudflared = $bundled }
$connector = (Get-Command $Cloudflared -ErrorAction Stop).Source
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
try { $listener.Start() } finally { $listener.Stop() }
# Use one backend process: this gateway runs the unchanged app and its lifecycle.
# Stop the usual backend first; analysis jobs remain owned by this one process.
$server = Start-Process -FilePath $python -ArgumentList @('-m', 'uvicorn', 'tools.tunnel_gateway:app', '--host', '127.0.0.1', '--port', $Port) -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru
try {
    $ready = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if ($server.HasExited) { throw 'Tunnel backend failed to start. Check whether the port is already in use.' }
        try {
            $response = Invoke-RestMethod "http://127.0.0.1:$Port/healthz" -TimeoutSec 2
            if ($response.status -eq 'ok') { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (!$ready) { throw 'Tunnel backend did not become ready.' }
    & $connector tunnel --url "http://127.0.0.1:$Port"
} finally {
    if (!$server.HasExited) { Stop-Process -Id $server.Id }
}
