#!/usr/bin/env bash
# audit.sh — сводный аудит для практических работ DevOps №5–7
# (методички Гиматдинова Д.М., ИПТИП)
#
# Разделы:
#   [1]–[3]  — ПР5: SSH / UFW / базовая безопасность
#   [4]      — ПР6: веб-сервер (nginx, TLS, права)
#   [5]      — ПР7: контейнеризация (Docker Compose)
#
# Запуск на ВМ:  ./scripts/audit.sh
# Код выхода: 0 — все проверки PASS, 1 — есть FAIL

set -uo pipefail

PASS=0
FAIL=0

# Универсальная проверка: check "описание" <команда...>
# Команда считается успешной при exit code 0.
check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "[PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "========================================"
echo " DevOps audit (ПР5 + ПР6 + ПР7)"
echo " $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "========================================"
echo

# ---------------------------------------------------------------------------
# [1] SSH hardening (ПР5)
# ---------------------------------------------------------------------------
echo "=== [1] SSH ==="

# Порт SSH должен быть не 22 (после hardening — 2222)
check "sshd Port != 22" \
  bash -c 'port=$(sudo sshd -T 2>/dev/null | awk "/^port /{print \$2; exit}"); [[ -n "$port" && "$port" != "22" ]]'

# MaxAuthTries == 3
check "sshd MaxAuthTries == 3" \
  bash -c 'tries=$(sudo sshd -T 2>/dev/null | awk "/^maxauthtries /{print \$2; exit}"); [[ "$tries" == "3" ]]'

# PermitRootLogin no (доп. проверка из типичного hardening)
check "sshd PermitRootLogin no" \
  bash -c 'v=$(sudo sshd -T 2>/dev/null | awk "/^permitrootlogin /{print \$2; exit}"); [[ "$v" == "no" ]]'

# PasswordAuthentication no
check "sshd PasswordAuthentication no" \
  bash -c 'v=$(sudo sshd -T 2>/dev/null | awk "/^passwordauthentication /{print \$2; exit}"); [[ "$v" == "no" ]]'

echo

# ---------------------------------------------------------------------------
# [2] UFW (ПР5)
# ---------------------------------------------------------------------------
echo "=== [2] UFW ==="

# Default incoming deny
check "UFW default incoming deny" \
  bash -c 'sudo ufw status verbose 2>/dev/null | grep -qiE "Default: deny \(incoming\)|deny \(incoming\)"'

# UFW активен
check "UFW status active" \
  bash -c 'sudo ufw status 2>/dev/null | grep -qi "Status: active"'

echo

# ---------------------------------------------------------------------------
# [3] Базовые пользователи / sudo (ПР5, вспомогательно)
# ---------------------------------------------------------------------------
echo "=== [3] Пользователи ==="

check "пользователь devops существует" \
  id devops

check "devops в группе sudo" \
  bash -c 'id -nG devops | grep -qw sudo'

echo

# ---------------------------------------------------------------------------
# [4] Веб-сервер (ПР6)
# ---------------------------------------------------------------------------
echo "=== [4] Веб-сервер (nginx / TLS) ==="

check "nginx is-active" \
  bash -c '[[ "$(systemctl is-active nginx 2>/dev/null)" == "active" ]]'

check "nginx -t успешен" \
  sudo nginx -t

# Сертификат не истекает в ближайшие 30 дней (2592000 сек)
check "сертификат /etc/ssl/certs/devops.crt действует ещё ≥30 дней" \
  sudo openssl x509 -in /etc/ssl/certs/devops.crt -checkend 2592000 -noout

# Нет world-writable файлов в каталоге сайта
check "нет файлов с -perm -o+w в /var/www/devops-site" \
  bash -c '! sudo find /var/www/devops-site -perm -o+w -type f 2>/dev/null | grep -q .'

# Ключ только для владельца
check "права ключа /etc/ssl/private/devops.key == 600" \
  bash -c '[[ "$(sudo stat -c %a /etc/ssl/private/devops.key 2>/dev/null)" == "600" ]]'

echo

# ---------------------------------------------------------------------------
# [5] Контейнеризация (ПР7)
# ---------------------------------------------------------------------------
echo "=== [5] Контейнеризация (Docker) ==="

check "docker is-active" \
  bash -c '[[ "$(systemctl is-active docker 2>/dev/null)" == "active" ]]'

# Health СУБД: сначала пробуем compose ps -q db, иначе имена app-db-1 / app_db_1
check "healthcheck СУБД (db) = healthy" \
  bash -c '
    cid=""
    if [[ -f "$HOME/app/docker-compose.yml" ]]; then
      cid=$(docker compose -f "$HOME/app/docker-compose.yml" ps -q db 2>/dev/null || true)
    fi
    if [[ -z "$cid" ]]; then
      for name in app-db-1 app_db_1 db; do
        cid=$(docker ps -qf "name=^${name}$" 2>/dev/null || true)
        [[ -n "$cid" ]] && break
        cid=$(docker ps -qf "name=${name}" 2>/dev/null | head -1 || true)
        [[ -n "$cid" ]] && break
      done
    fi
    [[ -n "$cid" ]] || exit 1
    status=$(docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" "$cid" 2>/dev/null)
    [[ "$status" == "healthy" || "$status" == "running" ]]
  '

# Порты 5000 и 5432 слушаются только на 127.0.0.1 (или не слушаются вовсе)
check "порт 5000 не слушается вне 127.0.0.1" \
  bash -c '
    # строки вида *:5000, 0.0.0.0:5000, [::]:5000 — плохо; 127.0.0.1:5000 — ок
    bad=$(ss -tln 2>/dev/null | awk '\''/:(5000)\s/ {
      if ($4 !~ /^127\.0\.0\.1:5000$/ && $4 !~ /^\[::1\]:5000$/) print $4
    }'\'')
    [[ -z "$bad" ]]
  '

check "порт 5432 не слушается вне 127.0.0.1" \
  bash -c '
    bad=$(ss -tln 2>/dev/null | awk '\''/:(5432)\s/ {
      if ($4 !~ /^127\.0\.0\.1:5432$/ && $4 !~ /^\[::1\]:5432$/) print $4
    }'\'')
    [[ -z "$bad" ]]
  '

check "права ~/app/.env == 600" \
  bash -c '[[ -f "$HOME/app/.env" && "$(stat -c %a "$HOME/app/.env")" == "600" ]]'

echo
echo "========================================"
echo " Итого: PASS=$PASS  FAIL=$FAIL"
echo "========================================"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
