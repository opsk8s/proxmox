#!/usr/bin/env bash

# ==============================================================================
# Configuration & Defaults
# ==============================================================================
export LD_LIBRARY_PATH=/opt/rocm/lib:$LD_LIBRARY_PATH

# Parameterizable defaults (can be overridden via command-line arguments)

API=${1:-"rocm"}
PORT=${2:-8001}
CONTEXT_SIZE=${3:-262144}
DEVICE_ID=${4:-0,1,2,3}
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
    *)    echo "❌ Error: invalid QUANT '$QUANT' (expected IQ4, Q4, Q6, Q8, or BF16)"; exit 1 ;;
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
generate_vulkan_devices() {
    # Takes physical device IDs (e.g. "0,2" or "0,1,3")
    # and returns VulkanX list with the **same** IDs
    # Example: generate_devices "0,1,3" → "Vulkan0,Vulkan1,Vulkan3"

    local input_ids="$1"
    local prefix="${2:-Vulkan}"   # Default prefix is Vulkan

    if [[ -z "$input_ids" ]]; then
        echo ""
        return 1
    fi

    local device_list=""
    local first=1

    # Split by comma and process each ID
    IFS=',' read -ra ids <<< "$input_ids"

    for id in "${ids[@]}"; do
        if [[ "$first" -eq 0 ]]; then
            device_list+=","
        fi
        device_list+="${prefix}${id}"
        first=0
    done

    echo "$device_list"
}

