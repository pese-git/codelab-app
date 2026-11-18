# Ход, инструменты, разрешения, сессии

Документ для разработчика ядра. Обзор пакета — в [README](../README.md), правила — в [AGENTS.md](../AGENTS.md), устройство — в [agent-core-architecture](../../../../docs/architecture/proposals/agent-core-architecture.md) и разделах `docs/architecture/proposals/agent-core/`.

## Цикл хода

`runAgentLoop` (`lib/src/loop/agent_loop.dart`) проводит один ход: вызывает модель, исполняет вызовы инструментов из ответа и повторяет, пока модель зовёт инструменты или приходит новый ввод. Функция не знает ни хранилища, ни протокола (LOOP-6), состояние между ходами держит `Agent` (`lib/src/loop/agent.dart`) в сессии. `TurnEnded` — всегда последнее событие хода, ровно одно, даже при исключении в хуке (LOOP-1). Бюджет хода проверяется на границе шага (LOOP-12).

События хода — sealed-иерархия `AgentEvent` (`lib/src/loop/agent_events.dart`). Новое событие добавляется веткой иерархии, а не условием в цикле. `AgentSession.prompt` возвращается после `TurnEnded` и записи журнала; к этому моменту события хода доставлены подписчикам `events`.

Встроенные слэш-команды (`compact`, `mode`, `model`, `status`, `usage`, `config`, `mcp`, `help`) исполняются в `prompt` без модели и без записи в журнал, но занимают слот хода.

## Инструменты

Базовый класс — `AgentTool` (`lib/src/tools/agent_tool.dart`): имя, описание, схема параметров, уровень `ToolTier` (`read`, `write`, `network`, `exec`; по умолчанию `exec` — неизвестное считается самым опасным, TOOL-5), вид `ToolKind` и доверие к выводу `ContentTrust`.

Реестр `ToolRegistry` собирает `buildAgentCore`: `read`, `write`, `edit`, `task_create`, `task_update`, `task_list`, `task_get` — всегда; `exec` — при `shellExec`; `ls` и `search` — при `fileListing`. Рантайм добавляет инструменты сессии: `skill`, `agent` (субагенты) и инструменты MCP-серверов.

Единственный код, который вызывает `AgentTool.execute`, — `ToolCallExecutor` (`lib/src/tools/executor.dart`, TOOL-1). Вызов идёт двумя фазами: `announce` объявляет все вызовы пакета по порядку ответа модели (`ToolCallStarted`), затем `complete` исполняет каждый. Шаги `complete`:

1. заблокированный вызов (`MisuseBreaker`) не проверяется и не исполняется;
2. проверка аргументов по схеме инструмента и `preflight`; ошибка возвращается модели текстом;
3. хуки `beforeToolCall` по порядку; первый, вернувший `Block`, прекращает вызов;
4. блокировка пути (`PathLock`), чтобы вызовы к одному пути шли по очереди (TOOL-7);
5. `execute`, затем хуки `afterToolCall` и `ToolCallFinished`.

Инструмент получает окружение `ToolContext.env` — оно уже ограничено рабочей папкой сессии (`BoundedEnv`): путь за её пределами возвращается как `Err(FileError(FileErrorCode.outsideWorkspace, …))`, а не исключением.

## Разрешения

Политика `PermissionPolicy` (`lib/src/permissions/policy.dart`) — первый хук `beforeToolCall` каждой сессии; хуки хоста идут после неё (`SessionSpec.extraBeforeToolCall`). Решение зависит от режима и уровня инструмента (`tierDecision` в `modes.dart`):

| Режим (`PermissionMode`) | `read` | `write` | `exec` | `network` |
|---|---|---|---|---|
| `alwaysAsk` | вопрос | вопрос | вопрос | вопрос |
| `write` | разрешено | вопрос | вопрос | вопрос |
| `acceptEdits` | разрешено | разрешено | вопрос | вопрос |
| `yolo` | разрешено | разрешено | разрешено | вопрос |
| `autopilot` | разрешено | разрешено | разрешено | запрет |

Клиент видит режимы как `ModeId`: `plan`, `ask`, `standard`, `accept-edits`, `bypass`; `autopilot` включается только флагом запуска, не идентификатором режима. Поверх таблицы действуют правила конфигурации `permissions.*` (`PolicyRules`), критические шаблоны команд, защита путей конфигурации агента (PERM-11) и решения «всегда» (`allowAlways`, `rejectAlways`), которые хранятся в `PermissionDecisionStore` сессии.

Вопрос задаёт `PermissionGate.request(PermissionRequest, CancelToken)`; `PermissionRequest` несёт `toolCallId`, инструмент, уровень, итоговые аргументы (PERM-6), места и diff. Без шлюза ответ — отказ (PERM-5). Время ожидания человека вычитается из времени хода (`ApprovalWaitMeter`). Ядро не знает, как шлюз спрашивает пользователя: `codelab_agent_acp` реализует его через ACP-запрос `session/request_permission`.

Исключение из общего правила про одобрение (ACP-методы `fs/*` и `terminal/*`) описано в `AGENTS.md` репозитория, §10.

## Сессии и журнал

`AgentRuntime` создаёт (`createSession`), загружает (`loadSession`) и перечисляет (`listSessions`) сессии. Журнал — дерево записей (`lib/src/session/records.dart`); хранилище отвечает только за байты, а разбор, ремонт и проекции живут в ядре (`SessionStore`). Каждая запись дописывается одной полной строкой (SES-4), точки восстановления сбрасываются на носитель.

Сжатие контекста (`lib/src/compaction/`) включается capability `compaction` и настройкой конфигурации; оно заменяет историю краткой выжимкой и пишет `ContextCompacted`.

## Субагенты и список задач

Субагенты — инструмент `agent` (`lib/src/subagents/`). Особых случаев для детей в цикле, исполнителе и политике нет: потомок — обычная сессия со своим журналом, набором инструментов и режимом не мягче родительского. Вопрос потомка идёт через `SubagentPermissionGate` в шлюз корневой сессии, а отчёт потомка оборачивается как недоверенный вывод (`wrapSubagentReport`). Лимиты (`subagents.*`: глубина, одновременные потомки, запуски за ход, шаги, время) читаются из `SubagentsConfig` при каждом запуске, поэтому перезагрузка конфигурации действует на следующий запуск. Подробности — `agent-core/17-3-subagents.md` и спецификация `openspec/specs/agent-subagents`.

Список задач — порт `TaskList` и инструменты `task_*` (`agent-core/17-16-task-list.md`); состояние восстанавливается из журнала корневой сессии.

## Промпты

Тексты промптов лежат в `prompts/**/*.md` и превращаются в Dart-константы `lib/src/prompts/prompts.g.dart`: на web нет файловой системы, а ядро файлов само не читает. Проверка синхронности — `melos run prompts:check`. Тексты пишутся заново; копировать чужие промпты запрещено (AGENTS.md репозитория, §5).
