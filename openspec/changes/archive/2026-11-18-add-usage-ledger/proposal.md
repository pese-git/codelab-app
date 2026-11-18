## Why

Change `add-usage-extension` дал клиенту живой usage: агент шлёт `_codelab/session/usage` после шага, хода и сжатия, а клиент держит только последний ход и сумму сессии (`UsageView.lastTurn`, `UsageView.session`). Истории ходов и шагов у клиента нет. После `session/load` сумма сессии неполная: ранние ходы в неё не входят, и агент ставит причину `beforeLoad` (D6 того change, R5). Поэтому после перезапуска клиента или внешнего агента сумма почти всегда показывается с «~». Вызовы суммаризатора в сумму сессии не входят совсем (R2 того change).

Следующий change, `add-desktop-usage-pane`, — панель Usage по артборду «17 Usage pane». На артборде карточки Input, Output, Cost и Turns · steps, кнопка «Rebuild from log», таблица «Per turn» с раскрытием до шагов, таблица моделей, Export CSV и прогресс бюджета хода. Для неё клиенту нужна история ходов и шагов всей сессии, в том числе после `session/load`. Ни уведомление, ни транскрипт её не дают: в транскрипте нет usage, а уведомления до загрузки не приходили.

Change вводит журнал usage сессии (L-29, `agent-core` §12.6.1): свёртку журнала сессии по ходам, шагам, моделям, субагентам и суммаризатору. Это второй из четырёх usage-changes (`delivery-roadmap.md` §4.6, §6.2 п. 1): `add-usage-extension` → `add-usage-ledger` → `add-desktop-usage-pane` → `add-session-deadline`.

## What Changes

Решения пользователя 2026-11-17 по Q1–Q9 внесены (design.md, «Решения пользователя 2026-11-17»): все вопросы — вариант (а).

