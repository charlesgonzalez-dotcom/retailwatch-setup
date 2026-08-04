# RetailWatch - Back Office Setup Script
# Downloads all dependencies from Google Drive and GitHub
# Right-click -> Run with PowerShell (as Administrator)

param([string]$USB = "")
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  RetailWatch - Back Office PC Setup" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Google Drive file IDs
$gdPython   = "1L9nL-Vwkp2szhXhYYIh5b27Uk8m41Iz2"
$gdZeroTier = "1RZBaS6TfhY1WDpporg0PcRj07_WZayTo"
$gdMediamtx = "1fmj9aoixtMdsT2YppbgvmWkK8aosdMOp"

$dlPath = "C:\RetailWatch\downloads"
New-Item -ItemType Directory -Force -Path $dlPath | Out-Null
New-Item -ItemType Directory -Force -Path "C:\RetailWatch\mediamtx" | Out-Null

function Get-GDriveFile($id, $dest, $label) {
    Write-Host "      Downloading $label..." -ForegroundColor Gray
    try {
        $url = "https://drive.google.com/uc?export=download&id=$id&confirm=t"
        curl.exe -L -o $dest $url --silent --show-error
        if (-not (Test-Path $dest) -or (Get-Item $dest).Length -lt 100000) {
            throw "File too small - likely a Google Drive warning page"
        }
        Write-Host "      $label downloaded." -ForegroundColor Green
    } catch {
        Write-Host "      ERROR downloading $label`: $_" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Step 1: Download and install Python
Write-Host "[1/5] Installing Python 3.11..." -ForegroundColor Yellow
$pyPath = "$dlPath\python-3.11.exe"
if (-not (Test-Path "C:\Program Files\Python311\python.exe")) {
    Get-GDriveFile $gdPython $pyPath "Python 3.11"
    Start-Process -FilePath $pyPath -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1" -Wait
    Write-Host "      Python installed." -ForegroundColor Green
} else {
    Write-Host "      Python already installed. Skipping." -ForegroundColor Green
}

# Step 2: Install Python packages
Write-Host "[2/5] Installing Python packages..." -ForegroundColor Yellow
$python = "C:\Program Files\Python311\python.exe"
& $python -m pip install --upgrade pip --quiet
& $python -m pip install opencv-python-headless ultralytics requests --quiet
Write-Host "      Packages installed." -ForegroundColor Green

# Step 3: Download and install ZeroTier
Write-Host "[3/5] Installing ZeroTier..." -ForegroundColor Yellow
$ztPath = "$dlPath\ZeroTierOne.msi"
Get-GDriveFile $gdZeroTier $ztPath "ZeroTier"
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$ztPath`" /quiet /norestart" -Wait
Write-Host "      ZeroTier installed." -ForegroundColor Green
Start-Sleep 5
Write-Host "      Joining Talk4Less ZeroTier network..." -ForegroundColor Yellow
& "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat" join cf719fd5401745ac
Write-Host "      Network join requested. Approve device in ZeroTier Central." -ForegroundColor Green

# Step 4: Download mediamtx and copy detector
Write-Host "[4/5] Installing RetailWatch files..." -ForegroundColor Yellow
$mtxZip = "$dlPath\mediamtx.zip"
Get-GDriveFile $gdMediamtx $mtxZip "mediamtx"
Expand-Archive -Path $mtxZip -DestinationPath "C:\RetailWatch\mediamtx" -Force
Write-Host "      mediamtx installed." -ForegroundColor Green

# Download detector and model from GitHub
Write-Host "      Downloading person detector..." -ForegroundColor Gray
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/charlesgonzalez-dotcom/retailwatch-setup/main/scripts/person-detector-template.py" `
    -OutFile "C:\RetailWatch\person-detector.py" -UseBasicParsing
Write-Host "      Downloading YOLOv8 model..." -ForegroundColor Gray
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/charlesgonzalez-dotcom/retailwatch-setup/main/scripts/yolov8n-pose.pt" `
    -OutFile "C:\RetailWatch\yolov8n-pose.pt" -UseBasicParsing
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
Write-Host "  Setup COMPLETE." -ForegroundColor Green
Write-Host ""
Write-Host "  IMPORTANT - Approve this PC in ZeroTier Central:" -ForegroundColor White
Write-Host "  zerotier.com -> Networks -> cf719fd5401745ac" -ForegroundColor Gray
Write-Host ""
Write-Host "  AT THE STORE run: 2-configure-store.ps1" -ForegroundColor White
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to close"
