@echo off
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1
set "OPENCODE_GO_API_KEY=sk-cBNmterEUq2HcfdMzOcKstHuMpfeUXzqDf78QkFjKfY1rnu3sEXLij1L5x5KBBPy"
set "LITELLM_MASTER_KEY=sk-litellm-master-key-1234"
cd /d F:\Projects\litellm-byok
litellm --config config-cc.yaml --port 4000 > litellm-cc.log 2> litellm-cc-err.log
