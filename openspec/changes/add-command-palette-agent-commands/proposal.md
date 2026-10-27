## Why

Строка R-20 матрицы паритета (Must, этап 5) требует доказательства: агент объявил `/compact` → агент получает `session/prompt` с `/compact`, в транскрипте его ответ. Команды агента в палитре app уже есть (agent-workbench-ui «Командная палитра представляет команды, объявленные агентом»), но интеграционного теста на настоящем процессе агента нет. Без него Must этапа 5 не закрыт, а вместе с ним и веха M2.

Change `extract-acp-client-kit` перенёс сюда (design D9) остаток задачи 5.6 плана `09-10`: `CommandCatalog` в `codelab_client_core` и нечёткий поиск. Сегодня список палитры склеивает app (`ShellState.paletteActions`), а отбирает виджет `codelab_ui` подстрокой (`CodeLabCommandAction.filter`), то есть логика живёт в слое UI. Конфликты имён не разрешаются никак: если агент объявит `/compact`, в палитре окажутся две строки `/compact` — неработающая заглушка клиента «coming soon» и рабочая команда агента.

## What Changes

- E2E R-20 `apps/codelab_desktop/integration_test/command_palette_flow_test.dart` на scripted-агенте и новый режим `withAvailableCommands` в `codelab_acp_testing`. Режим объявляет `/compact` без `input` и `/plan` с `input.hint`, а на промпт `/compact` отвечает отчётом о сжатии. Тест пишется первым.
- `CommandCatalog` в `codelab_client_core` (`lib/src/commands/`). Он сливает команды хоста с командами агента активной сессии и разрешает конфликты имён. Поиск по подпоследовательности ранжирует совпадения: префикс имени, подстрока имени, подпоследовательность имени, подстрока названия или описания.
- Конфликт имён: недоступная команда клиента (`isAvailable: false`) скрывается, если агент объявил команду с тем же именем. Доступные команды клиента (`/new`, `/reconnect`, `/logs`) не скрываются, одноимённая команда агента показывается в своей секции.
- Палитра app (`Ctrl/Cmd+K` и inline `/`) строит список и фильтрует по запросу через `CommandCatalog`. `CodeLabCommandPaletteSurface` получает функцию поиска от app вместо своего фильтра подстрокой.
- Выбор команды агента не меняется: в композер вставляется `/{name} ` с подсказкой `input.hint` в placeholder, отправляет пользователь (решение владельца продукта; ACP поведение при выборе не задаёт, `14-Slash Commands.md`).
- Документы: в плане `09-10` (задача 5.6) формулировка «выбор `/compact` отправляет `session/prompt`» заменяется на «выбор вставляет, отправка отправляет»; эскиз API — `CommandCatalog` как значение, которое строит хост, без `ClientWorkspace.commands`; строка R-20 в `agent-parity-goals.md` получает доказательство.

Не входит:
- `SessionHandle.runCommand` из эскиза `09-10`: разбор введённой команды и выбор между клиентом и агентом нужен CLI (этап 6), app выполняет команды по выбору в палитре;
- команды самого Dart-агента: `codelab-agent` объявляет пустой `availableCommands`, поэтому тест идёт только на scripted-агенте (тег `scripted-only`);
- реализация `/plan`, `/permissions` и `/compact` как команд клиента.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities
- `agent-workbench-ui`: «Командная палитра представляет команды, объявленные агентом» — команда агента вытесняет одноимённую недоступную команду клиента, отбор по запросу — нечёткий; «Командная палитра честно помечает нереализованные действия как недоступные» — заглушка скрывается, когда агент объявил команду с её именем.
- `acp-client-kit`: новое требование «Каталог команд палитры».
- `testing-quality`: новое требование «Интеграционный тест палитры с командами агента».

## Impact

- `packages/dart/codelab_client_core`: `lib/src/commands/command_catalog.dart`, экспорт из бареля, `test/commands/command_catalog_test.dart`.
- `packages/flutter/codelab_ui`: `CodeLabCommandPaletteSurface` (параметр поиска), тесты организма.
- `apps/codelab_desktop`: `ShellState.paletteActions`, `ui_mappers.dart`, `workbench_shell.dart`, `main_pane.dart`, тесты application; `integration_test/command_palette_flow_test.dart`; скрипт melos `test:e2e:app:command-palette`.
- `packages/dart/codelab_acp_testing`: режим `withAvailableCommands` и его тест на настоящем процессе.
- Документы: `09-10-stage-5-client-kit.md`, `agent-parity-goals.md` (R-20), `AGENTS.md` пакета `codelab_client_core`.
- ACP-контракт и зависимости не меняются.
