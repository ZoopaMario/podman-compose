# Remote Ollama Performance Runbook

This stack uses LiteLLM on this host and Ollama on a remote host:

- `litellm/.env` currently points to `OLLAMA_API_BASE=http://remote-llm-host.local:11434`

Use this runbook on the remote machine (`remote-llm-host.local`) to apply safe, incremental performance tuning.

## 1) Inspect current Ollama service

```bash
ssh remote-user@remote-llm-host.local
systemctl status ollama --no-pager
systemctl show ollama -p Environment --no-pager
```

## 2) Apply conservative tuning via systemd override

```bash
sudo systemctl edit ollama
```

Add:

```ini
[Service]
Environment="OLLAMA_KEEP_ALIVE=30m"
Environment="OLLAMA_NUM_PARALLEL=2"
Environment="OLLAMA_MAX_LOADED_MODELS=2"
Environment="OLLAMA_MAX_QUEUE=512"
```

Then:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
systemctl show ollama -p Environment --no-pager
journalctl -u ollama -n 100 --no-pager
```

## 3) Roll back quickly if unstable

```bash
sudo systemctl revert ollama
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

## 4) Validate from LiteLLM host

Run benchmark before and after each change set:

```bash
MODEL="<your-model>" \
API_KEY="<your-litellm-master-key>" \
BASE_URL="http://127.0.0.1:4000" \
CONCURRENCY=4 \
RUNS=5 \
./scripts/benchmark_llm_stack.sh
```

If stable, test the next step:

- raise `OLLAMA_NUM_PARALLEL` from `2` to `4` only if no memory pressure or queue failures.
