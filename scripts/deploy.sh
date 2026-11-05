#!/usr/bin/env bash
# deploy.sh — деплой статики сайта на ВМ (ПР6, задания 3–4)
#
# Минимальное число SSH-соединений: ControlMaster + один rsync.
# Права выставляются через rsync --chmod (и при необходимости один
# удалённый chmod через тот же multiplexed-канал).
#
# Использование:
#   export DEPLOY_HOST=192.168.56.101   # Host-only IP ВМ (зафиксировать свой)
#   export DEPLOY_USER=devops
#   export DEPLOY_PORT=2222
#   ./scripts/deploy.sh
#
# Опционально:
#   SITE_SRC=./site
#   REMOTE_DIR=/var/www/devops-site
#   CA_CERT=./certs/devops.crt          # для curl --cacert (или скопировать с ВМ)

set -euo pipefail

DEPLOY_HOST="${DEPLOY_HOST:?Укажите DEPLOY_HOST (Host-only IP ВМ)}"
DEPLOY_USER="${DEPLOY_USER:-devops}"
DEPLOY_PORT="${DEPLOY_PORT:-2222}"
SITE_SRC="${SITE_SRC:-$(cd "$(dirname "$0")/.." && pwd)/site}"
REMOTE_DIR="${REMOTE_DIR:-/var/www/devops-site}"
CA_CERT="${CA_CERT:-}"
PUBLIC_URL="${PUBLIC_URL:-https://${DEPLOY_HOST}}"

# --- SSH multiplexing: одно TCP-соединение на весь скрипт ---
CTRL_DIR="${HOME}/.ssh/cm"
mkdir -p "$CTRL_DIR"
CTRL_PATH="${CTRL_DIR}/%r@%h:%p"

SSH_OPTS=(
  -p "$DEPLOY_PORT"
  -o ControlMaster=auto
  -o ControlPath="$CTRL_PATH"
  -o ControlPersist=60
  -o StrictHostKeyChecking=accept-new
)

cleanup() {
  # Закрываем master-соединение, если ещё живо
  ssh -O exit "${SSH_OPTS[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Проверка SSH (${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PORT})"
ssh "${SSH_OPTS[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}" 'echo OK: $(hostname)'

echo "==> rsync статики ${SITE_SRC}/ → ${REMOTE_DIR}/"
# --chmod=D755,F644: каталоги 755, файлы 644 (закрывает world-writable)
# Владелец на сервере: devops:devops (rsync от пользователя devops)
rsync -avz --delete \
  -e "ssh ${SSH_OPTS[*]}" \
  --chmod=D755,F644 \
  "${SITE_SRC}/" \
  "${DEPLOY_USER}@${DEPLOY_HOST}:${REMOTE_DIR}/"

# Доп. страховка прав (один remote-вызов через тот же ControlMaster)
echo "==> Удалённый chmod/chown (один SSH)"
ssh "${SSH_OPTS[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}" \
  "find '${REMOTE_DIR}' -type d -exec chmod 755 {} +; \
   find '${REMOTE_DIR}' -type f -exec chmod 644 {} +; \
   # если каталог принадлежит root — нужен sudo; иначе no-op
   if [[ ! -w '${REMOTE_DIR}' ]]; then
     sudo chown -R devops:devops '${REMOTE_DIR}'
     sudo find '${REMOTE_DIR}' -type d -exec chmod 755 {} +
     sudo find '${REMOTE_DIR}' -type f -exec chmod 644 {} +
   fi"

echo "==> Проверки HTTP(S)"
CURL_OPTS=(-fsS --connect-timeout 5)
if [[ -n "$CA_CERT" && -f "$CA_CERT" ]]; then
  CURL_OPTS+=(--cacert "$CA_CERT")
else
  # Учебный self-signed: разрешаем insecure, но предупреждаем
  echo "    (CA_CERT не задан — curl -k для учебного сертификата)"
  CURL_OPTS+=(-k)
fi

# Главная
code=$(curl "${CURL_OPTS[@]}" -o /tmp/devops-deploy-index.html -w '%{http_code}' \
  "${PUBLIC_URL}/" || true)
echo "    GET /        → HTTP ${code}"
[[ "$code" == "200" ]] || { echo "FAIL: ожидался 200 на /"; exit 1; }

# 404
code=$(curl "${CURL_OPTS[@]}" -o /tmp/devops-deploy-404.html -w '%{http_code}' \
  "${PUBLIC_URL}/no-such-page-$$" || true)
echo "    GET /missing → HTTP ${code}"
[[ "$code" == "404" ]] || { echo "FAIL: ожидался 404 на отсутствующей странице"; exit 1; }

# Редирект HTTP→HTTPS (если доступен :80)
code=$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 \
  "http://${DEPLOY_HOST}/" || true)
echo "    GET http://  → HTTP ${code} (ожидается 301/302)"

echo "==> Деплой завершён успешно"
