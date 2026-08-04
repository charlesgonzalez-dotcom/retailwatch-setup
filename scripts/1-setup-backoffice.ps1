# RetailWatch - Back Office Setup Script
# Run this at the back office BEFORE taking the PC to the store
# Right-click -> Run with PowerShell (as Administrator)

$ErrorActionPreference = 'Stop'
$USB = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  RetailWatch - Back Office PC Setup" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Install Python
Write-Host "[1/5] Installing Python 3.11..." -ForegroundColor Yellow
$pyInstaller = Join-Path $USB "installers\python-3.11.exe"
if (Test-Path $pyInstaller) {
    Start-Process -FilePath $pyInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1" -Wait
    Write-Host "      Python installed." -ForegroundColor Green
} else {
    Write-Host "      MISSING: Drop python-3.11.exe into installers\" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 2: Install Python packages
Write-Host "[2/5] Installing Python packages..." -ForegroundColor Yellow
$python = "C:\Program Files\Python311\python.exe"
& $python -m pip install --upgrade pip --quiet
& $python -m pip install opencv-python-headless ultralytics requests --quiet
Write-Host "      Packages installed." -ForegroundColor Green

# Step 3: Install ZeroTier
Write-Host "[3/5] Installing ZeroTier..." -ForegroundColor Yellow
$ztInstaller = Join-Path $USB "installers\ZeroTierOne.msi"
if (Test-Path $ztInstaller) {
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$ztInstaller`" /quiet /norestart" -Wait
    Write-Host "      ZeroTier installed." -ForegroundColor Green
    Start-Sleep 5
    Write-Host "      Joining Talk4Less ZeroTier network..." -ForegroundColor Yellow
    & "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat" join cf719fd5401745ac
    Write-Host "      Network join requested. Approve device in ZeroTier Central." -ForegroundColor Green
} else {
    Write-Host "      MISSING: Drop ZeroTierOne.msi into installers\" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 4: Copy mediamtx and detector
Write-Host "[4/5] Installing RetailWatch files..." -ForegroundColor Yellow
$src = Join-Path $USB "mediamtx"
if (-not (Test-Path (Join-Path $src "mediamtx.exe"))) {
    Write-Host "      MISSING: Copy mediamtx.exe into the mediamtx\ folder." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
New-Item -ItemType Directory -Force -Path "C:\RetailWatch\mediamtx" | Out-Null
Copy-Item -Path "$src\*" -Destination "C:\RetailWatch\mediamtx" -Recurse -Force

$detectorSrc = Join-Path $USB "scripts\person-detector-template.py"
if (Test-Path $detectorSrc) {
    Copy-Item $detectorSrc "C:\RetailWatch\person-detector.py" -Force
}

$modelSrc = Join-Path $USB "scripts\yolov8n-pose.pt"
if (Test-Path $modelSrc) {
    Copy-Item $modelSrc "C:\RetailWatch\yolov8n-pose.pt" -Force
    Write-Host "      YOLOv8 model copied." -ForegroundColor Green
} else {
    Write-Host "      MISSING: yolov8n-pose.pt not found in scripts\" -ForegroundColor Red
}
Write-Host "      Files installed to C:\RetailWatch\" -ForegroundColor Green

# Step 5: Install startup scripts
Write-Host "[5/5] Installing auto-start..." -ForegroundColor Yellow
$startupDir = [System.Environment]::GetFolderPath('Startup')

$ps1Content = '# mediamtx
$p1 = New-Object System.Diagnostics.ProcessStartInfo
$p1.FileName = "C:\RetailWatch\mediamtx\mediamtx.exe"
$p1.Arguments = "C:\RetailWatch\mediamtx\mediamtx-store.yml"
$p1.CreateNoWindow = $true
$p1.UseShellExecute = $false
[System.Diagnostics.Process]::Start($p1) | Out-Null

# person detector
$p2 = New-Object System.Diagnostics.ProcessStartInfo
$p2.FileName = "C:\Program Files\Python311\python.exe"
$p2.Arguments = "C:\RetailWatch\person-detector.py"
$p2.CreateNoWindow = $true
$p2.UseShellExecute = $false
[System.Diagnostics.Process]::Start($p2) | Out-Null'

Set-Content -Path "C:\RetailWatch\rw-startup.ps1" -Value $ps1Content -Encoding UTF8

$vbs = 'CreateObject("WScript.Shell").Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\RetailWatch\rw-startup.ps1""", 0, False'
Set-Content -Path (Join-Path $startupDir "retailwatch-start.vbs") -Value $vbs -Encoding UTF8
Write-Host "      Auto-start installed." -ForegroundColor Green

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Back office setup COMPLETE." -ForegroundColor Green
Write-Host ""
Write-Host "  IMPORTANT - Before leaving back office:" -ForegroundColor White
Write-Host "  1. Approve this PC in ZeroTier Central" -ForegroundColor White
Write-Host "     zerotier.com -> Networks -> cf719fd5401745ac" -ForegroundColor Gray
Write-Host ""
Write-Host "  AT THE STORE:" -ForegroundColor White
Write-Host "  Run: 2-configure-store.bat" -ForegroundColor White
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to close"
