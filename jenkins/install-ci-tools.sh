#!/usr/bin/env bash
# install-ci-tools.sh - give the running Jenkins container the two tools the quality stages need:
#   ruff   (lint)         - single static binary, downloaded here on the host, checksum-verified,
#                           then copied in. No pip/apt needed inside Jenkins.
#   trivy  (image scan)   - already installed; this copies its vulnerability database so the
#                           pipeline can scan offline (the download is slow on this connection).
# Safe to re-run. Nothing here is committed; the Jenkins home is a Docker volume, so it survives restarts.
set -euo pipefail

CONTAINER="${CONTAINER:-jenkins}"
RUFF_VERSION="${RUFF_VERSION:-0.16.10}"          # same version as on the host: ruff --version
ARCH_TAG="x86_64-unknown-linux-gnu"
BASE="https://github.com/astral-sh/ruff/releases/download/${RUFF_VERSION}"
ASSET="ruff-${ARCH_TAG}.tar.gz"

docker inspect "$CONTAINER" >/dev/null 2>&1 || { echo "Container '$CONTAINER' is not running."; exit 1; }

echo "== ruff =="
if docker exec "$CONTAINER" sh -c "ruff --version" 2>/dev/null | grep -q "$RUFF_VERSION"; then
  echo "already installed: $(docker exec "$CONTAINER" ruff --version)"
else
  W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
  echo "downloading $ASSET ($RUFF_VERSION) ..."
  curl -fSL --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 20 -o "$W/$ASSET"        "$BASE/$ASSET"
  curl -fSL --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 20 -o "$W/$ASSET.sha256" "$BASE/$ASSET.sha256"
  # the .sha256 file names the asset; check against the downloaded copy
  ( cd "$W" && sha256sum -c "$ASSET.sha256" ) || { echo "CHECKSUM MISMATCH - refusing to install."; exit 1; }
  mkdir "$W/x" && tar -xzf "$W/$ASSET" -C "$W/x"
  BIN=$(find "$W/x" -type f -name ruff | head -1)
  [ -n "$BIN" ] || { echo "ruff binary not found in the archive"; exit 1; }
  docker cp "$BIN" "$CONTAINER:/usr/local/bin/ruff"
  docker exec -u root "$CONTAINER" chmod 0755 /usr/local/bin/ruff
  echo "installed: $(docker exec "$CONTAINER" ruff --version)"
fi

echo; echo "== trivy =="
docker exec "$CONTAINER" trivy --version | head -1
if [ -d "$HOME/.cache/trivy/db" ]; then
  docker exec "$CONTAINER" sh -c 'mkdir -p "$HOME/.cache"'
  docker cp "$HOME/.cache/trivy" "$CONTAINER:/var/jenkins_home/.cache/"
  docker exec -u root "$CONTAINER" chown -R jenkins:jenkins /var/jenkins_home/.cache
  echo "vulnerability database copied"
else
  echo "No database on the host. Run:  trivy image --download-db-only   (slow, retry if it times out), then re-run this script."
fi

echo; echo "== offline scan test, as the jenkins user (must print a report, not try to download) =="
IMG=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^vaultai-web:' | head -1)
[ -n "$IMG" ] || IMG=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^vaultai-api:' | head -1)
echo "image: ${IMG:-none found}"
if [ -n "${IMG:-}" ]; then
  docker exec "$CONTAINER" trivy image --skip-db-update --skip-java-db-update --no-progress --skip-version-check \
      --scanners vuln --ignore-unfixed --severity CRITICAL --exit-code 0 "$IMG" 2>&1 | tail -15
fi
echo; echo "Done. Next: run apply-gates-and-docs.sh"
