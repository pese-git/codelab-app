> Исполнители — по таблице зон `CLAUDE.md`:
> - `[agent]` — `codelab_agent_core` (`agent-core-engineer`);
> - `[protocol]` — `codelab_agent_acp` и фикстуры `codelab_acp_testing` (`acp-protocol-engineer`);
> - `[client]` — `codelab_client_acp`, `codelab_client_core`, `apps/codelab_cli` (`client-engineer`);
> - `[desktop]` — `apps/codelab_desktop` (`desktop-engineer`).
>
> У документов меток нет, исполнитель назван в задаче: `codelab-architect` — `docs/architecture/**`, `docs-writer` — README, `doc/`, `docs/user/`, `docs/backlog/`, `CHANGELOG.md`.
>
> Задачи идут парами «тест → реализация», красный тест первым (`packages/dart/codelab_agent_core/AGENTS.md` §2). Ссылка в скобках — требование дельты и сценарий.
>
> Q1–Q5 design.md решены пользователем 2026-11-26 по рекомендациям (для Q3 — (б)); задачи написаны под них.

## 0. Документы до кода

- [ ] 0.1 `codelab-architect`: `docs/architecture/proposals/agent-core/08-sessions.md`:
  - §8.2.3 — `origin: "turn_resume"`;
  - §8.2.4 — `customType` `codelab.turn_stopped`;
  - §8.2.5 — класс `turn_resume`;
  - §8.3 — строка `TurnEnded` со `stopMark`, функция `unfinishedTurnOf`;
  - §8.8 — незавершённый ход, таблица «как оборван ход» D3, `/continue`, защита повтора;
  - §8.11 — SES-17.
- [ ] 0.2 `codelab-architect`: `03-cancellation.md` — причина `ConnectionLost`, `AgentSession.cancel({reason})`, `TurnEnded.stopMark`. `05-agent-loop.md` §5.2 — поле `stopMark`.
- [ ] 0.3 `codelab-architect`: `07-permissions.md`:
  - §7.4 — правило 3a, мультимножество, снятие только разрешением, срок жизни, общий набор с потомками;
  - PERM-12;
  - §7.8 — метка `critical`.
- [ ] 0.4 `codelab-architect`: `13-acp-adapter.md`:
  - §13.4 — команда `continue`: условное объявление и резерв имени;
  - §13.5 — `_meta.codelab.unfinishedTurn`, резерв открытия после проверок cwd;
  - §13.10 — причины отмены по источнику;
  - §13.12 — новое расширение.
- [ ] 0.5 `codelab-architect`:
  - `12-observability-and-errors.md` — события D9;
  - `00-six-concepts.md`, строка «Checkpointing»;
  - `agent-parity-goals.md`, строка S-13 и её приёмка.
- [ ] 0.6 `docs-writer`: `packages/dart/codelab_agent_core/doc/algorithms/usage.md` (Д1) — граница хода `turn_resume`.

## 1. Ядро: причина отмены, отметка остановки, незавершённый ход (agent-runtime «AgentRuntime и AgentSession»; agent-sessions «Запись журнала из событий», «Незавершённый ход»)

- [ ] 1.1 `[agent]` Характеризационный тест `agent_loop`: отмена после пакета и бюджет оставляют хвостом `toolResult`. Отмена во время ответа модели оставляет ответ `aborted`. Зелёный до изменений.
- [ ] 1.2 `[agent]` Тесты: «Причина отмены в итоге хода» (agent-runtime); «Отметка остановки при отмене», «Отметка остановки по бюджету», «Обычный ход без отметки» (финальный ответ, отменённый `/compact`, `/compact` с `failed`), «Остановка процесса без отметки». Красные.
- [ ] 1.3 `[agent]` Причина `ConnectionLost`, `AgentSession.cancel({reason})`, `TurnEnded.stopMark` (ставит только `AgentLoop`), запись `codelab.turn_stopped` в `SessionWriter`. 1.2 зелёные. Golden-разбор `all_records.jsonl` пополнить записью `codelab.turn_stopped`.
- [ ] 1.4 `[agent]` Тесты `unfinished_turn_test.dart`: «Сбой во время инструмента», «Сбой во время ответа модели», «Отмена пользователем после пакета инструментов», «Остановка процесса во время инструмента», «Разрыв во время ответа модели», «Завершённый ход», «Служебная запись после хвоста», «Новый промпт оборван до ответа»; детерминизм (SES-17). Красные.
- [ ] 1.5 `[agent]` `unfinishedTurnOf`, `UnfinishedTurn` (экспорт через `show`), `AgentSession.unfinishedTurn`, лог `session.turn.unfinished`. 1.4 зелёные, `web-compile` зелёный.

## 2. Ядро: служебное сообщение и `/continue` (agent-sessions «Слова пользователя», «Продолжение прерванного хода»; agent-slash-commands «Команда /continue», «Резервные имена команд», «Список команд сессии»; agent-runtime)

