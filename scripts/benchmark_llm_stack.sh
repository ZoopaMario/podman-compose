#!/usr/bin/env bash
set -euo pipefail

# Simple before/after benchmark for LiteLLM -> Ollama path.
# Requires: curl, awk, date, xargs, mktemp.

BASE_URL="${BASE_URL:-http://127.0.0.1:4000}"
API_KEY="${API_KEY:-}"
MODEL="${MODEL:-}"
PROMPT="${PROMPT:-Write a concise summary of speculative decoding and when it helps.}"
MAX_TOKENS="${MAX_TOKENS:-256}"
RUNS="${RUNS:-5}"
CONCURRENCY="${CONCURRENCY:-4}"

if [[ -z "${MODEL}" ]]; then
  echo "error: MODEL is required (example: MODEL=llama3.1:8b)." >&2
  exit 1
fi

call_once() {
  local out_file metrics http_code ttfb total
  local auth_header=()
  if [[ -n "${API_KEY}" ]]; then
    auth_header=(-H "Authorization: Bearer ${API_KEY}")
  fi
  out_file="$(mktemp)"
  metrics="$(
    curl -sS -o "${out_file}" \
      -w "%{http_code} %{time_starttransfer} %{time_total}" \
      -H "Content-Type: application/json" \
      "${auth_header[@]}" \
      -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"${PROMPT}\"}],\"max_tokens\":${MAX_TOKENS},\"stream\":false}" \
      "${BASE_URL}/v1/chat/completions"
  )"
  read -r http_code ttfb total <<< "${metrics}"
  echo "${http_code} ${ttfb} ${total}"
  rm -f "${out_file}"
}

echo "== Benchmark target =="
echo "BASE_URL=${BASE_URL}"
echo "MODEL=${MODEL}"
echo "MAX_TOKENS=${MAX_TOKENS}"
echo "RUNS=${RUNS}"
echo "CONCURRENCY=${CONCURRENCY}"
echo

echo "== Single request runs =="
for i in $(seq 1 "${RUNS}"); do
  call_once
done | tee /tmp/llm-bench-single.txt

echo
echo "== ${CONCURRENCY}-concurrency runs (${RUNS} batches) =="
for _ in $(seq 1 "${RUNS}"); do
  pids=()
  for __ in $(seq 1 "${CONCURRENCY}"); do
    call_once &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do
    wait "${pid}"
  done
done | tee /tmp/llm-bench-concurrent.txt

echo
echo "== Summary =="
awk '
  BEGIN { single_n=0; single_ok=0; single_ttfb=0; single_total=0 }
  FNR==NR {
    single_n++;
    if ($1=="200") { single_ok++; single_ttfb+=$2; single_total+=$3 }
    next
  }
  {
    conc_n++;
    if ($1=="200") { conc_ok++; conc_ttfb+=$2; conc_total+=$3 }
  }
  END {
    printf("single: total=%d ok=%d avg_ttfb=%.3fs avg_total=%.3fs\n",
      single_n, single_ok,
      (single_ok?single_ttfb/single_ok:0),
      (single_ok?single_total/single_ok:0));
    printf("concurrent: total=%d ok=%d avg_ttfb=%.3fs avg_total=%.3fs\n",
      conc_n, conc_ok,
      (conc_ok?conc_ttfb/conc_ok:0),
      (conc_ok?conc_total/conc_ok:0));
  }
' /tmp/llm-bench-single.txt /tmp/llm-bench-concurrent.txt

echo
echo "raw outputs:"
echo "  /tmp/llm-bench-single.txt"
echo "  /tmp/llm-bench-concurrent.txt"
