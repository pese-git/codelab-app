Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). Красный тест — отдельный коммит до кода; коммит — только по просьбе пользователя. В скобках — сценарий дельты spec или решение design.md.

Метки исполнителей:
- `[agent]` — `codelab_agent_core`, `codelab_agent_acp`;
- `[protocol]` — корпус фикстур `codelab_acp_testing`;
- `[client]` — `codelab_client_acp`, `codelab_client_core`, `apps/codelab_cli`;
- `[desktop]` — `apps/codelab_desktop`.

Документы `docs/architecture/**` и `openspec/**` — `codelab-architect` (без метки); README, `doc/` пакетов и приложений и `docs/user/` — `docs-writer`.

Итерации 1 и 2 не зависят от клиентов. Итерация 3 (`[client]` и `[desktop]`) идёт одним PR: новый подтип sealed `NoticeReason` ломает исчерпывающий `switch` в `apps/codelab_desktop` (design.md, D7).

## 1. Ядро: цикл, конфигурация и составной гейт (итерация 1)

- [ ] 1.1 `[agent]` Красные тесты цикла в `packages/dart/codelab_agent_core/test/loop/final_response_hook_test.dart`, spec `agent-loop` «Вердикты финального гейта в цикле» (D10, D11):
  - «Заметка ревизии в транскрипте»: порядок транскрипта, `LoopNudgeOrigin(finalCheck, 1)`, нет двух `assistant` подряд в запросах scripted-модели;
  - «Steering после Hold» и «Бюджет после Hold и steering»: `held == null`;
  - «Исходы вызовов в TurnInfo»;
  - «Хук хоста без составного гейта»: две заметки в транскрипте.

  Существующие ожидания «заметка не в транскрипте» в этом файле меняются по D10 — это осознанное изменение поведения цикла, а не правка теста под код.
- [ ] 1.2 `[agent]` Реализация в цикле:
  - `agent_loop.dart`: при `Revise` — `_append(UserMessage(note), origin: LoopNudgeOrigin(LoopNudgeReason.finalCheck, revisions))` до опроса steering; удалить вставку `reviseNote` в payload; сбрасывать `held` в начале нового шага до проверки бюджета; собирать `toolOutcomes` из итогов пакета;
  - `loop_config.dart`: поле `TurnInfo.toolOutcomes` (по умолчанию пустое), обновить комментарий `BeforeFinalResponseHook` («в MVP хук не регистрируется» → кто собирает хук, D1);
  - `agent_events.dart`: `LoopNudgeReason.finalCheck`.

  Doc-комментарии на русском со ссылками на D10, D11.
- [ ] 1.3 `[agent]` Красные тесты журнала: `session/user_words.dart` даёт `nudge: "final_check"`; строка с этим значением в `test/fixtures/sessions/all_records.jsonl` разбирается и пишется обратно побайтово (spec `agent-sessions` «Формат журнала JSONL», сценарий «Golden-разбор»); `isUserWords` для неё — `false`. Затем реализация `_nudgeWire` и разбор значения.
- [ ] 1.4 `[agent]` Красный тест spec `agent-loop` «Следующий ход после ревизии» в `packages/dart/codelab_agent_core/test/runtime/`: ход с ревизией, закрытие и загрузка сессии из `JsonlSessionStore` в памяти, новый ход. Payload совпадает с живым порядком, двух `assistant` подряд нет. Сериализация каждым адаптером (`anthropic.dart`, `openai_compatible.dart`) проверяется отдельным тестом адаптера на той же истории: у OpenAI-совместимого нет двух сообщений `assistant` подряд, у Anthropic роли чередуются без склейки ответов. Зелёный после 1.2.
- [ ] 1.5 `[agent]` Красные тесты схемы и доверия в `packages/dart/codelab_agent_core/test/config/` (по образцу тестов `subagents.*`), spec `agent-configuration` «Ключи проверок финального ответа»:
  - «Умолчания», «Неизвестная проверка», «Лимит вне диапазона»;
  - «Недоверенный проект не снимает проверку», «Недоверенный проект не увеличивает лимит»;
  - «Недоверенный проект не снимает проверки лимитом», «Недоверенный проект ужесточает лимит при hold»;
  - «Доверенный проект».

  Ещё одна проверка: `loop.final_response.require_approval` даёт предупреждение о неизвестном ключе, а не маску `<opaque: edit the file>`.
