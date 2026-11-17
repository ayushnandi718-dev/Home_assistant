$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$serverDir = Join-Path $root 'server'
$venvDir = Join-Path $serverDir '.venv'
$pythonExe = Join-Path $venvDir 'Scripts\python.exe'

# Use an isolated environment so a fresh machine does not need psutil installed
# globally, and so a missing dependency cannot surface as ModuleNotFoundError.
if (-not (Test-Path $pythonExe)) {
  Write-Host 'Creating Python virtual environment for the AURA telemetry API...'
  & python -m venv $venvDir
  if (-not (Test-Path $pythonExe)) {
    throw 'Could not create the Python virtual environment. Check that Python 3 is installed and on PATH.'
  }
}

# Native commands write diagnostics to stderr. Under ErrorActionPreference=Stop,
# PowerShell turns that output into a terminating NativeCommandError, which
# would abort before dependencies get installed. Suspend it around those calls.
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  & $pythonExe -c 'import psutil' 2>$null
  $psutilAvailable = ($LASTEXITCODE -eq 0)
  if (-not $psutilAvailable) {
    Write-Host 'Installing telemetry API dependencies...'
    & $pythonExe -m pip install -r (Join-Path $serverDir 'requirements.txt')
    if ($LASTEXITCODE -ne 0) {
      throw 'Failed to install server requirements.'
    }
  }
} finally {
  $ErrorActionPreference = $previousPreference
}

if (-not $env:AURA_API_HOST) { $env:AURA_API_HOST = '127.0.0.1' }
if (-not $env:AURA_API_PORT) { $env:AURA_API_PORT = '8765' }

Write-Host "AURA Windows telemetry API: http://$($env:AURA_API_HOST):$($env:AURA_API_PORT)"
Write-Host 'This is local PC telemetry, not AURA device telemetry. No authentication is provided.'
& $pythonExe -u (Join-Path $serverDir 'aura_api.py')
