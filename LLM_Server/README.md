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

## Notiva AI Whisper Server

AZOOM voice-channel meeting minutes use a separate Whisper large-v3 server:

- Multipart endpoint: `http://127.0.0.1:8091/v1/notiva/transcribe`
- Raw-audio endpoint: `http://127.0.0.1:8091/v1/notiva/transcribe-raw?language=ko`
- Health: `http://127.0.0.1:8091/health`
- Default model: `large-v3`
- Model cache: `LLM_Server/models/whisper-large-v3`

Install and run:

```powershell
cd D:\AVA_Project\LLM_Server
.\install_whisper_large_v3.ps1
.\start_notiva_ai.cmd
```

NodeBackend calls this server through `AVA_NOTIVA_AI_BASE_URL`; uploaded audio files are stored under `NodeBackend/NotivaAudio` unless configured otherwise.
