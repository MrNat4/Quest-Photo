$ErrorActionPreference = 'Stop'
$project = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $project
try {
    & py -3.11 -c "import sys; assert sys.version_info[:2] == (3,11)"
    if ($LASTEXITCODE -ne 0) { throw 'Install 64-bit Python 3.11 from python.org with the Python launcher and tkinter, then rerun.' }
    $venv = Join-Path $project '.model-prep\venv'
    if (!(Test-Path "$venv\Scripts\python.exe")) {
        & py -3.11 -m venv $venv
        if ($LASTEXITCODE -ne 0) { throw 'Could not create isolated Python environment.' }
    }
    $python = "$venv\Scripts\python.exe"
    & $python -m pip install torch==2.6.0 torchvision==0.21.0 --index-url https://download.pytorch.org/whl/cpu
    if ($LASTEXITCODE -ne 0) { throw 'CPU PyTorch installation failed.' }
    & $python -m pip install -r "$PSScriptRoot\requirements.txt"
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
    $env:HF_HUB_OFFLINE = '1'
    $env:XFORMERS_DISABLED = '1'
    & $python "$PSScriptRoot\prepare.py" 2>&1 | Tee-Object -FilePath "$project\.model-prep\last-run.log"
    if ($LASTEXITCODE -ne 0) { throw 'Model preparation failed. See .model-prep\last-error.txt and last-run.log.' }
    Write-Host 'Model passed desktop validation. Run this launcher again for each remaining model.'
} catch { Write-Host "ERROR: $_" -ForegroundColor Red }
Read-Host 'Press Enter to close'
