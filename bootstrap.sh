#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# VPS Bootstrap — one-shot setup for disposable VPS
# ============================================================

USERNAME="awesome"
SSH_PORT="22022"
STACK_DIR="/opt/stacks"
BACKUP_DIR="/opt/backups"
SCRIPT_DIR="/opt/scripts"
LOGFILE="/var/log/vps-bootstrap.log"

# Redirect all output to log file + terminal
exec > >(tee -a "$LOGFILE") 2>&1

echo "[+] $(date) — VPS bootstrap started."
echo "[+] Target user: ${USERNAME}, SSH port: ${SSH_PORT}"

# --------------------------------------------------
# Root check
# --------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "[!] Please run this script as root."
  exit 1
fi

# --------------------------------------------------
# Rescue note
# --------------------------------------------------
# No SSH-IP safety net needed: this VPS keeps an out-of-band web console
# (Spaceship "Command line"/"Console") that is unaffected by SSH/firewall
# config, so we can harden aggressively without risk of lockout.

# --------------------------------------------------
# Base packages
# --------------------------------------------------
echo "[+] Updating package index..."
apt update

echo "[+] Installing base packages..."
DEBIAN_FRONTEND=noninteractive apt install -y \
  sudo curl git tmux ufw fail2ban ca-certificates gnupg lsb-release \
  unzip zip htop nano vim jq tree net-tools software-properties-common \
  zsh unattended-upgrades

# --------------------------------------------------
# Unattended upgrades (security patches)
# --------------------------------------------------
echo "[+] Configuring unattended-upgrades..."
cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades 2>/dev/null || true

# --------------------------------------------------
# Create user
# --------------------------------------------------
echo "[+] Creating user: ${USERNAME}"
if ! id "$USERNAME" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$USERNAME"
else
  echo "[=] User ${USERNAME} already exists."
fi

echo "[+] Adding ${USERNAME} to sudo and users group..."
usermod -aG sudo,users "$USERNAME"

echo "[+] Giving ${USERNAME} NOPASSWD sudo (disposable VPS)..."
cat > /etc/sudoers.d/${USERNAME} << EOF
${USERNAME} ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 /etc/sudoers.d/${USERNAME}

mkdir -p "$SCRIPT_DIR"
chown "${USERNAME}:${USERNAME}" "$SCRIPT_DIR"

# --------------------------------------------------
# SSH key directory (empty — Tailscale SSH handles auth)
# --------------------------------------------------
echo "[+] Preparing .ssh directory for ${USERNAME}..."
mkdir -p "/home/${USERNAME}/.ssh"
touch "/home/${USERNAME}/.ssh/authorized_keys"
chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.ssh"
chmod 700 "/home/${USERNAME}/.ssh"
chmod 600 "/home/${USERNAME}/.ssh/authorized_keys"

# --------------------------------------------------
# Docker
# --------------------------------------------------
echo "[+] Installing Docker..."
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
else
  echo "[=] Docker already installed."
fi

echo "[+] Adding ${USERNAME} to docker group..."
usermod -aG docker "$USERNAME"

echo "[+] Enabling Docker service..."
systemctl enable --now docker

echo "[+] Configuring Docker log rotation..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker || true

# --------------------------------------------------
# Working directories
# --------------------------------------------------
echo "[+] Creating working directories..."
mkdir -p "$STACK_DIR" "$BACKUP_DIR"
chown -R "${USERNAME}:${USERNAME}" "$STACK_DIR" "$BACKUP_DIR"

# --------------------------------------------------
# SSH hardening + port change
# --------------------------------------------------
echo "[+] Configuring SSH — port ${SSH_PORT} + hardening..."
cat > /etc/ssh/sshd_config.d/99-custom.conf << EOF
Port ${SSH_PORT}

# --- Hardening ---
# Primary access is Tailscale SSH; this system sshd is a tailnet-only
# fallback (see UFW rule binding it to tailscale0). Root and password
# logins are disabled — rescue is the provider web console.
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no

ClientAliveInterval 30
ClientAliveCountMax 10
TCPKeepAlive yes
UseDNS no
LoginGraceTime 30
MaxAuthTries 3
EOF

echo "[+] Checking SSH config..."
sshd -t

echo "[+] Reloading SSH service..."
systemctl reload ssh || systemctl reload sshd

# --------------------------------------------------
# UFW firewall
# --------------------------------------------------
echo "[+] Configuring UFW firewall..."

# SSH is NOT exposed publicly. Trust the whole Tailscale interface: this
# allows both Tailscale SSH (port 22 on the tailnet) AND the fallback
# system sshd on ${SSH_PORT}. The tailnet is private and ACL-controlled.
# (The rule references tailscale0 even before the interface exists — it
#  simply starts matching once tailscaled brings the interface up.)
ufw allow in on tailscale0 comment "Trust Tailscale tailnet"

# Public services for Docker stacks
ufw allow 80/tcp  comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw --force enable
ufw reload

