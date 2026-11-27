# Сборка и деплой Flutter-приложения для Web

Документация описывает настройку проекта, передачу переменных окружения, команды Melos, локальное тестирование и конфигурацию веб-серверов для публикации Flutter Web-приложения.

---

## 1. Подготовка кодовой базы для Web

Перед первой сборкой убедитесь, что в коде нет необработанных вызовов `dart:io`, которые в браузере вызывают ошибку `UnsupportedError`:

* **`Platform.environment` и файловая система (`File`, `Directory`):**
  В браузере недоступны. Используйте проверку `kIsWeb` из `package:flutter/foundation.dart`:
  ```dart
  import 'package:flutter/foundation.dart' show kIsWeb;

  if (!kIsWeb) {
    // Логика чтения локального .env файла через path_provider и dart:io
  }
  ```
* **Переменные окружения в Web:**
  Передаются только на этапе компиляции через `--dart-define-from-file=.env` и читаются в коде через `const String.fromEnvironment('KEY')`.
* **Иконки и манифест PWA:**
  Проверьте файлы в папке `apps/codelab_desktop/web/`:
  * `index.html` — заголовок `<title>CodeLab</title>`, мета-теги и favicon.
  * `manifest.json` — имя приложения (`name`, `short_name`), цвета темы (`theme_color`, `background_color`) и иконки для установки как PWA.
  * `icons/` — `Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`, `Icon-maskable-512.png`.

---

## 2. Скрипты сборки в Melos

Добавьте задачи сборки в корневой `pubspec.yaml` вашего монорепозитория:

```yaml
melos:
  scripts:
    build:web:
      description: Сборка Web release приложения
      run: >
        melos exec --scope="codelab_desktop" --
        flutter build web --release --dart-define-from-file=.env

    build:web:wasm:
      description: Сборка Web release с компиляцией в WebAssembly (WasmGC)
      run: >
        melos exec --scope="codelab_desktop" --
        flutter build web --release --wasm --dart-define-from-file=.env
```

### Полезные флаги `flutter build web`
* `--base-href=/app/` — обязателен, если приложение размещается не в корне домена (`https://example.com`), а в поддиректории (`https://example.comapp/`). Должен начинаться и заканчиваться символом `/`.
* `--wasm` — компилирует Dart в WebAssembly (значительно повышает производительность рендеринга и работы с памятью в современных браузерах Chromium/Firefox/Safari, с автоматическим откатом на JS для старых браузеров).
* `--no-tree-shake-icons` — отключает вырезание неиспользуемых иконок из шрифтов, если иконки формируются динамически по коду.

### Артефакты сборки
Готовые статические файлы для загрузки на хостинг находятся в:
`apps/codelab_desktop/build/web/`

---

## 3. Локальная проверка собранного релиза

Открывать `build/web/index.html` напрямую как файл (`file://...`) нельзя из-за политики безопасности браузера (CORS). Для локальной проверки поднимите HTTP-сервер:

```bash
python3 -m http.server 8080 --directory apps/codelab_desktop/build/web
```
После запуска откройте `http://localhost:8080`.

---

## 4. Настройка веб-сервера и SPA-роутинга

Если в приложении используется роутинг без символа `#` (`PathUrlStrategy` / `GoRouter`), при прямом переходе по ссылке (например, `https://example.comsettings`) или обновлении страницы сервер должен отдавать `index.html`, а не ошибку `404`.

### Nginx
```nginx
server {
    listen 80;
    server_name ://example.com;
    root /var/www/codelab/web;
    index index.html;

    location / {
        try_files uri uri/ /index.html;
    }

    # Отключаем агрессивное кэширование для entrypoint и service worker
    location ~* (index\.html|flutter_service_worker\.js|flutter_bootstrap\.js|version\.json)\$ {
        add_header Cache-Control "no-store, no-cache, must-revalidate";
    }

    # Долгое кэширование для статических ассетов и скомпилированных бандлов
    location ~* \.(js|wasm|css|png|jpg|jpeg|gif|ico|svg|woff2|ttf|otf)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

### Vercel (`vercel.json`)
```json
{
  "rewrites": [
    { "source": "/(.*)", "destination": "/index.html" }
  ]
}
```

### Firebase Hosting (`firebase.json`)
```json
{
  "hosting": {
    "public": "build/web",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      { "source": "**", "destination": "/index.html" }
    ]
  }
}
```

---

## 5. Важные нюансы деплоя и безопасности

* **Безопасность секретов:** Все значения, переданные через `--dart-define-from-file=.env`, встраиваются в клиентский JS/Wasm-код и видны в DevTools браузера. Никогда не передавайте в Web-сборку приватные API-ключи (секреты БД, ключи OpenAI/Claude напрямую и т.д.) — проксируйте такие запросы через ваш бэкенд.
* **CORS на бэкенде:** В отличие от десктопных и мобильных приложений, браузер блокирует запросы к API на другом домене, если сервер не возвращает заголовок `Access-Control-Allow-Origin`.
* **Шрифты и кириллица (CanvasKit):** При первом запуске в браузере Flutter загружает движок рендеринга и системные шрифты. Чтобы кириллица отображалась мгновенно без квадратов и зависимости от CDN Google Fonts, добавьте локальный шрифт (например, `Roboto` или `Inter`) в `pubspec.yaml` в секцию `fonts:`.
