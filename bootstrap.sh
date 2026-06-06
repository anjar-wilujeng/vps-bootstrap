#!/usr/bin/env bash
set -euo pipefail

USERNAME="awesome"
SSH_PORT="22022"
STACK_DIR="/opt/stacks"
BACKUP_DIR="/opt/backups"
SCRIPT_DIR="/opt/scripts"

echo "[+] Starting VPS bootstrap..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[!] Please run this script as root."
  exit 1
fi

echo "[+] Updating package index..."
apt update

echo "[+] Installing base packages..."
apt install -y \
  sudo curl git tmux ufw fail2ban ca-certificates gnupg lsb-release \
  unzip zip htop nano vim jq tree net-tools software-properties-common \
  zsh

echo "[+] Creating user: ${USERNAME}"
if ! id "$USERNAME" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$USERNAME"
  echo "[!] User ${USERNAME} created without password."
  echo "[!] Set password manually later with: passwd ${USERNAME}"
else
  echo "[=] User ${USERNAME} already exists."
fi

echo "[+] Adding ${USERNAME} to sudo and users group..."
usermod -aG sudo,users "$USERNAME"

echo "[+] Copying root SSH authorized_keys to ${USERNAME}, if available..."
mkdir -p "/home/${USERNAME}/.ssh"

if [ -f /root/.ssh/authorized_keys ] && [ -s /root/.ssh/authorized_keys ]; then
  cp /root/.ssh/authorized_keys "/home/${USERNAME}/.ssh/authorized_keys"
  echo "[+] SSH key copied from root."
else
  touch "/home/${USERNAME}/.ssh/authorized_keys"
  echo "[!] /root/.ssh/authorized_keys is empty or missing."
  echo "[!] You may need to manually add your public key to /home/${USERNAME}/.ssh/authorized_keys"
fi

chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.ssh"
chmod 700 "/home/${USERNAME}/.ssh"
chmod 600 "/home/${USERNAME}/.ssh/authorized_keys"

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

echo "[+] Creating working directories..."
mkdir -p "$STACK_DIR" "$BACKUP_DIR" "$SCRIPT_DIR"
chown -R "${USERNAME}:${USERNAME}" "$STACK_DIR" "$BACKUP_DIR" "$SCRIPT_DIR"

echo "[+] Configuring SSH keepalive..."
cat > /etc/ssh/sshd_config.d/99-custom-keepalive.conf << EOF
ClientAliveInterval 30
ClientAliveCountMax 10
TCPKeepAlive yes
UseDNS no
LoginGraceTime 60
MaxAuthTries 6
EOF

echo "[+] Checking SSH config..."
sshd -t

echo "[+] Reloading SSH service..."
systemctl reload ssh || systemctl reload sshd

echo "[+] Configuring UFW firewall..."
ufw allow "${SSH_PORT}/tcp"
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
ufw reload

echo "[+] Installing Oh My Zsh for ${USERNAME}..."
if [ ! -d "/home/${USERNAME}/.oh-my-zsh" ]; then
  sudo -u "$USERNAME" sh -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
else
  echo "[=] Oh My Zsh already installed."
fi

echo "[+] Installing Zsh plugins..."
ZSH_CUSTOM="/home/${USERNAME}/.oh-my-zsh/custom"

if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
  sudo -u "$USERNAME" git clone https://github.com/zsh-users/zsh-autosuggestions.git "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
else
  echo "[=] zsh-autosuggestions already installed."
fi

if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
  sudo -u "$USERNAME" git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
else
  echo "[=] zsh-syntax-highlighting already installed."
fi

echo "[+] Writing .zshrc..."
cat > "/home/${USERNAME}/.zshrc" << 'EOF'
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
EOF

chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.zshrc"

echo "[+] Changing default shell to zsh for ${USERNAME}..."
chsh -s "$(command -v zsh)" "$USERNAME"

echo "[+] Installing Tailscale..."
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
else
  echo "[=] Tailscale already installed."
fi

systemctl enable --now tailscaled

echo "[+] Configuring fail2ban basic status..."
systemctl enable --now fail2ban || true

echo "[+] Creating helper info file..."
cat > "${SCRIPT_DIR}/README-FIRST.txt" << EOF
VPS bootstrap completed.

Default user:
  ${USERNAME}

SSH public access:
  ssh ${USERNAME}@YOUR_PUBLIC_IP -p ${SSH_PORT}

Recommended access:
  Use Tailscale, then:
  ssh ${USERNAME}@TAILSCALE_IP -p ${SSH_PORT}

Working directories:
  ${STACK_DIR}
  ${BACKUP_DIR}
  ${SCRIPT_DIR}

Useful commands:
  docker ps
  docker compose up -d
  tmux new -s work
  tmux attach -t work

Next manual step:
  Run: tailscale up
EOF

chown -R "${USERNAME}:${USERNAME}" "$SCRIPT_DIR"

echo ""
echo "============================================================"
echo "[+] VPS bootstrap completed."
echo "============================================================"
echo ""
echo "User created:"
echo "  ${USERNAME}"
echo ""
echo "SSH command:"
echo "  ssh ${USERNAME}@YOUR_PUBLIC_IP -p ${SSH_PORT}"
echo ""
echo "Recommended next step:"
echo "  tailscale up"
echo ""
echo "After Tailscale login, check IP:"
echo "  tailscale ip -4"
echo ""
echo "Then login from Windows:"
echo "  ssh ${USERNAME}@TAILSCALE_IP -p ${SSH_PORT}"
echo ""
echo "Working directory:"
echo "  ${STACK_DIR}"
echo ""
echo "Important:"
echo "  If docker command fails for ${USERNAME}, logout and login again."
echo "============================================================"
