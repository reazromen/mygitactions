#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/reazromen/nextcloud-prod-restore-fimi-20260501-154159}"
RUNNER_TOKEN="${RUNNER_TOKEN:-}"
RUNNER_NAME="${RUNNER_NAME:-hserver}"
RUNNER_USER="${RUNNER_USER:-opsbot}"
RUNNER_DIR="${RUNNER_DIR:-/opt/github-runner}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo."
  exit 1
fi

if [[ -z "$RUNNER_TOKEN" ]]; then
  read -r -s -p "GitHub runner registration token: " RUNNER_TOKEN
  echo
fi
if [[ -z "$RUNNER_TOKEN" ]]; then
  echo "Runner token is required."
  exit 1
fi

command -v curl >/dev/null
command -v python3 >/dev/null
command -v tar >/dev/null

id "$RUNNER_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$RUNNER_USER"
getent group docker >/dev/null 2>&1 && usermod -aG docker "$RUNNER_USER" || true
getent group systemd-journal >/dev/null 2>&1 && usermod -aG systemd-journal "$RUNNER_USER" || true

install -d -o "$RUNNER_USER" -g "$RUNNER_USER" "$RUNNER_DIR"
install -d -o "$RUNNER_USER" -g "$RUNNER_USER" /opt/remote-ops

release_json="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest)"
tag="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])' <<<"$release_json")"
ver="${tag#v}"

case "$(uname -m)" in
  x86_64|amd64) arch=x64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

pkg="actions-runner-linux-${arch}-${ver}.tar.gz"
url="https://github.com/actions/runner/releases/download/${tag}/${pkg}"

if [[ ! -x "$RUNNER_DIR/config.sh" ]]; then
  tmp="$(mktemp)"
  curl -fL "$url" -o "$tmp"
  tar -xzf "$tmp" -C "$RUNNER_DIR"
  rm -f "$tmp"
  chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"
fi

if [[ ! -f "$RUNNER_DIR/.runner" ]]; then
  sudo -u "$RUNNER_USER" bash -lc "cd '$RUNNER_DIR' && ./config.sh --url '$REPO_URL' --token '$RUNNER_TOKEN' --name '$RUNNER_NAME' --labels hserver --work _work --unattended --replace"
fi

cd "$RUNNER_DIR"
./svc.sh install "$RUNNER_USER" 2>/dev/null || true
./svc.sh start
./svc.sh status || true

unset RUNNER_TOKEN
echo "hserver GitHub runner is registered and started."
