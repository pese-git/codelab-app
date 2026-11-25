# Опции, команды агента, план и палитра команд

Глава разбирает управляющие элементы сессии, которые агент объявляет по ходу работы: опции конфигурации (режим, модель), команды, план. Для каждого слой даёт готовое представление, чтобы app и CLI не разбирали протокол по-своему. В конце — каталог команд палитры, который склеивает команды хоста и агента.

Все три представления выводятся из снимка `AcpSession` при каждой публикации `SessionView` (`_SessionHandle._sessionFields`, [глава 2](02-state-ownership.md)); состояния, которого нет в протоколе, в них нет, кроме `configOptionInFlight`.

## Опции конфигурации

`SessionView.configOptions` — `List<ConfigOptionView>`:

| Поле | Что |
|---|---|
| `id` | идентификатор опции |
| `name`, `description` | подпись и пояснение |
| `currentValue` | текущее значение (`value` из списка) |
| `values` | `ConfigOptionValueView(value, name, description?)` |
| `category` | категория ACP: `mode`, `model`, `thought_level`; незнакомая приходит как есть |

`ConfigOptionView.of(SessionConfigOption)` разбирает единственный в ACP вид опции — `select`. По `category` хост находит, например, режим для шапки сессии (change `redesign-workbench-shell`, D7). Опции приходят от агента в ответе `session/new`, обновлении `config_option_update` и ответе `session/set_config_option`.

Изменить опцию — `SessionHandle.setConfigOption(configId, valueId)`:

1. Если `SessionView.configOptionInFlight` уже не `null`, вызов — пустая операция: второго запроса нет.
2. Иначе публикуется представление с `configOptionInFlight = configId`.
3. Бэкенд отправляет `session/set_config_option`.
4. Успех или ошибка снимают признак (`configOptionInFlight = null`); успех пишет диагностику `Set config option <id> to <value>.`, ошибка — `Failed to set config option <id>: …` и **повторно бросает** исключение.

Показываемое значение хост берёт из `currentValue`, пришедшего от агента, а не выставляет заранее: слой не показывает значение, которое агент ещё не подтвердил.

## Команды агента

`SessionView.agentCommands` — `List<AgentCommandView(name, description, hint?)>` из последнего `available_commands_update`. В ACP у команды нет отдельного вызова: хост вставляет `/<name> ` в текст промпта, а `hint` — подсказка к аргументам (пустая подсказка превращается в `null`).

## План

`SessionView.plan` — `List<PlanEntryView>` из последнего `SessionUpdate.plan`. Каждое обновление плана заменяет его целиком; план раннего хода остаётся текущим в следующем ходе, который своего не прислал; до первого обновления список пуст (`planOf`).

`PlanEntryView` несёт `content`, `status`, `priority` (значения ACP как есть) и, для списка задач CodeLab, поля из `_meta.codelab.task` пункта: `taskId`, `owner`, `blockedBy`, а также вычисленные `openBlockers` и `ownerLabel`.

- `openBlockers` — подмножество `blockedBy`: id пунктов, которые есть в текущем плане и не `completed`;
- `ownerLabel` — тип субагента из вызова `agent` сессии (`subagentTypesOf`: `id` → `type` по вызовам всех ходов и по запросам разрешения потомков), а без известного вызова — его `id`; для `owner: main` и без владельца метки нет;
- у плана стороннего агента без `_meta` поля задачи пусты: `taskId == null`, списки пусты.

Хост печатает `#<taskId> [<status>] <content>`, а `ownerLabel` и `openBlockers` — суффиксами. Разбор терпимый: `taskMetaOf` при любой неверной форме возвращает `null`, отказа обработки обновления нет. Тесты — `test/session/session_plan_test.dart`, `plan_task_meta_test.dart`.

## Каталог команд палитры

Палитра показывает команды двух источников: те, что хост умеет сам (у app — `/logs`, у CLI — свои), и команды агента активной сессии. Раньше список склеивал app, а отбирал виджет подстрокой — логика жила в UI. Теперь правила палитры — в `CommandCatalog`, единственном месте для app и CLI (change `add-command-palette-agent-commands`, D2–D4).

`HostCommand(id, name, label, description, isAvailable = true, searchAliases = [])` — команда хоста. `name` без `/`. `isAvailable: false` — заглушка «coming soon». `searchAliases` — дополнительные строки поиска: хост, показывающий `label` и `description` на своём языке, кладёт сюда те же тексты на другом (app — английские), чтобы команда находилась по обоим. Ядро язык не знает; CLI поле не заполняет.

`CatalogCommand` — `HostCatalogCommand(command)` или `AgentCatalogCommand(command)`; `name` общий.

```dart
final catalog = CommandCatalog(
  host: hostCommands,
  agent: session.current.agentCommands,
);
final shown = catalog.search(query); // пустой запрос — все команды
```

Каталог неизменяем; хост строит его заново, когда меняется `SessionView.agentCommands` активной сессии.

Правила слияния (`CommandCatalog` factory, D3):

- повтор имени у агента — одна команда, первая;
- заглушка хоста (`isAvailable: false`) вытесняется одноимённой командой агента;
- доступная команда хоста остаётся рядом с одноимённой командой агента;
- порядок: сначала команды хоста в его порядке, затем команды агента в порядке `available_commands_update`.

Поиск `search(query)` (D4): пробелы по краям и ведущий `/` снимаются, регистр не учитывается, пустой запрос — все команды. Ранги, лучшие первыми, внутри ранга — порядок каталога:

| Ранг | Правило |
|---|---|
| 0 | имя начинается с запроса |
| 1 | имя содержит запрос |
| 2 | запрос — подпоследовательность имени |
| 3 | `label` или `description` содержат запрос (у команды агента — имя и описание); у команд хоста ещё и `searchAliases` |

Подпоследовательность проверяется только по имени: по описанию она находила бы почти всё. Реальный прогон каталога с заглушкой `/compact`, одноимённой командой агента и повтором `plan`:

```text
all:     host:logs agent:compact agent:plan agent:explain
"/pl": agent:plan agent:explain
"lo": host:logs
"cmp": agent:compact
"file": agent:explain
"LOG": host:logs
"": host:logs agent:compact agent:plan agent:explain
```

Источник: временный скрипт с `CommandCatalog`. `/plan` стоит перед `/explain`: первый — по префиксу (ранг 0), второй содержит `pl` внутри имени (ранг 1). Заглушка `compact` хоста вытеснена командой агента; `file` находит `explain` по описанию («Explain the open file») — это ранг 3. Тест — `test/commands/command_catalog_test.dart`.

В CLI каталог использует разбор `/команд` и Tab-дополнение (`apps/codelab_cli/lib/src/repl/command_router.dart`).

Сквозной разбор настроек клиента и агента: [настройки на клиенте](settings-on-client.md), [алгоритм настроек агента](../../codelab_agent_core/doc/algorithms/settings.md).
