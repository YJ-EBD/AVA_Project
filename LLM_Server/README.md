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

## Notiva AI Whisper Server

AZOOM voice-channel meeting minutes use a separate Whisper large-v3 server:

- Multipart endpoint: `http://127.0.0.1:8091/v1/notiva/transcribe`
- Spring Boot internal raw-audio endpoint: `http://127.0.0.1:8091/v1/notiva/transcribe-raw?language=ko`
- Health: `http://127.0.0.1:8091/health`
- Default model: `large-v3`
- Model cache: `LLM_Server/models/whisper-large-v3`
- Default runtime: CPU `int8` for Windows machines without CUDA 12/cuBLAS. Set `NOTIVA_WHISPER_DEVICE=cuda` and `NOTIVA_WHISPER_COMPUTE_TYPE=float16` only on hosts with the matching CUDA runtime installed.

Install and run:

```powershell
cd D:\AVA_Project\LLM_Server
.\install_whisper_large_v3.ps1
.\start_notiva_ai.cmd
```

Spring Boot reads this server through `AVA_NOTIVA_AI_BASE_URL`; audio files are stored under `AVA_NOTIVA_AUDIO_DIR`.
