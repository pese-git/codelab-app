## Why

Три строки Must матрицы целей ([`agent-parity-goals.md`](../../../../docs/architecture/proposals/agent-parity-goals.md)) не закрываются без встроенных слэш-команд Dart-агента, а без них не открываются ворота MVP change [`switch-default-agent-to-dart`](../../switch-default-agent-to-dart/design.md) (решение пользователя Q9, 2026-11-10):

- **K-02** — `/compact [указание]` объявлен агентом и сразу сжимает историю (`acp/slash-compact`; app-часть — `app:command_palette_flow_test.dart`);
- **R-08** — `/help`, `/status`, `/mode <id>`, `/compact` обрабатывает агент, неизвестная команда — текстовый ответ, а не ход модели (`acp/slash-help`, `acp/slash-mode-plan`);
- **U-03** — меню CLI объединяет команды клиента и агента против Dart- и встроенного агента (`cli/slash-menu-merges-agent-commands`); сегодня тест только `scripted-only`, и в отчёте ночного `parity` он `not-run`.

Сейчас агент объявляет только `/mcp` (и `/config` при источнике конфигурации), имя `compact` лишь зарезервировано (`codelab_agent_core/lib/src/commands/builtin_commands.dart`), а спецификация `agent-slash-commands` отправляет `/x` без шаблона модели как текст. Это противоречит R-08 и `agent-core-architecture` §13.6 (правило 3: `Unknown command: /<name>. Run /help to list commands.`), где поведение заложено отложенным до «change встроенных команд» (§13.6 «Этап 8.10», §17.2.6 «Этап 8.7»).

Шаг красных тестов итерации 2 `switch-default-agent-to-dart` нашёл ещё одно следствие: интеграционный тест палитры app (`command_palette_flow_test.dart`, доказательство K-02 и R-20) в режиме `dart` пропускается, «пока `codelab-agent` объявляет пустой `availableCommands`». Пропуск в обязательном источнике оставит обе строки открытыми на итоговом прогоне ворот (D5 того change).

## What Changes

- **Встроенные команды MVP** (`agent-slash-commands`, ADDED «Встроенные команды MVP»): `/compact [focus]` (триггер `manual`, `SummaryRequest.focus`), `/mode [<id>]`, `/model [<provider/model>]`, `/status`, `/help`. Объявляются в `available_commands_update` в порядке §13.4: `compact`, `mode`, `model`, `status`, `config`, `mcp`, `help`, затем шаблоны. Исполняются механизмом встроенных команд `/config` и `/mcp` (design.md change `add-config-writer-and-reload`, D12): без хода модели, без записи промпта и ответа в журнал, со слотом хода и отменой. `/mode` и `/model` меняют состояние сессии тем же путём, что `session/set_config_option`, и пишут `mode_change` / `model_change`.
- **Неизвестная команда** (`agent-slash-commands`, ADDED «Неизвестная команда»): `/x` с именем по `^[A-Za-z0-9][A-Za-z0-9:_-]*$`, которое не является ни объявленной встроенной командой, ни шаблоном, получает ответ `Unknown command: /x. Run /help to list commands.` и не уходит модели. Необъявленные `/config` и `/mcp` (WebSocket, нет источника конфигурации) — тоже неизвестные команды. **BREAKING** для пользователей, которые начинали промпт с `/слово` и ждали ответа модели (design.md, «Risks»).
- **Фикстуры** (`acp-golden-fixtures`): новые `acp/slash-compact`, `acp/slash-help`, `acp/slash-mode-plan` (готовы, красные тесты, перенесены из итерации 2 `switch-default-agent-to-dart`); точные списки команд в `acp/available-commands-no-tools`, `acp/prompt-template-command` и `acp/slash-mcp-list` обновляются со ссылкой на это требование.
- **E2E CLI U-03**: вариант `cli/slash-menu-merges-agent-commands` против Dart- и встроенного агента (без тега `scripted-only`); проверка одноимённых команд клиента и агента через `/help`, `/mode`, `/model` → `/agent:<имя>` (`codelab-cli`, сценарий «Одноимённые команды клиента и Dart-агента»).
- **Интеграционный тест палитры app** (`testing-quality`, MODIFIED): тест без тега для встроенной `compact` во всех режимах и `scripted-only` тест для полного сценария scripted-агента; пропуск в режиме `dart` убирается.
- **Сопутствующие правки спецификаций**, где список команд был «пуст» или «ровно `mcp` и шаблон»: `agent-acp-server` («session/new»; «session/cancel» — отмена команды, меняющей состояние, D14), `agent-binary` («Файлы проекта в бинаре», «Перезагрузка конфига в serve»), `agent-project-context` («Порт файлов проекта»).
- **Матрица и ворота**: записи K-02 и R-08 удаляются из `knownGaps` (`parity_evidence_test.dart`); если список пуст — удаляется и константа с проверкой устаревания (D4 change `switch-default-agent-to-dart`).

