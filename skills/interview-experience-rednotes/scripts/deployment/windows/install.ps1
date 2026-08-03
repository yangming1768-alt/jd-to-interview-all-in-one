[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Json,
    [string]$RuntimeRoot = (Join-Path $env:LOCALAPPDATA 'RednoteInterviewSkill')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$SkillRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$RuntimeDir = Join-Path $RuntimeRoot 'runtime'
$StateDir = Join-Path $RuntimeRoot 'state'
$LogDir = Join-Path $RuntimeRoot 'logs'
$DownloadDir = Join-Path $RuntimeRoot 'downloads'
$ModelsDir = Join-Path $RuntimeRoot 'models\paddleocr'
$env:PADDLE_PDX_CACHE_HOME = $ModelsDir
$env:PADDLE_PDX_MODEL_SOURCE = 'bos'
$env:PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK = 'True'
$StatePath = Join-Path $StateDir 'deployment.json'
$ExtensionUrl = 'https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk'
$XiaohongshuUrl = 'https://www.xiaohongshu.com/'

$state = [ordered]@{
    schema_version = 1
    checked_at = (Get-Date).ToString('o')
    platform = 'windows'
    runtime_root = $RuntimeRoot
    check_only = [bool]$CheckOnly
    node = [ordered]@{ status = 'missing'; version = $null; path = $null; source = $null }
    opencli = [ordered]@{ status = 'missing'; version = $null; mode = $null; command_path = $null; node_path = $null; entry_path = $null }
    python = [ordered]@{ status = 'missing'; version = $null; path = $null; source = $null }
    paddleocr = [ordered]@{ status = 'missing'; smoke_test = $false; python_path = $null; models_dir = $ModelsDir }
    chrome = [ordered]@{ status = 'missing'; path = $null }
    bridge = [ordered]@{ status = 'unknown'; doctor_exit_code = $null }
    xiaohongshu = [ordered]@{ status = 'unknown'; search_exit_code = $null }
    overall = 'checking'
    next_action = $null
    errors = @()
}

function Show-Stage {
    param([int]$Number, [string]$Message, [string]$Status = 'running')
    if (-not $Json) { Write-Host ("[{0}/8] {1}: {2}" -f $Number, $Status, $Message) }
}

function Add-StateError {
    param([string]$Component, [string]$Message)
    $state.errors += [ordered]@{ component = $Component; message = $Message }
}

function Get-ExecutableVersion {
    param([string]$Executable, [string[]]$Arguments = @('--version'))
    try {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $value = (& $Executable @Arguments 2>$null | Select-Object -First 1)
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        if ($exitCode -ne 0 -or -not $value) { return $null }
        return ([string]$value).Trim()
    }
    catch {
        $ErrorActionPreference = $previousPreference
        return $null
    }
}

function Get-NodeMajor {
    param([string]$Version)
    if ($Version -match 'v?(\d+)') { return [int]$Matches[1] }
    return 0
}

function Find-Node {
    $command = Get-Command node -ErrorAction SilentlyContinue
    if ($command) {
        $version = Get-ExecutableVersion -Executable $command.Source
        if ($version -and (Get-NodeMajor $version) -ge 20) {
            return @{ Path = $command.Source; Version = $version; Source = 'existing' }
        }
    }
    $local = Get-ChildItem -LiteralPath (Join-Path $RuntimeDir 'node') -Filter node.exe -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($local) {
        $version = Get-ExecutableVersion -Executable $local.FullName
        if ($version -and (Get-NodeMajor $version) -ge 20) {
            return @{ Path = $local.FullName; Version = $version; Source = 'skill' }
        }
    }
    return $null
}

function Install-PrivateNode {
    Show-Stage 2 'Preparing the Node.js LTS runtime from the official source'
    New-Item -ItemType Directory -Force -Path $DownloadDir, (Join-Path $RuntimeDir 'node') | Out-Null
    $index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json'
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $release = $index | Where-Object { $_.lts -and ($_.files -contains "win-$arch-zip") } | Select-Object -First 1
    if (-not $release) { throw "No compatible Node.js LTS release was found for $arch." }
    $baseName = "node-$($release.version)-win-$arch"
    $versionUrl = "https://nodejs.org/dist/$($release.version)"
    $zipPath = Join-Path $DownloadDir "$baseName.zip"
    Invoke-WebRequest -Uri "$versionUrl/$baseName.zip" -OutFile $zipPath
    $checksums = (Invoke-WebRequest -Uri "$versionUrl/SHASUMS256.txt").Content
    $escapedName = [regex]::Escape("$baseName.zip")
    if ($checksums -notmatch "(?m)^([a-fA-F0-9]{64})\s+$escapedName$") { throw 'Node.js checksum was not found.' }
    $expected = $Matches[1].ToLowerInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw 'Node.js download checksum verification failed.' }
    $destination = Join-Path (Join-Path $RuntimeDir 'node') $baseName
    if (-not (Test-Path -LiteralPath $destination)) {
        Expand-Archive -LiteralPath $zipPath -DestinationPath (Join-Path $RuntimeDir 'node')
    }
    return Join-Path $destination 'node.exe'
}

