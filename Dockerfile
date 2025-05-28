ARG PYTHON_VERSION=3.12

# ---------- Builder Base ----------
FROM ghcr.io/astral-sh/uv:python${PYTHON_VERSION}-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

RUN apt update && apt upgrade -y && \
    apt install -y --no-install-recommends \
        curl git libibverbs-dev zlib1g-dev aria2 \
        libgl1 libglib2.0-0 fonts-dejavu-core ffmpeg && \
    apt clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# Setup workspace and venv
WORKDIR /app

RUN uv venv --python ${PYTHON_VERSION} --seed --python-preference system
ENV VIRTUAL_ENV=/app/.venv
ENV PATH=${VIRTUAL_ENV}/bin:${PATH}

ENV COMFY_HOME=/app/ComfyUI

# Install all Python packages in one layer
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install torch torchvision torchaudio --pre --index-url https://download.pytorch.org/whl/nightly/cu128 && \
    uv pip install "https://github.com/arsac/comfyui-flux/releases/download/xformers-v0.0.30-cuda12.9.0/xformers-0.0.30+4cf69f0.d20250529-cp312-cp312-linux_x86_64.whl" && \
    uv pip install pynvml flatbuffers numpy packaging protobuf sympy comfy-cli && \
    uv pip install onnxruntime-gpu --pre --index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/ORT-Nightly/pypi/simple/ && \
    comfy --skip-prompt --workspace ${COMFY_HOME} install --nvidia --version nightly --fast-deps

RUN mkdir -p /scripts
COPY scripts/entrypoint.sh /scripts/entrypoint.sh
RUN chmod +x /scripts/entrypoint.sh

# Debug: Verify venv exists before cache clean
RUN ls -la /app/.venv/bin/ && echo "venv exists in builder"

RUN uv cache clean

# Debug: Verify venv still exists after cache clean
RUN ls -la /app/.venv/bin/ && echo "venv still exists after cache clean"

# Use runtime image for final stage
FROM python:${PYTHON_VERSION}-slim-bookworm AS comfyui-runtime


# Install minimal runtime dependencies
RUN apt update && apt install -y --no-install-recommends \
    libgl1 libglib2.0-0 fonts-dejavu-core ffmpeg git \
    && apt clean && rm -rf /var/lib/apt/lists/*

# Create user and transfer ownership including the venv
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN groupadd -g ${GROUP_ID} comfyui && \
    useradd -u ${USER_ID} -g ${GROUP_ID} -d /app -s /bin/bash comfyui

# Set up directories
ENV COMFY_HOME=/app/ComfyUI
ENV MODEL_DIR=${COMFY_HOME}/models
ENV OUTPUT_DIR=${COMFY_HOME}/output
ENV INPUT_DIR=${COMFY_HOME}/input
ENV WOKFLOWS_DIR=${COMFY_HOME}/workflows

# Copy the application from the builder
COPY --from=builder --chown=comfyui:comfyui /app /app
COPY --from=builder --chown=comfyui:comfyui /scripts /scripts

# Debug: Verify venv was copied
RUN ls -la /app/ && echo "Contents of /app after copy"
RUN ls -la /app/.venv/bin/ 2>/dev/null && echo "venv copied successfully" || echo "ERROR: venv not found in runtime"

# Set up virtual environment path BEFORE switching to user
ENV VIRTUAL_ENV=/app/.venv
ENV PATH="/app/.venv/bin:$PATH"

USER comfyui

# Explicitly activate virtual environment and run comfy commands
RUN . /app/.venv/bin/activate && \
    comfy --skip-prompt tracking disable && \
    comfy --skip-prompt set-default ${COMFY_HOME}

COPY --chown=comfyui:comfyui workflows/. ${WOKFLOWS_DIR}/

WORKDIR ${COMFY_HOME}

EXPOSE 8188
CMD ["/scripts/entrypoint.sh"]