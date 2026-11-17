## Why

У CodeLab нет публичной точки входа. Документация для пользователя и DevOps есть (`docs/user/`, `docs/ops/`, `README.md` и `doc/` приложений), но её читают только на GitHub, разбросанной по каталогам. Нет страницы, которая коротко объясняет три продукта — CodeLab app, терминальный клиент `codelab` и агент `codelab-agent` — и ведёт к установке. Выпуски никак не объявляются.

Решения о сайте пользователь принял в обсуждении 2026-11-17, ответы на открытые вопросы design.md — там же; архитектурная часть — ADR-0003 (`Proposed` до одобрения этого change) (`docs/architecture/adr/0003-build-project-site-with-astro-in-monorepo.md`).

Ограничения, которые меняют способ работы репозитория:
- «Один факт — одно место» (`.claude/skills/codelab-docs/SKILL.md` §3): сайт не должен стать второй копией документации.
- Node и npm — новый тулчейн в monorepo на Dart (`docs/architecture/technology-stack.md`). Его надо отделить от pub workspace, Melos и сторожа.
- CI проверяет затронутое (`AGENTS.md` §21). Сейчас любой файл вне пакетов workspace запускает полный прогон Dart-джобов (`tool/ci/ci_scope.dart`). Если ничего не менять, каждая правка `site/` запустит полный прогон.

## What Changes

- **Каталог `site/`** — статический сайт на Astro, отдельный Node-проект: свой `package.json` с точными версиями, закоммиченный `package-lock.json`, Node закреплён в `site/.nvmrc`, пакетный менеджер npm. В pub workspace и в Melos `site/` не входит, сторож его не проверяет. Правило сторожа не нужно (design.md, D1).
- **Разделы:** главная и страницы возможностей трёх продуктов; установка и быстрый старт; документация; новости выпусков. Сайт только на русском.
- **Документация читается на месте.** Content collections Astro берут Markdown из закрытого списка источников: `docs/user/**`, `docs/ops/**`, `apps/*/README.md`, `apps/*/doc/**`, `packages/*/*/README.md`, `packages/*/*/doc/**`. Остальное не публикуется. В `site/` лежит только то, что существует ради сайта.
- **Перевод ссылок при сборке.** Относительная ссылка на опубликованный файл становится адресом страницы сайта. Ссылка на неопубликованный файл ведёт на GitHub, на коммит сборки (параметр конфигурации). Ссылка на несуществующий файл ломает сборку.
- **Mermaid** рисуется в браузере (`mermaid.js`) с учётом светлой и тёмной темы. Скрипт загружается только на страницах со схемами.
- **Новости** — коллекция `site/src/content/news/`, одна запись на выпуск. Её пишет `docs-writer` в `release/<version>` из корневого `CHANGELOG.md` и архива OpenSpec changes выпуска.
- **`CHANGELOG.md`** в корне — новый файл: формат разделов выпуска на русском, ведётся в `release/<version>`.
- **Оформление** как у приложения: токены Fluent из `docs/design/claude-design/fluent.css` и `codelab_ui`, светлая и тёмная темы.
- **Скриншоты** — существующие снимки из `apps/*/doc/images/`, без копий в `site/`.
- **CI.** Джоб `scope` получает второй выход — `site`. Новый джоб `site`: `npm ci`, `astro check`, тесты плагинов, `astro build` с непустым `base`, проверка внутренних ссылок. Его запускают правки `site/**`, `docs/**`, `openspec/**`, `apps/*/README.md`, `apps/*/doc/**`, `packages/**/README.md`, `packages/**/doc/**`, а также любой полный прогон. Джоб обязательный: его ждёт итоговый джоб `ci`, красный `site` блокирует merge в `develop`. Правка только `site/` не запускает Dart-джобы. Публикации нет. `base` и `site` Astro задаются переменными окружения, чтобы потом подключить хостинг без переделок.
- **Команда и процесс.**
  - Новый агент `.claude/agents/site-engineer.md` и новый skill `.claude/skills/codelab-site/`. Метка задач — `[site]`, строка агента — в таблице `CLAUDE.md`.
  - В `codelab-docs` — правило «ссылки — только относительные пути к существующим файлам».
  - В `docs-writer` — запись новости на выпуск.
  - В `AGENTS.md` — `site/` в структуре (§5), проверка сайта (§21), `CHANGELOG.md` и новость в чек-листе выпуска (§22).
  - Ревью — `architecture-reviewer` по чек-листу skill. Отдельная команда `/site` не нужна.

