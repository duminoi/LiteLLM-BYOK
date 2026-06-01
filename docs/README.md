# LiteLLM BYOK cho Codex Desktop

Proxy LiteLLM trung gian giữa Codex Desktop và OpenCode Go (BYOK subscription), trỏ 17 model open-source qua 1 endpoint duy nhất.

## Khởi động nhanh

Mỗi lần trước khi vào Codex Desktop, chạy:

```powershell
powershell -ExecutionPolicy Bypass -File F:\Projects\litellm-byok\start-proxy.ps1
```

Script tự:
1. Kill LiteLLM process cũ (nếu có)
2. Set env vars (`OPENCODE_GO_API_KEY`, `LITELLM_MASTER_KEY`, `PYTHONUTF8`)
3. Start proxy ở port 4000
4. Đợi `/health/liveliness` rồi in hướng dẫn config Codex

Đợi dòng `OK - proxy live at http://127.0.0.1:4000` rồi mở Codex Desktop là dùng được.

## Cấu trúc thư mục

```
F:\Projects\litellm-byok\
  config.yaml         # Định nghĩa 17 model + master key
  .env                # OPENCODE_GO_API_KEY + LITELLM_MASTER_KEY
  start-proxy.ps1     # Script khởi động (Windows)
  litellm.log         # Log stdout proxy
  litellm-err.log     # Log stderr proxy
```

## Endpoint Codex Desktop

`C:\Users\ADMIN\.codex\config.toml` đã được cấu hình sẵn:

```toml
model = "mimo-v2.5"
model_provider = "litellm_byok"

[model_providers.litellm_byok]
name = "LiteLLM BYOK (OpenCode Go)"
base_url = "http://127.0.0.1:4000/v1"
wire_api = "chat"
experimental_bearer_token = "sk-litellm-master-key-1234"
```

Đổi `model = "..."` sang bất kỳ model nào trong danh sách dưới.

## Danh sách 17 model

| Model | Endpoint | Ghi chú |
|---|---|---|
| `deepseek-v4-flash` | OpenAI-compat | Rẻ nhất, dùng cho task đơn giản |
| `deepseek-v4-pro` | OpenAI-compat | |
| `glm-5` | OpenAI-compat | |
| `glm-5.1` | OpenAI-compat | |
| `kimi-k2.5` | OpenAI-compat | |
| `kimi-k2.6` | OpenAI-compat | |
| `mimo-v2.5` | OpenAI-compat | Default hiện tại |
| `mimo-v2.5-pro` | OpenAI-compat | |
| `mimo-v2-pro` | OpenAI-compat | |
| `mimo-v2-omni` | OpenAI-compat | |
| `qwen3.5-plus` | OpenAI-compat | |
| `qwen3.6-plus` | OpenAI-compat | |
| `qwen3.7-max` | **Anthropic-compat** | Qwen lớn nhất, expensive |
| `minimax-m2.5` | OpenAI-compat | |
| `minimax-m2.7` | OpenAI-compat | |
| `minimax-m3` | OpenAI-compat | |
| `hy3-preview` | OpenAI-compat | |

**Lưu ý:** `qwen3.7-max` upstream OpenCode Go từ chối OpenAI format — phải dùng Anthropic Messages API. LiteLLM tự convert khi client (Codex) gọi `/v1/chat/completions`.

## Test thủ công (không qua Codex)

```powershell
# List models
curl http://127.0.0.1:4000/v1/models -H "Authorization: Bearer sk-litellm-master-key-1234"

# Chat completion
curl -X POST http://127.0.0.1:4000/v1/chat/completions `
  -H "Authorization: Bearer sk-litellm-master-key-1234" `
  -H "Content-Type: application/json" `
  -d '{\"model\":\"mimo-v2.5\",\"messages\":[{\"role\":\"user\",\"content\":\"PONG\"}],\"max_tokens\":20}'

# Health check
curl http://127.0.0.1:4000/health/liveliness
```

## Troubleshooting

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `UnicodeEncodeError: cp1252` lúc start | Windows console không hỗ trợ UTF-8 | Script đã set `PYTHONUTF8=1`. Nếu chạy tay, set env trước khi gọi `litellm` |
| `port already in use` | LiteLLM cũ chưa tắt | Chạy lại `start-proxy.ps1` (script tự kill) hoặc `Stop-Process -Name litellm -Force` |
| Codex báo `401 Unauthorized` | Sai key trong `config.toml` hoặc proxy chưa start | Verify proxy live + kiểm tra `experimental_bearer_token` |
| `404 Not Found` từ opencode.ai | Model không tồn tại trong gói Go | Kiểm tra `https://opencode.ai/zen/go/v1/models` (auth = API key) |
| `Model … not supported for format oa-compat` | Model upstream chỉ Anthropic (vd `qwen3.7-max`) | Đã fix trong `config.yaml` (dùng `anthropic/qwen3.7-max`) |

## Cập nhật model

Sửa `F:\Projects\litellm-byok\config.yaml`, thêm/sửa block:

```yaml
  - model_name: <tên-trong-codex>
    litellm_params:
      model: <provider>/<model-id-trên-upstream>
      api_key: os.environ/OPENCODE_GO_API_KEY
      api_base: https://opencode.ai/zen/go/v1   # hoặc /v1 nếu là OpenAI-compat
```

Restart: chạy lại `start-proxy.ps1`.

## Liên hệ upstream

- API docs: https://opencode.ai/docs/go/
- Model list: `GET https://opencode.ai/zen/go/v1/models` (header `Authorization: Bearer <key>`)
- LiteLLM docs: https://docs.litellm.ai/docs/simple_proxy
