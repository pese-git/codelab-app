## Context

Источники:
- `agent-core-architecture` [§13.4](../../../docs/architecture/proposals/agent-core/13-acp-adapter.md) (элементы и порядок команд), §13.6 (список MVP, правила разбора 1–3, «Этап 8.10»), §13.7 (`/compact` → `Compacted: X → Y tokens.`), [§9.2, §9.5](../../../docs/architecture/proposals/agent-core/09-compaction.md) (`manual`, `SummaryRequest.focus`), [§17.2.6](../../../docs/architecture/proposals/agent-core/17-2-skills-and-templates.md) (алгоритм `expandCommand`, отступления этапа 8.7), §17.5.6 (строки `/status` о конфигурации);
- матрица целей — строки K-02, R-08, U-03, R-20, E-24; решения пользователя Q9 и Q10 (2026-11-10) в design.md change [`switch-default-agent-to-dart`](../switch-default-agent-to-dart/design.md);
- спецификации `agent-slash-commands`, `agent-compaction`, `agent-acp-server`, `agent-binary`, `codelab-cli`, `testing-quality`, `acp-golden-fixtures`;
- ACP — только `docs/protocols/acp/protocol/14-Slash Commands.md` («Commands are run as part of regular prompt requests»), `05-Prompt Turn.md`, `13-Session Config Options.md`, `12-Session Model.md`;
- `docs/architecture/acp-boundary.md`, `concurrency.md`, `permissions.md`, `observability.md`, `testing.md`; `packages/dart/codelab_agent_core/AGENTS.md`.

Что есть в коде:
- **Механизм встроенных команд** (design.md change `add-config-writer-and-reload`, D12): `BuiltinCommands` в `codelab_agent_core/lib/src/commands/builtin_commands.dart` объявляет `config` и `mcp`, `match` узнаёт `/config` и `/mcp`, `AgentSession.prompt` исполняет без модели: `TurnStarted`, одно сообщение агента, `TurnEnded(endTurn)`, слот хода, отмена, отказ `AgentError(hook)`, журнал не пишется.
- **Резервные имена** (`reservedCommandNames`, `command_template.dart`): `compact`, `mode`, `model`, `status`, `help` и др. — шаблон с таким именем не загружается (`reserved_name`).
- **Сжатие**: `CompactionTrigger.manual` и `focus` в компакторе есть (`compaction/compactor.dart`), команды `/compact` нет.
- **Смена режима и модели**: `AgentSession.setMode`, `setModel` (`runtime/agent_session.dart`) — путь `session/set_config_option`; проекция `ModeChanged` → `current_mode_update` (+ `config_option_update`, если смена не ответ на запрос клиента), `ModelOptionsChanged` → `config_option_update` с полным снимком опций, построенным из текущего состояния сессии (событие перезагрузки каталога, D8 change `add-config-writer-and-reload`; отдельного события смены опции в ядре нет).
- **Состояние для `/status`**: `ConfigStatus` (`lastFailureAt`, `lastIssues`, `pendingRestartKeys`), `McpSessionTools.servers`.
- **Клиенты**: `CommandCatalog` (`codelab_client_core`) уже объединяет команды хоста и агента; одноимённая команда агента — `/agent:<имя>` в CLI.
- **E2E**: `codelab-agent serve --stdio --llm-script` и `scriptedEmbeddedAgentOpener` собирают ядро **без** `ConfigSource` (D13 change `add-config-writer-and-reload`; `serve_config.dart`, `agent_host.dart`): команда `/config` в e2e со сценарием не объявляется, даже если передать `--config`.

Ограничения: `AGENTS.md` §2 (не скрывать ошибки), §3.4 (ACP не придумывать), §9 и §12 (слот хода, отмена, поздние события), §10 (разрешения), §13 (пропорциональность), §16 (без пользовательских строк в логах); `codelab_agent_core/AGENTS.md` §2 — TDD.

## Goals / Non-Goals

**Goals:**
- закрыть K-02, R-08 и U-03 (и снять пропуск, из-за которого `app:command_palette_flow_test.dart` не закрывает K-02 и R-20 в режиме `dart`);
- одно место разбора и исполнения команд в ядре для всех хостов: `codelab-agent`, встроенного агента app и CLI;
- поведение `agent-core-architecture` §13.6 для неизвестной команды.

