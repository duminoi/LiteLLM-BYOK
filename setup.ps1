<#
.SYNOPSIS
    Setup LiteLLM BYOK proxy cho Codex Desktop.
    Tự động kiểm tra môi trường, cài đặt dependencies, patch LiteLLM.

.DESCRIPTION
    Script này chạy 1 lần duy nhất trên máy mới:
    1. Kiểm tra Python 3.12+
    2. Tạo .env từ .env.example (nếu chưa có)
    3. Prompt nhập OpenCode Go API key
    4. pip install -r requirements.txt
    5. Apply patches cho LiteLLM
    6. Hướng dẫn config Codex Desktop

.EXAMPLE
    .\setup.ps1
#>

$ErrorActionPreference = "Stop"
$repoDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg){ Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "  [ERROR] $msg" -ForegroundColor Red }

Write-Host @"
====================================
  LiteLLM BYOK Setup - Codex Desktop
====================================
"@ -ForegroundColor Magenta

# --------------------------------------------------
# 1. Check Python
# --------------------------------------------------
Write-Step "1. Kiem tra Python installation..."
$py = Get-Command "python" -ErrorAction SilentlyContinue
if (-not $py) {
    $py = Get-Command "python3" -ErrorAction SilentlyContinue
}
if (-not $py) {
    Write-Err "Python chua duoc cai dat. Tai tu: https://www.python.org/downloads/"
    Write-Host "  Cai Python 3.12+, nho check 'Add Python to PATH'."
    exit 1
}
Write-OK "Tim thay Python tai: $($py.Source)"

$ver = & $py.Source -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
Write-OK "Python version: $ver"

[int]$maj = $ver.Split('.')[0]
[int]$min = $ver.Split('.')[1]
if ($maj -lt 3 -or ($maj -eq 3 -and $min -lt 10)) {
    Write-Err "Can Python 3.10+, dang dung $ver. Hay nang cap."
    exit 1
}

# --------------------------------------------------
# 2. Create .env from template
# --------------------------------------------------
Write-Step "2. Thiet lap file .env..."
$envFile = Join-Path $repoDir ".env"
$envExample = Join-Path $repoDir ".env.example"

if (-not (Test-Path $envFile)) {
    if (Test-Path $envExample) {
        Copy-Item $envExample $envFile
        Write-OK "Da tao .env tu .env.example"
    } else {
        Write-Warn "Khong tim thay .env.example, tao .env moi..."
        Set-Content -Path $envFile -Value "OPENCODE_GO_API_KEY=`nLITELLM_MASTER_KEY=sk-litellm-master-key-1234"
    }
}

# --------------------------------------------------
# 3. Prompt for API key
# --------------------------------------------------
Write-Step "3. Kiem tra API key..."
$currentKey = (Get-Content $envFile | Where-Object { $_ -match "^OPENCODE_GO_API_KEY=" }) -replace "^OPENCODE_GO_API_KEY=", ""
$currentKey = $currentKey.Trim()

if ([string]::IsNullOrEmpty($currentKey) -or $currentKey -match "your-opencode-go-api-key-here") {
    Write-Warn "OPENCODE_GO_API_KEY chua duoc cau hinh."
    Write-Host "  Lay API key tu: https://opencode.ai (dashboard cua ban)" -ForegroundColor Yellow
    $newKey = Read-Host "  Nhap OPENCODE_GO_API_KEY cua ban (hoac Enter de bo qua)"
    if (-not [string]::IsNullOrEmpty($newKey)) {
        $content = Get-Content $envFile -Raw
        if ($content -match "OPENCODE_GO_API_KEY=.*") {
            $content = $content -replace "OPENCODE_GO_API_KEY=.*", "OPENCODE_GO_API_KEY=$newKey"
        } else {
            $content += "`r`nOPENCODE_GO_API_KEY=$newKey"
        }
        Set-Content -Path $envFile -Value $content
        Write-OK "Da cap nhat OPENCODE_GO_API_KEY"
    } else {
        Write-Warn "Bo qua nhap key. Proxy se khong the goi API cho den khi ban set key trong .env"
    }
} else {
    Write-OK "OPENCODE_GO_API_KEY da duoc cau hinh"
}

