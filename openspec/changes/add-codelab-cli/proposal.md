## Why

Этапы 4 и 5 закрыты: Dart-агент работает по stdio и WebSocket, общий клиентский слой `codelab_client_core` вынесен из codelab-app. Но терминального клиента нет — Python TUI остаётся единственным способом работать с агентом из консоли, а скрипты и CI не могут запустить ход без интерфейса. Веха «первый полезный результат» (M2, `delivery-roadmap.md`) требует полностью выполненного этапа 6 — `codelab_cli` MVP (`docs/architecture/proposals/dart-agent-and-clients/09-11-stage-6-cli-mvp.md`).

Этот change закрывает строки матрицы целей уровня Must этапа 6 (`agent-parity-goals.md`): H-01, H-02, H-04, U-01–U-07, U-15, и две строки Should — U-08 (мысли отдельно от ответа) и U-09 (строки инструментов без сырого JSON). Формат `stream-json` (H-03, Should) и расширение модели отображения kit, которое ему нужно (§12.1), идут следующим change `add-cli-stream-json`; разведка `dart_tui` (задача 6.11) — в change полноэкранного TUI (U-12, после MVP). Решение владельца проекта; §9.11 правится в этом change (design.md, D1).

## What Changes

- **Новое приложение `apps/codelab_cli`** (чистый Dart, бинарь `codelab`): каркас на `package:args`, composition root поверх `ClientWorkspace`, `ioTransportResolver` и адаптеров `codelab_client_io` (задача 6.1); скрипт `build:cli` → `build/bin/codelab`.
- **Профили подключения (6.2, U-06)**: значение `--agent` — id профиля из `$CODELAB_HOME/profiles.json` (по умолчанию `~/.codelab`), `stdio:<команда> [аргументы]` с разбором как в shell, `ws://…`/`wss://…` с токеном из `CODELAB_AGENT_TOKEN`; профиль `default`, если `--agent` не задан; команда `codelab profiles list|show|add|remove`. `embedded` до этапа 7 — код 64 `Embedded agent is not available in this build.`
- **Headless (6.7, H-01, H-02)**: `codelab -p`, `-f <файл>`, `-f -` и промпт из stdin, позиционные аргументы по правилам H-01; ответ — в stdout байт в байт, диагностика — в stderr; политика одобрений `--approve reject|read-only|allow-all` (запросы с `_meta.codelab.critical: true` `allow-all` не разрешает); `--timeout`; `--resume`/`--continue`; `--model`/`--mode`; коды выхода `0`, `1`, `64`, `130`, `143` из ответа `session/prompt` и ошибок, а не из транскрипта.
- **REPL (6.3–6.6, U-01–U-05, U-07, U-15)**: поверхности вывода `raw`/`plain`/`ansi` (§12.2.1, без ANSI в pipe, при `NO_COLOR`, `--no-color`, `TERM=dumb`); потоковый ответ, мысли приглушённо (U-08), строки инструментов без сырого JSON (U-09), план; редактор строки в raw-режиме с историей `$CODELAB_HOME/cli_history` и многострочным вводом, без TTY — построчный ввод; клавиши — одна таблица действий; блок одобрения `y`/`a`/`n`/`N`/`?` только с вариантами агента; slash-меню, где команды клиента слиты с командами агента через `CommandCatalog`, Tab-дополнение; клиентские команды MVP (design.md, D7); очередь промптов из kit.
- **Сигналы (6.9)**: SIGINT и SIGTERM отменяют ход, закрывают транспорт и дочерний процесс агента.
- **Драйвер фикстур (6.8, H-04)**: `codelab test-scenario <путь>... --agent <профиль> [--filter] [--timeout]` поверх `runAgentFixtureOver` из `codelab_acp_testing`; вывод `PASS|FAIL|SKIP <id> (<время>)`, при расхождении — дифф кадров; коды `0`/`1`/`64`. Для `stdio:codelab-agent …` блок `llm` фикстуры передаётся флагом `--llm-script`.
- **E2E (6.10)**: собранный бинарь против scripted stdio-агента; интерактивные сценарии — через псевдотерминал системной утилиты `script` (обвязка `PtyProcess`, macOS и Linux; на Windows — пропуск с сообщением). Идут на Dart VM в `melos run check` и отдельным скриптом `test:e2e:cli` (`AGENTS.md` §21).
- **Доработки `codelab_client_core`**, нужные CLI и полезные app:
  - `SessionView.plan` — план сессии в модели kit (сейчас app строит его сам в `currentPlanOf`);
  - `PendingApprovalView.critical` — признак `_meta.codelab.critical` запроса одобрения;
  - `parseShellWords` понимает кавычки и экранирование.
