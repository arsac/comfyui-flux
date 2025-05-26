ARG CUDA_VERSION=12.9.0
ARG IMAGE_DISTRO=ubuntu24.04
ARG PYTHON_VERSION=3.12

# ---------- Builder Base ----------
FROM nvcr.io/nvidia/cuda:${CUDA_VERSION}-devel-${IMAGE_DISTRO} AS base


ARG TORCH_CUDA_ARCH_LIST="12.0"
ENV TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST}

ENV DEBIAN_FRONTEND=noninteractive
RUN apt update
RUN apt upgrade -y
RUN apt install -y --no-install-recommends \
        curl \
        git \
        libibverbs-dev \
        zlib1g-dev \
        aria2 \
        libgl1 \
        libglib2.0-0 \
        fonts-dejavu-core \
        ffmpeg

# Clean apt cache
RUN apt clean
RUN rm -rf /var/lib/apt/lists/*
RUN rm -rf /var/cache/apt/archives

# Set compiler paths
ENV CC=/usr/bin/gcc
ENV CXX=/usr/bin/g++

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Setup build workspace
WORKDIR /workspace

# Set UV cache directory
ENV UV_CACHE_DIR=/tmp/uv-cache
ENV UV_PYTHON_INSTALL_DIR=/opt/python

# Prep build venv
ARG PYTHON_VERSION
RUN uv venv -p ${PYTHON_VERSION} --seed --python-preference only-managed
ENV VIRTUAL_ENV=/workspace/.venv
ENV PATH=${VIRTUAL_ENV}/bin:${PATH}
ENV CUDA_HOME=/usr/local/cuda
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}

# Install pytorch nightly
RUN --mount=type=cache,target=/tmp/uv-cache \
    uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128

FROM base AS build-base
RUN mkdir /wheels

# Install build deps that aren't in project requirements files
# Make sure to upgrade setuptools to avoid triton build bug
RUN --mount=type=cache,target=/tmp/uv-cache \
    uv pip install -U build cmake ninja pybind11 setuptools wheel

FROM build-base AS build-xformers
ARG XFORMERS_REF=v0.0.30
ARG XFORMERS_BUILD_VERSION=0.0.30+cu128
ENV BUILD_VERSION=${XFORMERS_BUILD_VERSION:-${XFORMERS_REF#v}} \
    TORCH_CUDA_ARCH_LIST="12.0"
RUN git clone https://github.com/facebookresearch/xformers.git
RUN cd xformers && \
    git checkout ${XFORMERS_REF} && \
    git submodule sync && \
    git submodule update --init --recursive -j 8 && \
    uv build --wheel --no-build-isolation -o /wheels

FROM base AS comfyui

ENV COMFY_HOME=/app/ComfyUI
ENV UV_CACHE_DIR=/tmp/uv-cache
ENV UV_NO_PROGRESS=1

WORKDIR /app

# Use the existing venv from base stage
ENV VIRTUAL_ENV=/workspace/.venv
ENV PATH=${VIRTUAL_ENV}/bin:${PATH}

# Install packages using the existing venv
COPY --from=build-xformers /wheels/* wheels/
RUN --mount=type=cache,target=/tmp/uv-cache \
    uv pip install wheels/* pynvml flatbuffers numpy packaging protobuf sympy comfy-cli && \
    rm -r wheels

# Install onnxruntime-gpu (optional)
RUN --mount=type=cache,target=/tmp/uv-cache \
    uv pip install onnxruntime-gpu \
    --pre --index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/ORT-Nightly/pypi/simple/

# Install ComfyUI
RUN --mount=type=cache,target=/tmp/uv-cache \
    comfy --skip-prompt tracking disable && \
    comfy --skip-prompt --workspace ${COMFY_HOME} install --nvidia --fast-deps

# Set comfy-cli default workspace
RUN comfy --skip-prompt set-default ${COMFY_HOME}

# Use runtime image for final stage
FROM python:${PYTHON_VERSION}-slim-bookworm AS comfyui-runtime
# Copy from the build stage
COPY --from=base /workspace/.venv /workspace/.venv
COPY --from=comfyui /app /app

# Install minimal runtime dependencies
RUN apt update && apt install -y --no-install-recommends \
    libgl1 libglib2.0-0 fonts-dejavu-core ffmpeg \
    && apt clean && rm -rf /var/lib/apt/lists/*

# Set up environment
ENV VIRTUAL_ENV=/workspace/.venv
ENV PATH=${VIRTUAL_ENV}/bin:${PATH}
ENV COMFY_HOME=/app/ComfyUI

# Create and copy entrypoint script
RUN mkdir -p /scripts
COPY scripts/entrypoint.sh /scripts/entrypoint.sh
RUN chmod +x /scripts/entrypoint.sh

# Create user and transfer ownership including the venv
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN groupadd -g ${GROUP_ID} comfyui && \
    useradd -u ${USER_ID} -g ${GROUP_ID} -d /app -s /bin/bash comfyui

# Set up directories
ENV MODEL_DIR=${COMFY_HOME}/models
ENV OUTPUT_DIR=${COMFY_HOME}/output
ENV INPUT_DIR=${COMFY_HOME}/input
ENV WOKFLOWS_DIR=${COMFY_HOME}/workflows

RUN mkdir -p ${MODEL_DIR} ${OUTPUT_DIR} ${INPUT_DIR} ${COMFY_HOME}/custom_nodes && \
    chown -R comfyui:comfyui /workspace/.venv /app && \
    chmod -R 755 /app

COPY --chown=comfyui:comfyui workflows/. ${WOKFLOWS_DIR}/

USER comfyui
WORKDIR ${COMFY_HOME}

EXPOSE 8188
CMD ["/scripts/entrypoint.sh"]