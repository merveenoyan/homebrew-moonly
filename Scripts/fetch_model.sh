#!/usr/bin/env bash
#
# Pre-download the Gemma 4 E4B (QAT) GGUF into Moonly's app-owned model cache.
#
# Moonly now runs llama.cpp in-process via LlamaKit, which downloads the model
# from the Hugging Face Hub on first launch into HF_HUB_CACHE. This script just
# warms that cache at install time using the `hf` CLI when it's available; if
# `hf` isn't installed (or this is skipped/offline), the app downloads on first
# launch instead. The download is the only outbound traffic Moonly ever makes.
set -euo pipefail

REPO="google/gemma-4-E4B-it-qat-q4_0-gguf"
CACHE="$HOME/Library/Application Support/Moonly/models"
mkdir -p "$CACHE"
export HF_HUB_CACHE="$CACHE"

HF="$(command -v hf || true)"
if [ -z "$HF" ]; then
  echo "hf CLI not found; Moonly will download the model on first launch."
  exit 0
fi

echo "Pre-downloading $REPO (~5 GB, one time) into $CACHE …"
# Only the main weights — skip the optional multimodal mmproj projector.
if "$HF" download "$REPO" --include "*q4_0.gguf" >/dev/null 2>&1; then
  echo "Model ready in $CACHE"
else
  echo "Pre-download didn't finish; the app will retry on first launch."
fi
exit 0
