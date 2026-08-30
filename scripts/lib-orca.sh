#!/usr/bin/env bash
# lib-orca.sh — shared paths and helpers for Orca runtime (persistent, updatable)
# Official refs:
#   https://github.com/stablyai/orca/blob/main/docs/reference/headless-linux-server.md
#   https://github.com/stablyai/orca/releases/latest/download/orca-linux.AppImage
#
# Runtime lives under HOME so the AppImage can be replaced without image rebuild.
# State (pairing, projects metadata) stays in ~/.config/{orca,Orca} — independent of binary.

# shellcheck shell=bash

orca_default_install_dir() {
  echo "${ORCA_INSTALL_DIR:-${HOME:-/home/orca}/.local/share/orca}"
}

orca_log() {
  printf '[orca] %s\n' "$*"
}

orca_warn() {
  printf '[orca] WARN: %s\n' "$*" >&2
}

orca_die() {
  printf '[orca] ERROR: %s\n' "$*" >&2
  exit 1
}

# Select release asset for this machine (official naming).
orca_select_asset() {
  case "$(uname -m)" in
    x86_64)
      ORCA_ASSET="orca-linux.AppImage"
      ORCA_FILE_MACHINE="x86-64"
      ;;
    aarch64|arm64)
      ORCA_ASSET="orca-linux-arm64.AppImage"
      ORCA_FILE_MACHINE="ARM aarch64"
      ;;
    *)
      orca_die "Unsupported architecture: $(uname -m)"
      ;;
  esac
  export ORCA_ASSET ORCA_FILE_MACHINE
}

# Normalize version tag: "1.4.192" | "v1.4.192" | "latest"
orca_normalize_version() {
  local v="${1:-latest}"
  if [[ "${v}" == "latest" ]]; then
    echo "latest"
    return
  fi
  v="${v#v}"
  echo "v${v}"
}

orca_resolve_download_url() {
  local version_spec
  version_spec="$(orca_normalize_version "${1:-${ORCA_VERSION:-latest}}")"
  orca_select_asset

  if [[ -n "${ORCA_DOWNLOAD_URL:-}" ]]; then
    echo "${ORCA_DOWNLOAD_URL}"
    return
  fi

  if [[ "${version_spec}" == "latest" ]]; then
    echo "https://github.com/stablyai/orca/releases/latest/download/${ORCA_ASSET}"
  else
    echo "https://github.com/stablyai/orca/releases/download/${version_spec}/${ORCA_ASSET}"
  fi
}

# Resolve the tag that "latest" currently points to (best-effort via GitHub API).
orca_resolve_latest_tag() {
  local tag
  tag="$(curl -fsSL https://api.github.com/repos/stablyai/orca/releases/latest \
    | jq -r '.tag_name // empty' 2>/dev/null || true)"
  if [[ -z "${tag}" ]]; then
    # Fallback: follow redirect of latest asset
    tag="$(curl -fsSIL "https://github.com/stablyai/orca/releases/latest/download/orca-linux.AppImage" 2>/dev/null \
      | tr -d '\r' \
      | awk -F/ 'tolower($0) ~ /^location:/ {print $(NF-1); exit}')"
  fi
  [[ -n "${tag}" ]] || orca_die "Could not resolve latest Orca release tag"
  echo "${tag}"
}

orca_installed_version() {
  local dir
  dir="$(orca_default_install_dir)"
  if [[ -f "${dir}/VERSION" ]]; then
    cat "${dir}/VERSION"
    return 0
  fi
  return 1
}

orca_is_installed() {
  local dir
  dir="$(orca_default_install_dir)"
  [[ -x "${dir}/squashfs-root/AppRun" ]]
}

orca_apprun() {
  echo "$(orca_default_install_dir)/squashfs-root/AppRun"
}
