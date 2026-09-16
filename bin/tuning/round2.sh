#!/bin/bash
L=/home/ocino/round2.log
: > $L
for t in UD-Q4_K_M UD-IQ4_XS; do
  echo "=== $(date -Is) PULL $t" >> $L
  ollama pull hf.co/unsloth/Qwen3.8-27B-GGUF:$t >> $L 2>&1 \
    && echo "=== OK $t" >> $L || echo "=== FAIL $t" >> $L
done
export OUT=/home/ocino/eval_round2
python3 /home/ocino/eval.py \
  hf.co/unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M \
  hf.co/unsloth/Qwen3.8-27B-GGUF:UD-IQ4_XS >> $L 2>&1
echo "=== ROUND2 DONE" >> $L
