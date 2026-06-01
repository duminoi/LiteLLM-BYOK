$env:OPENCODE_GO_API_KEY = "sk-cBNmterEUq2HcfdMzOcKstHuMpfeUXzqDf78QkFjKfY1rnu3sEXLij1L5x5KBBPy"
$env:LITELLM_MASTER_KEY = "sk-litellm-master-key-1234"
$env:PYTHONIOENCODING = "utf-8"

Write-Host "=== Starting LiteLLM Proxy for OpenCode Go BYOK ===" -ForegroundColor Cyan
Write-Host "OpenCode Go API key configured" -ForegroundColor Green
Write-Host "Proxy URL: http://localhost:4000" -ForegroundColor Yellow
Write-Host ""
Write-Host "Available models: deepseek-v4-flash, deepseek-v4-pro, glm-5, glm-5.1," -ForegroundColor Gray
Write-Host "                 kimi-k2.5, kimi-k2.6, mimo-v2.5, mimo-v2.5-pro" -ForegroundColor Gray
Write-Host ""
Write-Host "Codex config already set to use: mimo-v2.5 @ LiteLLM BYOK" -ForegroundColor Cyan
Write-Host ""

litellm --config F:\Projects\litellm-byok\config.yaml --port 4000