function Resolve-OpenCliEntry {
    param([string]$OpenCliRoot)
    $packagePath = Join-Path $OpenCliRoot 'node_modules\@jackwener\opencli\package.json'
    if (-not (Test-Path -LiteralPath $packagePath)) { return $null }
    $package = Get-Content -Raw -Encoding utf8 -LiteralPath $packagePath | ConvertFrom-Json
    $relative = if ($package.bin -is [string]) { $package.bin } else { $package.bin.opencli }
    if (-not $relative) { return $null }
    return Join-Path (Split-Path -Parent $packagePath) $relative
}

function Find-OpenCli {
    param([string]$NodePath)
    # Prefer the skill-managed copy. This also avoids execution-policy issues
    # when a globally installed opencli.ps1 shim happens to be discovered first.
    $root = Join-Path $RuntimeDir 'opencli'
    $entry = Resolve-OpenCliEntry -OpenCliRoot $root
    if ($entry -and (Test-Path -LiteralPath $entry) -and $NodePath) {
        $packagePath = Join-Path $root 'node_modules\@jackwener\opencli\package.json'
        $package = Get-Content -Raw -Encoding utf8 -LiteralPath $packagePath | ConvertFrom-Json
        if ($package.version) {
            return @{ Mode = 'local'; Version = ([string]$package.version).Trim(); Command = $null; Entry = $entry }
        }
    }
    $global = Get-Command opencli -ErrorAction SilentlyContinue
    if ($global) {
        $version = Get-ExecutableVersion -Executable $global.Source
        if ($version) { return @{ Mode = 'global'; Version = $version; Command = $global.Source; Entry = $null } }
    }
    return $null
}

function Install-PrivateOpenCli {
    param([string]$NodePath)
    Show-Stage 3 'Installing OpenCLI from the official npm registry'
    $npm = Join-Path (Split-Path -Parent $NodePath) 'npm.cmd'
    if (-not (Test-Path -LiteralPath $npm)) { throw 'npm.cmd was not found beside the selected Node.js runtime.' }
    $root = Join-Path $RuntimeDir 'opencli'
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    & $npm install --prefix $root '@jackwener/opencli@latest' --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw "npm failed with exit code $LASTEXITCODE." }
    $entry = Resolve-OpenCliEntry -OpenCliRoot $root
    if (-not $entry -or -not (Test-Path -LiteralPath $entry)) { throw 'OpenCLI entry point was not created.' }
    return $entry
}

function Get-PythonInfo {
    $command = Get-Command python -ErrorAction SilentlyContinue
    if ($command) {
        $version = Get-ExecutableVersion -Executable $command.Source
        # PaddlePaddle wheels commonly lag the newest Python release. Keep the
        # automatically managed OCR runtime on versions with broad wheel support.
        if ($version -match 'Python 3\.(9|10|11|12)(?:\.|$)') { return @{ Path = $command.Source; Version = $version; Source = 'existing' } }
    }
    $localPath = Join-Path $RuntimeDir 'python\python.exe'
    if (Test-Path -LiteralPath $localPath) {
        $version = Get-ExecutableVersion -Executable $localPath
        if ($version) { return @{ Path = $localPath; Version = $version; Source = 'skill' } }
    }
    return $null
}

function Test-AuthenticodePublisher {
    param([string]$Path, [string]$PublisherPattern)
    $signature = Get-AuthenticodeSignature -FilePath $Path
    return $signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match $PublisherPattern
}

function Install-PrivatePython {
    Show-Stage 4 'Preparing a private Python runtime from the official source'
    New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
    $version = '3.11.9'
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $installer = Join-Path $DownloadDir "python-$version-$arch.exe"
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/$version/python-$version-$arch.exe" -OutFile $installer
    if (-not (Test-AuthenticodePublisher -Path $installer -PublisherPattern 'Python Software Foundation')) {
        throw 'Python installer signature verification failed.'
    }
    $target = Join-Path $RuntimeDir 'python'
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    $arguments = @('/quiet', 'InstallAllUsers=0', 'PrependPath=0', 'Include_launcher=0', 'Include_test=0', 'Include_pip=1', "TargetDir=$target")
    $process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Python installer failed with exit code $($process.ExitCode)." }
    $python = Join-Path $target 'python.exe'
    if (-not (Test-Path -LiteralPath $python)) { throw 'Private Python installation did not create python.exe.' }
    return $python
}

