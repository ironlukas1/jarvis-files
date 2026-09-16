#!/bin/bash
M=/mnt/models2/qwen38-iq1s/UD-IQ1_S/Qwen3.8-Flash-Next-UD-IQ1_S-00001-of-00003.gguf
B=~/llama.cpp/build-cuda/bin/llama-cli
run() {
  local tag="$1"; shift
  echo "##### $tag #####"
  timeout 900 $B -m $M -t 24 -c 4096 -n 150 --no-warmup -st -f /tmp/prompt.txt "$@" > ~/logs/q38_$tag.log 2>&1
  echo "  exit=$?"
  grep -oE "\[ Prompt: [0-9.]+ t/s \| Generation: [0-9.]+ t/s \]" ~/logs/q38_$tag.log | tail -1
  nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1 | sed "s/^/  vram_after: /"
  echo "  --- output ---"
  sed -n "/^> /,\$p" ~/logs/q38_$tag.log | sed -n "3,12p" | head -8
  echo
}
run ngl8  -ngl 8
run ngl16 -ngl 16
run cpumoe -ngl 99 --n-cpu-moe 48
