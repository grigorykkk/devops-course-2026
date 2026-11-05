# Настройка учебной ВМ DevOps Course 2026

Документ позволяет восстановить конфигурацию с снимка `01-clean-install` примерно за 10 минут.
Все команды — для Ubuntu Server 22.04/24.04. Подставьте свои значения вместо плейсхолдеров.

| Параметр | Учебное значение | Ваше |
|---|---|---|
| Hostname | `devops-vm` | |
| User (админ) | `devops` | |
| User (учёба) | `student` | |
| Host-only IP | `192.168.56.101` | **зафиксировать свой** |
| SSH port (после hardening) | `2222` | |
| Фамилия в приложении | `[Surname]` | |
| GitHub username | `[GitHubUsername]` | |

---

## 1. Виртуальная машина (VirtualBox)

Параметры ВМ:

- **CPU:** 2
- **RAM:** 2 GB
- **Disk:** 25 GB (динамический VDI)
- **Hostname:** `devops-vm`
- **Пользователи при установке:** `student` (опционально) и `devops` (основной, с sudo)

Сетевые адаптеры:

1. **Adapter1 — NAT**
   - Проброс портов (Port Forwarding):
     - до hardening: host `2222` → guest `22` (временно, чтобы не потерять доступ);
     - **после hardening:** host `2222` → guest `2222`.
2. **Adapter2 — Host-only Adapter**
   - Пример адреса ВМ: `192.168.56.101` (DHCP Host-only или статикой).
   - **Зафиксируйте свой IP** — он понадобится в `DEPLOY_HOST` и отчётах.

Проверка с хоста после установки:

```bash
ping -c 2 192.168.56.101
ssh -p 22 devops@192.168.56.101    # до hardening
```

---

## 2. Первичная настройка ОС

```bash
sudo hostnamectl set-hostname devops-vm
sudo apt update && sudo apt -y upgrade
sudo apt -y install curl ca-certificates gnupg lsb-release ufw openssh-server \
  nginx openssl rsync net-tools iproute2
```

Создать пользователя `devops` (если ещё нет) и дать sudo:

```bash
sudo adduser devops
sudo usermod -aG sudo devops
```

Добавить свой SSH-ключ:

```bash
# на хосте
ssh-copy-id -p 22 devops@192.168.56.101
```

---

## 3. Hardening SSH (ПР5)

Файл: `/etc/ssh/sshd_config.d/99-hardening.conf`  
(готовая копия в репозитории: `configs/ssh/99-hardening.conf`)

```bash
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'EOF'
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
AllowUsers devops
X11Forwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

# Проверка синтаксиса и применение
sudo sshd -t
sudo systemctl reload ssh
# либо: sudo systemctl restart ssh
```

**Важно:** до `reload` обновите Port Forwarding в VirtualBox: host `2222` → guest `2222`.
Не закрывайте текущую сессию, пока не проверите новую:

```bash
# с хоста, в новом терминале
ssh -p 2222 devops@192.168.56.101
sudo sshd -T | egrep '^(port|maxauthtries|permitrootlogin|passwordauthentication) '
```

Ожидаемо: `port 2222`, `maxauthtries 3`, `permitrootlogin no`, `passwordauthentication no`.

---

## 4. UFW (ПР5)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limit'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw --force enable
sudo ufw status verbose
```

В выводе должно быть: `Default: deny (incoming), allow (outgoing)`.

---

## 5. Снимки (snapshots)

Делайте снимок **после** каждого стабильного этапа:

| № | Имя | Когда |
|---|---|---|
| 01 | `01-clean-install` | Чистая ОС, сеть, пользователь `devops`, SSH-ключ |
| 02 | `02-ssh-hardening` | Порт 2222, MaxAuthTries 3, без пароля/root |
| 03 | `03-ufw` | UFW active, deny incoming, 2222/80/443 |
| 04 | `04-nginx-tls` | nginx + self-signed cert + сайт |
| 05 | `05-docker-compose` | Docker, `~/app`, compose up, healthcheck ok |

Восстановление «с нуля» ≈ 10 минут: откат на `01-clean-install` и прогон разделов 2–9 по этому документу.

---

## 6. DNS / hosts (по необходимости, ПР5)

Если в методичке нужен учебный hostname:

```bash
echo '192.168.56.101 devops.local' | sudo tee -a /etc/hosts
# на хосте (macOS/Linux):
# echo '192.168.56.101 devops.local' | sudo tee -a /etc/hosts
```

---

## 7. Проверка аудита после ПР5

Скопируйте `scripts/audit.sh` на ВМ и выполните (разделы [1]–[3] должны PASS; [4]–[5] пока FAIL — это нормально):

```bash
chmod +x ~/audit.sh
~/audit.sh; echo exit:$?
```

---

## 8. Веб-сервер: nginx + TLS (ПР6)

### 8.1. Каталог сайта

```bash
sudo mkdir -p /var/www/devops-site
sudo chown -R devops:devops /var/www/devops-site
sudo chmod 755 /var/www/devops-site
```

Задеплоить статику с хоста (см. `scripts/deploy.sh`) или вручную:

```bash
# с хоста
rsync -avz -e 'ssh -p 2222' --chmod=D755,F644 \
  ./site/ devops@192.168.56.101:/var/www/devops-site/
