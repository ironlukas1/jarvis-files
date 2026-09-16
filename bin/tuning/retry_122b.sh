#!/bin/bash
L=/home/ocino/retry_122b.log
DL=/home/ocino/models
R=jamiefutch/Qwen3.5-122B-A10B-MXFP4_MOE-MTP-GGUF
F=Qwen3.5-122B-A10B-MXFP4_MOE-MTP-merged.gguf
: > $L
for a in 1 2 3 4; do
  echo "--- attempt $a  ($(du -h "$DL/$F" 2>/dev/null | cut -f1) so far)" >> $L
  if curl -fL -sS --http1.1 --retry 8 --retry-delay 15 --retry-all-errors \
       -C - -o "$DL/$F" "https://huggingface.co/$R/resolve/main/$F" >> $L 2>&1; then
    echo "=== $(date -Is) DL OK" >> $L; break
  fi
done
printf "FROM %s\n" "$DL/$F" > "$DL/qwen35-122b.Modelfile"
if ollama create qwen35-122b-a10b -f "$DL/qwen35-122b.Modelfile" >> $L 2>&1; then
  echo "=== $(date -Is) OK qwen35-122b-a10b" >> $L
else
  echo "=== $(date -Is) FAIL-IMPORT (likely MXFP4_MOE unsupported by ollama 0.32.14)" >> $L
fi
echo "=== 122B DONE" >> $L
