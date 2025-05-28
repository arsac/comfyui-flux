#!/bin/bash
set -e

echo "########################################"
echo "[INFO] Downloading models..."
echo "########################################"

# Function to download model if it doesn't exist
download_model() {
    local url="$1"
    local path="$2"
    
    if [ ! -f "${COMFY_HOME}/${path}" ]; then
        comfy --skip-prompt --workspace "${COMFY_HOME}" model download --url "${url}" --relative-path "${path}" --set-hf-api-token "${HF_TOKEN}"
    else
        echo "${url} already exists, skipping download"
    fi
}

# Download essential models based on environment variables
if [ "${DOWNLOAD_FLUX}" = "true" ]; then
    download_model "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors" \
                   "models/unet/flux1-schnell.safetensors"

    download_model "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors" \
                   "models/unet/flux1-dev.safetensors"

    download_model "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" \
                   "models/clip/clip_l.safetensors"

    download_model "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors" \
                   "models/clip/t5xxl_fp16.safetensors"

    download_model "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" \
                   "models/clip/t5xxl_fp8_e4m3fn.safetensors"

    download_model "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors" \
                   "models/vae/ae.safetensors"

    download_model "https://huggingface.co/comfyanonymous/flux_RealismLora_converted_comfyui/resolve/main/flux_realism_lora.safetensors" \
                   "models/loras/flux_realism_lora.safetensors"
fi

if [ "${DOWNLOAD_SD15}" = "true" ]; then
    download_model "https://huggingface.co/runwayml/stable-diffusion-v1-5" \
                   "models/checkpoints/sd15.safetensors"
fi

if [ "${DOWNLOAD_CLIP}" = "true" ]; then
    download_model "https://huggingface.co/openai/clip-vit-large-patch14" \
                   "models/clip/clip-vit-large-patch14.safetensors"
fi

# Download custom models from environment variable
if [ -n "${CUSTOM_MODELS}" ]; then
    echo "Downloading custom models: ${CUSTOM_MODELS}"
    IFS=',' read -ra MODELS <<< "${CUSTOM_MODELS}"
    for model_url in "${MODELS[@]}"; do
        echo "Downloading ${model_url}..."
        comfy --workspace "${COMFY_HOME}" model download --url "${model_url}" --set-hf-api-token "${HF_TOKEN}"
    done
fi

# Download models from a file if it exists
if [ -f "/app/models.txt" ]; then
    echo "Found models.txt, downloading listed models..."
    while IFS= read -r line; do
        if [ -n "$line" ] && [[ ! "$line" =~ ^# ]]; then
            echo "Downloading ${line}..."
            comfy --workspace "${COMFY_HOME}" model download --url "${line}" --set-hf-api-token "${HF_TOKEN}"
        fi
    done < "/app/models.txt"
fi

echo "########################################"
echo "[INFO] Starting ComfyUI..."
echo "########################################"

# Debug information for troubleshooting
echo "[DEBUG] PATH: $PATH"
echo "[DEBUG] COMFY_HOME: $COMFY_HOME"
echo "[DEBUG] which comfy: $(which comfy 2>/dev/null || echo 'not found')"
echo "[DEBUG] type comfy: $(type comfy 2>/dev/null || echo 'not found')"

echo "[DEBUG] Python version: $(python --version 2>&1)"

ls -la /app
ls -la /app/.venv/
ls -la /app/.venv/bin/
# Check if comfy command exists and is executable
if ! command -v comfy >/dev/null 2>&1; then
    echo "[ERROR] comfy command not found in PATH"
    echo "[ERROR] Available commands in PATH:"
    ls -la /usr/local/bin/ 2>/dev/null | grep comfy || echo "No comfy binaries found"
    exit 1
fi

if [ -d "$(which comfy)" ]; then
    echo "[ERROR] comfy resolves to a directory instead of executable: $(which comfy)"
    ls -la "$(which comfy)"
    exit 1
fi

# Start ComfyUI with any additional arguments
exec comfy launch -- --listen "0.0.0.0" --port "8188" "$@"