**Non-Goals:** MCP prompts (E-24), команды и строки `/status` после MVP, `System prompt` и `Tools disabled` в `/status`, `CommandFailed` для незакрытой кавычки, изменения ACP, изменения клиентских команд, источник конфигурации у `--llm-script` (proposal.md, «Не входит»).

## Decisions

### D1. Где живут команды

Расширяется существующий `BuiltinCommands` в `codelab_agent_core`: объявление, разбор и тексты всех встроенных команд — в одном файле, исполнение — в `AgentSession.prompt` тем же путём, что `/config` и `/mcp` (D12 change `add-config-writer-and-reload`). Новые порты — функции, как у `reconnect` и `setEnabled`: ручное сжатие (`compactNow(focus, cancel)`), смена режима и модели (`setMode`, `setModel` сессии), снимок состояния для `/status` (модель, режим, `cwd`, сводка MCP, `ConfigStatus`), список команд для `/help`. ACP-адаптер (`codelab_agent_acp`) кода не получает: команды отвечают событиями ядра, которые уже проецируются.

*Альтернативы:*
- (а) обрабатывать команды в ACP-адаптере — встроенный агент app и `codelab` идут через тот же мост, но `AgentSession` вне ACP (тесты ядра, будущие хосты) остался бы без команд; §13.6 и D12 уже держат команды в ядре;
- (б) класс на команду (`CompactCommand`, `HelpCommand` …) с общим интерфейсом — пять команд с фиксированными текстами не оправдывают иерархию (`AGENTS.md` §13); перечисление имён встроенных команд (`enum`) и `switch` по нему в одном диспетчере проще: анализатор проверяет исчерпываемость `switch` по `enum`, и новая команда не останется без исполнения или текста.

### D2. Объявление и порядок

`AgentSession.commands`: `compact` (только при capability `compaction`), `mode`, `model`, `status`, `config` (как прежде), `mcp` (как прежде), `help`, затем шаблоны — правило порядка §13.4. Элементы — побайтово по §13.4 (MVP-подсказка `model` — `provider/model`). Список строится при открытии сессии и не меняется до закрытия (D9 change `add-config-writer-and-reload`).

*Альтернатива:* объявлять `/model` только при каталоге больше одной модели — каталог меняется перезагрузкой, а список нет; команда без выбора честно отвечает текущей моделью.

### D3. Порядок разбора промпта

Разбирается только первый текстовый блок (как у шаблонов):
1. не начинается с `/` или имя не соответствует `^[A-Za-z0-9][A-Za-z0-9:_-]*$` → промпт уходит модели без изменений (`/usr/bin/foo`, ведущий пробел);
2. объявленная встроенная команда → исполнение без модели;
3. шаблон → разворачивание (как прежде);
4. иначе → неизвестная команда (D4).

Слово команды и `raw` (остаток после ведущих пробелов без завершающего `\r?\n`) для встроенных команд и шаблонов определяет одна функция разбора строки команды (`commands/command_line.dart`), чтобы правила шагов 1–4 не разошлись. Шаг MCP prompt (§17.2.6, шаг 6) не добавляется: E-24 после MVP (Q10). Шаблон с именем встроенной команды уже не загружается (`reserved_name`), поэтому конфликта шагов 2 и 3 нет; поведение резервных имён не меняется.

### D4. Неизвестная команда

Ответ `Unknown command: /<name>. Run /help to list commands.` одним сообщением агента, `TurnEnded(endTurn)`, модель не вызывается, журнал не пишется (§13.6, правило 3; §17.2.6, шаг 7). `<name>` обрезается до 64 рун. Лог `command.unknown {session_id, name_bytes}` без имени; `name_bytes` — длина имени в байтах UTF-8 без ведущего `/`, до обрезки (решение оркестратора 2026-11-10: показывает размер ввода для диагностики, не раскрывая его).

Необъявленные `/config` (WebSocket, нет `ConfigSource`) и `/mcp` (нет capability `mcp`) — тоже неизвестные команды (рекомендация по Q6). Ответ не раскрывает ни путей, ни текстов конфига, поэтому R0-3 соблюдается; модель при этом не получает текста, который пользователь набирал как команду.

*Альтернативы:*
- (а) оставить «уходит модели как текст» — противоречит R-08 (Must) и §13.6;
- (б) JSON-RPC ошибка `-32602` — R-08 прямо требует «текстовый ответ, а не ошибка протокола».

### D5. `/compact [focus]`

