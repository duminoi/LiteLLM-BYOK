# LiteLLM BYOK cho Codex Desktop

Proxy LiteLLM trung gian giữa Codex Desktop và OpenCode Go (BYOK subscription), trỏ 17 model open-source qua 1 endpoint duy nhất.

## Kiến trúc

```
Codex Desktop ──gọi /v1/responses──→ LiteLLM ──gọi /v1/chat/completions──→ OpenCode Go API
  (model picker)         (localhost:4000)                 (BYOK upstream)
                              │
                              │ 17 models từ config.yaml
                              v
                        LiteLLM Router
                        (17 deployments)
```

## Quick Start (máy mới)

```powershell
# 1. Clone repo
git clone <url> F:\Projects\litellm-byok
cd F:\Projects\litellm-byok

# 2. Auto setup: check Python → tạo .env → cài pip → patch LiteLLM
powershell -ExecutionPolicy Bypass -File .\setup.ps1

# 3. Start proxy (detached, sống khi đóng terminal)
powershell -ExecutionPolicy Bypass -File .\start-proxy.ps1

# 4. Mở Codex Desktop, chọn model và dùng
```

## Mỗi lần dùng

```powershell
powershell -ExecutionPolicy Bypass -File F:\Projects\litellm-byok\start-proxy.ps1
```

Đợi dòng `OK - proxy live at http://127.0.0.1:4000` rồi mở Codex Desktop.

## Cấu trúc thư mục

```
F:\Projects\litellm-byok\
├── docs/
│   ├── AGENTS.md          ← Hướng dẫn chi tiết cho AI agent
│   └── README.md          ← File này
├── requirements.txt       ← Python dependency (litellm==1.86.2)
├── setup.ps1              ← Script setup 1 lần trên máy mới
├── config.yaml            ← 17 models + master key
├── model-catalog.json     ← Catalog cho Codex Desktop picker
├── patch-litellm.py       ← Patch LiteLLM bridge bugs (idempotent)
├── start-litellm.bat      ← Launcher (đọc key từ .env)
├── start-proxy.ps1        ← Detach script (UseShellExecute)
├── .env                   ← API keys (không commit)
├── .env.example           ← Template env vars
├── litellm.log            ← Proxy stdout
├── litellm-err.log        ← Proxy stderr
└── .gitignore
```

## Vai trò các thành phần

| Thành phần | Vai trò |
|-----------|---------|
| LiteLLM (pip) | Proxy engine core, route + transform request/response |
| config.yaml | Định nghĩa 17 model, mỗi model map với 1 upstream + key |
| patch-litellm.py | Sửa 2 bugs trong LiteLLM bridge khi transform Responses→Chat |
| model-catalog.json | JSON để Codex Desktop hiển thị 17 models trong picker |
| setup.ps1 | Tự động check Python, tạo .env, pip install, patch |
| start-proxy.ps1 | Kill proxy cũ, start mới, đợi health check |

## Config Codex Desktop

File: `C:\Users\<USER>\.codex\config.toml`

```toml
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

model_catalog_json = 'F:\Projects\litellm-byok\model-catalog.json'
```

## Danh sách 17 model

| Model | Provider | Ghi chú |
|---|---|---|
| `deepseek-v4-flash` | DeepSeek | Rẻ nhất, task đơn giản |
| `deepseek-v4-pro` | DeepSeek | Code specialist |
| `glm-5` | Zhipu | |
| `glm-5.1` | Zhipu | Latest |
| `kimi-k2.5` | Moonshot | 256K context |
| `kimi-k2.6` | Moonshot | 256K, latest |
| `mimo-v2.5` | Xiaomi | Default |
| `mimo-v2.5-pro` | Xiaomi | |
| `mimo-v2-pro` | Xiaomi | |
| `mimo-v2-omni` | Xiaomi | Text + image |
| `qwen3.5-plus` | Alibaba | 1M context |
| `qwen3.6-plus` | Alibaba | 1M, reasoning |
| `qwen3.7-max` | Alibaba | Anthropic bridge, flagship |
| `minimax-m2.5` | MiniMax | |
| `minimax-m2.7` | MiniMax | |
| `minimax-m3` | MiniMax | Latest |
| `hy3-preview` | TBD | Preview |

## Test thủ công

```powershell
# Health check
curl http://127.0.0.1:4000/health/liveliness

# List models
curl http://127.0.0.1:4000/v1/models -H "Authorization: Bearer sk-litellm-master-key-1234"

# Chat (Responses API)
curl -X POST http://127.0.0.1:4000/v1/responses `
  -H "Authorization: Bearer sk-litellm-master-key-1234" `
  -H "Content-Type: application/json" `
  -d '{\"model\":\"mimo-v2.5\",\"input\":\"PONG\"}'

# Chat (Chat Completions - test trực tiếp)
curl -X POST http://127.0.0.1:4000/v1/chat/completions `
  -H "Authorization: Bearer sk-litellm-master-key-1234" `
  -H "Content-Type: application/json" `
  -d '{\"model\":\"mimo-v2.5\",\"messages\":[{\"role\":\"user\",\"content\":\"PONG\"}],\"max_tokens\":20}'
```

## Troubleshooting

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| port 4000 already in use | Proxy cũ chưa tắt | Chạy lại `start-proxy.ps1` |
| 401 Unauthorized | Sai key trong config.toml hoặc proxy chưa start | Verify proxy live, check `experimental_bearer_token` |
| 404 từ opencode.ai | Model không tồn tại trong gói Go | Kiểm tra `GET https://opencode.ai/zen/go/v1/models` |
| `[] is too short` | PATCH 1 chưa apply | Chạy `python patch-litellm.py` |
| `'function' is a required property` | PATCH 2 chưa apply | Chạy `python patch-litellm.py` |
| Picker không hiện 17 models | model_catalog_json sai path | Kiểm tra đường dẫn absolute, restart Codex |
| Codex báo deprecated wire_api | Đang dùng `"chat"` thay vì `"responses"` | Sửa config.toml |

## Cập nhật model

Sửa `config.yaml`, thêm entry:

```yaml
- model_name: <slug>
  litellm_params:
    model: openai/chat_completions/<slug>
    api_key: os.environ/OPENCODE_GO_API_KEY
    api_base: https://opencode.ai/zen/go/v1
```

Thêm entry tương ứng vào `model-catalog.json`, restart proxy + Codex.

## Liên hệ / Tài liệu

- OpenCode Go API: https://opencode.ai/docs/go/
- OpenCode Go dashboard: https://opencode.ai
- LiteLLM docs: https://docs.litellm.ai/docs/simple_proxy
- LiteLLM source (issues): https://github.com/BerriAI/litellm
- Codex model_catalog_json bug: https://github.com/openai/codex/issues/19694