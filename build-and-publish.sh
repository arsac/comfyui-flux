#!/bin/bash
set -e

docker buildx build --platform linux/amd64 . -t ghcr.io/arsac/comfyui-flux:latest

docker push ghcr.io/arsac/comfyui-flux:latest
echo "Docker image built and pushed successfully."