- [ ] 1.6 `[agent]` Реализация (D5):
  - `schema.dart`: раздел `final_response` вместо `_opaque`, ключи применяемые;
  - `FinalResponseSettings` в `core_config.dart`;
  - `_lowerFinalResponse` в `trust.dart` по образцу `_lowerSubagents`, включая правило уменьшения лимита при итоговой `accept` (S1 ревью);
  - дескриптор `_fileOnly` в `settings_registry.dart`, не `restartRequired`.
- [ ] 1.7 `[agent]` Красные тесты составного хука `packages/dart/codelab_agent_core/test/loop/final_checks_test.dart` на фейковых проверках и `TurnInfo`, без цикла (D1, D3; spec `agent-runtime` «Проверки финального ответа сессии»):
  - нет замечаний → `Accept`;
  - два замечания → одна заметка в порядке каталога;
  - `revisions == max_revisions` → `Hold` с префиксом `revision limit reached:`; при политике `accept` → `Accept`;
  - «Обрезка причины по рунам»;
  - «Сбой проверки»: лог без текста исключения, поля `check`, `error_class`, `stack`;
  - логи `revise` (с `step_index`) и `limit` без текста ответа и замечаний;
  - неизвестный id в снимке пропускается.
- [ ] 1.8 `[agent]` Реализация `lib/src/loop/final_checks.dart`: внутренний `FinalResponseCheck` с синхронным `review`, `composeFinalChecks`, текст заметки, обрезка по рунам (`String.runes`). Барель не меняется (PKG-5).
- [ ] 1.9 `[agent]` Красные тесты встроенных проверок в том же файле (D2):
  - `open_tasks`: пункт `in_progress` владельца `main` → замечание с `#id` и без `subject`; `pending` и пункт субагента → нет; шесть пунктов → пять id и `and 1 more`; без списка задач → нет;
  - `unverified_success`: `All tests pass.`, `The build succeeded.`, `Тесты прошли.` без попытки → замечание; `exec` с исходом `completed` или `failed` → нет; `exec` с исходом `rejected` или `cancelled` → замечание («Отклонённый exec не считается»); `agent` с исходом `completed` → нет («Проверка через субагента»); утверждение только в `thinking` → нет; текст без утверждения → нет.
- [ ] 1.10 `[agent]` Реализация каталога проверок. Выражение утверждений пишется заново, без чужих списков (корневой `AGENTS.md` §5); комментарий ссылается на D2 и R1. Проверить потребителей `LoopNudgeReason` вне `lib/src/session/user_words.dart` (`grep -rn LoopNudgeReason packages apps`): исчерпывающие `switch` получают ветку `finalCheck`.
- [ ] 1.11 `[agent]` Красные тесты рантайма `packages/dart/codelab_agent_core/test/runtime/final_response_checks_test.dart` на scripted-модели и `FakeClock`, остальные сценарии spec `agent-runtime` «Проверки финального ответа сессии»:
  - «Пустой список проверок», «Незакрытая задача и ревизия», «Задачи pending и задачи субагента»;
  - «Успех без запуска», «Успех после запуска», «Политика accept», «Две проверки в одной заметке»;
  - «Бюджет во время ревизий», «Отмена во время ревизии», «Субагент без гейта», «Перезагрузка включает проверку»;
  - «Сессия другой папки» — через порт конфигурации папки, как тесты требования «Конфигурация сессии вне корня запуска».

  Отдельно: usage шага ревизии входит в `TurnEnded.usage`.
- [ ] 1.12 `[agent]` Реализация в `agent_runtime.dart`. Корень: `beforeFinalResponse: composeFinalChecks(...)` со снимком конфигурации сессии и `TaskList` сессии, `maxResponseRevisions: 5`. Ребёнок (`:583`) без изменений, комментарий ссылается на D9.

## 2. Проекция агента и фикстуры (итерация 2)

