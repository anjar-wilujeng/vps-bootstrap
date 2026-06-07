# VPS Bootstrap

Setup VPS disposable dari kondisi **fresh install** cukup **1 baris perintah**.

## Cara Pakai

### 🚀 1-Line Install (Recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/anjar-wilujeng/vps-bootstrap/main/go.sh)
```

> **Jalankan di dalam `tmux`** agar tidak terputus jika koneksi SSH drop:
> ```bash
> # Sebelum curl, jalankan tmux dulu:
> tmux new -s setup
> ```
> Jika koneksi putus, login ulang lalu `tmux attach -t setup`.

### Manual Install

Kalau mau step-by-step (tanpa `go.sh`):

```bash
apt update
apt install -y git curl tmux

tmux new -s setup

git clone https://github.com/anjar-wilujeng/vps-bootstrap.git
cd vps-bootstrap
chmod +x bootstrap.sh
./bootstrap.sh
```

---

## Yang Dilakukan Script

| Step | Detail |
|------|--------|
| **System** | Update packages + install tools (curl, git, ufw, fail2ban, unattended-upgrades, dll) |
| **User** | Membuat user `awesome`, set password random, sudo + docker group |
| **SSH** | Port diubah ke `22022`, konfigurasi keepalive |
| **Docker** | Install Docker Engine + Compose, log rotation 10MB |
| **Firewall** | UFW aktif: port 22022, 80, 443 |
| **Zsh** | Oh My Zsh + plugin autosuggestions & syntax-highlighting |
| **Tailscale** | Install + set hostname `awesome-vps` |
| **Security** | Unattended-upgrades untuk security patch otomatis |
| **Timezone** | Asia/Jakarta |
| **MOTD** | Banner info setelah login |

---

## Setelah Script Selesai

### 1. Login ke Tailscale

```bash
tailscale up --ssh
```

Buka link yang muncul di browser, login akun Tailscale kamu.

### 2. Test koneksi dari laptop

```powershell
# Cukup ini — Tailscale resolve otomatis:
ssh awesome@awesome-vps
```

Atau via public IP (fallback):

```powershell
ssh awesome@PUBLIC_IP -p 22022
```

### 3. Verifikasi

```bash
whoami           # → awesome
groups           # → sudo, docker
docker ps        # → tidak error permission
zsh --version    # → terinstall
```

> **Catatan:** Jika `docker ps` masih permission denied, logout lalu login ulang.

---

## Direktori

| Path | Fungsi |
|------|--------|
| `/opt/stacks` | Tempat semua Docker Compose service |
| `/opt/backups` | Backup sementara |
| `/opt/scripts` | Script tambahan + `.credentials.txt` |

### Struktur contoh

```
/opt/stacks/caddy
/opt/stacks/n8n
/opt/stacks/uptime-kuma
```

---

## SSH Config Laptop (untuk akses lebih nyaman)

Edit `~/.ssh/config` (Windows: `%USERPROFILE%\.ssh\config`):

```sshconfig
Host awesome-vps
    HostName awesome-vps
    User awesome
    Port 22022
    ServerAliveInterval 15
    ServerAliveCountMax 10
    TCPKeepAlive yes
```

Kemudian tinggal:

```powershell
ssh awesome-vps
```

> **Catatan:** `HostName awesome-vps` bisa dipakai karena Tailscale MagicDNS me-resolve hostname ke IP Tailscale-nya.

---

## Rescue (jika SSH bermasalah)

Gunakan web console VPS:

```bash
# Cek SSH
systemctl status ssh --no-pager
ss -lntp | grep 22022

# Cek firewall
ufw status verbose
ufw allow 22022/tcp
ufw reload

# Cek fail2ban
fail2ban-client status sshd
fail2ban-client unban --all
```

---

## Flow Ganti VPS Baru

Dapat VPS baru → lakukan ini:

```bash
# 1. 1 baris — semua beres
bash <(curl -fsSL https://raw.githubusercontent.com/anjar-wilujeng/vps-bootstrap/main/go.sh)

# 2. Login Tailscale
tailscale up --ssh

# 3. Dari laptop — langsung masuk, IP tetap resolve
ssh awesome@awesome-vps
```

**VPS siap digunakan. 🎉**