- [ ] 2.1 `[agent]` Тест полноты `user_words_test.dart` и `all_origins.jsonl` со строкой `turn_resume`; «Продолжение хода не слова пользователя». Красные.
- [ ] 2.2 `[agent]` `RecordOrigin.turnResume`, `TurnResumeOrigin`, константа `turnResumeNote` рядом с `emptyResponseNudge` (`loop/agent_loop.dart`; не каталог `prompts/`, `prompts:check` не нужен). 2.1 зелёные.
- [ ] 2.3 `[agent]` Тесты:
  - «Продолжение после сбоя», «Повторный /continue» (с логом `command.continue.nothing`), «Новая сессия без команды», «Аргумент не принимается», «Отмена продолжения»;
  - «Шаблон continue»;
  - «Загруженная сессия с незавершённым ходом»;
  - «Продолжение командой», «Загрузка не начинает ход»;
  - «Загрузка с незавершённым ходом» (agent-runtime);
  - два `/continue` подряд дают один ход продолжения.

  Красные.
- [ ] 2.4 `[agent]` `continue` в `BuiltinName`: условное объявление при `loadSession`, резерв имени, исполнение через общий внутренний вход хода с `prompt()`, лог `session.turn.resumed`. 2.3 зелёные.

## 3. Ядро: защита повтора (agent-permissions «Повтор прерванного вызова», «Порядок правил решения»)

- [ ] 3.1 `[agent]` Тесты политики:
  - «Повтор exec в режиме bypass», «Повтор в autopilot», «Повтор без gate», «Чтение не защищается», «Изменённые аргументы», «Приведённые аргументы совпадают», «Отказ, затем повтор», «Первый ход отменён», «Одно разрешение — одно вхождение», «Повтор через субагента», «Deny сильнее защиты повтора»;
  - `policy_order_test.dart` с парой «3a против 4».

  Красные.
- [ ] 3.2 `[agent]` Набор защиты: мультимножество, канонизация через валидатор инструмента. Набор живёт до закрытия сессии, общий для `childPolicy`. Правило 3a в `decide` (через `_ask` с `criticalLabel` и `allowAlways: false`), снятие вхождения только по разрешению, лог `permission.interrupted_repeat`. 3.1 зелёные.

## 4. Ядро: usage и сквозной сценарий (agent-sessions «Журнал usage сессии»)

- [ ] 4.1 `[agent]` Тест свёртки «Ход продолжения»; живой учёт и свёртка дают равные итоги. Красный.
- [ ] 4.2 `[agent]` Граница хода `turn_resume` и подпись `/continue` в `UsageLedger`. 4.1 зелёный.
- [ ] 4.3 `[agent]` Сценарий `core/resume-after-crash-continue` (`test/scenarios/`, по образцу `resume_after_crash_test.dart`): `write` выполнен, `exec` прерван, перезапуск, `/continue`, модель повторяет `exec` в `bypass`. Пишется до 2.4 и 3.2 и падает красным. Проверить: `write` не повторён; модель видит обе пары и служебное сообщение; повтор `exec` спрашивает человека. Зелёный после 2.4 и 3.2.

## 5. ACP-сервер (agent-acp-server «session/load и реплей», «Отсоединение, переподключение и завершение», «Расширения протокола этапа 4»)

- [ ] 5.1 `[protocol]` Тесты: «Два одновременных session/load», «Ошибка открытия у ожидающего», «Ожидающий запрос с неверным cwd» (REV-34). Красные.
- [ ] 5.2 `[protocol]` Резерв открытия по id после проверок запроса, лог `acp.session.load_joined`. 5.1 зелёные. Порядок с `add-agent-remote-exec` — design.md, «Миграция», п. 3.
- [ ] 5.3 `[protocol]` Тесты:
  - «Разрыв оставляет ход незавершённым», «Отмена пользователем завершает ход»;
  - `shutdown()` отменяет с `ShutdownCancel`;
  - «Прерванный ход» (`_meta`, `continue`), «Завершённая сессия без поля»;
  - поля нет при переподключении идущего хода;
  - «Вопрос о повторе прерванного вызова».

  Красные.
- [ ] 5.4 `[protocol]` Причины отмены в `SessionBridge.cancel` (`session/cancel` → `UserCancel`, `_expire` → `ConnectionLost`, `shutdown` → `ShutdownCancel`), поле `cause` в логе; `_meta.codelab.unfinishedTurn` в ответе `session/load`; метка `critical`. 5.3 зелёные.
- [ ] 5.5 `[protocol]` Фикстуры (acp-golden-fixtures «Фикстуры продолжения хода»):
  - сначала новая `acp/prompt-continue-interrupted-turn` и новые ожидания `acp/session-load-interrupted-turn`; агентский прогон до 5.4 и 2.4 красный;
  - затем прогоны `conformance:agent`, `conformance:client`, `protocol-conformance` зелёные.

## 6. Клиентский протокольный слой и kit (acp-protocol-client «Незавершённый ход в ответе session/load»; acp-client-kit «Продолжение незавершённого хода»)

