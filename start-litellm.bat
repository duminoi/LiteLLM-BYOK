@echo off
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1

:: Load OPENCODE_GO_API_KEY from .env if not already set
if "%OPENCODE_GO_API_KEY%"=="" (
    if exist "%~dp0.env" (
        for /f "usebackq tokens=1,* delims==" %%a in ("%~dp0.env") do (
            if "%%a"=="OPENCODE_GO_API_KEY" set "OPENCODE_GO_API_KEY=%%b"
            if "%%a"=="LITELLM_MASTER_KEY" set "LITELLM_MASTER_KEY=%%b"
        )
    )
)

:: Fallback defaults if still empty
if "%OPENCODE_GO_API_KEY%"=="" (
    echo [ERROR] OPENCODE_GO_API_KEY not set. Create .env from .env.example and add your key.
    exit /b 1
)
if "%LITELLM_MASTER_KEY%"=="" set "LITELLM_MASTER_KEY=sk-litellm-master-key-1234"

cd /d %~dp0
echo [Setup] Applying LiteLLM patches (idempotent)...
python patch-litellm.py || goto :error
litellm --config config.yaml --port 4000 > litellm.log 2> litellm-err.log
goto :eof
:error
echo.
echo [ERROR] patch-litellm.py failed. LiteLLM version may have changed.
echo Run: pip install litellm==1.86.2
exit /b 1