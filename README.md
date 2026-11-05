# devops-course-2026

Локальный каркас практических работ DevOps **№5–7** (методички Гиматдинова Д.М., ИПТИП) и заготовки к **КР2**.

## Что подставить

| Плейсхолдер | Куда | Пример |
|---|---|---|
| `[Surname]` | `site/*.html`, `app/.env`, отчёты | `Ivanov` |
| Host-only IP | `DEPLOY_HOST`, SAN сертификата, `docs/server-setup.md` | `192.168.56.101` (**свой**) |
| `[GitHubUsername]` | remote origin, ссылки в отчётах | `grigory-…` |
| Пароли БД / Redis | `app/.env`, `configs/kr2/.env` | не коммитить |

## Структура

```
scripts/audit.sh      # аудит ПР5 + веб ПР6 + docker ПР7
scripts/deploy.sh     # деплой статики (rsync, ControlMaster, curl)
docs/server-setup.md  # разделы 1–9, восстановление с 01-clean-install
site/                 # index.html + 404.html
app/                  # Flask + Dockerfile + compose (postgres:16-alpine)
configs/ssh/          # 99-hardening.conf
configs/nginx/        # devops-site (HTTP→HTTPS + /app/)
configs/kr2/          # шаблоны к контрольной №2
```

## Быстрый старт

1. Прочитайте `docs/server-setup.md` и поднимите ВМ по разделам 1–4.
2. Скопируйте `scripts/audit.sh` на ВМ, сделайте исполняемым, гоняйте после каждого этапа.
3. Деплой сайта с хоста:

```bash
export DEPLOY_HOST=192.168.56.101   # свой Host-only IP
export DEPLOY_USER=devops
export DEPLOY_PORT=2222
# опционально: export CA_CERT=/path/to/devops.crt
./scripts/deploy.sh
```

4. ПР7 — на ВМ:

```bash
mkdir -p ~/app && cd ~/app
# скопируйте файлы из app/
cp .env.example .env && chmod 600 .env
# отредактируйте SURNAME и пароли
docker compose up -d --build
```

5. Реальный `.env` **не коммитится** (см. `.gitignore`). Только `.env.example`.

## Коммит

Репозиторий инициализирован локально. Когда будете готовы выложить на GitHub:

```bash
git remote add origin git@github.com:[GitHubUsername]/devops-course-2026.git
git push -u origin main
```