- [ ] 6.1 `[client]` Тесты `codelab_client_acp`: «Ответ с признаком», «Неверная форма», «Признак снимается промптом», «Вместе с пометкой замены транспорта». Красные.
- [ ] 6.2 `[client]` Разбор `_meta.codelab.unfinishedTurn` в `AcpClientApplication`. 6.1 зелёные.
- [ ] 6.3 `[client]` Тесты `codelab_client_core`: «Можно продолжить», «Сторонний агент с командой continue», «Восстановление не продолжает ход», «Обычный промпт снимает признак», «Промпт в очереди не снимает признак», «Отказ turnActive», «Обрыв до отправки». Красные.
- [ ] 6.4 `[client]` `UnfinishedTurnView`, `SessionView.unfinishedTurn`, `canContinue`, `SessionHandle.continueTurn()`. 6.3 зелёные, `web-compile` зелёный.

## 7. CLI (codelab-cli «Незавершённый ход в REPL»; codelab-tui «Незавершённый ход в TUI»; cli-headless «Продолжение хода в headless»)

- [ ] 7.1 `[client]` Тесты REPL: «Подсказка после --resume», «Без незавершённого хода». TUI: «Заметка в TUI», «Продолжение из композера». Headless: «Headless продолжение», «Повтор прерванного вызова отклоняется». Красные.
- [ ] 7.2 `[client]` Подсказка в REPL, заметка в TUI (`sanitizeTerminalText`). 7.1 зелёные.
- [ ] 7.3 `[client]` E2E `test:e2e:cli:embedded` и `test:e2e:cli:dart-agent`: агент убит во время `exec`, `--resume`, подсказка, `/continue`, ответ модели. Сценарий пишется до 7.2 и падает красным на отсутствии подсказки, затем зелёный.

## 8. Desktop (agent-workbench-ui «Unfinished turn notice with Continue»)

- [ ] 8.1 `[desktop]` Тесты Cubit и модели отображения и widget-тест заметки: «Continue after an agent crash», «Notice without the command», «A regular prompt instead of Continue». Красные.
- [ ] 8.2 `[desktop]` Заметка с действием Continue, ARB en/ru. 8.1 зелёные, `l10n:check` зелёный.

## 9. Документация (`docs-writer`)

- [ ] 9.1 `docs-writer`:
  - `packages/dart/codelab_agent_core/doc/algorithms/sessions.md`, `turn.md`, `doc/08-sessions-and-compaction.md`, `doc/07-permissions.md` — незавершённый ход, отметка, `/continue`, защита повтора;
  - ограничение REV-36: два процесса над одним журналом.
- [ ] 9.2 `docs-writer`: README и `doc/` `codelab_agent_acp` — расширение ответа `session/load`, причины отмены, резерв открытия.
- [ ] 9.3 `docs-writer`: `packages/dart/codelab_client_core/doc/04-sessions.md`, `session-management.md` — `unfinishedTurn`, `canContinue`, `continueTurn()`.
- [ ] 9.4 `docs-writer`: CLI.
  - Для разработчика: `apps/codelab_cli/doc/03-repl.md`, `04-tui.md`, `05-headless.md`.
  - Для пользователя: `apps/codelab_cli/doc/user/02-repl.md`, `03-tui.md`, `04-headless.md`, `11-reference.md` — команда `/continue` и резерв имени шаблона `continue`.
- [ ] 9.5 `docs-writer`: desktop — `apps/codelab_desktop/doc/user/03-conversation.md` (заметка и Continue), `02-projects-and-sessions.md` (закрытие во время хода и восстановление).
- [ ] 9.6 `docs-writer`: `docs/backlog/review-2026-11-25-developer-guides.md` — REV-34 отмечен как исправленный этим change.
- [ ] 9.7 `docs-writer`: раздел выпуска `CHANGELOG.md` при подготовке `release/*` — резерв имени `continue` (R4). Документация команд — в 0.4 и 9.4.

## 10. Проверки (§21 `AGENTS.md`) и архивация

- [ ] 10.1 `fvm dart format --set-exit-if-changed` по изменённым файлам. `fvm dart analyze` в изменённых пакетах (`codelab_agent_core`, `codelab_agent_acp`, `codelab_client_acp`, `codelab_client_core`, `apps/codelab_cli`, `apps/codelab_desktop`) и в зависимых: `codelab_embedded`, `apps/codelab_agent`.
- [ ] 10.2 Тесты изменённых пакетов; `melos run guard`; `protocol-conformance`, `conformance:agent`, `conformance:client`, `conformance:embedded`; `test:e2e:cli:embedded`, `test:e2e:cli:dart-agent`; `web-compile`; `l10n:check`. `prompts:check` не нужен: текст продолжения — константа в коде (2.2).
- [ ] 10.3 `openspec validate add-interrupted-turn-resume --strict`.
- [ ] 10.4 Перед архивацией сверить дельту `agent-acp-server` «Расширения протокола этапа 4» с действующей спекой. Если `add-final-response-guardrails` уже архивирован, перебазировать полный текст требования, сохранив строки и сценарии обоих changes (design.md, «Миграция», п. 6).