- Вызов компактора с `CompactionTrigger.manual`; непустой `raw` — `focus`, пустой — без `focus` (agent-compaction «Указание focus»).
- Если идёт фоновое `afterTurn`, команда ждёт его завершения (как следующий `prompt`, §9.5): двух сжатий одной ветки одновременно нет.
- Итог: `Compacted: <tokensBefore> → <tokensAfter> tokens.` (§13.7); `NothingToCompact` — `Nothing to compact.` (рекомендация по Q10).
- `CompactionFailed` — `AgentError(compaction)` без `retrying`, `TurnEnded(failed)`, мост отвечает `-32603` с классом ошибки (§13.8) — как отказ провайдера в обычном ходе (рекомендация по Q9: ошибку модели не скрываем текстом, `AGENTS.md` §2).
- Отмена во время резюме — `CancelledException` компактора → `TurnEnded(cancelled)`, записи `compaction` нет (CMP-4).
- Запись `compaction` пишется как при любом сжатии; запись промпта `/compact` и ответа — нет.
- Без capability `compaction` команда не объявлена и, значит, неизвестная.

### D6. `/mode` и `/model`

- Исполнение — `AgentSession.setMode` / `setModel`: те же записи (`mode_change`, `model_change`), события и правила `effort`, что у `session/set_config_option`. Это не обход политики разрешений: режим меняет тот же клиент, что мог бы прислать `session/set_config_option`; `autopilot` режимом сессии не является (§10.5) и отвечает `Unknown mode`.
- Порядок событий: сначала событие смены (`ModeChanged` / `ModelOptionsChanged`; для `/model` событие публикует команда после `setModel`, оно буферизуется в истории хода — MODIFIED-дельта `agent-runtime`), затем сообщение агента, затем `TurnEnded` (рекомендация по Q3). В ACP — `current_mode_update` и `config_option_update` (смена не ответ на запрос клиента, §13.6 п. 4), `agent_message_chunk`, ответ на `session/prompt` — все уведомления до ответа (ACP-3).
- Тексты — спецификация `agent-slash-commands`, «Встроенные команды MVP» (рекомендация по Q3).
- Записи смены режима и модели — данные сессии: `session/load` восстанавливает выбранные режим и модель, реплей не содержит текстов команд.

### D7. `/status` и `/help`

- `/status`: `Model`, `Mode`, `Working directory`, `MCP servers`; строки `Config` и `Restart required` — только если в сессии объявлена `config` (рекомендация по Q2): по WebSocket `/config` скрыт ради R0-3, и `/status` не должен раскрывать то же другим путём. Строка `Model` — короткая (`Model: <provider/model>`); происхождение окна из §2.12.2 — после MVP или по ответу на Q2.
- `/help`: `Commands:` и строки `/<name>[ <hint>] - <description>[ (template)]` в порядке `AgentSession.commands` (§17.2.9: «`/help` выводит тот же список с источником в скобках»; рекомендация по Q1).
- Обе команды не принимают аргументов: лишние игнорируются.

### D8. Фикстуры

- Новые: `acp/slash-compact`, `acp/slash-help`, `acp/slash-mode-plan` — готовы (шаг красных тестов итерации 2 change `switch-default-agent-to-dart`), переносятся сюда как красные тесты. Сценарий приёмки R-08 (`/help`, `/mode plan`, `/nope`) целиком покрывает `acp/slash-mode-plan`; если перенесённая фикстура не содержит `/nope`, кадр дописывается со ссылкой на «Неизвестная команда».
- Обновляются точные списки `availableCommands` в `acp/available-commands-no-tools`, `acp/prompt-template-command`, `acp/slash-mcp-list` (acp-golden-fixtures «Правила изменения фикстур»: ссылка на это требование). Фикстуры с `$any` не меняются.
- Фикстуры с ролью только `agent`: клиентский прогон их пропускает. `test-scenario --agent embedded` проигрывает `slash-help` и `slash-mode-plan` (без `setup.*`); `slash-compact` с `setup.config` пропускается по правилу cli-scenario-driver.

### D9. Интеграционный тест палитры app

Файл `command_palette_flow_test.dart` делится на два теста: `scripted-only` — нынешний полный сценарий (команда `plan` с подсказкой, ответ scripted-агента); тест без тега — встроенная `compact` Dart-агента во всех режимах: вытеснение заглушки, вставка без `session/prompt`, отправка, реплика и ответ из помощника `integration_test/support/e2e_agent.dart`. В файле остаётся тест без тега, поэтому «No tests ran» не возникает, и пропуск `!isScripted` больше не нужен. В `feature/*` тест только компилируется и анализируется; на устройстве — в `release/*` (`AGENTS.md` §21).

