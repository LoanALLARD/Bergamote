#!/usr/bin/env bash
# Lance une commande dans le conteneur de développement Linux (voir Dockerfile.dev), avec le
# dépôt monté et des caches de compilation persistants.
#
#   linux/scripts/docker.sh cargo test
#   linux/scripts/docker.sh scripts/smoke-test.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
docker image inspect bergamote-linux-dev >/dev/null 2>&1 || docker build -q -t bergamote-linux-dev -f "$ROOT/linux/scripts/Dockerfile.dev" "$ROOT/linux/scripts"
exec docker run --rm -v "$ROOT":/src -v bergamote-target:/target -v bergamote-cargo:/root/.cargo/registry \
  -e BERGAMOTE_DEBUG="${BERGAMOTE_DEBUG:-}" bergamote-linux-dev "$@"
