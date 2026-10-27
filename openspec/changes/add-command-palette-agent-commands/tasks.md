## 1. Тестовый агент и e2e R-20 (итерация 1)

- [x] 1.1 Красный тест режима `withAvailableCommands`: `packages/dart/codelab_acp_testing/test/available_commands_agent_test.dart` на настоящем процессе (как `session_list_agent_test.dart`): после `session/new` приходит `available_commands_update` с `compact` без `input` и `plan` с `input.hint` `what to plan`; промпт `/compact` получает `agent_message_chunk` `Compacted the conversation.` и `end_turn`; другой промпт — `echo: <text>` (D6).
- [x] 1.2 Красный e2e `apps/codelab_desktop/integration_test/command_palette_flow_test.dart`, тег `scripted-only`, шаги 1–5 D6; скрипт melos `test:e2e:app:command-palette`. Ожидаемо красный на шагах 1 (заглушка `/compact` видна) и 4 (нет нечёткого поиска) до итерации 3; в feature-ветке — `flutter analyze integration_test`, прогон на macOS — по команде владельца (`AGENTS.md` §21). Источник: testing-quality «Интеграционный тест палитры с командами агента».
- [x] 1.3 Режим `withAvailableCommands` в `codelab_compatible_stdio_agent.dart` — 1.1 зелёный.

## 2. `CommandCatalog` в kit (итерация 2)

- [x] 2.1 Красные тесты `packages/dart/codelab_client_core/test/commands/command_catalog_test.dart` по сценариям acp-client-kit «Каталог команд палитры»: порядок `commands`, заглушка уступает агенту, доступная команда хоста и одноимённая агента остаются обе, повтор имени у агента, заглушка возвращается при новом списке, поиск — пустой запрос, ведущий `/`, регистр, четыре правила и порядок внутри правила.
- [x] 2.2 `lib/src/commands/command_catalog.dart`: `HostCommand`, `CatalogCommand` (`HostCatalogCommand`, `AgentCatalogCommand`), `CommandCatalog` (D2–D4); экспорт из бареля — 2.1 зелёный.

## 3. Палитра app на каталоге (итерация 3)

- [x] 3.1 Красные тесты: `codelab_ui` — `CodeLabCommandPaletteSurface` и `CodeLabPromptComposer` с параметром `search` показывают результат поиска в его порядке, без параметра — отбор `CodeLabCommandAction.filter`; app — `ShellState.paletteActions` без заглушки `/compact` при команде агента `compact`, поиск `ShellState` находит `compact` по `cpt` и ставит `plan` первым по `/pl`.
- [x] 3.2 `codelab_ui`: `typedef CodeLabCommandSearch`, параметр `search` у обоих виджетов (D5).
- [x] 3.3 App: `ShellState.paletteActions` и поиск из `CommandCatalog` (`HostCommand` из `CodeLabCommandAction.defaults`, сопоставление по `id`); `workbench_shell.dart` и `main_pane.dart` передают поиск — 3.1 и e2e 1.2 зелёные.

## 4. Документы и Definition of Done

- [ ] 4.1 Документы:
  - `09-10-stage-5-client-kit.md`: задача 5.6 — выбор команды агента вставляет её в композер, отправка уходит `session/prompt` (D1); эскиз API — `CommandCatalog` как значение хоста вместо `ClientWorkspace.commands`, `runCommand` — этап 6 (D2);
  - `agent-parity-goals.md`: строка R-20 — доказательство `app:command_palette_flow_test.dart`;
  - `AGENTS.md` пакета `codelab_client_core`: каталог команд в назначении пакета.
- [ ] 4.2 Definition of Done:
  - `fvm dart run melos run check` и `melos run guard` зелёные;
  - тесты `codelab_client_core`, `codelab_acp_testing`, `codelab_ui` и app зелёные;
  - интеграционные тесты собираются (`flutter analyze integration_test`); прогон на macOS — по команде владельца (`AGENTS.md` §21);
  - тексты прежних 9 интеграционных тестов не изменены.
- [ ] 4.3 Перед архивированием: `openspec validate add-command-palette-agent-commands --strict`.
