# llama.cpp Build and Update Runbook (Local SBC)

This runbook documents the operator steps to update and rebuild `llama.cpp` for the Open WebUI/LiteLLM stack in this repository.

## Scope

- Source tree: `~/llama.cpp`
- Served binary: `~/llama.cpp/build-vulkan/bin/llama-server`
- Systemd unit source (repo): `systemd/llama-server.service`
- Active unit on host: `~/.config/systemd/user/llama-server.service`
- Active model presets: `~/.config/llama/models.ini`

## 1) Pre-update safety (preserve local compatibility patch if present)

```bash
cd ~/llama.cpp
git status --short
```

If `ggml/src/ggml-vulkan/ggml-vulkan.cpp` has local changes (for example Vulkan-HPP compatibility edits), save them before pulling:

```bash
git diff ggml/src/ggml-vulkan/ggml-vulkan.cpp > /tmp/llama-vulkan-local.patch
```

If needed, return the file to upstream state before pull:

```bash
git checkout -- ggml/src/ggml-vulkan/ggml-vulkan.cpp
```

## 2) Update source and rebuild Vulkan target

```bash
cd ~/llama.cpp
git pull --ff-only
cmake -S . -B build-vulkan -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-vulkan -j"$(nproc)"
```

## 3) Re-apply compatibility patch only if still required

If build fails with Vulkan-HPP symbol errors in `ggml-vulkan.cpp`, re-apply your saved patch and rebuild:

```bash
cd ~/llama.cpp
git apply /tmp/llama-vulkan-local.patch
cmake --build build-vulkan -j"$(nproc)"
```

## 4) Restart llama service

If the unit in this repo changed, sync it to user systemd first (copy or symlink), then:

```bash
systemctl --user daemon-reload
systemctl --user restart llama-server.service
systemctl --user status llama-server.service --no-pager
```

## 5) Post-build verification

Check running server and model list:

```bash
curl -s http://127.0.0.1:8765/health
curl -s http://127.0.0.1:8765/v1/models | jq -r '.data[] | .id'
```

Smoke test chat model:

```bash
curl -s http://127.0.0.1:8765/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"Qwen3.5-4B-Q4_0",
    "messages":[{"role":"user","content":"Reply with exactly: ok"}],
    "temperature":0,
    "max_tokens":16,
    "stream":false
  }' | jq
```

Smoke test embedding model:

```bash
curl -s http://127.0.0.1:8765/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"Qwen3-Embedding-0.6B-Q8_0",
    "input":"ping"
  }' | jq '.data[0].embedding | length'
```

## 6) Troubleshooting checklist

- Confirm `llama-server` version after restart:
  - `~/llama.cpp/build-vulkan/bin/llama-server --version`
- Inspect recent logs:
  - `journalctl --user -u llama-server.service --since "30 min ago" --no-pager`
- If Qwen3.5 fails with cache/flash-attn mismatch errors, ensure model preset is internally consistent:
  - with `flash-attn = off`, use `cache-type-k = f16` and `cache-type-v = f16`
  - with quantized KV cache (`q8_0`, `q4_0`), keep `flash-attn = on`
- If Open WebUI web search still fails after server fix, check:
  - Open WebUI logs (`podman logs` for `open-webui_open-webui_1`)
  - vector DB state (`open-webui_qdrant_1`)
  - RAG chunking and embedding model settings in Open WebUI admin settings