function Ensure-PaddleOcr {
    param([string]$PythonPath)
    Show-Stage 4 'Creating a private Python environment and installing PaddleOCR'
    $venv = Join-Path $RuntimeDir 'python-env'
    $venvPython = Join-Path $venv 'Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $venvPython)) {
        & $PythonPath -m venv $venv
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the PaddleOCR virtual environment.' }
    }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $venvPython -c 'import paddleocr, paddle, PIL, docx, markdown' 2>$null
    $importExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($importExitCode -ne 0) {
        & $venvPython -m pip install --upgrade pip
        if ($LASTEXITCODE -ne 0) { throw 'Could not update pip.' }
        & $venvPython -m pip install 'paddlepaddle>=3.0,<4' -i 'https://www.paddlepaddle.org.cn/packages/stable/cpu/'
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the PaddlePaddle CPU runtime.' }
        & $venvPython -m pip install paddleocr pillow python-docx markdown
        if ($LASTEXITCODE -ne 0) { throw 'Could not install PaddleOCR and document export dependencies.' }
    }
    return $venvPython
}

function Find-Chrome {
    $candidates = @(
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    return $candidates | Select-Object -First 1
}

function Install-Chrome {
    Show-Stage 5 'Installing Chrome from the official Google source'
    New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
    $installer = Join-Path $DownloadDir 'chrome-installer.exe'
    Invoke-WebRequest -Uri 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' -OutFile $installer
    if (-not (Test-AuthenticodePublisher -Path $installer -PublisherPattern 'Google')) {
        throw 'Chrome installer signature verification failed.'
    }
    $process = Start-Process -FilePath $installer -ArgumentList @('/silent', '/install') -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Chrome installer failed with exit code $($process.ExitCode)." }
    return Find-Chrome
}

function Invoke-OpenCli {
    param([string[]]$Arguments)
    $output = $null
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    if ($state.opencli.mode -eq 'local') {
        $output = & $state.opencli.node_path $state.opencli.entry_path @Arguments 2>&1
    }
    elseif ($state.opencli.mode -eq 'global') {
        $output = & $state.opencli.command_path @Arguments 2>&1
    }
    else {
        $ErrorActionPreference = $previousPreference
        return @{ ExitCode = 78; Output = 'OpenCLI is unavailable.' }
    }
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    return @{ ExitCode = $exitCode; Output = ($output -join [Environment]::NewLine) }
}

try {
    Show-Stage 1 'Checking the local environment'
    if (-not $CheckOnly) {
        New-Item -ItemType Directory -Force -Path $RuntimeRoot, $RuntimeDir, $StateDir, $LogDir, $ModelsDir | Out-Null
    }

    $node = Find-Node
    if (-not $node -and -not $CheckOnly) {
        $installedNode = Install-PrivateNode
        $node = @{ Path = $installedNode; Version = (Get-ExecutableVersion $installedNode); Source = 'skill' }
    }
    if ($node) {
        $state.node.status = 'ready'; $state.node.path = $node.Path; $state.node.version = $node.Version; $state.node.source = $node.Source
    }

    $opencli = if ($node) { Find-OpenCli -NodePath $node.Path } else { $null }
    if (-not $opencli -and $node -and -not $CheckOnly) {
        $entry = Install-PrivateOpenCli -NodePath $node.Path
        $opencli = Find-OpenCli -NodePath $node.Path
    }
    if ($opencli) {
        $state.opencli.status = 'ready'; $state.opencli.version = $opencli.Version; $state.opencli.mode = $opencli.Mode
        $state.opencli.command_path = $opencli.Command; $state.opencli.node_path = $node.Path; $state.opencli.entry_path = $opencli.Entry
    }

    $python = Get-PythonInfo
    if (-not $python -and -not $CheckOnly) {
        $installedPython = Install-PrivatePython
        $python = @{ Path = $installedPython; Version = (Get-ExecutableVersion $installedPython); Source = 'skill' }
    }
    if ($python) {
        $state.python.status = 'ready'; $state.python.path = $python.Path; $state.python.version = $python.Version; $state.python.source = $python.Source
        $venvPython = Join-Path $RuntimeDir 'python-env\Scripts\python.exe'
        if (-not $CheckOnly) { $venvPython = Ensure-PaddleOcr -PythonPath $python.Path }
        if (Test-Path -LiteralPath $venvPython) {
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & $venvPython -c 'import paddleocr, paddle, PIL, docx, markdown' 2>$null
            $importExitCode = $LASTEXITCODE
            $ErrorActionPreference = $previousPreference
            if ($importExitCode -eq 0) {
                $state.paddleocr.status = 'ready'; $state.paddleocr.python_path = $venvPython
                if (-not $CheckOnly) {
                    $smokeScript = Join-Path $SkillRoot 'scripts\ocr_smoke_test.py'
                    & $venvPython $smokeScript --json --models-dir $ModelsDir | Out-Null
                    $state.paddleocr.smoke_test = ($LASTEXITCODE -eq 0)
                }
            }
        }
    }

    $chrome = Find-Chrome
    if (-not $chrome -and -not $CheckOnly) { $chrome = Install-Chrome }
    if ($chrome) { $state.chrome.status = 'ready'; $state.chrome.path = $chrome }

    if ($state.opencli.status -eq 'ready' -and $state.chrome.status -eq 'ready') {
        Show-Stage 7 'Verifying the OpenCLI Browser Bridge'
        $doctor = Invoke-OpenCli -Arguments @('doctor')
        $state.bridge.doctor_exit_code = $doctor.ExitCode
        if ($doctor.ExitCode -eq 0) {
            $state.bridge.status = 'ready'
            $searchTerm = ([char]0x9762).ToString() + ([char]0x8BD5).ToString()
            $search = Invoke-OpenCli -Arguments @('xiaohongshu', 'search', $searchTerm, '--limit', '1', '-f', 'json')
            $state.xiaohongshu.search_exit_code = $search.ExitCode
            if ($search.ExitCode -in @(0, 66)) { $state.xiaohongshu.status = 'ready' }
            elseif ($search.ExitCode -eq 77) { $state.xiaohongshu.status = 'login_required' }
            else { $state.xiaohongshu.status = 'unavailable' }
        }
        else { $state.bridge.status = 'extension_required' }
    }

    $coreReady = $state.node.status -eq 'ready' -and $state.opencli.status -eq 'ready' -and $state.python.status -eq 'ready' -and $state.paddleocr.status -eq 'ready' -and $state.chrome.status -eq 'ready'
    if ($coreReady -and $state.bridge.status -eq 'ready' -and $state.xiaohongshu.status -eq 'ready') {
        $state.overall = 'ready'; Show-Stage 8 'The environment is ready for collection' 'complete'
    }
    elseif ($CheckOnly) {
        if ($coreReady -and $state.bridge.status -ne 'ready') {
            $state.overall = 'user_action_required'; $state.next_action = 'Install or enable the OpenCLI Chrome extension.'
        }
        elseif ($coreReady -and $state.bridge.status -eq 'ready' -and $state.xiaohongshu.status -ne 'ready') {
            $state.overall = 'user_action_required'; $state.next_action = 'Log in to Xiaohongshu in the connected Chrome profile.'
        }
        else {
            $state.overall = 'setup_required'; $state.next_action = 'Run this installer without -CheckOnly after user approval.'
        }
    }
    elseif ($state.bridge.status -ne 'ready') {
        $state.overall = 'user_action_required'; $state.next_action = 'Install the OpenCLI Chrome extension.'
        Show-Stage 5 'Confirm installation of the OpenCLI extension in Chrome' 'user_action'
        Start-Process -FilePath $state.chrome.path -ArgumentList $ExtensionUrl
    }
    elseif ($state.xiaohongshu.status -ne 'ready') {
        $state.overall = 'user_action_required'; $state.next_action = 'Log in to Xiaohongshu in the connected Chrome profile.'
        Show-Stage 6 'Log in to Xiaohongshu in Chrome' 'user_action'
        Start-Process -FilePath $state.chrome.path -ArgumentList $XiaohongshuUrl
    }
    else {
        $state.overall = 'failed'; $state.next_action = 'Review component status and retry only the failed component.'
    }
}
catch {
    Add-StateError -Component 'installer' -Message $_.Exception.Message
    $state.overall = 'failed'
    $state.next_action = 'Retry, continue later, or inspect technical details.'
}

if (-not $CheckOnly) {
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $state | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -LiteralPath $StatePath
}

if ($Json) { $state | ConvertTo-Json -Depth 8 }
else {
    Write-Host ("Result: {0}" -f $state.overall)
    if ($state.next_action) { Write-Host ("Next: {0}" -f $state.next_action) }
}

if ($state.overall -eq 'failed') { exit 1 }
exit 0
