#!/usr/bin/env python3
"""Check that .env.example files cover variables referenced in compose files."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

COMPOSE_FILENAME = "docker-compose.yml"
ENV_EXAMPLE_FILENAME = ".env.example"

ENV_VAR_PATTERN = re.compile(r"(?<!\$)\$\{([A-Z0-9_]+)(?::[^}]*)?\}")
ENV_LINE_PATTERN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=")


def parse_env_example(env_path: Path) -> set[str]:
    variables: set[str] = set()
    for line in env_path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = ENV_LINE_PATTERN.match(stripped)
        if match:
            variables.add(match.group(1))
    return variables


def parse_compose_env_vars(compose_path: Path) -> set[str]:
    content = compose_path.read_text(encoding="utf-8")
    return set(ENV_VAR_PATTERN.findall(content))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=".")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    compose_files = sorted(root.rglob(COMPOSE_FILENAME))

    missing_total: list[str] = []

    for compose_file in compose_files:
        env_vars = parse_compose_env_vars(compose_file)
        if not env_vars:
            continue
        env_example = compose_file.parent / ENV_EXAMPLE_FILENAME
        if not env_example.exists():
            missing_total.append(
                f"{compose_file}: missing {ENV_EXAMPLE_FILENAME} for {sorted(env_vars)}"
            )
            continue
        example_vars = parse_env_example(env_example)
        missing = sorted(env_vars - example_vars)
        if missing:
            missing_total.append(
                f"{compose_file}: missing variables in {ENV_EXAMPLE_FILENAME}: {missing}"
            )

    if missing_total:
        print(".env.example coverage check failed:")
        for entry in missing_total:
            print(f"- {entry}")
        return 1

    print(".env.example coverage check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