- **Ядро: свёртка журнала** (D1, D2). Чистая функция `buildUsageLedger` превращает записи журнала сессии в итоги: всего, по ходам с их шагами, по моделям, по субагентам и по суммаризатору. Ход журнала начинается со слов пользователя (`isUserWords`, кроме `steer`). Шаг — запись `assistant` с usage. Причины неполноты считаются так же, как у живых снимков: `noUsage` берётся из записи, `noPrice` — из каталога моделей в момент показа, в файл она не пишется (Q4).
- **Ядро: файл `usage.json`** (L-29, D3, Q5). Производный кэш рядом с журналом. Ядро пишет его лениво: на `/usage` и на запрос журнала, если файла нет или он устарел, и всегда при `rebuild`. Запись идёт через новый необязательный порт хоста `UsageLedgerStore`. Без порта (встроенный агент на web, тесты) свёртка живёт только в памяти. Формат — §12.6.1 и список ходов (`turns`); `byBranch` и `inherited` откладываются до веток и fork (§17.6).
- **Ядро: usage суммаризатора** (D4, Q6). `Summarizer` возвращает текст вместе с usage и моделью ответа. Запись `compaction` получает `details.usage` (форма уже описана в §8.2.4), событие `ContextCompacted` — поле `usage`. Ход usage суммаризатора не включает, сумма сессии и журнал — включают (`summaries`).
- **Встроенная команда `/usage [rebuild]`** (D5, Q7). Текстовый отчёт по §12.6.1 без вызова модели и без записи в журнал (ACP-12). В списке команд `usage` встаёт сразу после `status` (порядок §13.4). Неизвестная цена выводится словом `unknown`, а не `$0.0000`.
- **Расширение ACP: запрос `_codelab/session/usage/ledger`** (клиент → агент; D6, D7, Q1, Q2, Q8). Агент объявляет его ключом `usageLedger: {"version": 1}` в `agentCapabilities._meta.codelab`. В ответе журнал сессии: итог, ходы с шагами (модель, токены, стоимость, причины, `toolCallIds` для подписи из транскрипта), модели, субагенты, суммаризатор, состояние файла и `seq` последнего снимка. Параметр `rebuild: true` — это кнопка «Rebuild from log».
- **Полная сумма после `session/load`** (D8, Q3). При загрузке адаптер засевает агрегаты сессии свёрткой журнала. Причину `beforeLoad` агент CodeLab больше не ставит. Сразу после ответа на `session/load` соединение, объявившее `usage`, получает снимок `_codelab/session/usage` с новым поводом `trigger: "load"`. Строка статуса и статус-строка CLI показывают сумму сессии до первого хода. Клиент v1 принимает незнакомый повод без правки (D2 change `add-usage-extension`).
- **Клиент** (D9, D10). `codelab_client_acp` видит ключ `usageLedger` и шлёт запрос. `codelab_client_core` разбирает ответ терпимо (`UsageLedgerDecoder`) и публикует `SessionView.usageLedger` — состояние загрузки и модель журнала. Операция `ClientWorkspace.refreshUsageLedger(sessionId, {rebuild})` защищена от устаревших ответов. Снимок `load` не теряется, если пришёл раньше регистрации сессии или раньше сброса usage при загрузке.
- **Фикстуры** (D11): `acp/slash-usage`, `acp/usage-ledger-request`, `acp/usage-ledger-rebuild`, `acp/session-load-usage-full`, `acp/compact-usage-summary`. Фикстура `acp/session-load-usage-partial` заменяется на `acp/session-load-usage-full`. Списки команд в фикстурах с `available_commands_update` дополняются `usage`.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-sessions`: свёртка журнала usage, файл `usage.json`, порт `UsageLedgerStore`.
- `agent-compaction`: usage суммаризатора в записи `compaction` и в `ContextCompacted`.
- `agent-slash-commands`: встроенная команда `/usage [rebuild]`, место `usage` в списке команд.
- `agent-acp-server`: ключ `usageLedger` в `initialize`, запрос `_codelab/session/usage/ledger`, снимок `load`, полная сумма сессии после загрузки вместо `beforeLoad`, суммаризатор в сумме сессии.
- `acp-protocol-client`: ключ `usageLedger` и запрос журнала.
- `acp-client-kit`: `SessionView.usageLedger`, `refreshUsageLedger`, снимок `load` при загрузке сессии.
- `acp-golden-fixtures`: фикстуры журнала usage.

## Не входит

- **`add-desktop-usage-pane`** — панель Usage, клик по строке статуса, Export CSV, когда и как часто обновлять журнал (`refreshUsageLedger` по снимкам `turn`, пока панель открыта), прогресс бюджета хода C-13 и поля лимитов в `_codelab/session/usage`.
- **`add-session-deadline`** — C-15, `/timer`.
- `byBranch` и `inherited` в `usage.json` и в ответе — вместе с ветками, перемоткой и fork (§17.6, change дерева сессии); сейчас ядро ветки и fork не пишет.
- `auxUsage` вспомогательных запросов инструментов (`inspect_image`, §17.11.5) — вместе с этим инструментом.
- Учёт неудачного вызова суммаризатора (`CompactionFailed`, отмена после ответа): записи `compaction` нет, и его usage в журнал не попадает (R3).
- Пагинация ответа журнала (Q8 (а)): весь журнал одним ответом, предел размера — R4.
- Чтение чужого `usage_update`, стоимость не в USD, обнуляемые `cacheRead`/`cacheWrite` — как в `add-usage-extension`.
- Изменение формата записей журнала сессии, кроме `compaction.details.usage` (Q6), и изменение `Usage` ядра.
- Клиентская команда CLI `/usage`: команда агентская, CLI и TUI показывают её ответ как обычное сообщение агента.

## Impact

- `packages/dart/codelab_agent_core`: `lib/src/usage/` (свёртка, модель журнала, отчёт `/usage`), порт `UsageLedgerStore` в `AgentCoreServices`, `AgentSession.usageLedger`, `Summarizer` с usage, `compaction/compactor.dart` (`details.usage`), `ContextCompacted.usage`, `commands/builtin_commands.dart` (`/usage`), барель.
- `packages/dart/codelab_agent_io`: `UsageLedgerStore` на файлах каталога сессии (`usage.json.tmp` → `rename`).
- `packages/dart/codelab_agent_acp`: ключ `usageLedger`, обработчик `_codelab/session/usage/ledger`, засев `UsageAccounting` на `session/load`, снимок `load` через `Reply.after`, usage суммаризатора в сумме сессии.
- `packages/dart/codelab_embedded`, `apps/codelab_agent`: передать `UsageLedgerStore` хосту ядра (настольный открыватель, бинарь).
- `packages/dart/codelab_acp_testing`: новые фикстуры, правка списков команд, повод `load` у scripted-агента.
- `packages/dart/codelab_client_acp`: разбор ключа `usageLedger`, метод запроса журнала.
- `packages/dart/codelab_client_core`: `lib/src/usage/` (`UsageLedgerDecoder`, `UsageLedgerView`, `UsageLedgerState`), `SessionView.usageLedger`, `refreshUsageLedger`, порт `AgentBackend`, снимок `load` при загрузке; барель; `AGENTS.md` §5.
- `apps/codelab_desktop`, `apps/codelab_cli`: кода нет. Тесты: сумма сессии в строке статуса до первого хода после загрузки и после `--continue`.
- Документы: `agent-core/12-observability-and-errors.md` §12.6, §12.6.1, OBS-10; `08-sessions.md` §8.2.4, §8.9; `09-compaction.md`; `13-acp-adapter.md` §13.2, §13.4, §13.5, §13.7, §13.12, §13.16; `dart-agent-and-clients/12-1-view-model.md` §12.1.5; `agent-parity-goals.md` (L-29); `delivery-roadmap.md` §4.6, §6.2.
- Новых пакетов, внешних зависимостей, рёбер графа и правил сторожа нет; allowlist ядра (PKG-2) не меняется.
- Зависимость: change `add-usage-extension` (влит в `develop`, не архивирован). Дельты этого change написаны поверх его требований, поэтому архивируется после него (design.md, R1).