## Не входит

- **MCP prompts как команды** `<server>:<prompt>` — строка Should E-24, этап 9+, отдельный change (решение пользователя Q10, 2026-11-10). До него `/server:prompt` — неизвестная команда.
- **Команды после MVP** (§13.4): `usage`, `redact`, команды сессии, `approve`, `timer`, `memory`, `tasks`, форма `/model --role`, строки `/status` после MVP (`Roles`, `Tools`, `Deadline`, `Hooks`, `Plugins`).
- **Строки `/status` `System prompt: …` и `Tools disabled: …`** — вместе с E-08 (`--system-prompt`) и выключением инструментов (§6.3.8): в ядре этих настроек ещё нет.
- **Незакрытая кавычка в аргументах шаблона** остаётся закрытой концом ввода (D8 change `add-agent-project-files`); `CommandFailed("Unterminated quote in arguments.")` из §17.2.6 — не в этом change (вопрос Q7 design.md).
- **Изменения ACP:** новых методов, полей, `_meta` и `_codelab/*` нет. Команды идут обычным `session/prompt`, список — `available_commands_update` (`docs/protocols/acp/protocol/14-Slash Commands.md`).
- **Клиентские команды CLI и app** не меняются: `/help`, `/mode`, `/model`, `/config` клиента сохраняют приоритет, одноимённые команды агента доступны как `/agent:<имя>` (codelab-cli «Slash-меню и клиентские команды»).
- **Источник конфигурации у `codelab-agent --llm-script`** не появляется (D13 change `add-config-writer-and-reload`): команда `/config` в e2e со сценарием не объявляется (вопрос Q8 design.md).

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-slash-commands` — ADDED «Встроенные команды MVP», «Неизвестная команда»; MODIFIED «Список команд сессии», «Разворачивание команды», «Встроенные команды config и mcp».
- `agent-runtime` — MODIFIED «Живая перезагрузка конфигурации»: `ModelOptionsChanged` публикуется и при смене модели командой `/model`, тогда оно — событие хода и буферизуется в его истории (design.md, D6).
- `agent-acp-server` — MODIFIED «session/new» (состав и порядок `available_commands_update`), «session/cancel» (кадры смены, применённой командой до отмены, — до ответа `cancelled`; D14).
- `agent-binary` — MODIFIED «Файлы проекта в бинаре», «Перезагрузка конфига в serve» (ответ на `/config` по WebSocket).
- `agent-project-context` — MODIFIED «Порт файлов проекта» (список команд без порта).
- `acp-golden-fixtures` — ADDED «Фикстуры встроенных команд агента»; MODIFIED «Фикстуры файлов проекта этапа 8».
- `codelab-cli` — MODIFIED «Slash-меню и клиентские команды» (сценарий одноимённых команд, U-03).
- `testing-quality` — MODIFIED «Интеграционный тест палитры с командами агента».

## Impact

- **Код:**
  - `packages/dart/codelab_agent_core/lib/src/commands/builtin_commands.dart` — объявление и исполнение новых команд, неизвестная команда;
  - `packages/dart/codelab_agent_core/lib/src/runtime/` — `AgentSession.prompt` (порядок разбора), порт ручного сжатия и состояния для `/status`;
  - `packages/dart/codelab_agent_acp` — без новой проекции (события уже проецируются); тесты и `conformance:agent`;
  - `packages/dart/codelab_acp_testing/fixtures/acp/` — три новые фикстуры, три обновлённых списка;
  - `apps/codelab_agent/test/`, `packages/dart/codelab_embedded/test/` — ожидания списков команд;
  - `apps/codelab_cli/test/e2e/` — вариант U-03, сценарий `--llm-script` и ожидания помощника `e2e_agent.dart`;
  - `apps/codelab_desktop/integration_test/command_palette_flow_test.dart` и `support/e2e_agent.dart`;
  - `packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart` — записи `knownGaps`.
- **Зависимости:** новых нет. Граф `README.md` не меняется, нового правила сторожа нет (design.md, D11).
- **Данные пользователя:** журнал сессии получает записи `mode_change`, `model_change` и `compaction` от команд — те же типы записей, что сегодня; формат журнала не меняется.
- **Документы:** `agent-core-architecture` §13.4, §13.6 (тексты ответов, MCP prompts — после MVP по Q10), §17.2.6 (отступления этапа 8.7 сняты, кроме кавычки); матрица — пометки «закрыто change» в K-02, R-08, U-03 после зелёного ночного `parity`.