# --------------------------------------------------
# Oh My Zsh + plugins
# --------------------------------------------------
echo "[+] Installing Oh My Zsh for ${USERNAME}..."
if [ ! -d "/home/${USERNAME}/.oh-my-zsh" ]; then
  sudo -u "$USERNAME" bash -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes bash <(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)' </dev/null
else
  echo "[=] Oh My Zsh already installed."
fi

ZSH_CUSTOM="/home/${USERNAME}/.oh-my-zsh/custom"

echo "[+] Installing Zsh plugins..."
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
  sudo -u "$USERNAME" git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
fi
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
  sudo -u "$USERNAME" git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
fi

echo "[+] Writing .zshrc..."
cat > "/home/${USERNAME}/.zshrc" << 'ZSHRCEOF'
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(
  git
  sudo
  docker
  docker-compose
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias c='clear'
alias dps='docker ps'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'
alias stacks='cd /opt/stacks'
alias scripts='cd /opt/scripts'
alias backups='cd /opt/backups'

export EDITOR=nano
ZSHRCEOF

chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.zshrc"

echo "[+] Changing default shell to zsh for ${USERNAME}..."
chsh -s "$(command -v zsh)" "$USERNAME"

# --------------------------------------------------
# Tailscale
# --------------------------------------------------
echo "[+] Installing Tailscale..."
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
else
  echo "[=] Tailscale already installed."
fi

systemctl enable --now tailscaled

# Pre-set hostname so Tailscale SSH works with consistent name
# User still needs to run: tailscale up --ssh
# After that: ssh USERNAME@awesome-vps from laptop
echo "[+] Pre-configuring Tailscale hostname..."
tailscale set --hostname=awesome-vps 2>/dev/null || true

# --------------------------------------------------
# Fail2ban
# --------------------------------------------------
echo "[+] Enabling fail2ban..."
systemctl enable --now fail2ban 2>/dev/null || true

# --------------------------------------------------
# Timezone
# --------------------------------------------------
echo "[+] Setting timezone to Asia/Jakarta..."
timedatectl set-timezone Asia/Jakarta 2>/dev/null || ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime

# --------------------------------------------------
# MOTD banner
# --------------------------------------------------
echo "[+] Creating MOTD banner..."
cat > /etc/update-motd.d/99-vps-bootstrap << 'MOTDEOF'
#!/bin/sh
echo "============================"
echo " VPS Bootstrap"
echo "============================"
echo " User:    awesome"
echo " SSH:     Tailscale SSH only (no public SSH)"
echo " Stacks:  /opt/stacks"
echo " Scripts: /opt/scripts"
echo "============================"
echo " Tailscale:"
echo "   tailscale up --ssh"
echo "   tailscale ip -4"
echo " Rescue: provider web console"
echo "============================"
MOTDEOF
chmod +x /etc/update-motd.d/99-vps-bootstrap

# --------------------------------------------------
# Health checks
# --------------------------------------------------
echo ""
echo "============================================"
echo "[+] Running health checks..."
echo "============================================"

HC_PASS=0
HC_FAIL=0
check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  ✅ ${label}"
    HC_PASS=$((HC_PASS + 1))
  else
    echo "  ❌ ${label}"
    HC_FAIL=$((HC_FAIL + 1))
  fi
}

check "Docker running"          systemctl is-active docker
check "SSH on port ${SSH_PORT}" ss -lntp | grep -q ":${SSH_PORT}"
check "UFW active"              ufw status | grep -q "Status: active"
check "User ${USERNAME}"        id "$USERNAME"
check "User in docker group"    groups "$USERNAME" | grep -q docker
check "User in sudo group"      groups "$USERNAME" | grep -q sudo
check "Zsh installed"           command -v zsh
check "Oh My Zsh installed"     [ -d "/home/${USERNAME}/.oh-my-zsh" ]
check "Tailscale installed"     command -v tailscale

# --------------------------------------------------
# Done
# --------------------------------------------------
echo ""
echo "============================================"
echo "[+] VPS bootstrap completed! ($(date))"
echo "============================================"
echo ""
echo "  ✅ Health: ${HC_PASS} passed, ${HC_FAIL} failed"
echo ""
echo "  NEXT STEPS (do this now):"
echo "  ─────────────────────────"
echo "  1. tailscale up --ssh"
echo "     -> Buka link login di browser, login akun Tailscale"
echo ""
echo "  2. Cek IP Tailscale:"
echo "     tailscale ip -4"
echo ""
echo "  3. Dari laptop, SSH via Tailscale (tanpa key/password):"
echo "     ssh awesome@awesome-vps"
echo ""
echo "  ⚠  SSH publik DIMATIKAN. Jika Tailscale bermasalah,"
echo "     rescue lewat web console provider (Command line / Console)."
echo ""
echo "  ─── Directories ───"
echo "     /opt/stacks   → Docker Compose services"
echo "     /opt/backups  → Backup files"
echo "     /opt/scripts  → Helper scripts"
echo ""
echo "  Log file: ${LOGFILE}"
echo "============================================"
