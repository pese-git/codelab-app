# AGENTS.md — codelab_agent

Правила этого приложения дополняют корневой `AGENTS.md` и `packages/dart/codelab_agent_core/AGENTS.md`.

Источники: `docs/architecture/proposals/dart-agent-and-clients/09-09-stage-4-acp-adapter.md` (задачи 4.5, 4.6), документ ядра `agent-core-architecture.md` — §12.3 (логи), §13.1, §13.3, §13.10 (адаптер и транспорт), §15.6 (флаги и переменные), §14 (фикстуры); `design.md` OpenSpec change `add-codelab-agent-binary` и `add-agent-configuration` (D4, D10, D11, D16). Если документов не хватает, сначала дополняется документация, потом пишется код.

## 1. Назначение

`apps/codelab_agent` — бинарь `codelab-agent serve --stdio | --ws`: хост ядра в профиле `agent-serve`. Он разбирает флаги, загружает конфигурацию (`ConfigLoader` из `codelab_agent_io`: `config.yaml`, переменные `CODELAB_*`, флаги — `agent-core-architecture` §15; change `add-agent-configuration`), собирает ядро через `buildAgentCore`, поднимает `AcpAgentServer` на серверном транспорте и отвечает за логи, сигналы и коды выхода. Команда `codelab-agent config check [--cwd <dir>]` проверяет конфиг без запуска сервера: разбор аргументов — `lib/src/cli/config_cli.dart`, тексты, правила и коды выхода — общий `ConfigCommands` из `codelab_agent_io` (design.md change `add-agent-configuration`, D13); свой вывод здесь не формируется. Поведения агента здесь нет: оно в пакетах `codelab_agent_*`.

## 2. Границы

* Чистый Dart: НЕ ДОЛЖЕН импортировать `package:flutter/`, `package:fluent_ui/` и клиентские пакеты (`codelab_client_acp`, `codelab_ui`) — правило `apps/codelab_agent` в `packages/dart/codelab_architecture_tests/test/support/rules.dart`.
* `dependencies` — только `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `codelab_agent_mcp`, `codelab_acp_protocol`, `codelab_acp_transports`, `args`, `http`, `async`, `meta`. Расширение — только через OpenSpec change.
* Ядро собирается только через `buildAgentCore` (HOST-6): `ToolRegistry(`, `Agent(`, `AgentRuntime(` в `lib/` и `bin/` запрещены.
* stdout в режиме `--stdio` несёт только кадры ACP; логи — stderr и файл.
* Значение ключа провайдера (`CODELAB_API_KEY`, переменные из `api_key_env`, подстановки `${ENV}`) и токен WebSocket не попадают в лог, текст ошибок и строковое представление опций.
* Флаги строят слой `ConfigTree` (`ServeOptions.flags`), а не модели: настройки ядра берутся из результата `loadServeConfig`. С `--llm-script` слои 2–4 не читаются; невалидный конфиг — код `64` до старта транспорта.
* Файлы конфигурации (`agent-core-architecture` §15.2): `$CODELAB_HOME/config.yaml`, `<cwd>/.codelab/config.yaml`, `<cwd>/.codelab/config.local.yaml` и дополнительный файл `--config <path>` / `CODELAB_CONFIG` (только `.yaml`/`.yml`; `CODELAB_CONFIG` — только абсолютный путь, `--config` — от текущего каталога процесса; явно названный, но отсутствующий файл — код `64`). Файлы Python-агента (`$CODELAB_HOME/codelab.toml`, `$CODELAB_HOME/auth.toml`, `<cwd>/codelab.toml`, `<cwd>/codelab.local.toml`) не читаются: найденный файл даёт только предупреждение `config.legacy_found` (D12).
* `--max-steps <n>` и `CODELAB_MAX_STEPS` — `budget.max_steps`, целое `≥ 1`: неверный флаг — ошибка использования, неверная переменная — проблема конфигурации `budget.max_steps`; в обоих случаях код `64`; `--model <provider>/<model>` без `--provider` выбирает модель конфига (§15.6; D4).
* `config` — единственная подкоманда `check [--cwd <dir>]`; `set`, `migrate` и прочие не регистрируются и дают `64` со справкой. `config check` не запускает сервер, не читает stdin и ничего не пишет.

## 3. Тесты

* TDD — по `packages/dart/codelab_agent_core/AGENTS.md` §2.
* Процессные тесты запускают `fvm dart run bin/codelab_agent.dart` с `--llm-script`: это интеграционные тесты на Dart VM, они входят в `melos run test` (`AGENTS.md` §21).
