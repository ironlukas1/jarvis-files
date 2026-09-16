#!/bin/bash
# Sequential model pulls for .59 benchmark sweep.
LOG=/home/ocino/model_pulls.log
: > "$LOG"

pull() {
  echo "=== $(date -Is) START $1" >> "$LOG"
  if ollama pull "$1" >> "$LOG" 2>&1; then
    echo "=== $(date -Is) OK   $1" >> "$LOG"
  else
    echo "=== $(date -Is) FAIL $1" >> "$LOG"
  fi
  df -h / | tail -1 >> "$LOG"
}

# Ordered: highest-value first, biggest/riskiest last.
pull hf.co/ornith-ai/Ornith-1.5-35B-A3B-GGUF:Q8_0
pull hf.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF:Q8_0
pull hf.co/unsloth/Qwen3.8-27B-GGUF:Q8_0
pull hf.co/logic65/Qwen3.8-Whittle-MoE-27B-A17.8B-GGUF:Q8_0
pull hf.co/HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF:Q8_K_P
pull hf.co/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:Q8_K_P
pull hf.co/jamiefutch/Qwen3.5-122B-A10B-MXFP4_MOE-MTP-GGUF:MXFP4_MOE

echo "=== $(date -Is) ALL DONE" >> "$LOG"
ollama list >> "$LOG" 2>&1
