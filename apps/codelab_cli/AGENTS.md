# AGENTS.md — codelab_cli

Правила этого приложения дополняют корневой `AGENTS.md` и `packages/dart/codelab_client_core/AGENTS.md`.

Источники: `docs/architecture/proposals/dart-agent-and-clients/09-11-stage-6-cli-mvp.md` (задачи 6.1–6.10), §12.2 (отображение и ввод CLI), §9.10 (API kit), документ ядра §13 (коды выхода из событий) и §14 (фикстуры); `design.md` OpenSpec change `add-codelab-cli`; для полноэкранного режима — §12.2.7 и `design.md` change `add-cli-tui`. Если документов не хватает, сначала дополняется документация, потом пишется код.

## 1. Назначение

`apps/codelab_cli` — терминальный клиент `codelab`: REPL, полноэкранный режим `--ui tui` и headless-режим `codelab -p` поверх `ClientWorkspace` из `codelab_client_core`, драйвер фикстур `codelab test-scenario`. Состояния сессий, очереди промптов и одобрений у CLI нет: их владелец — kit; CLI только отображает `SessionView` и вызывает `SessionHandle`.

## 2. Границы

* Чистый Dart: НЕ ДОЛЖЕН импортировать `package:flutter/`, `package:fluent_ui/`, `package:codelab_ui/` и `package:codelab_agent_*` — правило `apps/codelab_cli` в `packages/dart/codelab_architecture_tests/test/support/rules.dart`.
* `dependencies` — только `codelab_client_core`, `codelab_client_io`, `codelab_client_acp`, `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_acp_testing`, `args`, `async`, `path`, `meta`, `dart_tui`. Расширение — только через OpenSpec change.
* `package:codelab_acp_testing/` импортируется только из `lib/src/scenario/` (драйвер фикстур, design.md, D3).
* `package:dart_tui/` импортируется только из `lib/src/tui/` (адаптер полноэкранного режима); чистое ядро экрана `lib/src/tui/core/` не импортирует ни пакет, ни `dart:io` (TUI-5) — два правила сторожа, design.md change `add-cli-tui`, D3.
* `dart:io` — только в composition root, точке входа, порте терминала (`IoTerminal`), домашнем каталоге, сигналах, connector драйвера фикстур (design.md, D2) и запуске TUI (`TuiRunner`). Логика — рендер, декодер клавиш, редактор строки, политика одобрений, коды выхода — чистая и тестируется без процессов.
* В headless stdout несёт только ответ агента; всё остальное — stderr. Ошибка использования оставляет stdout пустым.
* Значение `CODELAB_AGENT_TOKEN` не попадает ни в вывод, ни в `profiles.json`.

## 3. Тесты

* TDD — пары «тест → реализация» (§9.0, правило 3); красный тест коммитится до кода.
* Модульные тесты — `test/` на фейковом терминале и `ClientWorkspace` поверх `FakeAcpTransport` или `InProcessAcpLink`.
* Процессные и PTY-e2e — `test/e2e/` против scripted stdio-агента из `codelab_acp_testing`; CLI запускается из kernel, скомпилированного один раз. Это интеграционные тесты на Dart VM, они входят в `melos run test` (`AGENTS.md` §21). Имена e2e — id критериев матрицы целей (`cli/<id>`).

## 4. Готовность итерации

По `09-00-migration-plan.md` §9.0, правило 8: критерии строк матрицы итерации зелёные, `melos run check` зелёный, документы и код не расходятся, в PR названа следующая итерация по `tasks.md`.
