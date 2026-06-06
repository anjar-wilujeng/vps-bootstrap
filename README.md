# VPS Bootstrap

Repository ini berisi script bootstrap untuk menyiapkan VPS disposable/trial dari kondisi fresh install.

Default setup:

* User Linux: `awesome`
* SSH Port: `22022`
* Working directory: `/opt/stacks`
* Backup directory: `/opt/backups`
* Script directory: `/opt/scripts`
* Docker + Docker Compose
* UFW firewall
* Fail2ban
* Zsh + Oh My Zsh
* Tailscale

---

## 1. Cara Menjalankan dari VPS Baru

Login ke VPS sebagai `root`, lalu jalankan:

```bash
apt update
apt install -y git curl tmux

git clone https://github.com/anjar-wilujeng/vps-bootstrap.git
cd vps-bootstrap

chmod +x bootstrap.sh
./bootstrap.sh
```

Disarankan menjalankan script di dalam `tmux`:

```bash
tmux new -s setup
```

Jika koneksi SSH putus, login ulang lalu attach lagi:

```bash
tmux attach -t setup
```

---

## 2. Setelah Script Selesai

Setelah `bootstrap.sh` selesai, jalankan Tailscale:

```bash
tailscale up
```

Buka link login yang muncul di browser, lalu cek IP Tailscale VPS:

```bash
tailscale ip -4
```

Contoh output:

```text
100.xx.xx.xx
```

Login dari laptop/Windows menggunakan user `awesome`:

```powershell
ssh awesome@100.xx.xx.xx -p 22022
```

Jika masih ingin menggunakan public IP VPS:

```powershell
ssh awesome@PUBLIC_IP_VPS -p 22022
```

Namun akses via Tailscale lebih disarankan karena biasanya lebih stabil.

---

## 3. Verifikasi Setelah Login sebagai `awesome`

Setelah berhasil login sebagai user `awesome`, cek:

```bash
whoami
groups
docker ps
zsh --version
```

Expected:

```text
whoami  -> awesome
groups  -> ada sudo dan docker
docker ps -> tidak permission denied
```

Jika `docker ps` masih permission denied, logout lalu login ulang:

```bash
exit
```

Kemudian SSH lagi sebagai `awesome`.

---

## 4. Struktur Direktori

Script akan membuat direktori berikut:

```text
/opt/stacks
/opt/backups
/opt/scripts
```

Fungsinya:

```text
/opt/stacks   -> tempat semua Docker Compose service
/opt/backups  -> tempat backup sementara
/opt/scripts  -> tempat script tambahan
```

Contoh struktur service:

```text
/opt/stacks/caddy
/opt/stacks/n8n
/opt/stacks/uptime-kuma
/opt/stacks/defectdojo
```

---

## 5. Test Docker Compose

Login sebagai `awesome`, lalu jalankan:

```bash
cd /opt/stacks
mkdir hello
cd hello
nano docker-compose.yml
```

Isi file:

```yaml
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
    restart: unless-stopped
```

Jalankan:

```bash
docker compose up -d
docker ps
curl http://127.0.0.1:8080
```

Jika muncul halaman `Welcome to nginx!`, berarti Docker Compose sudah berjalan normal.

Untuk menghapus test stack:

```bash
cd /opt/stacks/hello
docker compose down
cd ..
rm -rf hello
```

---

## 6. Command Harian

Masuk ke folder stack:

```bash
cd /opt/stacks
```

Atau gunakan alias:

```bash
stacks
```

Menjalankan service Docker Compose:

```bash
docker compose up -d
```

Melihat container aktif:

```bash
docker ps
```

Melihat log service:

```bash
docker compose logs -f
```

Mematikan service:

```bash
docker compose down
```

---

## 7. SSH Keepalive dari Windows

Jika koneksi SSH sering putus, buat file config di Windows:

```powershell
notepad $env:USERPROFILE\.ssh\config
```

Isi:

```sshconfig
Host awesome-vps
    HostName TAILSCALE_IP
    User awesome
    Port 22022
    ServerAliveInterval 15
    ServerAliveCountMax 10
    TCPKeepAlive yes
    IPQoS none
```

Lalu login cukup dengan:

```powershell
ssh awesome-vps
```

---

## 8. Rescue via Web Console

Jika SSH public atau Tailscale bermasalah, gunakan web console dari provider VPS.

Cek SSH service:

```bash
systemctl status ssh --no-pager
ss -lntp | grep ssh
```

Cek firewall:

```bash
ufw status verbose
```

Pastikan port `22022` terbuka:

```bash
ufw allow 22022/tcp
ufw reload
```

Cek log SSH:

```bash
journalctl -u ssh --since "30 minutes ago" --no-pager | tail -100
```

Cek fail2ban:

```bash
fail2ban-client status
fail2ban-client status sshd
```

Unban semua IP jika perlu:

```bash
fail2ban-client unban --all
```

---

## 9. Catatan Keamanan

Jangan commit file berikut ke repository:

```text
.env
private key
API key
password
database dump
backup asli
token Tailscale
credential production
```

Gunakan `.env.example` untuk contoh konfigurasi.

Contoh:

```text
APP_PORT=8080
APP_DOMAIN=example.com
DATABASE_USER=changeme
DATABASE_PASSWORD=changeme
```

---

## 10. Flow VPS Baru

Ringkasan flow saat mendapat VPS trial baru:

```bash
ssh root@PUBLIC_IP -p PORT_PROVIDER

apt update
apt install -y git curl tmux

tmux new -s setup

git clone https://github.com/anjar-wilujeng/vps-bootstrap.git
cd vps-bootstrap

chmod +x bootstrap.sh
./bootstrap.sh

tailscale up
tailscale ip -4
```

Lalu dari Windows:

```powershell
ssh awesome@TAILSCALE_IP -p 22022
```

Setelah masuk:

```bash
whoami
docker ps
cd /opt/stacks
```

## Recommended SSH Access

Gunakan Tailscale sebagai jalur SSH utama karena lebih stabil dibanding public IP provider.

```powershell
ssh awesome@TAILSCALE_IP -p 22022

VPS siap digunakan.