- [ ] 2.1 `[protocol]` Фикстуры, красные до 2.3 (сценарии «Ответ удержан» и «Ответ принят» spec `agent-acp-server`):
  - `packages/dart/codelab_acp_testing/fixtures/acp/prompt-response-held.json`: `"extensions": ["held"]`, `setup.config.loop.final_response: {checks: [unverified_success], max_revisions: 0}`, scripted ответ `All tests pass.`, ожидаемый ответ `end_turn` с `_meta.codelab.held`, равным точной строке из сценария. Новых матчеров в `_schema.json` не вводить;
  - `prompt-response-accepted.json`: тот же конфиг, scripted вызов `exec`, затем `All tests pass.`, ожидаемый ответ `end_turn` без `_meta`.
- [ ] 2.2 `[agent]` Красный тест `turnResponse` в `packages/dart/codelab_agent_acp/test/` (рядом с тестами `budgetExceeded`), D6:
  - `completed` с `held` → `end_turn` и `_meta.codelab.held`;
  - без `held` → `end_turn` без `_meta`;
  - `cancelRequested` с `held` → `cancelled`.
- [ ] 2.3 `[agent]` Реализация ветки в `event_projection.dart`. Doc-комментарий проекции дополнить ссылкой на change.
- [ ] 2.4 `[agent]` Прогон фикстур агентским conformance и встроенным агентом (`conformance:agent`, `conformance:embedded`).

## 3. Клиенты (итерация 3, один PR)

- [ ] 3.1 `[client]` Красные тесты `codelab_client_acp` (рядом с тестами `budgetExceeded` в `acp_client_application`), spec `acp-protocol-client` «Удержанный ответ в итоге хода»: «Удержанный ответ», «Многострочная причина», «Причина не строкой», «held при другом stopReason», «Сторонний агент»; обрезка до 500 рун без разрыва суррогатной пары.
- [ ] 3.2 `[client]` Реализация: поле `PromptTurn.held` (freezed, перегенерация через `build_runner` пакета), разбор `_heldOf(PromptResponse)` по образцу `_budgetExceededOf` (D7).
- [ ] 3.3 `[client]` Красные тесты `codelab_client_core` (`transcript_projector` и эталон `projectTranscript`), spec `acp-client-kit`:
  - «Инкрементальная проекция транскрипта»: «Удержанный ответ», «Удержанный ответ после session/load», обновлённый «Отказ агента после текста»;
  - «Типизированная причина заметки транскрипта»: «Причина удержанного ответа».
- [ ] 3.4 `[client]` Реализация: `ResponseHeldReason` в `transcript_item.dart`, ветка в `_stoppedReason` и `_stoppedNoticeText` для `endTurn` с `held` (D7). Doc-комментарий `NoticeKind.turnStopped` дополнить удержанным ответом.
- [ ] 3.5 `[client]` Красные тесты `apps/codelab_cli`, сценарий «Ответ удержан» spec `cli-headless`:
  - модуль кодов выхода и `headless/outcome.dart`: `end_turn` с `held` → `1`, строка `Response held: <reason>` в stderr, ответ в stdout;
  - e2e headless на встроенном агенте с конфигом `checks: [unverified_success]`, `max_revisions: 0` (по образцу `test/e2e/headless_print_basic_test.dart`).
- [ ] 3.6 `[client]` Реализация в `exit_codes.dart` и `headless/outcome.dart`. Тексты stderr — в `strings.dart`, если там живут остальные.
- [ ] 3.7 `[desktop]` Красный тест `apps/codelab_desktop/test/features/workbench/application/` для `ui_mappers.dart`, spec `agent-workbench-ui` «Заметка исхода хода в ленте»: сценарии «Удержанный ответ на русском» и «Удержанный ответ на английском».
- [ ] 3.8 `[desktop]` Реализация: ветка `ResponseHeldReason` в `_noticeBodyOf`, ключ `workbenchNoticeResponseHeld(reason)` во всех ARB-каталогах app, перегенерация локализации.

## 4. Документация

- [ ] 4.1 Архитектура (`codelab-architect`, до архивации change):
  - `docs/architecture/proposals/agent-core/17-12-loop-and-security.md` §17.12.1 и §17.12.4:
    - синхронный внутренний `review` и сборка в рантайме без `SessionSpec.finalResponseChecks` (D1);
    - встроенные проверки и ключ `checks` (D2, D5);
    - заметка в транскрипте (D10) и сброс `held` (D11);
    - `require_approval`, `/approve`, `response_hold`, `response_review` и пометка реплея — «не реализовано, Q2 change `add-final-response-guardrails`»;
  - `05-agent-loop.md` §5.2 (шаг 4 payload удалён) и §5.4 (шаг 22);
  - `08-sessions.md` §8.2.3: значение `nudge: "final_check"`;
  - `13-acp-adapter.md` §13.8, §13.10 (строка stderr), §13.12 (ссылка на change);
  - строка C-14 `docs/architecture/proposals/agent-parity-goals.md`: статус и тесты 1.11, 2.1, 3.5 — после зелёных тестов.