*Альтернатива:* оставить пропуск в `dart` — тогда `app:command_palette_flow_test.dart` в обязательном источнике `app/dart-agent` всегда `skipped`, и K-02 с R-20 на итоговом прогоне ворот открыты.

### D10. E2E CLI U-03

- Вариант `cli/slash-menu-merges-agent-commands` без тега `scripted-only` для `dart` и `embedded`: сценарий `--llm-script` режима `withAvailableCommands` (или `normal`, если ход модели не нужен) и ожидания из `test/e2e/support/e2e_agent.dart` — какие команды агента объявляет каждый вид агента. Нынешняя проверка scripted-агента (`plan`, `/agent:plan`) остаётся отдельным тестом с тегом.
- **Одноимённые команды.** У Dart-агента со сценарием нет `ConfigSource`, поэтому агентская `/config` не объявляется, и решение «в режиме `dart` запускать агента с конфигом» её не даст: `--config` при `--llm-script` не создаёт источник (D13 change `add-config-writer-and-reload`), у `scriptedEmbeddedAgentOpener` его тоже нет. Правило слияния одноимённых команд (`/agent:<имя>`) проверяется на `/help`, `/mode` и `/model`, которые теперь объявляет агент и у которых есть клиентские тёзки (рекомендация по Q8; codelab-cli, сценарий «Одноимённые команды клиента и Dart-агента»).

### D11. Пакеты, зависимости, сторож, граф

- Затронутые пакеты по ADR-0002: `codelab_agent_core` (логика), `codelab_agent_acp` (тесты), `codelab_acp_testing` (фикстуры), `codelab_embedded` и `apps/codelab_agent` (тесты), `apps/codelab_cli` (e2e), `apps/codelab_desktop` (интеграционный тест), `codelab_architecture_tests` (`knownGaps`).
- Новых пакетов и зависимостей нет; направление зависимостей не меняется; нового правила в `test/support/rules.dart` нет; граф `README.md` не меняется.
- Web-безопасность: правки ядра без `dart:io` (ядро web-безопасно); `web-compile` — по правилу §21, потому что меняется `codelab_agent_core`, который входит во встроенный агент.
- Allowlist ядра (PKG-2) не затрагивается.

### D12. Наблюдаемость

- `command.builtin {session_id, name, subcommand}` для новых команд: `subcommand` — `run` у `compact`, `set` / `show` / `unknown` у `mode` и `model` (`unknown` — значение не найдено), `show` у `status` и `help`. Аргументы, указание `focus` и имена моделей в лог не идут.
- `command.unknown {session_id, name_bytes}` (info).
- Сжатие пишет свои события (`compaction.*`) с `trigger: manual`.

### D13. Итерации

Один pull request в `develop` из `feature/add-agent-builtin-slash-commands`; внутри — порядок `tasks.md`: документы (0), красные тесты (1), реализация ядра (2), клиенты (3), закрытие строк матрицы (4).

### D14. Отмена команд, меняющих состояние

Решение оркестратора (2026-11-10) по гонке отмены и завершения (`AGENTS.md` §9, §12; `docs/architecture/concurrency.md`). `/compact`, `/mode` и `/model` всегда дожидаются своей работы, а итог хода в ядре (`TurnEnded`, `TurnResult`) — по факту:
- смена применена (запись `compaction`, `mode_change` или `model_change` дописана в журнал) → событие смены, если есть, сообщение агента и `TurnEnded(endTurn)`, даже если отмена пришла после применения;
- отмена успела до применения → `TurnEnded(cancelled)` без записи, без события смены и без сообщения;
- все события хода команды публикуются до его `TurnEnded`; после итога событий этого хода нет.

На проводе ACP итог ядра не меняет ответа: при любом `session/cancel` мост отвечает на `session/prompt` `stopReason: cancelled` (ACP-5, `turnResponse` с `cancelRequested`; `docs/protocols/acp/protocol/05-Prompt Turn.md` «Cancellation»: агент MUST ответить `cancelled` после отправки ожидающих уведомлений). Кадры смены, применённой до отмены (`current_mode_update`, `config_option_update`), и `agent_message_chunk` уходят до этого ответа; мост кода не получает (agent-acp-server, сценарий «Отмена /mode после применения»).

