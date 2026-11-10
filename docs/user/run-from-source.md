# Запуск из исходников

Пока нет установщика, `codelab`, `codelab-agent` и app собираются из репозитория. **Установщик — с выпуском 1.0**; до этого другого способа установки нет.

## Требования

- [FVM](https://fvm.app). Версия Flutter SDK закреплена в файле `.fvmrc` в корне репозитория — номер здесь не дублируется.
- Для app на macOS — Xcode с командной строкой.

Все команды ниже выполняются из корня репозитория и идут через `fvm`.

## 1. Подготовка

```bash
fvm install
fvm flutter pub get
fvm dart run melos bootstrap
```

`fvm install` ставит SDK из `.fvmrc`. `melos bootstrap` связывает пакеты репозитория между собой.

Сгенерированный код (`*.freezed.dart`) в git не хранится. Перед первой сборкой создайте его:

```bash
fvm dart run melos exec -c 1 --depends-on=build_runner -- "fvm dart run build_runner build --delete-conflicting-outputs"
```

## 2. Сборка CLI и агента

```bash
fvm dart run melos run build:cli      # build/bin/codelab
fvm dart run melos run build:agent    # build/bin/codelab-agent
```

Бинари появятся в `build/bin/`. Проверка:

```bash
build/bin/codelab --version
build/bin/codelab --help
build/bin/codelab-agent             # без команды печатает справку по командам и флагам агента
```

Чтобы вызывать их по имени, добавьте `build/bin` в `PATH` или скопируйте файлы в каталог из `PATH`.

## 3. Запуск CLI

Профиль по умолчанию — **встроенный агент**: ни `codelab-agent`, ни профиль создавать не нужно. Ему нужны настройки модели, см. [configuration.md](configuration.md).

```bash
build/bin/codelab                      # интерактивный режим (построчный REPL)
build/bin/codelab --ui=tui             # полноэкранный TUI
build/bin/codelab -p "Объясни, что делает этот проект"   # headless: один ход, ответ в stdout
```

Полезные флаги (полный список — `codelab --help`):

- `-C, --cwd=<dir>` — папка сессии;
- `-a, --agent=<profile>` — профиль агента (`embedded` и `default` — встроенный агент; также `stdio:<command> [args]` и `ws://`/`wss://` адрес);
- `-c, --continue` — продолжить последнюю сессию папки;
- `--approve=<reject|read-only|allow-all>` — как headless отвечает на запросы разрешений (по умолчанию `reject`). `allow-all` разрешает все запросы, кроме критических команд, — используйте его только в доверенном проекте.

Проверка настроек: `build/bin/codelab config check`.

## 4. Запуск app

```bash
cd apps/codelab_desktop
fvm flutter run -d macos
```

Приложение при старте подключает встроенный агент. Если провайдер модели не настроен, окно предложит «Add provider».

## Что дальше

- [Настройка](configuration.md);
- [Zed](zed.md) — использовать `codelab-agent` из Zed.
