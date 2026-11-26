source .bashrc
source .vllm/bin/activate

export VLLM_TARGET_DEVICE=cuda
export CUDA_VISIBLE_DEVICES=0,1

# Set logging to INFO (DEBUG is too noisy, removes the harmless spam)
export VLLM_LOGGING_LEVEL=INFO

# RTX 3090 (sm_86) has no FP8 (Hopper+) or MXFP4 (Blackwell+) support, so use a
# plain AWQ/FP16 model and let kv-cache dtype be chosen automatically.
MODEL=${1:-"Qwen/Qwen3.8-27B-AWQ"}
MODEL_ALIAS=${2:-"Qwen3.8-27B"}
EXTRA_ARGS=("${@:3}")

vllm serve "$MODEL" \
    --served-model-name "$MODEL_ALIAS" \
    --tensor-parallel-size 2 \
    --max-num-seqs 8 \
    --max-num-batched-tokens 4096 \
    --max-model-len 131072 \
    --kv-cache-dtype auto \
    --gpu-memory-utilization 0.90 \
    --enable-prefix-caching \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_xml \
    --reasoning-parser qwen3 \
    --host 0.0.0.0 \
    --port 8004 "${EXTRA_ARGS[@]}"
