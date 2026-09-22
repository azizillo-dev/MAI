# Mentor AI: backend + Cloudflare tunnel'ni ishga tushiradi.
# Ishlatish: PowerShell'da  powershell -ExecutionPolicy Bypass -File D:\mentor_AI\start_server.ps1
# Diqqat: bepul tunnel har ishga tushishda YANGI manzil beradi — manzil o'zgarsa APK qayta yig'ilishi kerak.

$ErrorActionPreference = "Stop"
$backend = "D:\mentor_AI\backend"
$logs = "$backend\logs"
New-Item -ItemType Directory -Force $logs | Out-Null

# Eski jarayonlarni to'xtatish
Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -Confirm:$false }
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false

# 1) Tunnel
Remove-Item "$logs\tunnel.log" -ErrorAction SilentlyContinue
Start-Process -FilePath "D:\dev\cloudflared\cloudflared.exe" `
    -ArgumentList "tunnel", "--no-autoupdate", "--url", "http://localhost:8000", "--logfile", "$logs\tunnel.log" `
    -WindowStyle Hidden
$url = $null
for ($i = 0; $i -lt 30 -and -not $url; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path "$logs\tunnel.log") {
        $m = Select-String -Path "$logs\tunnel.log" -Pattern "https://[a-z0-9-]+\.trycloudflare\.com" | Select-Object -First 1
        if ($m) { $url = $m.Matches[0].Value }
    }
}
if (-not $url) { throw "Tunnel manzili olinmadi, $logs\tunnel.log ni tekshiring" }

# 2) Rasm havolalari to'g'ri ishlashi uchun PUBLIC_API_URL yangilanadi
$envFile = "$backend\.env"
$lines = Get-Content $envFile | Where-Object { $_ -notmatch '^PUBLIC_API_URL=' }
$lines += "PUBLIC_API_URL=$url"
# BOM'siz yozish: aks holda .env'ning birinchi qatori (ENVIRONMENT) noto'g'ri o'qiladi
[System.IO.File]::WriteAllLines($envFile, [string[]]$lines)

# 3) Backend
Start-Process -FilePath "$backend\.venv\Scripts\python.exe" `
    -ArgumentList "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips=*" `
    -WorkingDirectory $backend -WindowStyle Hidden `
    -RedirectStandardOutput "$logs\api.log" -RedirectStandardError "$logs\api.err.log"
# Lokal server tayyorligini tekshiramiz. Tunnel manzilini shu kompyuterdan tekshirmaymiz:
# yangi nom kompyuter DNS keshiga kech tushadi, telefonlarda esa darhol ishlaydi.
$health = $null
for ($i = 0; $i -lt 20 -and -not $health; $i++) {
    Start-Sleep -Seconds 2
    try { $health = (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:8000/health" -TimeoutSec 10).Content } catch { }
}
if (-not $health) { throw "Backend ishga tushmadi, $logs\api.err.log ni tekshiring" }
$registered = $false
for ($i = 0; $i -lt 20 -and -not $registered; $i++) {
    $registered = [bool](Select-String -Path "$logs\tunnel.log" -Pattern "Registered tunnel connection" -Quiet)
    if (-not $registered) { Start-Sleep -Seconds 2 }
}
if (-not $registered) { throw "Tunnel Cloudflare'ga ulanmadi, $logs\tunnel.log ni tekshiring" }

Write-Host ""
Write-Host "Server ishlayapti: $health"
Write-Host "Manzil:       $url"
Write-Host "Admin panel:  $url/admin"
Write-Host ""
Write-Host "Agar manzil APK'dagidan farq qilsa, APK'ni qayta yig'ing:"
Write-Host "  flutter build apk --release --dart-define=API_BASE_URL=$url/api/v1"

