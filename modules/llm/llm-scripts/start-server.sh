#!/usr/bin/env bash

# ==============================================================================
# Configuration & Defaults
# ==============================================================================
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

API=${1:-"cuda"}
PORT=${2:-8001}
CONTEXT_SIZE=${3:-131072}
DEVICE_ID=${4:-0,1}
MODEL_NAME=${5:-"Qwen3.8-27B"}
QUANT=${6:-"Q8"}
TEMPERATURE=${7:-"thinking"}
MTP=${8:-"mtp-vision"}
EXTRA_ARGS=("${@:9}")
SPLIT_MODE="layer"

# Derive MODEL_QUANT and KV_CACHE_TYPE from the QUANT selector
case "$QUANT" in
    IQ4)   MODEL_QUANT="IQ4_XS"; KV_CACHE_TYPE="q4_0" ;;
    Q4)   MODEL_QUANT="Q4_K_XL"; KV_CACHE_TYPE="q4_0" ;;
    Q6)   MODEL_QUANT="Q6_K_XL"; KV_CACHE_TYPE="q8_0" ;;
    Q8)   MODEL_QUANT="Q8_K_XL"; KV_CACHE_TYPE="q8_0" ;;
    BF16) MODEL_QUANT="BF16";    KV_CACHE_TYPE="f16"  ;;
    *)    echo "Error: invalid QUANT '$QUANT' (expected IQ4, Q4, Q6, Q8, or BF16)"; exit 1 ;;
esac

MODELS_HOME="/mnt/models"
LLAMA_BIN="$HOME/llama.cpp/build-${API}/bin/llama-server"
# File discovery: globs tolerate tags (e.g. -UD) between model name and quant/mmproj
shopt -s nullglob
MODEL_MATCHES=( "$MODELS_HOME"/${MODEL_NAME}*-${MODEL_QUANT}.gguf )
MMPROJ_MATCHES=( "$MODELS_HOME"/${MODEL_NAME}*-mmproj*.gguf )
MTP_MATCHES=( "$MODELS_HOME"/${MODEL_NAME}*-mtp*.gguf )
DFLASH_MATCHES=( "$MODELS_HOME"/${MODEL_NAME}*-dflash*.gguf )
shopt -u nullglob
MODEL_FILE="${MODEL_MATCHES[0]:-}"
MMPROJ_FILE="${MMPROJ_MATCHES[0]:-}"
DFLASH_FILE="${DFLASH_MATCHES[0]:-}"
MTP_FILE="${MTP_MATCHES[0]:-}"
LOG_FILE="$HOME/logs/llama_server_port_${PORT}.log"
PID_FILE="$HOME/logs/llama_server_port_${PORT}.pid"

