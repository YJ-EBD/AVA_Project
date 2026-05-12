# AVA Local LLM Server

Model:

- `bartowski/Qwen_Qwen3.5-27B-GGUF`
- Quant: `Qwen_Qwen3.5-27B-Q4_K_M.gguf`
- Runtime: `llama.cpp` CUDA build

Endpoint:

- `http://127.0.0.1:8088/v1/chat/completions`
- Model alias: `ava-qwen3.5-27b-q4km`

Run:

```powershell
cd D:\AVA_Project\LLM_Server
.\start_server.cmd
```

Test after the server is ready:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test_server.ps1
```

Production starting point:

- Concurrent slots: `10`
- Context size: `40960` total slot pool
- KV cache: `q4_0`
- Keep prompts concise for speed. If AVA later sends model-specific template options, disable thinking per request for simple lookup tasks.
