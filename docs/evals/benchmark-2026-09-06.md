# Jarvis model benchmark — 2026-09-06

- Endpoint: `http://localhost:8000` (llama.cpp on jarvis, RTX 5070 Ti 16 GB + 61 GB RAM)
- Prompt: fixed, ~50 tokens in; `max_tokens=256`, `temperature=0`, non-streaming
- Each model: 1 warmup + 3 timed runs; `gen/s` and `prompt/s` are medians
- Speeds from llama.cpp `timings` (server-side; wall-clock fallback)
- `RAM MB` / `VRAM MB` = total jarvis usage while the model was loaded, not the model's own footprint

| key      | model                | quant       | load s | prompt/s |   gen/s |  RAM MB |  VRAM MB |
|----------|----------------------|-------------|--------|----------|---------|---------|----------|
| q38-q2 | Qwen3.8-Flash-Next | UD-Q2_K_XL | 7 | 24.4 | 14.4 | 3432 | 13628 |
| q38-27b | Qwen3.8-27B dense | UD-IQ4_XS | 7 | 45.4 | 50.0 | 3139 | 13864 |

_Raw: `benchmark-2026-09-06.json`_
