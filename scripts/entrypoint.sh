#!/bin/bash
set -e

echo "########################################"
echo "[INFO] Downloading models..."
echo "########################################"

# Function to download model if it doesn't exist
download_model() {
    local url="$1"
    local path="$2"
    local name="$3"
    
    if [ ! -f "${COMFY_HOME}/${path}" ]; then
        echo "Downloading ${name}..."
        comfy --workspace "${COMFY_HOME}" model download --url "${url}" --relative-path "${path}" --token "${HF_TOKEN}"
    else
        echo "${name} already exists, skipping download"
    fi
}

# Download essential models based on environment variables
if [ "${DOWNLOAD_FLUX}" = "true" ]; then
    download_model "https://huggingface.co/black-forest-labs/FLUX.1-schnell" \
                   "models/unet/flux1-schnell.safetensors" \
                   "FLUX.1 Schnell"
fi

if [ "${DOWNLOAD_SD15}" = "true" ]; then
    download_model "https://huggingface.co/runwayml/stable-diffusion-v1-5" \
                   "models/checkpoints/sd15.safetensors" \
                   "Stable Diffusion 1.5"
fi

if [ "${DOWNLOAD_CLIP}" = "true" ]; then
    download_model "https://huggingface.co/openai/clip-vit-large-patch14" \
                   "models/clip/clip-vit-large-patch14.safetensors" \
                   "CLIP ViT Large"
fi

# Download custom models from environment variable
if [ -n "${CUSTOM_MODELS}" ]; then
    echo "Downloading custom models: ${CUSTOM_MODELS}"
    IFS=',' read -ra MODELS <<< "${CUSTOM_MODELS}"
    for model_url in "${MODELS[@]}"; do
        echo "Downloading ${model_url}..."
        comfy --workspace "${COMFY_HOME}" model download --url "${model_url}" --token "${HF_TOKEN}"
    done
fi

# Download models from a file if it exists
if [ -f "/app/models.txt" ]; then
    echo "Found models.txt, downloading listed models..."
    while IFS= read -r line; do
        if [ -n "$line" ] && [[ ! "$line" =~ ^# ]]; then
            echo "Downloading ${line}..."
            comfy --workspace "${COMFY_HOME}" model download --url "${line}" --token "${HF_TOKEN}"
        fi
    done < "/app/models.txt"
fi

echo "########################################"
echo "[INFO] Starting ComfyUI..."
echo "########################################"

# Start ComfyUI with any additional arguments
exec comfy --workspace "${COMFY_HOME}" launch -- --listen "0.0.0.0" --port "8188" "$@"