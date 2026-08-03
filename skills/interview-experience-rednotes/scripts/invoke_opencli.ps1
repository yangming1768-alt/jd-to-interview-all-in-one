[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$OpenCLIArguments,

    [string]$RuntimeRoot = (Join-Path $env:LOCALAPPDATA 'RednoteInterviewSkill')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $OpenCLIArguments -or $OpenCLIArguments.Count -eq 0) {
    throw 'Missing OpenCLI arguments.'
}

$statePath = Join-Path $RuntimeRoot 'state\deployment.json'
$script:OpenCLIExitCode = 78

function Invoke-ResolvedOpenCLI {
    param([string[]]$Arguments)

    if (Test-Path -LiteralPath $statePath) {
        $state = Get-Content -Raw -Encoding utf8 -LiteralPath $statePath | ConvertFrom-Json
        if ($state.opencli.mode -eq 'local' -and
            (Test-Path -LiteralPath $state.opencli.node_path) -and
            (Test-Path -LiteralPath $state.opencli.entry_path)) {
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & $state.opencli.node_path $state.opencli.entry_path @Arguments
            $script:OpenCLIExitCode = $LASTEXITCODE
            $ErrorActionPreference = $previousPreference
            return
        }
        if ($state.opencli.mode -eq 'global' -and (Test-Path -LiteralPath $state.opencli.command_path)) {
            & $state.opencli.command_path @Arguments
            $script:OpenCLIExitCode = $LASTEXITCODE
            return
        }
    }

    $globalCommand = Get-Command opencli -ErrorAction SilentlyContinue
    if ($globalCommand) {
        & $globalCommand.Source @Arguments
        $script:OpenCLIExitCode = $LASTEXITCODE
        return
    }

    $packageJson = Join-Path $RuntimeRoot 'runtime\opencli\node_modules\@jackwener\opencli\package.json'
    if (Test-Path -LiteralPath $packageJson) {
        $package = Get-Content -Raw -Encoding utf8 -LiteralPath $packageJson | ConvertFrom-Json
        $binRelative = if ($package.bin -is [string]) { $package.bin } else { $package.bin.opencli }
        $entry = Join-Path (Split-Path -Parent $packageJson) $binRelative
        $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
        $nodePath = if ($nodeCommand) { $nodeCommand.Source } else { $null }
        if (-not $nodePath) {
            $node = Get-ChildItem -LiteralPath (Join-Path $RuntimeRoot 'runtime\node') -Filter node.exe -Recurse -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending | Select-Object -First 1
            if ($node) { $nodePath = $node.FullName }
        }
        if ($nodePath -and (Test-Path -LiteralPath $entry)) {
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & $nodePath $entry @Arguments
            $script:OpenCLIExitCode = $LASTEXITCODE
            $ErrorActionPreference = $previousPreference
            return
        }
    }

    throw 'OpenCLI is not available. Run scripts/deployment/windows/install.ps1 first.'
}

try {
    Invoke-ResolvedOpenCLI -Arguments $OpenCLIArguments
    exit $script:OpenCLIExitCode
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 78
}
