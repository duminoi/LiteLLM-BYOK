$ErrorActionPreference = "Continue"

$logDir = "F:\Projects\litellm-byok"
$cfgFile = Join-Path $logDir "config.yaml"
$port = 4000
$batFile = Join-Path $logDir "start-litellm.bat"

# Load keys from .env if not set
$envFile = Join-Path $logDir ".env"
if (-not $env:LITELLM_MASTER_KEY -and (Test-Path $envFile)) {
    Get-Content $envFile | ForEach-Object {
        $parts = $_ -split "=", 2
        if ($parts.Count -eq 2) { Set-Item -Path "Env:$($parts[0].Trim())" -Value $parts[1].Trim() }
    }
}

Get-Process -Name "litellm" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Output "Stopping existing LiteLLM (PID $($_.Id))..."
    Stop-Process -Id $_.Id -Force
}
Start-Sleep -Seconds 1

Write-Output "Starting LiteLLM proxy..."
Write-Output "  Batch : $batFile"

# UseShellExecute = true: launch via Windows shell (explorer) = fully detached
#   - new process tree NOT in this terminal's Job Object
#   - survives terminal close
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $batFile
$psi.WorkingDirectory = $logDir
$psi.UseShellExecute = $true
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized
$psi.ErrorDialog = $false
[System.Diagnostics.Process]::Start($psi) | Out-Null
Write-Output "Started (UseShellExecute, minimized) - waiting for proxy..."

$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port/health/liveliness" -UseBasicParsing -TimeoutSec 2 -Headers @{"Authorization" = "Bearer $env:LITELLM_MASTER_KEY"} -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
}

if ($ready) {
    $p = Get-Process -Name "litellm" -ErrorAction SilentlyContinue | Select-Object -First 1
    Write-Output "OK - proxy live at http://127.0.0.1:$port (litellm PID $($p.Id))"
    Write-Output "`nYou can close this terminal - proxy will stay running."
} else {
    Write-Output "ERROR - proxy not ready after 30s."
    $err = Get-Content (Join-Path $logDir "litellm-err.log") -Tail 20 -ErrorAction SilentlyContinue
    if ($err) { Write-Output "Err log:"; $err }
    $out = Get-Content (Join-Path $logDir "litellm.log") -Tail 5 -ErrorAction SilentlyContinue
    if ($out) { Write-Output "Stdout log:"; $out }
}