Закрытие сессии во время команды отменяет её и ждёт её завершения до закрытия журнала: запись, начатая командой, дописывается целиком или не начинается.

*Альтернативы:*
- (а) в ядре давать `TurnEnded(cancelled)` при любой отмене, даже после применения, — итог хода в ядре разошёлся бы с журналом и событиями: запись `mode_change` или `compaction` есть, событие смены опубликовано, а ход «отменён»; потребители ядра вне ACP (тесты, будущие хосты) и `TurnResult` получили бы ложный факт (`AGENTS.md` §2, приоритет 4);
- (б) откатывать применённую смену при отмене — журнал append-only, отката записи нет, а компенсирующая запись усложнила бы реплей без пользы;
- (в) закрывать журнал, не дожидаясь команды, — поздняя запись после закрытия либо теряется, либо пишется в закрытый журнал (CMP-4, §9 «late events»).

## Risks / Trade-offs

- **Промпт `/слово …` больше не доходит до модели (BREAKING).** Пользователь, который начинает сообщение с `/etc is weird` или `/tmp`, получит `Unknown command`. *Смягчение:* так требует R-08 и §13.6; ответ называет `/help`; пробел перед `/` или любой другой первый символ отправляет текст модели. Решение — Q5.
- **Гонка `/compact` и фонового сжатия** (`AGENTS.md` §9, §12): команда ждёт `afterTurn`, слот хода исключает параллельный промпт; отмена во время резюме не оставляет записи. Поздний результат суммаризатора после отмены выбрасывается компактором (CMP-4).
- **Отмена и поздние события.** Команды — ход без модели в слоте сессии; гонку отмены и применения решает D14: итог — по факту применения, все события хода до `TurnEnded`, событие смены уходит до ответа (ACP-3). Новых подписок нет.
- **Разрешения** (§10): `/mode bypass` — тот же уровень доверия, что `session/set_config_option` от того же клиента; команда разбирается только из первого текстового блока промпта пользователя, не из вывода модели, инструментов или ресурсов; `autopilot` недоступен. Containment не меняется.
- **Раскрытие данных по WebSocket:** `/status` без строк конфигурации при скрытом `/config` (D7); `cwd` — каталог, который выбрал сам клиент; имена MCP-серверов по WebSocket не появляются, потому что capability `mcp` там выключена.
- **Forward compatibility ACP:** протокол не меняется; клиенты без поддержки `available_commands_update` просто вводят команды текстом.
- **Широкое обновление ожиданий.** Списки команд перестают быть пустыми — меняются фикстуры и тесты `agent_host_*`, встроенного агента, e2e. *Смягчение:* задача 1.6 — поиск всех точных ожиданий списка по `availableCommands`, `agentCommands` и `session.commands`.

## Migration Plan

1. Журналы сессий совместимы: новые команды пишут только существующие виды записей.
2. Сохранённые профили и конфигурация не меняются.
3. Откат — revert pull request; записи `mode_change` / `model_change` от команд остаются валидными.

## Решения пользователя 2026-11-10

Все ответы — по рекомендации; спецификации и задачи написаны под них и не менялись.

- **Q1** (а): `/help` — `Commands:` и по строке `/<name>[ <hint>] - <description>[ (template)]`.
- **Q2** (а): `/status` — `Model`, `Mode`, `Working directory`, `MCP servers`; `Config` и `Restart required` — только при объявленной `/config`.
- **Q3** (а): сначала смена (`current_mode_update` / `config_option_update`), затем текст, затем `end_turn`; неизвестное значение — текстом.
- **Q5** (а): неизвестная `/x` — всегда `Unknown command`, модель не вызывается (BREAKING, см. «Risks»).
- **Q6** (а): необъявленные `/config` и `/mcp` — неизвестная команда.
- **Q9** (а): отказ сжатия — `AgentError(compaction)`, `TurnEnded(failed)`, `-32603`.
- **Q10** (а): `/compact` объявляется только при capability `compaction`; пустой регион — `Nothing to compact.`.

Технические решения оркестратора (2026-11-10): Q4 (а), Q7 (а), Q8 (а), Q11 (а).

## Open Questions

Открытых вопросов нет; история — в «Решения пользователя 2026-11-10» и в списке ниже.

