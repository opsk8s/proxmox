source .bashrc
source .vllm/bin/activate

# Force V0 engine to prevent the int32 overflow crash
# export VLLM_USE_V1=0

# Keep ROCm/MI300 optimizations
export VLLM_TARGET_DEVICE=rocm
export ROCM_VISIBLE_DEVICES=0,1,2,3
export HIP_VISIBLE_DEVICES=0,1,2,3
export HSA_OVERRIDE_GFX_VERSION=12.0.1

export VLLM_ROCM_USE_AITER=1
# export VLLM_USE_FLASHINFER_MOE_FP8=1
# export VLLM_USE_FLASHINFER_MOE_FP4=1
# export VLLM_USE_FLASHINFER_MOE_MXFP4_BF16=1
# export VLLM_ROCM_USE_AITER_MOE=1

export HIP_FORCE_DEV_KERNARG=1
export SAFETENSORS_FAST_GPU=1
export TORCH_BLAS_PREFER_HIPBLASLT=1
export NCCL_MIN_NCHANNELS=112


# export VLLM_ROCM_USE_AITER=1
# export VLLM_ROCM_USE_AITER_PAGED_ATTN=1

# export LLM_ROCM_USE_AITER=1
export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"

# export RCCL_DEBUG=INFO
# export RCCL_DEBUG_SUBSYS=INIT,GRAPH

# Set logging to INFO (DEBUG is too noisy, removes the harmless spam)
export VLLM_LOGGING_LEVEL=INFO

unset CUDA_VISIBLE_DEVICES

MODEL=${1:-"Qwen/Qwen3.6-27B-FP8"}
MODEL_ALIAS=${2:-"Qwen3.6-27B"}
EXTRA_ARGS=("${@:3}")

# REMOVE: TORCH_DISTRIBUTED_DEBUG=DETAIL TRITON_DEBUG=1 (They kill performance)
# --speculative-config '{"method":"mtp","num_speculative_tokens":2}' \


vllm serve "$MODEL" \
    --served-model-name "$MODEL_ALIAS" \
    --tensor-parallel-size 4 \
    --max-num-seqs 8 \
    --max-num-batched-tokens 4096 \
    --max-model-len 131072 \
    --kv-cache-dtype fp8_e4m3 \
    --gpu-memory-utilization 0.90 \
    --enable-prefix-caching \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_xml \
    --reasoning-parser qwen3 \
    --host 0.0.0.0 \
    --port 8001 "${EXTRA_ARGS[@]}"
    # --speculative-config '{"model":"poolside/Laguna-S-2.1-DFlash-INT4","num_speculative_tokens":15,"method":"dflash"}' \
    # --host 0.0.0.0 \
    # --port 8001 "${EXTRA_ARGS[@]}"