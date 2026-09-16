#!/bin/bash
L=/home/ocino/retry_hauhau.log
DL=/home/ocino/models
R=HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF
F=Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-Q8_K_P.gguf
: > $L
echo "=== $(date -Is) DL hauhau-qwen38-27b (http1.1, resume)" >> $L
for attempt in 1 2 3; do
  echo "--- attempt $attempt" >> $L
  if curl -fL -sS --http1.1 --retry 8 --retry-delay 15 --retry-all-errors \
       -C - -o "$DL/$F" "https://huggingface.co/$R/resolve/main/$F" >> $L 2>&1; then
    echo "=== $(date -Is) DL OK" >> $L; break
  fi
  echo "--- attempt $attempt failed, size so far: $(du -h "$DL/$F" 2>/dev/null | cut -f1)" >> $L
done
if [ -f "$DL/$F" ] && [ "$(stat -c%s "$DL/$F")" -gt 29000000000 ]; then
  printf "FROM %s\n" "$DL/$F" > "$DL/hauhau-qwen38-27b.Modelfile"
  if ollama create hauhau-qwen38-27b -f "$DL/hauhau-qwen38-27b.Modelfile" >> $L 2>&1; then
    echo "=== $(date -Is) OK hauhau-qwen38-27b" >> $L; rm -f "$DL/$F"
  else
    echo "=== $(date -Is) FAIL-IMPORT" >> $L
  fi
else
  echo "=== $(date -Is) FAIL-DL incomplete" >> $L
fi
echo "=== HAUHAU DONE" >> $L
