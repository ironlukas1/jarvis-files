#!/bin/bash
export OUT=/home/ocino/eval_round3
python3 /home/ocino/eval.py hauhau-qwen36-35b-a3b hauhau-qwen38-27b > /home/ocino/round3.log 2>&1
echo "=== ROUND3 DONE" >> /home/ocino/round3.log