generate_rocm_devices() {
    # Takes physical device IDs (e.g., "0,2" or "1,0,3"), counts them,
    # and generates a sequential ROCm list (e.g., "ROCm0,ROCm1" or "ROCm0,ROCm1,ROCm2")
    local input_ids=$1

    # Pure bash way to count commas and add 1 to get the number of devices
    local stripped="${input_ids//[^,]/}"
    local num_devices=$(( ${#stripped} + 1 ))

    local rocm_ids=""
    for ((i=0; i<num_devices; i++)); do
        rocm_ids+="ROCm$i"
        if ((i < num_devices - 1)); then rocm_ids+=","; fi
    done
    echo "$rocm_ids"
}

usage() {
    echo "Usage: $0 [API] [PORT] [CONTEXT_SIZE] [QUANT] [DEVICE_ID] [MODEL_NAME] [TEMPERATURE] [MTP] [EXTRA_ARGS...]"
    echo ""
    echo "Arguments:"
    echo "  API           : Api of server rocm or vulkan (default: rocm)"
    echo "  PORT          : Port to run the server on (default: 8001)"
    echo "  CONTEXT_SIZE  : Context size in tokens (default: 262144)"
    echo "  QUANT         : Model quant to load: Q4, Q6, Q8, or BF16 (default: Q8)"
    echo "  DEVICE_ID     : ROCm Device ID(s) to use, e.g., '0' or '0,1' (default: 0,1,2,3)"
    echo "  MODEL_NAME    : Name of model, e.g., (default: Qwen3.8-27B-UD)"
    echo "  SPLIT_MODE    : Split mode of model, e.g., 'row' or 'tensor' (default: layer)"
    echo "  TEMPERATURE   : Temperatore of model, e.g., 'thinking', 'instruct' (default: thinking)"
    echo "  MODE           : Only mtp supported models, e.g., 'mtp', 'mtp-vision',  'dspark', 'dspark-vision', 'dflash', 'dflash-vision', 'vision' (default: none)"
    echo ""
    echo "Examples:"
    echo "  # Run default rocm Qwen3.8-27B-UD Q8_K_XL on devices 0,1,2,3 at port 8001"
    echo "  $0"
    echo ""
    echo "  # QUANT (4th arg) selects the model: Q4 | Q6 | Q8 | BF16"
    echo "  # Run Q8 (Q8_K_XL model, q8_0 KV cache) on devices 2,3 / 0,1"
    echo "  $0 rocm 8001 $CONTEXT_SIZE 2,3 Qwen3.8-27B Q8 thinking mtp-vision -np 1"
    echo "  $0 rocm 8002 $CONTEXT_SIZE 0,1 Qwen3.8-27B Q8 thinking mtp-vision -np 1"
    echo "  $0 vulkan 8001 $CONTEXT_SIZE 2,3 Qwen3.8-27B Q8 thinking mtp-vision -np 1"
    echo "  $0 vulkan 8002 $CONTEXT_SIZE 0,1 Qwen3.8-27B Q8 thinking mtp-vision -np 1"
    echo "  # Run Q6 (Q6_K_XL model, q8_0 KV cache) on devices 2,3 / 0,1"
    echo "  $0 rocm 8001 $CONTEXT_SIZE 2,3 Qwen3.8-27B Q6 thinking mtp-vision -np 1"
    echo "  $0 rocm 8002 $CONTEXT_SIZE 0,1 Qwen3.8-27B Q6 thinking mtp-vision -np 1"
    echo "  # Run Q4 (Q4_K_XL model, q4_0 KV cache) on a single device at ports 8001-8004"
    echo "  $0 rocm 8001 $CONTEXT_SIZE 0 Qwen3.8-27B Q4 thinking mtp-vision -np 1"
    echo "  $0 rocm 8002 $CONTEXT_SIZE 1 Qwen3.8-27B Q4 thinking mtp-vision -np 1"
    echo "  $0 rocm 8003 $CONTEXT_SIZE 2 Qwen3.8-27B Q4 thinking mtp-vision -np 1"
    echo "  $0 rocm 8004 $CONTEXT_SIZE 3 Qwen3.8-27B Q4 thinking mtp-vision -np 1"
    echo "  $0 vulkan 8001 $CONTEXT_SIZE 0 Qwen3.8-27B Q4 thinking mtp-vision -np 1"
    echo "  $0 vulkan 8002 $CONTEXT_SIZE 1 Qwen3.8-27B Q4 thinking mtp-vision -np 1"
    echo "  $0 vulkan 8003 $CONTEXT_SIZE 2 Qwen3.8-27B Q4 thinking mtp-vision -np 1"
    echo "  $0 vulkan 8004 $CONTEXT_SIZE 3 Qwen3.8-27B Q4 thinking mtp-vision -np 1"
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
echo "🔍 Checking prerequisites..."

if [ ! -f "$LLAMA_BIN" ]; then
    echo "❌ Error: llama-server binary not found at $LLAMA_BIN"
    echo "   Please ensure you have built llama.cpp with Vulkan support."
    exit 1
fi

if [[ -z "$MODEL_FILE" ]]; then
    echo "❌ Error: no model file matching '$MODELS_HOME/${MODEL_NAME}*-${MODEL_QUANT}.gguf'"
    exit 1
fi

case "$MTP" in
    mtp-vision|dspark-vision|dflash-vision|vision)
        if [[ -z "$MMPROJ_FILE" ]]; then
            echo "❌ Error: no mmproj file matching '$MODELS_HOME/${MODEL_NAME}*-mmproj*.gguf' (required for '$MTP' mode)"
            exit 1
        fi
        ;;
esac

# Check if already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "⚠️  A server is already running on PID $OLD_PID. Stopping it first..."
        kill "$OLD_PID"
        sleep 2
    fi
    rm -f "$PID_FILE"
fi
# ==============================================================================
# Generate Device Lists
# ==============================================================================
# The ROCm IDs are generated sequentially based on the count of physical IDs
ROCM_DEVICES=()


# ==============================================================================
# Build and Print Command
# ==============================================================================
# We use a Bash array to safely handle all arguments and paths
LLAMA_CMD=()

if [[ "$API" == "rocm" ]]; then
    ROCM_DEVICES=$(generate_rocm_devices "$DEVICE_ID")
    LLAMA_CMD+=(
        env
        GGML_HIP=1
        HSA_OVERRIDE_GFX_VERSION="12.0.1"
        GGML_VK_DISABLE=1
        HIP_VISIBLE_DEVICES="$DEVICE_ID"
        "$LLAMA_BIN"
        --device "$ROCM_DEVICES"
    )
elif [[ "$API" == "vulkan" ]]; then
    ROCM_DEVICES=$(generate_vulkan_devices "$DEVICE_ID")
    LLAMA_CMD+=(
        env
        RADV_PERFTERMS="compute"
        RADV_DEBUG="nocng,nodcc"
        RADV_PERFTEST="nogttspill"
        DISABLE_LAYER_AMD_SWITCHABLE_GRAPHICS_1=1
        GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1
        HSA_OVERRIDE_GFX_VERSION="12.0.1"
        MALLOC_TRIM_THRESHOLD_=-1
        "$LLAMA_BIN"
        --device "$ROCM_DEVICES"
    )
fi


LLAMA_CMD+=(
    --model "${MODEL_FILE}"
    --alias "${MODEL_NAME}"
)

# Conditionally add --mmproj only if the model is NOT 80B-A3B or 14B



if [[ "$MTP" == "mtp" ]]; then
    LLAMA_CMD+=(
      --cache-type-k-draft "$KV_CACHE_TYPE"
      --cache-type-v-draft "$KV_CACHE_TYPE"
      --spec-type draft-mtp
      --spec-draft-n-max 5
    )
     if [ -f "$MTP_FILE" ]; then
        LLAMA_CMD+=(
            --model-draft "$MTP_FILE"
        )
     fi
elif [[ "$MTP" == "mtp-vision" ]]; then
    LLAMA_CMD+=(
      --mmproj "$MMPROJ_FILE"
      --image-min-tokens 1024
      --cache-type-k-draft "$KV_CACHE_TYPE"
      --cache-type-v-draft "$KV_CACHE_TYPE"
      --spec-type draft-mtp
      --spec-draft-n-max 5
    )
    if [ -f "$MTP_FILE" ]; then
      LLAMA_CMD+=(
          --model-draft "$MTP_FILE"
      )
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
    LLAMA_CMD+=(
       --mmproj "$MMPROJ_FILE"
       --image-min-tokens 1024
    )
fi

if [[ "$TEMPERATURE" == "thinking" ]]; then
    # Thinking mode for general tasks: temperature=1.0, top_p=0.95, top_k=20, min_p=0.0, presence_penalty=1.5, repetition_penalty=1.0
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
    # Instruct (or non-thinking) mode for general tasks: temperature=0.7, top_p=0.8, top_k=20, min_p=0.0, presence_penalty=1.5, repetition_penalty=1.0
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

# disabled ram offloading
# --cache-ram 0
#	--ctx-checkpoints 0
# --cache-ram 8192 -> default

echo "🚀 Starting llama-server..."
echo "   RAW_IDS      : $DEVICE_ID"
echo "   DEVICES      : $ROCM_DEVICES"
echo "   Vision file  : $MMPROJ_FILE"
echo "   Model        : $MODEL_FILE"
echo "   Port         : $PORT"
echo "   Device ID    : $DEVICE_ID -> $ROCM_DEVICES"
echo "   Context      : ${CONTEXT_SIZE}"
echo "   KV Cache     : $KV_CACHE_TYPE"
echo "   Split Mode   : $SPLIT_MODE"
echo "   Log File     : $LOG_FILE"
echo "   Temperature  : $TEMPERATURE"
echo ""
echo "📝 Full command being executed:"
printf '%q ' "${LLAMA_CMD[@]}" "${EXTRA_ARGS[@]}"
echo ""

# ==============================================================================
# Execute Server
# ==============================================================================
# Execute the array in the background with nohup
nohup "${LLAMA_CMD[@]}" "${EXTRA_ARGS[@]}" >> "$LOG_FILE" 2>&1 &

# Capture the Process ID
SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"

echo "✅ Server started in background with PID: $SERVER_PID"
echo "   Tail the logs with: tail -f $LOG_FILE"
echo "   Stop the server with: kill $SERVER_PID (or run this script again to auto-restart)"