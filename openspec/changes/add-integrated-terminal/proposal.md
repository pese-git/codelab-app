## Why

Референсы (Zed, Claude Code Desktop) держат встроенный терминал рядом с агентским воркбенчем — удобство "не переключаться в отдельное приложение" для команд вроде `melos run analyze`/`git`. У CodeLab сегодня **нет вообще никакого process-execution, кроме запуска бинарника агента** (`Process.start` в `packages/dart/acp_transports/lib/src/stdio_acp_transport.dart:85`, структурированный stdio, не интерактивный PTY, и это осознанно принадлежит ACP-транспорту, а не общему terminal use case).

Это не расширение существующей возможности, а новая категория капабилити — интерактивный псевдотерминал (PTY), которого не было ни на уровне UI, ни на уровне инфраструктуры, ни как зависимость в `pubspec.yaml`. Требует явного архитектурного решения по `AGENTS.md` §4, а не тихого добавления пакета.

## What Changes

- Добавляется нижняя выезжающая панель "Terminal" в workbench: свёрнутое состояние — тонкая полоса с индикатором активной вкладки; развёрнутое — полноценный терминал с вкладками (несколько параллельных сессий), фиксированной высотой.
- Терминал открывается с рабочей директорией активного transport-профиля (`state.stdioCwd`) в момент создания вкладки — далее `cd` внутри терминала **не** влияет на `stdioCwd`/конфигурацию транспорта (односторонняя связь, не синхронизация).
- **Новая зависимость**: пакет для ANSI/rendering терминала (`xterm`, чистый Dart) + PTY-бэкенд для реального psuedo-terminal поведения (community-пакет, платформенно-зависимый). Точный выбор пакета — предмет `design.md`, не решается неявно через `pubspec.yaml` diff.
- Terminal-панель **не проходит через approval-safety** — это явно задокументированное намеренное решение (команды инициирует человек, а не агент), а не пробел в permission policy.
- Вывод терминала **не защищён `SecretRedactor`** — это отдельный, непроверяемый источник (интерактивный сторонний процесс), явно помечается в UI, а не тихо предполагается защищённым наравне с логами/диагностикой.
- **BREAKING**: нет. ACP contracts не меняются. Добавляется новая внешняя зависимость — требует явного одобрения архитектурного решения перед реализацией (см. design.md Open Questions).

## Capabilities

### New Capabilities

- `integrated-terminal`: интерактивный псевдотерминал (несколько вкладок) внутри workbench, независимый от ACP-сессии и approval-safety модели.

### Modified Capabilities

_(нет)_

## Impact

- `pubspec.yaml`/`melos.yaml` пакетов — новая зависимость (терминал-рендер + PTY-бэкенд), требует `fvm dart run melos bootstrap` после добавления.
- `apps/codelab_app/lib/core/platform/` — новый `TerminalProcessFactory`/`TerminalSession` (жизненный цикл, kill on dispose), использует `WorkingDirectoryProvider` для начального cwd, не связан с `acp_transports`.
- `packages/flutter/acp_ui/lib/src/organisms/` — новый `AcpTerminalPanel` (вкладки, expand/collapse, рендер через выбранный терминал-виджет).
- `apps/codelab_app/lib/features/workbench/presentation/` — интеграция панели в layout workbench (нижний слот, не расширяет существующие 4 слота `AcpWorkbenchLayout`, а отдельная строка под ними).
- `docs/architecture/` — вероятно нужна пометка в `concurrency.md`/`observability.md` о том, что terminal-процессы имеют собственный lifecycle и не покрываются secret redaction — выносится в design.md как явное решение, не тихое умолчание.
