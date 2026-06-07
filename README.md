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
| **System** | Update packages + install tools (curl, git, ufw, unattended-upgrades, dll) |
| **User** | Membuat user `awesome`, NOPASSWD sudo, docker group |
| **SSH** | `sshd` di-harden: **root login OFF, password login OFF**, hanya pubkey. SSH publik **tidak dibuka** |
| **Docker** | Install Docker Engine + Compose, log rotation 10MB, **default publish ke `127.0.0.1`** (tidak ada port bocor ke publik) |
| **Firewall** | UFW aktif: **80 & 443 publik**, SSH **hanya lewat interface `tailscale0`** |
| **Zsh** | Oh My Zsh + plugin autosuggestions & syntax-highlighting |
| **Tailscale** | Install + set hostname `awesome-vps` |
| **Security** | Unattended-upgrades untuk security patch otomatis (tanpa auto-reboot) |
| **Timezone** | Asia/Jakarta |
| **MOTD** | Banner info setelah login |

---

## Setelah Script Selesai

### 1. Login ke Tailscale

Script **otomatis** menjalankan `tailscale up --ssh --hostname=awesome-vps` di
akhir. Saat **link login muncul di output**, buka di browser dan otorisasi
mesin ini — script menunggu sampai login selesai.

Kalau tadi sempat di-skip (Ctrl-C), jalankan manual:

```bash
tailscale up --ssh --hostname=awesome-vps
```

### 2. Test koneksi dari laptop

```powershell
# Cukup ini — Tailscale SSH meng-auth via tailnet, tanpa password/key:
ssh awesome@awesome-vps
```

> **Tidak ada fallback public IP.** SSH publik sengaja ditutup. Kalau Tailscale
> bermasalah, gunakan **web console provider** (lihat bagian Rescue).

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
| `/opt/scripts` | Script tambahan |

### Struktur contoh

```
/opt/stacks/caddy
/opt/stacks/n8n
/opt/stacks/uptime-kuma
```

---

## Mengekspos Service (penting)

Docker dikonfigurasi dengan `"ip": "127.0.0.1"` di `daemon.json`, jadi
**publish port biasa otomatis hanya ke localhost** — tidak ada port yang bocor
ke internet meski Docker biasanya menembus UFW.

```yaml
# Default aman — hanya bisa diakses dari dalam VPS (localhost):
ports:
  - "8080:80"          # → 127.0.0.1:8080
```

Cara mengaksesnya:

| Tujuan | Cara |
|--------|------|
| **Web publik** (domain/HTTPS) | Reverse proxy via **Caddy** di port 80/443 → `localhost:8080` |
| **Akses pribadi via tailnet** | Publish eksplisit ke IP Tailscale: `"100.x.y.z:8080:80"`, lalu buka `http://100.x.y.z:8080` |
| **Akses pribadi (tanpa buka port)** | `tailscale serve 8080` — expose `localhost:8080` ke tailnet tanpa publish port sama sekali |

> Jangan pakai `"0.0.0.0:8080:80"` kecuali memang sengaja mau publik — itu
> menembus UFW dan membuka port ke internet.

---

## SSH Config Laptop (untuk akses lebih nyaman)

Edit `~/.ssh/config` (Windows: `%USERPROFILE%\.ssh\config`):

```sshconfig
Host awesome-vps
    HostName awesome-vps
    User awesome
    ServerAliveInterval 15
    ServerAliveCountMax 10
    TCPKeepAlive yes
    IPQoS none
```

Kemudian tinggal:

```powershell
ssh awesome-vps
```

> **Catatan:** `HostName awesome-vps` bisa dipakai karena Tailscale MagicDNS me-resolve hostname ke IP Tailscale-nya.

---

## Rescue (jika SSH/Tailscale bermasalah)

Akses **web console provider** (Spaceship: "Command line" / "Console") — ini
out-of-band, tidak terpengaruh konfigurasi SSH maupun firewall. Lalu:

```bash
# Cek Tailscale
tailscale status
systemctl restart tailscaled
tailscale up --ssh

# Cek sshd & firewall
systemctl status ssh --no-pager
ufw status verbose          # SSH harus muncul "ALLOW IN ... on tailscale0"
```

> **Jangan** menjalankan `ufw allow 22022/tcp` — itu akan membuka SSH ke
> internet publik dan membatalkan hardening. SSH cukup lewat `tailscale0`.

---

## Flow Ganti VPS Baru

Dapat VPS baru → lakukan ini:

```bash
# 1. 1 baris — semua beres (script otomatis 'tailscale up --ssh' di akhir)
bash <(curl -fsSL https://raw.githubusercontent.com/anjar-wilujeng/vps-bootstrap/main/go.sh)

# 2. Saat link login Tailscale muncul → buka di browser, otorisasi

# 3. Dari laptop — langsung masuk, IP tetap resolve
ssh awesome-vps
```

**VPS siap digunakan. 🎉**