# ==============================================================================
# Helper Functions
# ==============================================================================
generate_cuda_devices() {
    # Takes physical device IDs (e.g. "0,1") and returns a sequential CUDA list
    # ("CUDA0,CUDA1") matching CUDA_VISIBLE_DEVICES ordering.
    local input_ids=$1
    local stripped="${input_ids//[^,]/}"
    local num_devices=$(( ${#stripped} + 1 ))

    local cuda_ids=""
    for ((i=0; i<num_devices; i++)); do
        cuda_ids+="CUDA$i"
        if ((i < num_devices - 1)); then cuda_ids+=","; fi
    done
    echo "$cuda_ids"
}

usage() {
    echo "Usage: $0 [API] [PORT] [CONTEXT_SIZE] [DEVICE_ID] [MODEL_NAME] [QUANT] [TEMPERATURE] [MTP] [EXTRA_ARGS...]"
    echo ""
    echo "Arguments:"
    echo "  API           : cuda (default: cuda)"
    echo "  PORT          : Port to run the server on (default: 8001)"
    echo "  CONTEXT_SIZE  : Context size in tokens (default: 131072)"
    echo "  DEVICE_ID     : CUDA device ID(s) to use, e.g., '0' or '0,1' (default: 0,1)"
    echo "  MODEL_NAME    : Name of model, e.g., Qwen3.8-27B (default: Qwen3.8-27B)"
    echo "  QUANT         : Model quant to load: IQ4, Q4, Q6, Q8, or BF16 (default: Q8)"
    echo "  TEMPERATURE   : 'thinking' or 'instruct' (default: thinking)"
    echo "  MTP           : mtp, mtp-vision, dflash, dflash-vision, vision (default: mtp-vision)"
    echo ""
    echo "Examples:"
    echo "  # Run Qwen3.8-27B Q4_K_XL on device 0 at port 8001"
    echo "  $0 cuda 8001 $CONTEXT_SIZE 0 Qwen3.8-27B Q4 thinking mtp-vision -np 1"
    echo "  $0 cuda 8002 $CONTEXT_SIZE 1 Qwen3.8-27B Q4 thinking mtp-vision -np 1"
    echo ""
    exit 1
}

# Handle help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# ==============================================================================
# Pre-flight Checks
# ==============================================================================
echo "Checking prerequisites..."

if [ ! -f "$LLAMA_BIN" ]; then
    echo "Error: llama-server binary not found at $LLAMA_BIN"
    echo "   Please ensure you have built llama.cpp with CUDA support."
    exit 1
fi

if [[ -z "$MODEL_FILE" ]]; then
    echo "Error: no model file matching '$MODELS_HOME/${MODEL_NAME}*-${MODEL_QUANT}.gguf'"
    exit 1
fi

case "$MTP" in
    mtp-vision|dspark-vision|dflash-vision|vision)
        if [[ -z "$MMPROJ_FILE" ]]; then
            echo "Error: no mmproj file matching '$MODELS_HOME/${MODEL_NAME}*-mmproj*.gguf' (required for '$MTP' mode)"
            exit 1
        fi
        ;;
esac

# Check if already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "A server is already running on PID $OLD_PID. Stopping it first..."
        kill "$OLD_PID"
        sleep 2
    fi
    rm -f "$PID_FILE"
fi

# ==============================================================================
# Build and Print Command
# ==============================================================================
LLAMA_CMD=()

if [[ "$API" == "cuda" ]]; then
    CUDA_DEVICES=$(generate_cuda_devices "$DEVICE_ID")
    LLAMA_CMD+=(
        env
        CUDA_VISIBLE_DEVICES="$DEVICE_ID"
        "$LLAMA_BIN"
        --device "$CUDA_DEVICES"
    )
else
    echo "Error: unsupported API '$API' (expected cuda)"
    exit 1
fi

LLAMA_CMD+=(
    --model "${MODEL_FILE}"
    --alias "${MODEL_NAME}"
)

if [[ "$MTP" == "mtp" ]]; then
    LLAMA_CMD+=(
      --cache-type-k-draft "$KV_CACHE_TYPE"
      --cache-type-v-draft "$KV_CACHE_TYPE"
      --spec-type draft-mtp
      --spec-draft-n-max 4
    )
    if [ -f "$MTP_FILE" ]; then
        LLAMA_CMD+=( --model-draft "$MTP_FILE" )
    fi
elif [[ "$MTP" == "mtp-vision" ]]; then
    LLAMA_CMD+=(
      --mmproj "$MMPROJ_FILE"
      --image-min-tokens 1024
      --cache-type-k-draft "$KV_CACHE_TYPE"
      --cache-type-v-draft "$KV_CACHE_TYPE"
      --spec-type draft-mtp
      --spec-draft-n-max 4
    )
    if [ -f "$MTP_FILE" ]; then
        LLAMA_CMD+=( --model-draft "$MTP_FILE" )
    fi
elif [[ "$MTP" == "dflash" ]]; then
    LLAMA_CMD+=(
      --model-draft "$DFLASH_FILE"
      --cache-type-k-draft "$KV_CACHE_TYPE"
      --cache-type-v-draft "$KV_CACHE_TYPE"
      --spec-type draft-dflash
      --spec-draft-n-max 7
    )
elif [[ "$MTP" == "dflash-vision" ]]; then
    LLAMA_CMD+=(
      --model-draft "$DFLASH_FILE"
      --mmproj "$MMPROJ_FILE"
      --image-min-tokens 1024
      --cache-type-k-draft "$KV_CACHE_TYPE"
      --cache-type-v-draft "$KV_CACHE_TYPE"
      --spec-type draft-dflash
      --spec-draft-n-max 7
    )
elif [[ "$MTP" == "vision" ]]; then
    LLAMA_CMD+=( --mmproj "$MMPROJ_FILE" --image-min-tokens 1024 )
fi

if [[ "$TEMPERATURE" == "thinking" ]]; then
    LLAMA_CMD+=(
      --temp 1.0
      --top-p 0.95
      --top-k 20
      --min-p 0.0
      --presence-penalty 0.0
      --repeat-penalty 1.0
      --reasoning on
      --reasoning-preserve
    )
elif [[ "$TEMPERATURE" == "instruct" ]]; then
    LLAMA_CMD+=(
      --temp 0.7
      --top-p 0.80
      --top-k 20
      --min-p 0.0
      --presence-penalty 1.5
      --repeat-penalty 1.0
      --reasoning off
    )
else
    echo "Using default temperature!"
fi

LLAMA_CMD+=(
    --port "$PORT"
    --host 0.0.0.0
    --ctx-size "$CONTEXT_SIZE"
    --cache-type-k "$KV_CACHE_TYPE"
    --cache-type-v "$KV_CACHE_TYPE"
    --split-mode "$SPLIT_MODE"
    --flash-attn auto
    --n-gpu-layers 999
    --n-gpu-layers-draft 999
    --cache-ram 8192
    --load-mode dio
    --metrics
)

echo "Starting llama-server..."
echo "   RAW_IDS      : $DEVICE_ID"
echo "   DEVICES      : $CUDA_DEVICES"
echo "   Vision file  : $MMPROJ_FILE"
echo "   Model        : $MODEL_FILE"
echo "   Port         : $PORT"
echo "   Device ID    : $DEVICE_ID -> $CUDA_DEVICES"
echo "   Context      : ${CONTEXT_SIZE}"
echo "   KV Cache     : $KV_CACHE_TYPE"
echo "   Split Mode   : $SPLIT_MODE"
echo "   Log File     : $LOG_FILE"
echo "   Temperature  : $TEMPERATURE"
echo ""
echo "Full command being executed:"
printf '%q ' "${LLAMA_CMD[@]}" "${EXTRA_ARGS[@]}"
echo ""

nohup "${LLAMA_CMD[@]}" "${EXTRA_ARGS[@]}" >> "$LOG_FILE" 2>&1 &

SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"

echo "Server started in background with PID: $SERVER_PID"
echo "   Tail the logs with: tail -f $LOG_FILE"
echo "   Stop the server with: kill $SERVER_PID (or run this script again to auto-restart)"
