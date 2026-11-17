$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$env:AURA_API_HOST = '127.0.0.1'
$env:AURA_API_PORT = '8765'

Write-Host 'Starting AURA local telemetry API on http://127.0.0.1:8765'
& python -u (Join-Path $root 'server\aura_api.py')