## Не входит

- **Хостинг и публикация.** Выбор хостинга, деплой, домен, `CNAME`, CSP-заголовки хостинга. Конфигурация только готовит `base` и `site`.
- **Окончательная цель ссылок на GitHub** (коммит сборки, `master` или `develop`). До решения о хостинге — коммит сборки по умолчанию, параметр конфигурации (design.md, D5).
- **`docs:screenshots`** — витринные снимки (релизная сборка, нормальное окно, без баннера DEBUG) и их автоматическая съёмка. Это следующий шаг, отдельный change; до него сайт показывает существующие снимки.
- **Первая новость.** Её пишут в первой ветке `release/<version>` после этого change. До неё страница новостей показывает пустое состояние.
- Поиск по документации, английская версия, аналитика, комментарии, RSS.
- Публикация `openspec/`, `docs/architecture/`, `docs/protocols/`, `docs/backlog/`, `docs/design/`, `AGENTS.md`.
- Публикация `docs/integrations/claude-code.md` и `docs/codelab-spec.md` — решение отложено; по умолчанию они не публикуются (закрытый список), добавить их можно одной строкой списка публикации (design.md, D3).
- Новые документы для продуктов, у которых их нет (README пакетов). Это задача `/docs`; сайт подхватит их без своих правок.
- `/docs apps/codelab_agent` — отдельно, после этого change. До него страница возможностей `codelab-agent` ссылается на `docs/user/` и `docs/ops/`.
- Изменения Dart-кода продуктов, ACP, пакетов workspace и графа зависимостей.

## Capabilities

### New Capabilities

- `project-site`: сайт CodeLab — источники и адреса страниц документации, перевод ссылок, mermaid, разделы, новости, темы, безопасность публикации, проверка в CI.

### Modified Capabilities

- `testing-quality`: изменено «Непрерывная интеграция» — обязательный джоб `site` в списке обязательных джобов и сценарий «Красный `site` блокирует merge». Охват CI по затронутому по-прежнему описан в `docs/architecture/testing.md` §74.

## Impact

- **Новое:** `site/**`; `.claude/agents/site-engineer.md`; `.claude/skills/codelab-site/SKILL.md`.
- **CI:**
  - `.github/workflows/ci.yml` — джоб `site` и выход `site` у `scope`;
  - `tool/ci/ci_scope.dart`, `tool/ci/affected.dart` — признак сайта, файлы `site/` не запускают полный прогон;
  - `packages/dart/codelab_architecture_tests/test/ci_scope_test.dart` — тесты.
- **Корень:** `CHANGELOG.md` (новый); `.gitignore` (`site/node_modules/`, `site/dist/`, `site/.astro/`); `analysis_options.yaml` (`site/**` в `analyzer.exclude`); `README.md` (строка `site/` в таблице структуры); `AGENTS.md` §5, §21, §22; `CLAUDE.md`.
- **`.claude/`:**
  - `skills/codelab-docs/SKILL.md` — правило ссылок, публикация на сайте;
  - `agents/docs-writer.md` — новости;
  - `agents/architecture-reviewer.md` — ссылка на чек-лист сайта;
  - `agents/check-runner.md` — проверка сайта;
  - `commands/change.md`, `commands/implement.md` — метка `[site]`.
- **Документы архитектуры:** ADR-0003 и реестр ADR (`docs/architecture/adr/README.md`), `technology-stack.md` §1 и §28 — в этом change; `testing.md` §74 — после реализации CI.
- **Опубликованные документы:** правки только там, где сборка найдёт нарушение правил ссылок или безопасности публикации. На 2026-11-17 из 162 относительных ссылок и изображений в 15 опубликуемых файлах битых нет.
- **Не меняются:** пакеты и приложения workspace, `pubspec.yaml`, `pubspec.lock`, правила сторожа `rules.dart`, граф зависимостей в `README.md`, ACP.
