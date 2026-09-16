#!/bin/bash
# Round 2: retry the network-stalled pull, and side-load the three GGUFs whose
# filenames Ollama's HF tag resolver can't map.
LOG=/home/ocino/model_pulls2.log
DL=/home/ocino/models
mkdir -p "$DL"
: > "$LOG"

echo "=== $(date -Is) RETRY whittle" >> "$LOG"
if ollama pull hf.co/logic65/Qwen3.8-Whittle-MoE-27B-A17.8B-GGUF:Q8_0 >> "$LOG" 2>&1; then
  echo "=== $(date -Is) OK   whittle" >> "$LOG"
else
  echo "=== $(date -Is) FAIL whittle" >> "$LOG"
fi

fetch_import() {
  repo="$1"; file="$2"; name="$3"
  echo "=== $(date -Is) DL   $name" >> "$LOG"
  if curl -fL -sS --retry 5 --retry-delay 10 -C - -o "$DL/$file" \
      "https://huggingface.co/$repo/resolve/main/$file" >> "$LOG" 2>&1; then
    printf 'FROM %s\n' "$DL/$file" > "$DL/$name.Modelfile"
    if ollama create "$name" -f "$DL/$name.Modelfile" >> "$LOG" 2>&1; then
      echo "=== $(date -Is) OK   $name" >> "$LOG"
      rm -f "$DL/$file"
    else
      echo "=== $(date -Is) FAIL-IMPORT $name" >> "$LOG"
    fi
  else
    echo "=== $(date -Is) FAIL-DL $name" >> "$LOG"
  fi
  df -h / | tail -1 >> "$LOG"
}

fetch_import HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF \
  Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-Q8_K_P.gguf hauhau-qwen38-27b

fetch_import HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive \
  Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q8_K_P.gguf hauhau-qwen36-35b-a3b

fetch_import jamiefutch/Qwen3.5-122B-A10B-MXFP4_MOE-MTP-GGUF \
  Qwen3.5-122B-A10B-MXFP4_MOE-MTP-merged.gguf qwen35-122b-a10b

echo "=== $(date -Is) ALL DONE" >> "$LOG"
ollama list >> "$LOG" 2>&1
