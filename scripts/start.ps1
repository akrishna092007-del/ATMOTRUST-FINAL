param([switch]$SkipInstall)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$previous = Get-Location
try {
  Set-Location $projectRoot
  function Test-PythonCompat($cmd, $cmdArgs) {
    try {
      $out = & $cmd @cmdArgs -c "import sys; print(1 if sys.version_info >= (3, 11) else 0)" 2>$null
      return ($out -match '1')
    } catch {
      return $false
    }
  }

  $npmCommand = if (Get-Command npm.cmd -ErrorAction SilentlyContinue) { 'npm.cmd' } else { 'npm' }

  if ($env:ATMOTRUST_PYTHON) {
    $pythonCommand = $env:ATMOTRUST_PYTHON
    $pythonArgs = @()
  } elseif ((Test-Path (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')) -and (Test-PythonCompat (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe') @())) {
    $pythonCommand = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    $pythonArgs = @()
  } elseif ((Get-Command py -ErrorAction SilentlyContinue) -and (Test-PythonCompat 'py' @('-3'))) {
    $pythonCommand = 'py'
    $pythonArgs = @('-3')
  } elseif ((Get-Command python -ErrorAction SilentlyContinue) -and (Test-PythonCompat 'python' @())) {
    $pythonCommand = 'python'
    $pythonArgs = @()
  } else {
    $foundPython = Get-ChildItem "$env:LOCALAPPDATA\Python\pythoncore-3.*\python.exe", "$env:LOCALAPPDATA\Programs\Python\Python31*\python.exe" -ErrorAction SilentlyContinue | Where-Object { Test-PythonCompat $_.FullName @() } | Select-Object -First 1
    if ($foundPython) {
      $pythonCommand = $foundPython.FullName
      $pythonArgs = @()
    } else {
      throw 'Python 3.11+ is required. Install Python 3.11+ or set ATMOTRUST_PYTHON to its executable.'
    }
  }
  if (-not $SkipInstall) {
    & $pythonCommand @pythonArgs -m pip install -r backend/requirements.txt
    if ($LASTEXITCODE -ne 0) { throw 'Python dependency installation failed.' }
    if (-not (Test-Path frontend/node_modules)) {
      Push-Location frontend
      try { & $npmCommand ci; if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' } } finally { Pop-Location }
    }
    if (-not (Test-Path frontend/dist/index.html)) {
      Push-Location frontend
      try { & $npmCommand run build; if ($LASTEXITCODE -ne 0) { throw 'Frontend build failed.' } } finally { Pop-Location }
    }
  }
  & $pythonCommand @pythonArgs scripts/seed_accounts.py
  if ($LASTEXITCODE -ne 0) { throw 'Account setup failed.' }
  Write-Host 'AtmoTrust running at http://127.0.0.1:8000'
  & $pythonCommand @pythonArgs -m uvicorn app.main:app --app-dir backend --host 127.0.0.1 --port 8000
} finally {
  Set-Location $previous
}