```

### 8.2. Самоподписанный сертификат с SAN

```bash
# Ключ — только root/ssl-cert, права 600
sudo openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/C=RU/ST=Moscow/L=Moscow/O=DevOpsCourse/OU=PR6/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local,DNS:localhost,IP:127.0.0.1,IP:192.168.56.101"

sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
sudo chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt

# Проверка срока (≥30 дней для audit.sh)
sudo openssl x509 -in /etc/ssl/certs/devops.crt -checkend 2592000 -noout && echo OK
```

> Замените `IP:192.168.56.101` на **свой** Host-only адрес.

### 8.3. Конфиг сайта

Скопируйте `configs/nginx/devops-site` → `/etc/nginx/sites-available/devops-site`:

```bash
sudo cp ~/devops-site /etc/nginx/sites-available/devops-site
# либо: sudo nano /etc/nginx/sites-available/devops-site
# содержимое — см. configs/nginx/devops-site в репозитории

sudo ln -sf /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl enable --now nginx
```

Проверки:

```bash
systemctl is-active nginx          # active
curl -k -I https://192.168.56.101/
curl -k -I https://192.168.56.101/no-such-page   # 404
# нет world-writable:
sudo find /var/www/devops-site -perm -o+w
```

Снимок: `04-nginx-tls`.

---

## 9. Docker + Compose приложение (ПР7)

### 9.1. Установка Docker из официального репозитория

```bash
sudo apt -y install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt update
sudo apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

# Группа docker — чтобы не писать sudo
sudo usermod -aG docker devops
# перелогиньтесь (или: newgrp docker)
docker version
```

### 9.2. Приложение в `~/app`

```bash
mkdir -p ~/app
# скопируйте из репозитория: app.py, requirements.txt, Dockerfile,
# .dockerignore, docker-compose.yml, .env.example
cd ~/app
cp .env.example .env
nano .env          # SURNAME, пароли БД
chmod 600 .env

docker compose up -d --build
docker compose ps
docker compose -f ~/app/docker-compose.yml ps -q db
docker inspect --format '{{.State.Health.Status}}' $(docker compose ps -q db)
```

Ожидаемо:

- `app` слушает **только** `127.0.0.1:5000` (`ss -tln | grep 5000`);
- `5432` **не** опубликован на хосте (или только loopback, если явно добавите);
- `nginx` проксирует `https://…/app/` → `http://127.0.0.1:5000/`.

Проверки:

```bash
curl -s http://127.0.0.1:5000/
curl -k https://192.168.56.101/app/
ss -tln | egrep ':(5000|5432)\s'
ls -l ~/app/.env    # -rw------- (600)
```

Снимок: `05-docker-compose`.

### 9.3. Полный аудит

```bash
~/audit.sh; echo exit:$?
# ожидается exit 0 и все PASS по разделам [1]–[5]
```

---

## Быстрый чеклист восстановления (≈10 мин)

1. Откат на `01-clean-install`, сеть NAT+Host-only, IP зафиксирован.
2. Раздел 2 — пакеты, ключ SSH.
3. Раздел 3 — `99-hardening.conf`, PF host:2222→guest:2222.
4. Раздел 4 — UFW.
5. Раздел 8 — сайт, cert+SAN, nginx.
6. Раздел 9 — Docker, `~/app`, compose up, `.env` 600.
7. `./scripts/audit.sh` → exit 0.

---

## Связанные файлы репозитория

| Путь | Назначение |
|---|---|
| `scripts/audit.sh` | Сводный аудит ПР5–7 |
| `scripts/deploy.sh` | Деплой статики (rsync + curl) |
| `site/` | `index.html`, `404.html` |
| `app/` | Flask + Compose (ПР7) |
| `configs/ssh/99-hardening.conf` | Drop-in sshd |
| `configs/nginx/devops-site` | Vhost HTTP→HTTPS + `/app/` |
| `configs/kr2/` | Шаблоны к контрольной №2 |
