# AGENTS.md - Hướng dẫn tích hợp BYOK vào Codex Desktop qua LiteLLM

> **Audience:** AI agent hoặc developer muốn setup integration BYOK models
> (qwen, kimi, deepseek, glm, mimo, minimax, hy3) vào **OpenAI Codex Desktop**
> thông qua **LiteLLM proxy** + **OpenCode Go API**.
>
> Sau khi clone repo, làm theo [Quick Start](#quick-start) để có 17 models
> trong Codex Desktop picker trong ~5 phút.

---

## Quick Start

```powershell
# 1. Clone repo
git clone <repo-url> F:\Projects\litellm-byok
cd F:\Projects\litellm-byok

# 2. Tạo file .env từ template, điền API key thật
Copy-Item .env.example .env
notepad .env   # sửa OPENCODE_GO_API_KEY thành key thật của bạn

# 3. Patch LiteLLM (idempotent, tự động skip nếu đã patch)
python patch-litellm.py

# 4. Start proxy (detached, sống khi đóng terminal)
powershell -ExecutionPolicy Bypass -File .\start-proxy.ps1

# 5. Verify
curl http://127.0.0.1:4000/health/liveliness

# 6. Cấu hình Codex Desktop
#    Mở file C:\Users\<USER>\.codex\config.toml
#    Copy nội dung từ [Codex Desktop Config](#codex-desktop-config) bên dưới
#    Sửa đường dẫn model_catalog_json thành đường dẫn tuyệt đối của máy bạn

# 7. Restart Codex Desktop (close + reopen app) để load catalog
#    Picker sẽ hiển thị 17 models
```

---

## Kiến trúc

```
+------------------+         +--------------------+         +-------------------+
|                  |  HTTP   |                    |  HTTP   |                   |
|  Codex Desktop   | /v1/    |  LiteLLM Proxy     | /v1/    |  OpenCode Go API  |
|  (model picker)  +-------->|  (localhost:4000)  +-------->|  (BYOK)           |
|                  | 401     |                    |         |                   |
|  wire_api=       |         |  Responses API     |         |  Chat Completions |
|  responses       |         |  -> Chat Compl.    |         |  API              |
+------------------+         |  Bridge (+patch)   |         +-------------------+
                             +---------+----------+
                                       |
                                       |  17 models từ config.yaml
                                       v
                             +-------------------+
                             |  LiteLLM Router   |
                             |  config.yaml      |
                             |  (17 deployments) |
                             +-------------------+
```

**Vai trò mỗi thành phần:**

- **Codex Desktop** — GUI của OpenAI, gọi `/v1/responses` với wire_api="responses"
  (chat API đã bị deprecate, xem [note](#wire_api-responses-vs-chat))
- **LiteLLM Proxy** — local server (port 4000), dịch `/v1/responses`
  sang `/v1/chat/completions` cho từng model, thêm 2 patches để fix lỗi
  của LiteLLM bridge với Alibaba upstream
- **OpenCode Go API** — BYOK gateway, forward sang Alibaba/Moonshot/Zhipu/Xiaomi/MiniMax/...
  Tính phí theo token usage của upstream thật

---

## Cấu trúc thư mục

```
F:\Projects\litellm-byok\
├── docs/
│   ├── AGENTS.md            ← File này
│   └── README.md            ← (optional) human-facing overview
├── .env.example             ← Template env vars (copy thành .env)
├── .gitignore               ← Ignore .env, logs, __pycache__
│
├── config.yaml              ← LiteLLM config: 17 models + master_key
├── model-catalog.json       ← Codex Desktop catalog: 17 model entries
│
├── start-litellm.bat        ← Launcher that patches + starts proxy
├── start-proxy.ps1          ← Detach script (UseShellExecute, minimised)
├── patch-litellm.py         ← Apply 2 patches to LiteLLM source (idempotent)
│
├── litellm.log              ← Proxy stdout (sinh khi start)
├── litellm-err.log          ← Proxy stderr
└── proxy.log                ← (deprecated, giữ để tương thích người dùng cũ)
```

**Các file Codex (ngoài repo, user-scoped):**

```
C:\Users\<USER>\.codex\config.toml           ← Codex Desktop config chính
C:\Users\<USER>\.codex\model-catalogs\        ← (optional) catalog dir
```

---

## Chi tiết từng file

### `config.yaml` — LiteLLM config

17 model deployments. Mỗi entry:

```yaml
- model_name: qwen3.6-plus           # Tên hiển thị trong picker
  litellm_params:
    model: openai/chat_completions/qwen3.6-plus   # openai/<name> = forward
    api_key: os.environ/OPENCODE_GO_API_KEY
    api_base: https://opencode.ai/zen/go/v1
```

**Quy ước:**

- `openai/chat_completions/<name>` (có prefix `chat_completions/`)
  → LiteLLM bật bridge Responses → Chat Completions
- `openai/<name>` (không prefix) → forward raw, chỉ dùng nếu upstream support /v1/responses
- `anthropic/<name>` → dùng Anthropic Messages API (cho qwen3.7-max vì upstream reject OpenAI format)
- `os.environ/XXX` → lấy API key từ biến môi trường, KHÔNG hardcode

### `model-catalog.json` — Codex catalog

JSON file Codex Desktop đọc để populate model picker. Schema bám sát
`codex-rs/protocol/src/openai_models.rs::ModelInfo` (17+ required fields).
`model_catalog_json` **replace** bundled catalog (không merge) — nếu muốn
giữ GPT-5.x mặc định thì cũng include trong file này.

**Field bắt buộc (theo schema chuẩn):**

| Field                          | Ý nghĩa                                                |
|--------------------------------|--------------------------------------------------------|
| `slug`                         | Tên model, phải khớp với `model` trong config.toml     |
| `display_name`                 | Tên hiển thị trong UI (snake_case, KHÔNG phải camelCase) |
| `description`                  | Mô tả ngắn                                             |
| `visibility`                   | `"list"` để hiển thị, `"none"` để ẩn                   |
| `supported_in_api`             | `true` cho phép gọi API                                |
| `priority`                     | Thứ tự hiển thị (số nhỏ = lên đầu)                     |
| `shell_type`                   | `"shell_command"` cho codex shell                      |
| `default_reasoning_level`      | `low/medium/high/xhigh`                                |
| `supported_reasoning_levels`   | Array các object `{effort, description}`               |
| `default_reasoning_summary`    | `"auto"` hoặc `"none"`                                 |
| `default_verbosity`            | `"low"`                                                |
| `apply_patch_tool_type`        | `"freeform"`                                           |
| `web_search_tool_type`         | `"text"` (BYOK không có web search thật)               |
| `truncation_policy`            | `{mode: "bytes", limit: 10000}`                        |
| `context_window`/`max_context_window` | Token context (vd 1048576 = 1M)                  |
| `effective_context_window_percent` | Phần trăm context usable (thường 95)                |
| `input_modalities`             | `["text"]` hoặc `["text", "image"]`                    |
| `supports_parallel_tool_calls` | Multi-tool calls cùng lúc                              |
| `supports_image_detail_original` | Image detail gốc hay compressed                      |
| `supports_reasoning_summaries` | Reasoning ở chaining                                   |
| `supports_search_tool`         | Web search support                                     |
| `support_verbosity`            | Verbosity level support                                |
| `experimental_supported_tools` | `[]`                                                   |
| `additional_speed_tiers`       | `[]`                                                   |
| `availability_nux`             | `null` (hoặc object với `message` nếu cần NUX)         |
| `upgrade`                      | `null` (hoặc `{model, migration_markdown}`)            |
| `base_instructions`            | System prompt cho model                                |
| `model_messages`               | `null` (hoặc `{instructions_template, instructions_variables}`) |

**Field KHÔNG tồn tại trong struct** (gây parse error toàn file):
- `displayName` (camelCase) → dùng `display_name`
- `provider` → không cần, model match với provider qua `model_provider` config
- `hidden` (boolean) → dùng `visibility: "list"/"none"`

**Bug cần biết:** [GitHub #19694](https://github.com/openai/codex/issues/19694)
— Desktop UI có thể filter models từ `model_catalog_json` nếu không match
remote allowlist. Workaround: set `model = "<slug>"` trong `config.toml`
(model sẽ hiện `Custom` nhưng vẫn select được, slug được pass qua API).

**Encoding warning:** File phải là UTF-8 KHÔNG có BOM. Nếu dùng `Set-Content`
hoặc tool tự thêm BOM (`EF BB BF`) thì Codex sẽ fail parse với
"expected value at line 1 column 1".

### `start-litellm.bat` — Launcher

```bat
@echo off
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1
set "OPENCODE_GO_API_KEY=sk-..."         # Từ .env (hoặc copy từ đây)
set "LITELLM_MASTER_KEY=sk-..."          # Từ .env
cd /d F:\Projects\litellm-byok
python patch-litellm.py || exit /b 1
litellm --config config.yaml --port 4000 > litellm.log 2> litellm-err.log
```

**Vì sao cần hardcode trong .bat?**
Khi `start /MIN` mở cửa sổ console mới, nó KHÔNG kế thừa env vars từ
parent PowerShell shell. Phải set trong .bat.

### `start-proxy.ps1` — Detach script

PowerShell script gọi `start-litellm.bat` qua `ProcessStartInfo` với
`UseShellExecute = $true` để detach khỏi parent process. Nên dùng
`UseShellExecute` thay vì `start /MIN` (start /MIN bị hang khi gọi từ
PowerShell).

### `patch-litellm.py` — LiteLLM patches

Script idempotent apply 2 patches cần thiết. **KHÔNG thể skip patch này** —
nếu không patch, 1-2 model sẽ lỗi ngay.

#### PATCH 1: Empty tools list (line ~211)

**Lỗi:**

```
BadRequestError: OpenAIException - Error from provider (Alibaba):
  [] is too short - 'tools'
```

Khi Codex gọi `/v1/responses` mà KHÔNG có tools (chỉ text), LiteLLM
forward `"tools": []` (empty list) cho upstream. Alibaba upstream từ
chối vì schema yêu cầu `tools` là non-empty array.

**Fix:** Trong `transformation.py:211`, đổi `"tools": tools` thành
`"tools": tools if tools else None` → empty list thành None → bị filter
bởi dict comprehension `if v is not None`.

#### PATCH 2: Non-function tool conversion (line ~1415)

**Lỗi:**

```
BadRequestError: OpenAIException - Error from provider (Alibaba):
  'function' is a required property, expected an object - 'tools.8'
```

Khi Codex gọi tools (9+ tools bao gồm `code_interpreter`, `file_search`),
LiteLLM bridge ở `transform_responses_api_tools_to_chat_completion_tools`
có `else: pass-through` cho các tool type khác `function`/`mcp`/
`web_search`. Pass-through nguyên xi → upstream reject.

**Fix:** Thay `else:` bằng `elif isinstance(tool, dict) and any(k in tool for k in [...])`
→ best-effort convert: tool có `name`/`description`/`parameters` → wrap
trong `function{}`. Tool không có (vd `file_search`, `code_interpreter`)
bị skip.

**Tại sao cần patch source thay vì dùng config?**
LiteLLM bridge có thể được config qua `drop_params: true`, nhưng:
- `drop_params` chỉ drop params không support, không phải drop empty list
- Không có setting nào config behavior của `else` branch

→ Phải patch source. **Idempotent** + **auto-applied** qua `start-litellm.bat`.

#### Khi LiteLLM update

```powershell
pip install --upgrade litellm
python patch-litellm.py    # Nếu marker không khớp, script báo lỗi
# → Update marker trong patch-litellm.py cho khớp source mới
```

---

## Codex Desktop Config

File: `C:\Users\<USER>\.codex\config.toml`

```toml
# Chọn model mặc định
model = "qwen3.6-plus"
model_provider = "litellm_byok"

# Reasoning effort (low/medium/high/xhigh)
model_reasoning_effort = "high"

# Disable WebSocket - LiteLLM proxy chỉ support HTTPS
supports_websockets = true   # Đặt true để Codex tự fallback HTTPS

# QUAN TRỌNG: model_catalog_json PHẢI ở ROOT level (không phải trong [model_providers])
model_catalog_json = 'F:\Projects\litellm-byok\model-catalog.json'

[model_providers.litellm_byok]
name = "LiteLLM BYOK (OpenCode Go)"
base_url = "http://127.0.0.1:4000/v1"
wire_api = "responses"                           # Responses API, KHÔNG dùng "chat"
experimental_bearer_token = "sk-litellm-master-key-1234"
request_max_retries = 3
stream_max_retries = 3
stream_idle_timeout_ms = 600000
```

**Restart Codex Desktop** (close + reopen app, không chỉ refresh) để
load catalog mới.

**Verify:**

1. Click model picker → thấy 5 GPT-5.x mặc định → 17 BYOK models
2. Chọn 1 model, chat "hello" → response OK
3. Picker có thể hiện `Custom` thay vì tên model (bug #19694), vẫn select được

---

## wire_api: responses vs chat

OpenAI đang deprecate `wire_api = "chat"`. Cảnh báo trong Codex:

```
Support for the "chat" wire API is deprecated and will soon be removed.
Update your model provider definition in config.toml to use wire_api = "responses".
```

**Lý do chọn "responses":**

- Chat Completions không support reasoning, prompt caching, parallel tools đầy đủ
- Responses API là wire mới, OpenAI thêm features ở đây trước
- Bridge sang Chat Completions ở LiteLLM (forward compat)

**Bridge hoạt động như thế nào:**

Codex gửi POST /v1/responses với body Responses format →
LiteLLM transform thành POST /v1/chat/completions với body Chat Compl format →
OpenCode Go upstream xử lý → response về → LiteLLM transform ngược lại
→ Codex nhận Responses format.

Hai patches ở trên fix lỗi trong quá trình transform.

---

## 17 Models

| Slug              | Provider (real)       | Format           | Ghi chú                    |
|-------------------|----------------------|------------------|----------------------------|
| kimi-k2.5         | Moonshot             | chat_completions | 256K context               |
| kimi-k2.6         | Moonshot             | chat_completions | 256K context, latest        |
| qwen3.6-plus      | Alibaba              | chat_completions | 1M context, reasoning      |
| qwen3.5-plus      | Alibaba              | chat_completions | 1M context                  |
| qwen3.7-max       | Alibaba              | anthropic        | 1M context, flag-ship       |
| deepseek-v4-flash | DeepSeek             | chat_completions | 128K, fast                  |
| deepseek-v4-pro   | DeepSeek             | chat_completions | 128K, code                   |
| glm-5             | Zhipu                | chat_completions | 128K                         |
| glm-5.1           | Zhipu                | chat_completions | 128K, latest                 |
| mimo-v2.5         | Xiaomi               | chat_completions | 128K                         |
| mimo-v2.5-pro     | Xiaomi               | chat_completions | 128K                         |
| mimo-v2-pro       | Xiaomi               | chat_completions | 128K                         |
| mimo-v2-omni      | Xiaomi               | chat_completions | multimodal (text+image)     |
| minimax-m2.5      | MiniMax              | chat_completions | 128K                         |
| minimax-m2.7      | MiniMax              | chat_completions | 128K                         |
| minimax-m3        | MiniMax              | chat_completions | 128K, latest                 |
| hy3-preview       | (TBD)                | chat_completions | preview                       |

**Cách thêm model mới:**

1. Lấy slug + provider từ OpenCode Go dashboard
2. Thêm entry vào `config.yaml`:
   ```yaml
   - model_name: new-model-slug
     litellm_params:
       model: openai/chat_completions/new-model-slug
       api_key: os.environ/OPENCODE_GO_API_KEY
       api_base: https://opencode.ai/zen/go/v1
   ```
3. Thêm entry tương ứng vào `model-catalog.json`
4. Restart proxy + Codex Desktop

---

## Troubleshooting

### Proxy không start

```powershell
# Check process
Get-Process -Name litellm
Get-NetTCPConnection -LocalPort 4000 -State Listen

# Check logs
Get-Content F:\Projects\litellm-byok\litellm-err.log -Tail 30
```

**Lỗi thường gặp:**

- `Address already in use` → có proxy cũ chưa tắt, `Stop-Process -Name litellm -Force`
- `ModuleNotFoundError: litellm` → `pip install litellm==1.86.2`
- `OPENCODE_GO_API_KEY not set` → check `.env` hoặc hardcode trong `start-litellm.bat`

### Model trả lời lỗi 400 (Alibaba)

```powershell
Get-Content F:\Projects\litellm-byok\litellm-err.log -Tail 50
```

- `[] is too short - 'tools'` → PATCH 1 chưa apply, chạy `python patch-litellm.py`
- `'function' is a required property, expected an object - 'tools.N'` → PATCH 2 chưa apply
- `Invalid model name` → slug không match config.yaml

### Codex picker không hiện 17 models

1. Kiểm tra `config.toml` có `model_catalog_json` ở ROOT level
2. Kiểm tra đường dẫn absolute đúng
3. Restart Codex Desktop (close + reopen)
4. Kiểm tra JSON hợp lệ: `Get-Content model-catalog.json | ConvertFrom-Json`
5. Bug #19694: models hiện `Custom` thay vì tên → vẫn select được

### Proxy sống nhưng Codex không gọi được

```powershell
# Test trực tiếp
curl -H "Authorization: Bearer sk-litellm-master-key-1234" `
     -H "Content-Type: application/json" `
     -d '{"model":"kimi-k2.5","input":"hi"}' `
     http://127.0.0.1:4000/v1/responses
```

Nếu curl OK mà Codex fail → check `model_provider` trong config.toml
phải là `litellm_byok`, khớp với `[model_providers.litellm_byok]`.

---

## Common Tasks

### Update 1 model config (vd đổi base_url)

```yaml
# config.yaml
- model_name: qwen3.6-plus
  litellm_params:
    model: openai/chat_completions/qwen3.6-plus
    api_key: os.environ/OPENCODE_GO_API_KEY
    api_base: https://new-url.example.com/v1   # ← sửa ở đây
```

Sau đó restart proxy.

### Restart proxy

```powershell
Stop-Process -Name litellm -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
powershell -ExecutionPolicy Bypass -File F:\Projects\litellm-byok\start-proxy.ps1
```

### Test 1 model

```powershell
$body = '{"model":"kimi-k2.5","input":"Say OK"}'
$r = Invoke-RestMethod -Uri "http://127.0.0.1:4000/v1/responses" `
    -Method Post -Headers @{Authorization="Bearer sk-litellm-master-key-1234"} `
    -Body $body -ContentType "application/json"
$r.output[-1].content[0].text
```

### Add new OpenCode Go model

1. Lấy slug + provider từ dashboard
2. Add 1 entry vào `config.yaml` (copy từ model tương tự)
3. Add 1 entry vào `model-catalog.json`
4. Restart proxy + Codex

### Khi OpenCode Go đổi API key

```powershell
# Sửa .env
notepad F:\Projects\litellm-byok\.env
# Hoặc sửa trực tiếp start-litellm.bat nếu muốn hardcode

# Restart proxy
Stop-Process -Name litellm -Force
powershell -ExecutionPolicy Bypass -File F:\Projects\litellm-byok\start-proxy.ps1
```

---

## Biến môi trường

| Biến                 | Mặc định                   | Ý nghĩa                            |
|---------------------|----------------------------|-------------------------------------|
| `OPENCODE_GO_API_KEY`| (không có)                 | API key của OpenCode Go              |
| `LITELLM_MASTER_KEY`| `sk-litellm-master-key-1234` | Auth cho /v1/* của proxy            |
| `PYTHONIOENCODING`  | `utf-8`                     | Encoding stdout                     |
| `PYTHONUTF8`        | `1`                         | UTF-8 mode cho Python (Windows)     |

---

## Phiên bản

| Component   | Version  | Note                                       |
|-------------|----------|--------------------------------------------|
| Python      | 3.12     | Tested                                     |
| LiteLLM     | 1.86.2   | Patches written for this version           |
| Codex       | 26.422+  | Desktop app                                |
| OpenCode Go | (any)    | BYOK API                                   |

---

## Tài liệu tham khảo

- [Codex Desktop - Code GUI 3rd-party models](https://www.cnblogs.com/surenkid/p/20037840)
- [Codex Desktop - model_catalog_json filter bug](https://github.com/openai/codex/issues/19694)
- [Codex CLI - custom providers](https://ofox.ai/blog/codex-cli-custom-model-providers-byo-setup/)
- [Codex wire_api deprecation](https://blog.csdn.net/qq_36396104/article/details/156774089)
- [LiteLLM proxy docs](https://docs.litellm.ai/docs/proxy/quick_start)
- [OpenCode Go dashboard](https://opencode.ai)

---

## Contributing

Khi sửa config, ghi rõ:
- Số model thay đổi
- Lý do (vd: thêm model X, fix provider cho Y)
- Test: `python -c "import requests; ..."` để verify /v1/models trả về đúng

Khi LiteLLM update version, cần update marker trong `patch-litellm.py`
để khớp với source mới.
