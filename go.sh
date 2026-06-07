#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# go.sh — 1-line entry point for VPS bootstrap
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/anjar-wilujeng/vps-bootstrap/main/go.sh)
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
  echo "[!] Please run as root."
  exit 1
fi

apt update
apt install -y git curl tmux

rm -rf /tmp/vps-bootstrap
git clone https://github.com/anjar-wilujeng/vps-bootstrap.git /tmp/vps-bootstrap
cd /tmp/vps-bootstrap
chmod +x bootstrap.sh

exec ./bootstrap.sh