- **Q1. Формат `/help`.** (а) `Commands:` и `/<name>[ <hint>] - <description>[ (template)]` по строке на команду в порядке списка; (б) только имена через запятую; (в) таблица в ограде, как `/mcp list`. *Рекомендация:* (а) — §17.2.9 требует «тот же список с источником в скобках», строки читаются и в Zed, и в CLI.
- **Q2. Что показывает `/status`.** (а) четыре строки `Model`, `Mode`, `Working directory`, `MCP servers` плюс `Config` / `Restart required` только при объявленной `/config`; (б) то же и строка `Model` с происхождением окна по §2.12.2 (`(context … from …, max output … from …)`); (в) все строки всегда, включая WebSocket. *Рекомендация:* (а) — минимум §13.6 без раскрытия конфигурации по WebSocket (R0-3); (б) добавить позже, когда клиенты будут показывать окно модели.
- **Q3. `/mode` и `/model`: порядок кадров и тексты.** (а) смена (`current_mode_update` + `config_option_update` / `config_option_update`), затем текст `Mode: plan.` / `Model: <id>.`, затем `end_turn`; (б) текст до смены. Без аргумента — текущее значение и список (`/mode`) или подсказка (`/model`); неизвестное значение — `Unknown mode: …` / `Unknown model: …` текстом, без ошибки протокола. *Рекомендация:* (а) — клиент обновляет индикатор режима до того, как покажет ответ; так же эхо `ModeChanged` устроено для `session/set_config_option`.
- **Q4. Конфликт имён с шаблонами проекта.** Имена `compact`, `mode`, `model`, `status`, `help` уже зарезервированы с этапа 8 (`reserved_name`), шаблоны с ними не загружаются. (а) ничего не менять; (б) разрешить шаблону перекрывать встроенную команду. *Рекомендация:* (а) — SKL-7: команда не должна молча менять смысл в зависимости от файлов проекта, особенно в недоверенном окружении.
- **Q5. Неизвестная `/x` при наличии шаблонов и слова-пути.** (а) по §13.6: любое слово по регулярному выражению без встроенной команды и шаблона — `Unknown command`, модель не вызывается (в том числе `/etc`, `/tmp`); (б) отправлять неизвестную команду модели, если у сессии нет ни одного шаблона; (в) отправлять модели, если после имени есть текст. *Рекомендация:* (а) — R-08 (Must) и §13.6 не делают исключений, а предсказуемость важнее эвристик; пробел перед `/` остаётся способом отправить такой текст модели.
- **Q6. Необъявленные `/config` и `/mcp`.** (а) неизвестная команда; (б) как сейчас — текст модели. *Рекомендация:* (а) — единое правило §13.6; ответ не раскрывает конфигурацию (R0-3).
- **Q7. Незакрытая кавычка в аргументах шаблона.** (а) оставить закрытие концом ввода (D8 change `add-agent-project-files`), §17.2.6 обновить; (б) ввести `Unterminated quote in arguments.` по §17.2.6. *Рекомендация:* (а) — ни одна строка Must этого не требует, а (б) меняет поведение работающих шаблонов.
- **Q8. `/config` в e2e U-03 в режиме `dart`.** Решение «запускать агента с конфигом» не даёт агентской `/config`: при `--llm-script` источника конфигурации нет (D10). (а) проверять слияние одноимённых команд на `/help`, `/mode`, `/model`; (б) дать `--llm-script` источник конфигурации при `--config` — меняет D13 change `add-config-writer-and-reload` и спецификацию `agent-binary` («Сценарий без перезагрузки»). *Рекомендация:* (а).
- **Q9. Отказ сжатия по `/compact`.** (а) `AgentError(compaction)` → `TurnEnded(failed)` → `-32603` (§13.8); (б) текст `Compaction failed (<class>). See the agent log.` и `end_turn`. *Рекомендация:* (а) — ошибка провайдера не прячется за «успешным» ходом (`AGENTS.md` §2), как в обычном ходе.
- **Q10. `/compact` без возможности сжать.** (а) объявлять только при capability `compaction`; текст `Nothing to compact.` при пустом регионе; (б) объявлять всегда, без capability — `Compaction is off.`. *Рекомендация:* (а) — список отражает доступные действия.
- **Q11. Доказательство app-части K-02.** В режиме `dart` палитра отправляет `/compact` в новой сессии, и ответ — `Nothing to compact.`. (а) достаточно: сжатие доказывает фикстура `acp/slash-compact`, app — доставку команды и показ ответа; (б) сценарий модели с длинной историей, чтобы в app был `Compacted: …`. *Рекомендация:* (а).
