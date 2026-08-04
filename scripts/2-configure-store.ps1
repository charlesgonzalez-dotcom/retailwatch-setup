# RetailWatch - Store Configuration Script
# Run this AT THE STORE after plugging in ethernet

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  RetailWatch - Store Configuration" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$storeName = Read-Host "Store name (e.g. 145-Americas)"
$storeSlug = $storeName.ToLower().Replace(" ", "-")
$dvrIp     = Read-Host "DVR local IP (e.g. 192.168.1.118)"
$dvrPass   = Read-Host "DVR password"
$camCount  = [int](Read-Host "Number of cameras")
$dvrType   = Read-Host "DVR type - D for Dahua or H for Hikvision"

Write-Host ""
Write-Host "Building config for $storeName ($camCount cameras)..." -ForegroundColor Yellow

function Get-RtspUrl($ip, $pass, $ch, $type) {
    if ($type.ToUpper() -eq "H") {
        return "rtsp://admin:${pass}@${ip}:554/H264/ch${ch}/sub/av_stream"
    } else {
        return "rtsp://admin:${pass}@${ip}:554/cam/realmonitor?channel=${ch}&subtype=1"
    }
}

New-Item -ItemType Directory -Force -Path "C:\RetailWatch\mediamtx" | Out-Null

# Write mediamtx yml line by line
$ymlLines = @(
    "hlsSegmentCount: 10",
    "hlsSegmentDuration: 1s",
    'hlsAllowOrigin: "*"',
    "paths:"
)
for ($i = 1; $i -le $camCount; $i++) {
    $rtsp = Get-RtspUrl $dvrIp $dvrPass $i $dvrType
    $ymlLines += "  cam${i}:"
    $ymlLines += "    source: `"$rtsp`""
    $ymlLines += "    sourceOnDemand: no"
    $ymlLines += "    sourceProtocol: tcp"
}
$ymlLines | Set-Content -Path "C:\RetailWatch\mediamtx\mediamtx-store.yml" -Encoding UTF8
Write-Host "      mediamtx config written." -ForegroundColor Green

# Write store-config.json
$cameras = @()
for ($i = 1; $i -le $camCount; $i++) {
    $rtsp = Get-RtspUrl $dvrIp $dvrPass $i $dvrType
    $cameras += [PSCustomObject]@{ id = $i; url = $rtsp }
}
$config = [PSCustomObject]@{
    store_name = $storeName
    store_slug = $storeSlug
    cameras    = $cameras
}
$config | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\RetailWatch\store-config.json" -Encoding UTF8
Write-Host "      Person detector config written." -ForegroundColor Green

# Check ZeroTier
Write-Host ""
Write-Host "Checking ZeroTier..." -ForegroundColor Yellow
$ztIp = $null
try {
    $ztInfo = & "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat" listnetworks 2>$null
    if ($ztInfo -match "cf719fd5401745ac") {
        Write-Host "      ZeroTier connected." -ForegroundColor Green
        $ztMatch = [regex]::Match($ztInfo, "10\.23\.157\.\d+")
        if ($ztMatch.Success) {
            $ztIp = $ztMatch.Value
            Write-Host "      Store ZeroTier IP: $ztIp" -ForegroundColor Cyan
        }
    } else {
        Write-Host "      ZeroTier not connected - check ethernet and ZeroTier Central approval." -ForegroundColor Red
    }
} catch {
    Write-Host "      Could not check ZeroTier status." -ForegroundColor Red
}

# Launch mediamtx
Write-Host ""
Write-Host "Starting mediamtx..." -ForegroundColor Yellow
$p1 = New-Object System.Diagnostics.ProcessStartInfo
$p1.FileName = "C:\RetailWatch\mediamtx\mediamtx.exe"
$p1.Arguments = "C:\RetailWatch\mediamtx\mediamtx-store.yml"
$p1.CreateNoWindow = $true
$p1.UseShellExecute = $false
[System.Diagnostics.Process]::Start($p1) | Out-Null
Start-Sleep 5
Write-Host "      mediamtx running." -ForegroundColor Green

# Launch person detector
Write-Host "Starting person detector..." -ForegroundColor Yellow
$p2 = New-Object System.Diagnostics.ProcessStartInfo
$p2.FileName = "C:\Program Files\Python311\python.exe"
$p2.Arguments = "C:\RetailWatch\person-detector.py"
$p2.CreateNoWindow = $true
$p2.UseShellExecute = $false
[System.Diagnostics.Process]::Start($p2) | Out-Null
Write-Host "      Person detector running." -ForegroundColor Green

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Store configuration COMPLETE - $storeName" -ForegroundColor Green
Write-Host ""
Write-Host "  Verify cameras from your back-office PC:" -ForegroundColor White
if ($ztIp) {
    Write-Host "  http://${ztIp}:8888/cam1/index.m3u8" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "  Reboot to confirm auto-start works." -ForegroundColor White
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to close"
