## Why

Понятие 4 обвязки агента (`docs/architecture/proposals/agent-core/00-six-concepts.md`, «Checkpointing») обещает: состояние хранится вне модели, и после сбоя работа продолжается с сохранённого места. Сохранённое место у нас есть, а продолжения нет.

Что есть сейчас (S-01, S-02, S-13; SES-9, SES-10):

- результат каждого инструмента пишется в журнал с `durable` до следующего запроса к модели;
- при открытии сессии `_Session._heal` (`agent_runtime.dart`) дописывает синтетические `toolResult` с `outcome: interrupted` для вызовов без результата; прерванные субагенты не перезапускаются (SUB-9);
- сессия после загрузки — `idle`.

Чего нет:

- **Ход сам не продолжается.** Пользователь должен понять по реплею, что ход оборвался, и написать промпт вроде «продолжай». В журнал это попадает как слова пользователя, которых он по сути не говорил: заголовок, перемотка и поиск по сессии видят их как обычную реплику.
- **Клиент не знает, что ход не завершён.** Агент знает это точно (после лечения журнала), но сообщить не может. Desktop, REPL и TUI показывают оборванный ход как обычный.
- **Повтор необратимого держится только на тексте для модели.** Синтетический результат просит модель «проверить состояние перед повтором». Детерминированной защиты нет. В режиме `bypass` модель может молча повторить прерванный `exec` (`git push`, миграцию, деплой), который до сбоя уже успел отработать.
- **Гонка двух `session/load` (REV-34, issue #513).** Два одновременных `session/load` закрытой сессии открывают двух писателей над одним журналом. Лечение журнала тогда пишется дважды, а продолжение могут запустить обе копии.

## What Changes

- **Незавершённый ход — явное состояние журнала** (agent-sessions). Чистая функция ядра `unfinishedTurnOf(snapshot)` решает по активной ветке: последнее сообщение — не ответ модели, и после него нет отметки остановки. Отметку пишет писатель журнала, когда ход цикла отменил пользователь (`session/cancel`), ход сорвался или исчерпал бюджет: запись `custom` с `customType: "codelab.turn_stopped"`. Её не оставляют:
  - сбой процесса (`kill -9`, OOM);
  - остановка агента (`SIGTERM`, закрытие сессии, причина `ShutdownCancel`);
  - потеря соединения: закрыли desktop или CLI во время хода, упал WebSocket. Это новая причина отмены `ConnectionLost`.

  Такой ход считается незавершённым (D3).
- **Команда `/continue`** (agent-slash-commands). Встроенная команда агента продолжает незавершённый ход: новый ход цикла начинается со служебного сообщения `user` с `origin: "turn_resume"` (не слова пользователя, S-16). Текст сообщения предупреждает модель, что состояние проекта могло измениться. Команда идёт обычным `session/prompt`. Она объявляется через `available_commands_update`, только если при открытии сессии ход был незавершён. Имя `continue` резервируется. Автоматического продолжения нет (D1).
- **Защита от повтора прерванного вызова** (agent-permissions). Вызов с тем же инструментом и теми же аргументами, что прерванный вызов (`outcome: interrupted` или `cancelled`) в незавершённом ходе, требует человека в любом режиме — и у корня, и у субагентов. Одно разрешение снимает защиту с одного вызова. Отказ её не снимает. Защита живёт до закрытия сессии. `allow_always` при этом не предлагается, как у критических шаблонов. В `autopilot` и без интерфейса одобрения такой вызов отклоняется. Уровень `read` не затрагивается (D5).
- **Сигнал клиенту** (agent-acp-server). Ответ `session/load` несёт `_meta.codelab.unfinishedTurn: {"interruptedToolCalls": [...]}`, если ход незавершён. Вопрос о повторе использует существующее расширение `_meta.codelab.critical` с меткой `repeat of interrupted call`. Новых методов ACP нет (D4).
- **Учёт usage** (agent-sessions, «Журнал usage сессии»). Запись `origin: "turn_resume"` начинает ход и в свёртке журнала, и вживую. Сумма после загрузки совпадает с живой (D6).
- **REV-34 входит в change** (agent-acp-server). Второй `session/load` той же ещё не открытой сессии ждёт открытия первым и идёт по ветке уже открытой сессии. Двух писателей и двойного лечения нет (D7).
- **Клиенты.** `codelab_client_acp` читает `_meta.codelab.unfinishedTurn`. `codelab_client_core` отдаёт `SessionView.unfinishedTurn`, `canContinue` и `continueTurn()`. REPL и TUI после загрузки печатают подсказку `/continue`. Desktop показывает в ленте заметку с действием «Continue» (D8).

## Не входит

- **Продолжение идущего хода после переподключения** (`detachGrace` > 0 у бинаря, клиент читает `_meta.codelab.turnEnded`). Механизм `detach`/`reattach` в `codelab_agent_acp` есть, но бинарь и встроенный агент задают grace ноль (change `cancel-turn-on-ws-disconnect`, D1). Это продолжение живого хода, а не восстановление после сбоя. Нужен отдельный change; предлагаемое имя — `add-turn-reattach-after-reconnect` (D2, Q1).
- **Автоматическое продолжение после `session/load`** без действия пользователя (D1).
- **Продолжение хода, отменённого пользователем, сорвавшегося или остановленного бюджетом.** Такой ход завершён по правилам цикла, клиент видел итог. Пользователь продолжает его обычным промптом, как сейчас (D3, Q4).
- **Перезапуск прерванных субагентов** (`agent_resume`, C-17, M5). Прерванный ребёнок остаётся `failed`/`interrupted` (SUB-9). Повторный `agent` с теми же аргументами проходит защиту D5.
- **Блокировка писателя между процессами** (REV-36, issue #515, lease §17.6.8). `/continue` не добавляет нового класса риска к нынешнему «продолжай» обычным промптом (D7, R2).
- **Потерянный usage шага, оборванного сбоем.** Провайдер не прислал итог, в журнал он не попал, восстановить его нельзя. Дефект REV-43 (отброшенные ответы в живом процессе) — отдельная задача (D6).
- **Настройки.** Ключей конфигурации change не вводит.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-runtime`: «AgentRuntime и AgentSession» (`cancel` с причиной, `unfinishedTurn`, ход `/continue` через вход `prompt()`).
- `agent-sessions`: «Продолжение прерванного хода», «Слова пользователя», «Запись журнала из событий», «Журнал usage сессии»; новое требование «Незавершённый ход».
- `agent-slash-commands`: «Резервные имена команд», «Список команд сессии»; новое требование «Команда /continue».
- `agent-permissions`: «Порядок правил решения»; новое требование «Повтор прерванного вызова».
- `agent-acp-server`: «session/load и реплей», «Отсоединение, переподключение и завершение», «Расширения протокола этапа 4».
- `acp-golden-fixtures`: новое требование «Фикстуры продолжения хода».
- `cli-headless`: новое требование «Продолжение хода в headless».
- `acp-protocol-client`: новое требование «Незавершённый ход в ответе session/load».
- `acp-client-kit`: новое требование «Продолжение незавершённого хода».
- `codelab-cli`: новое требование «Незавершённый ход в REPL».
- `codelab-tui`: новое требование «Незавершённый ход в TUI».
- `agent-workbench-ui`: новое требование «Unfinished turn notice with Continue».

## Impact

- `packages/dart/codelab_agent_core`:
  - `session/`: `unfinishedTurnOf`, `RecordOrigin.turnResume`, `codelab.turn_stopped` в `SessionWriter`, свёртка usage;
  - `commands/builtin_commands.dart`: `BuiltinName.continue_`;
  - `runtime/agent_runtime.dart`: `AgentSession.unfinishedTurn`, ход `/continue`, набор защиты повтора;
  - `permissions/`: правило 3a;
  - текст служебного сообщения — константа рядом с `emptyResponseNudge` (`loop/agent_loop.dart`).
- `packages/dart/codelab_agent_core/lib/src/cancel/`: причина `ConnectionLost`; `TurnEnded.stopMark`.
- `packages/dart/codelab_agent_acp`:
  - `agent_server.dart` (`_sessionLoad`: `_meta.codelab.unfinishedTurn`, резерв открытия по id — REV-34; `shutdown` с `ShutdownCancel`);
  - `session_bridge.dart` (`_expire` с `ConnectionLost`);
  - проекция `critical` для повтора.
- `packages/dart/codelab_client_acp`: разбор `_meta.codelab.unfinishedTurn` ответа `session/load`.
- `packages/dart/codelab_client_core`: `SessionView.unfinishedTurn`, `canContinue`, `SessionHandle.continueTurn()`.
- `apps/codelab_cli`: подсказка после загрузки в REPL и TUI.
- `apps/codelab_desktop`: заметка в ленте с действием, ARB-строки en/ru.
- Фикстуры ACP:
  - `acp/session-load-interrupted-turn` — новое ожидание `_meta` ответа;
  - новая `acp/prompt-continue-interrupted-turn`;
  - остальные фикстуры со списком команд не меняются: `continue` объявляется только в сессии с незавершённым ходом (D4). Единственное исключение — `acp/session-load-interrupted-turn`.
- Документы — задачи раздела 0 `tasks.md`:
  - ядро: `agent-core/08-sessions.md`, `07-permissions.md`, `13-acp-adapter.md`, `12-observability-and-errors.md`, `00-six-concepts.md`;
  - `agent-parity-goals.md` (S-13);
  - продуктовые документы пакетов и приложений.
- ACP-модели (`codelab_acp_protocol`), транспорты, зависимости и allowlist сторожа не меняются. Правила сторожа не нужны.
- Пересечение с активным change `add-agent-remote-exec`: оба меняют `_sessionLoad` в `agent_server.dart` (там — проверка владельца и корней). Порядок слияния — в design.md, «Миграция».
- Пересечение с активным change `add-final-response-guardrails`: оба делают MODIFIED требования `agent-acp-server` «Расширения протокола этапа 4». Кто архивируется вторым, тот перебазирует полный текст с обеими строками и сценариями (design.md, «Миграция», п. 6).
