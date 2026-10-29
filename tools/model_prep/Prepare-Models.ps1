$ErrorActionPreference = 'Stop'
$project = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $project
$result = 1
try {
    $python = Join-Path $project '.model-prep\venv\Scripts\python.exe'
    if (!(Test-Path $python)) {
        throw 'Existing preparation environment not found. Extract this update into the SAME preparation folder used previously. No reinstall is needed.'
    }
    $env:HF_HUB_OFFLINE = '1'
    $env:XFORMERS_DISABLED = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    Write-Host 'Using existing Python environment. No pip installs or upgrades.'
    Write-Host 'xFormers disabled/not available warnings are expected for CPU inference.'
    # The Python wrapper merges stderr BEFORE PowerShell sees it. Do not use 2>&1 here:
    # Windows PowerShell 5.1 can turn native stderr warnings into terminating errors.
    & $python "$PSScriptRoot\run_logged.py"
    $result = $LASTEXITCODE
    if ($result -ne 0) { throw 'Preparation failed. Full details are in .model-prep\last-run.log and last-error.txt.' }
    Write-Host 'PASS: model validated and packaged. Android/Quest testing is still required.'
} catch { Write-Host "ERROR: $_" -ForegroundColor Red }
Read-Host 'Press Enter to close'
exit $result