- [ ] 4.2 `[agent]` (`docs-writer`) Документация ядра и проекции агента:
  - `packages/dart/codelab_agent_core/doc/algorithms/turn.md`: L21 — гейт достижим, составной хук, лимит из снимка, `maxResponseRevisions: 5`, заметка в транскрипте, сброс `held`; таблица хуков; строка `loop.final_response` в таблице ключей;
  - `packages/dart/codelab_agent_core/doc/algorithms/README.md`: ссылка на финальный гейт;
  - `packages/dart/codelab_agent_core/doc/algorithms/settings.md`: раздел `loop.final_response` больше не непрозрачный, правила доверия D5; в разделе «Ключи с `applied: false`» убрать `loop.final_response` и поправить счётчики: всего 88 ключей, «Непрозрачные узлы (51)»;
  - `packages/dart/codelab_agent_acp/doc/03-projection-and-client-requests.md`: итог хода с `_meta.codelab.held`;
  - `packages/dart/codelab_agent_acp/doc/05-extending-and-troubleshooting.md`: расширение `held` в перечне.
- [ ] 4.3 `[client]` (`docs-writer`) Документация клиентского слоя и CLI:
  - `packages/dart/codelab_client_acp/doc/02-connection-and-turns.md`: `PromptTurn.held`;
  - `packages/dart/codelab_client_core/README.md`, `doc/07-transcript.md` (заметка `turnStopped` для удержанного ответа), `doc/15-extending.md` (новый подтип `NoticeReason` и исчерпывающие `switch`);
  - `apps/codelab_cli/doc/05-headless.md`, `doc/user/04-headless.md`, `doc/user/11-reference.md`: код выхода `1` и строка `Response held: <reason>`.
- [ ] 4.4 `[desktop]` (`docs-writer`) `apps/codelab_desktop/doc/user/10-troubleshooting.md`: что значит заметка удержанного ответа и как выключить проверки.
- [ ] 4.5 (`docs-writer`) `docs/user/configuration.md`: короткий раздел «Проверки финального ответа» — ключи, умолчания, пример `checks: [open_tasks]`, что значит `hold` для CI, ограничения недоверенного проекта. Стандарт — `.claude/skills/codelab-docs/SKILL.md`.

## 5. Проверки (`AGENTS.md` §21)

- [ ] 5.1 `[agent]` `fvm dart format --set-exit-if-changed` изменённых файлов. `fvm dart analyze` и `fvm dart test` в `packages/dart/codelab_agent_core` и `packages/dart/codelab_agent_acp`. `fvm dart analyze` в зависимых `codelab_embedded`, `codelab_setup`, `apps/codelab_agent`: изменены реестр настроек и публичный `TurnInfo`.
- [ ] 5.2 `[agent]` `[protocol]` Melos-скрипты:
  - `protocol-conformance`, `conformance:agent`, `conformance:embedded` — новые фикстуры и проекция;
  - `web-compile` — ядро web-безопасно.

  Не нужны: `guard` — импорты и `pubspec.yaml` не меняются; `prompts:check` — тексты заметок живут в коде, как `emptyResponseNudge`.
- [ ] 5.3 `[client]` `fvm dart analyze` и `fvm dart test` в `codelab_client_acp`, `codelab_client_core`, `apps/codelab_cli`. Скрипты `conformance:client`, `test:e2e:cli:embedded`, `test:e2e:cli:dart-agent`, `web-compile`.
- [ ] 5.4 `[desktop]` `fvm flutter analyze` и `fvm flutter test` в `apps/codelab_desktop` (затронутые тесты workbench); `l10n:check`.
- [ ] 5.5 `openspec validate add-final-response-guardrails --strict`. Полный `melos run check` — только по просьбе пользователя.