# --------------------------------------------------
# 4. Install dependencies
# --------------------------------------------------
Write-Step "4. Cai dat Python dependencies..."
$reqFile = Join-Path $repoDir "requirements.txt"
if (-not (Test-Path $reqFile)) {
    Write-Err "Thieu file requirements.txt. Clone lai repo?"
    exit 1
}

Write-Host "  Chay: pip install -r requirements.txt..."
& $py.Source -m pip install -r $reqFile
if ($LASTEXITCODE -ne 0) {
    Write-Err "pip install that bai. Kiem tra ket noi mang."
    exit 1
}
Write-OK "Dependencies da duoc cai dat"

# --------------------------------------------------
# 5. Verify LiteLLM installed
# --------------------------------------------------
Write-Step "5. Kiem tra LiteLLM installation..."
try {
    $llmVer = & $py.Source -c "import litellm; print(litellm.__file__)"
    if ($LASTEXITCODE -eq 0) {
        Write-OK "LiteLLM da cai tai: $llmVer"
    }
} catch {
    Write-Err "LiteLLM khong tim thay du sau khi pip install."
    exit 1
}

# --------------------------------------------------
# 6. Apply patches
# --------------------------------------------------
Write-Step "6. Apply patches cho LiteLLM..."
$patchFile = Join-Path $repoDir "patch-litellm.py"
if (-not (Test-Path $patchFile)) {
    Write-Err "Thieu file patch-litellm.py"
    exit 1
}

& $py.Source $patchFile
if ($LASTEXITCODE -ne 0) {
    Write-Err "Patch that bai. Kiem tra phia tren de biet chi tiet."
    exit 1
}
Write-OK "LiteLLM da duoc patch"

# --------------------------------------------------
# 7. Guide Codex Desktop config
# --------------------------------------------------
Write-Step "7. Huong dan cau hinh Codex Desktop..."

$codexConfig = "$env:USERPROFILE\.codex\config.toml"
$codexConfigExists = Test-Path $codexConfig

if ($codexConfigExists) {
    Write-OK "Tim thay file config Codex tai: $codexConfig"
    $hasProvider = Select-String -Path $codexConfig -Pattern "litellm_byok" -SimpleMatch -Quiet
    if ($hasProvider) {
        Write-OK "Provider litellm_byok da duoc cau hinh trong config.toml"
    } else {
        Write-Warn "Provider litellm_byok chua co trong config.toml."
        Write-Host "  Them config sau day vao $codexConfig :" -ForegroundColor Yellow
        Write-Host @"

  model = "mimo-v2.5"
  model_provider = "litellm_byok"

  [model_providers.litellm_byok]
  name = "LiteLLM BYOK (OpenCode Go)"
  base_url = "http://127.0.0.1:4000/v1"
  wire_api = "responses"
  experimental_bearer_token = "sk-litellm-master-key-1234"
  request_max_retries = 3
  stream_max_retries = 3
  stream_idle_timeout_ms = 600000

  model_catalog_json = '$repoDir\model-catalog.json'

"@ -ForegroundColor Green
    }
} else {
    Write-Warn "Chua tim thay config Codex Desktop."
    Write-Host "  Tao file config thu cong tai: $codexConfig" -ForegroundColor Yellow
    Write-Host @"
  Voi noi dung:

  model = "mimo-v2.5"
  model_provider = "litellm_byok"

  [model_providers.litellm_byok]
  name = "LiteLLM BYOK (OpenCode Go)"
  base_url = "http://127.0.0.1:4000/v1"
  wire_api = "responses"
  experimental_bearer_token = "sk-litellm-master-key-1234"
  request_max_retries = 3
  stream_max_retries = 3
  stream_idle_timeout_ms = 600000

  model_catalog_json = '$repoDir\model-catalog.json'

"@ -ForegroundColor Green
}

# --------------------------------------------------
# 8. Done
# --------------------------------------------------
Write-Step "8. Hoan tat setup!"

Write-Host @"
  Tiep theo:
    1. Chay: .\start-proxy.ps1        (khoi dong proxy)
    2. Mo Codex Desktop, chon model va bat dau dung

  Neu gap loi, xem docs/AGENTS.md hoac docs/README.md.
"@ -ForegroundColor Cyan

Write-OK "Setup hoan tat!"