#!/usr/bin/env bash
set -euo pipefail

failed=0
files="$(find . -name docker-compose.yml -print)"

for file in $files; do
  echo "Validating $file"
  if ! podman-compose -f "$file" config >/dev/null; then
    failed=1
  fi
done

exit "$failed"
