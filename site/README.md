# Сайт CodeLab

Статический сайт проекта CodeLab, построенный на фреймворке [Astro](https://astro.build) с полнотекстовым поиском [Pagefind](https://pagefind.app).

## Требования

* **Node.js:** `26.13.1` (версия зафиксирована в `.nvmrc` и `package.json`)
* **Docker** с поддержкой `buildx` (для сборки и публикации образа)

## Локальная разработка

1. Перейдите в директорию сайта и установите зависимости:
   ```bash
   cd site
   npm ci
   ```

2. Запустите сервер для разработки:
   ```bash
   npm run dev
   ```
   Сайт будет доступен по адресу `http://localhost:4321`.

## Сборка статики (`dist/`)

При сборке сайт подтягивает документацию и ассеты из родительских директорий репозитория (`../docs`, `../apps`, `../packages`), а также формирует ссылки на GitHub. Для корректной сборки передайте переменную `SITE_URL` (и при необходимости `SITE_GITHUB_REF`):

```bash
SITE_URL=https://openidealab.com npm run build
```

В результате в папке `site/dist/` будут сгенерированы статические HTML/CSS/JS файлы и поисковый индекс Pagefind.

## Сборка и публикация Docker-образа

`Dockerfile` упаковывает уже собранную на хосте папку `dist/` вместе с конфигурацией `nginx.conf` в легковесный образ `nginx:1.28.0-alpine`.

### 1. Соберите статику на хосте
Перед каждой сборкой образа обязательно обновите `dist/`:
```bash
SITE_URL=https://openidealab.com npm run build
```

### 2. Соберите и отправьте образ в реестр (Harbor)
Убедитесь, что вы авторизованы в реестре (`docker login ://example.com`), и выполните команду из папки `site/`:

```bash
docker buildx build \
  --platform linux/amd64 \
  -t ://example.com/codelab/website:0.2.0-landing \
  -t ://example.com/codelab/website:latest \
  --push \
  .
```

### 3. Локальная проверка образа
Чтобы проверить собранный контейнер локально перед публикацией:

```bash
docker buildx build --load -t codelab-website:local .
docker run --rm -p 8080:80 codelab-website:local
```
После запуска откройте `http://localhost:8080` в браузере.

## Структура файлов для Docker

* **`Dockerfile`** — копирует `nginx.conf` и готовую директорию `dist/` в образ Nginx.
* **`nginx.conf`** — настраивает маршрутизацию с учётом `trailingSlash: 'always'`, страницу `404.html`, gzip-сжатие и долгосрочное кэширование для `/_astro/`.
* **`.dockerignore`** — ограничивает контекст сборки только файлами `Dockerfile`, `nginx.conf` и директорией `dist/`.
