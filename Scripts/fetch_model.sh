#!/usr/bin/env bash
#
# Pre-download the Gemma 4 E4B (QAT) GGUF into Moonly's app-owned model cache.
#
# llama.cpp's `-hf` flag downloads + caches + serves in one shot, so the
# simplest reliable way to "download at install time" is to start the server
# pointed at the model, wait until it's healthy (= fully downloaded + loadable),
# then stop it. The app uses the exact same command at runtime, so this just
# warms the cache; if it's skipped or offline, the app downloads on first launch.
set -euo pipefail

REPO="google/gemma-4-E4B-it-qat-q4_0-gguf"
CACHE="$HOME/Library/Application Support/Moonly/models"
mkdir -p "$CACHE"

SERVER="$(command -v llama-server || true)"
[ -z "$SERVER" ] && SERVER="${HOMEBREW_PREFIX:-/opt/homebrew}/bin/llama-server"
if [ ! -x "$SERVER" ]; then
  echo "llama-server not found; the app will download the model on first launch."
  exit 0
fi

PORT=$(( (RANDOM % 5000) + 40000 ))
echo "Pre-downloading $REPO (~5 GB, one time) into $CACHE …"

# -ngl 0: we only want the download here, no need to load onto the GPU.
LLAMA_CACHE="$CACHE" "$SERVER" -hf "$REPO" \
  --host 127.0.0.1 --port "$PORT" -ngl 0 --no-webui >/dev/null 2>&1 &
PID=$!

# Up to ~60 min for the download + load to report healthy.
ok=0
for _ in $(seq 1 1800); do
  if ! kill -0 "$PID" 2>/dev/null; then echo "server exited early"; break; fi
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then ok=1; break; fi
  sleep 2
done

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

if [ "$ok" = "1" ]; then
  echo "Model ready in $CACHE"
else
  echo "Pre-download didn't finish; the app will retry on first launch."
fi
exit 0
