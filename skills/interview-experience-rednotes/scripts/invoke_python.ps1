[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ScriptPath,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$ScriptArguments,

    [string]$RuntimeRoot = (Join-Path $env:LOCALAPPDATA 'RednoteInterviewSkill')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedScript = (Resolve-Path -LiteralPath $ScriptPath).Path
$statePath = Join-Path $RuntimeRoot 'state\deployment.json'
$modelsDir = Join-Path $RuntimeRoot 'models\paddleocr'
$env:PADDLE_PDX_CACHE_HOME = $modelsDir
$env:PADDLE_PDX_MODEL_SOURCE = 'bos'
$env:PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK = 'True'
$pythonPath = $null

if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -Raw -Encoding utf8 -LiteralPath $statePath | ConvertFrom-Json
    if ($state.paddleocr.python_path -and (Test-Path -LiteralPath $state.paddleocr.python_path)) {
        $pythonPath = $state.paddleocr.python_path
    }
    elseif ($state.python.path -and (Test-Path -LiteralPath $state.python.path)) {
        $pythonPath = $state.python.path
    }
}

$venvPython = Join-Path $RuntimeRoot 'runtime\python-env\Scripts\python.exe'
if (Test-Path -LiteralPath $venvPython) {
    $pythonPath = $venvPython
}

if (-not $pythonPath) {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) { $pythonPath = $python.Source }
}

if (-not $pythonPath) {
    throw 'Python is not available. Run scripts/deployment/windows/install.ps1 first.'
}

& $pythonPath $resolvedScript @ScriptArguments
exit $LASTEXITCODE
