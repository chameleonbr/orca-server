#!/usr/bin/env bash
# install-docker-cli.sh — Docker CLI + compose plugin (client only; daemon is the dind sidecar)
set -euo pipefail

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64) DOCKER_ARCH=x86_64 ;;
  aarch64|arm64) DOCKER_ARCH=aarch64 ;;
  *)
    echo "[install-docker-cli] unsupported arch: ${ARCH}" >&2
    exit 1
    ;;
esac

DOCKER_CLI_VERSION="${DOCKER_CLI_VERSION:-27.5.1}"
COMPOSE_VERSION="${DOCKER_COMPOSE_VERSION:-2.32.4}"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

echo "[install-docker-cli] Docker CLI ${DOCKER_CLI_VERSION} (${DOCKER_ARCH})"
curl -fsSL "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_CLI_VERSION}.tgz" \
  -o "${tmp}/docker.tgz"
tar -xzf "${tmp}/docker.tgz" -C "${tmp}"
install -m 755 "${tmp}/docker/docker" /usr/local/bin/docker

echo "[install-docker-cli] Compose plugin v${COMPOSE_VERSION}"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-${DOCKER_ARCH}" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod 755 /usr/local/lib/docker/cli-plugins/docker-compose
# convenience shim
ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

docker version --format 'Client: {{.Client.Version}}' 2>/dev/null || docker --version
echo "[install-docker-cli] OK (daemon via DOCKER_HOST / dind sidecar)"