- **`codelab_acp_testing`**: `FixtureReplayAgent` — агент, отвечающий ожидаемыми кадрами самой фикстуры (проверка драйвера без настоящего агента); новые режимы scripted stdio-агента для сценариев CLI (design.md, D10).
- **Сторож и workspace**: `apps/codelab_cli` в `workspace:`, правило сторожа (без Flutter и `package:codelab_agent_*`) и allowlist зависимостей; `codelab_acp_testing` — обычная зависимость только у CLI ради `test-scenario` (design.md, D3).

Не входит:
- `--output-format json|stream-json`, `--include-thoughts`, `--include-acp`, `--input-format`, `--trace-file`, `/trace`, `/inspect`, diff правки в `?` одобрения — change `add-cli-stream-json` вместе с расширением модели отображения kit (§12.1); до него флаги не регистрируются (код 64 `Unknown flag`);
- разведка `dart_tui` (6.11), `--ui tui` — change полноэкранного TUI (U-12);
- `--session <name>` (S-14, Should), bracketed paste, Shift+Enter и `/terminal-setup` (U-23, Should) — отдельные change;
- `~/.codelab/cli.yaml` (переопределение клавиш и отображения, §12.2.10) и язык строк `--lang` (TUI-12) — после MVP; строки CLI MVP — английские;
- `_meta.codelab.sealOnClose` и `jobBoard` в headless (S-15) — вместе с поддержкой агентом;
- `test-scenario --junit` и `--update-golden` — после MVP;
- `embedded` и `--permission-mode` — этап 7; подкоманды `config`, `provider`, `mcp`, `secret` — этап 8.

## Capabilities

### New Capabilities
- `codelab-cli`: терминальный клиент `codelab` — разбор команды и флагов, профили подключения, REPL (поверхности вывода, рендер, редактор строки, клавиши, slash-меню, клиентские команды, очередь), UX одобрения, сигналы.
- `cli-headless`: headless-режим `codelab -p` — источники промпта, вывод, политика `--approve`, `--timeout`, загрузка сессии, коды выхода.
- `cli-scenario-driver`: команда `codelab test-scenario` — проигрывание golden-фикстур против агента по профилю, вывод и коды выхода.

### Modified Capabilities
- `acp-client-kit`: «Публикация представлений сессии» — `SessionView.plan`; «Одобрения привязаны к вызову» — признак `critical`; «Профили и резолверы транспорта» — `parseShellWords` с кавычками и экранированием.
- `acp-golden-fixtures`: новое требование «Агент-повторитель фикстуры» (`FixtureReplayAgent`).
- `workspace-architecture`: «Границы пакетов monorepo» — приложение `apps/codelab_cli`; «Автоматический сторож границ пакетов» — правило и allowlist `apps/codelab_cli`.
- `testing-quality`: «Проверки workspace» — скрипты `build:cli` и `test:e2e:cli`; новое требование «PTY-e2e терминального клиента».

## Impact

- **Новое приложение** `apps/codelab_cli`: `bin/codelab.dart`, `lib/src/` — `cli_runner`, `composition_root`, `profiles/`, `render/`, `repl/`, `input/`, `headless/`, `scenario/`, `signals`; `test/` с модульными тестами и `test/e2e/` (PTY). Зависимости — `codelab_client_core`, `codelab_client_io`, `codelab_client_acp`, `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_acp_testing`, `args`, `async`, `path`, `meta` (design.md, D3). Новых технологий стека нет: `package:args` уже записан (technology-stack §20б).
- **`codelab_client_core`**: `SessionView.plan` и `PlanEntryView`, `PendingApprovalView.critical`, `parseShellWords`. `apps/codelab_desktop` переходит с `currentPlanOf` на `SessionView.plan`; поведение app не меняется.
- **`codelab_acp_testing`**: `FixtureReplayAgent`, новые режимы scripted stdio-агента.
- **`codelab_architecture_tests`**: правило и allowlist `apps/codelab_cli`, негативные тесты.
- **Корень**: `workspace:`, скрипты `build:cli` и `test:e2e:cli`.
- **Документы**: `09-11-stage-6-cli-mvp.md` (раздел «OpenSpec change», DoD, перенос stream-json и 6.11), `12-5-stream-json.md` (ссылка на change `add-cli-stream-json`), `agent-parity-goals.md` (статусы строк по мере закрытия), `AGENTS.md` §5 (`codelab_cli` в структуре, исключение для `codelab_acp_testing`), вложенный `apps/codelab_cli/AGENTS.md`.
- **ACP-контракт** не меняется: CLI использует только стандартные методы и уже введённое агентом поле `_meta.codelab.critical`.
