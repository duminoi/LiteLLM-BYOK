@echo off
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1
set "OPENCODE_GO_API_KEY=sk-cBNmterEUq2HcfdMzOcKstHuMpfeUXzqDf78QkFjKfY1rnu3sEXLij1L5x5KBBPy"
set "LITELLM_MASTER_KEY=sk-litellm-master-key-1234"
cd /d F:\Projects\litellm-byok
echo [Setup] Applying LiteLLM patches (idempotent)...
python patch-litellm.py || goto :error
litellm --config config.yaml --port 4000 > litellm.log 2> litellm-err.log
goto :eof
:error
echo.
echo [ERROR] patch-litellm.py failed. LiteLLM version may have changed.
echo Update markers in patch-litellm.py, or run: pip install litellm==1.86.2
exit /b 1
