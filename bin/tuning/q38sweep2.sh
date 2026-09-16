#!/bin/bash
M=/mnt/models2/qwen38-iq1s/UD-IQ1_S/Qwen3.8-Flash-Next-UD-IQ1_S-00001-of-00003.gguf
B=~/llama.cpp/build-cuda/bin/llama-cli
run() {
  local n="$1"
  echo "##### n-cpu-moe=$n #####"
  timeout 900 $B -m $M -t 24 -c 4096 -n 150 --no-warmup -st -f /tmp/prompt.txt \
     -ngl 99 --n-cpu-moe $n > ~/logs/q38_moe$n.log 2>&1 &
  local pid=$!
  local peak=0
  while kill -0 $pid 2>/dev/null; do
    v=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
    [ "$v" -gt "$peak" ] 2>/dev/null && peak=$v
    sleep 3
  done
  wait $pid; local rc=$?
  echo "  exit=$rc  peak_vram=${peak}MiB"
  grep -oE "Generation: [0-9.]+ t/s" ~/logs/q38_moe$n.log | tail -1
  grep -oE "Prompt: [0-9.]+ t/s" ~/logs/q38_moe$n.log | tail -1
  grep -icE "out of memory|error|abort" ~/logs/q38_moe$n.log | sed "s/^/  errlines: /"
  sed -n "/^> /,\$p" ~/logs/q38_moe$n.log | sed -n "/End thinking/,\$p" | sed -n "2,5p"
  echo
}
for n in 44 40 36 32; do run $n; done
