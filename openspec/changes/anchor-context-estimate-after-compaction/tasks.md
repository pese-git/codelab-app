Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). Красные тесты пишутся одной задачей и коммитятся отдельно, до кода, — только по явной просьбе пользователя. В скобках — сценарий delta spec `agent-compaction`, решение design.md или инвариант.

Метки исполнителей (CLAUDE.md, таблица зон): `[agent]` — `codelab_agent_core` и документы ядра. Задач `[protocol]`, `[client]`, `[desktop]` нет: мост ACP, фикстуры и клиенты кода не меняют (design.md, D10); задача 3.2 только прогоняет их проверки, а красная фикстура — остановка и вопрос архитектору.

Порядок: 0.1 → 0.2 → 1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.6 → 2.1 → 3. Ветка `feature/anchor-context-estimate-after-compaction`, один PR в `develop`.

Проверки — только затронутое (корневой `AGENTS.md` §21); полный `melos run check` — по просьбе пользователя.

## 0. Подготовка

- [x] 0.1 `[agent]` Дождаться merge `feature/compaction-no-gain` (change `fix-compaction-estimate-and-no-gain`) в `develop` и обновить ветку `feature/anchor-context-estimate-after-compaction` от `develop`. Сверить, что в коде есть `estimateAfterCompaction`, `compaction.skipped`, D9 (`max(after, raw)` в `compactor.dart`) и тест `test/compaction/preflight_after_compaction_test.dart`; если предшественник при merge изменился — сверить с ним design.md этого change (Context, D8) до кода. Выполнено: ветка обновлена от `develop` (merge `e954ee24`); Context design.md сверен с кодом, delta spec — с текстом предшественника.
- [x] 0.2 `[agent]` Документы ядра до кода (выполняет архитектор после 0.1; `codelab_agent_core/AGENTS.md`, «сначала документ»):
  - `docs/architecture/proposals/agent-core/09-compaction.md`:
    - §9.2 — параметр якоря сжатия у `compact` и оценщика;
    - §9.3 — алгоритм `estimateContextTokens` с тремя ветвями (usage → сжатие → эвристика), подраздел «Якорь на последнее сжатие» (D1, D2, D4 с таблицей, D6, D7); в «Оценке после сжатия» убрать D9 и абзац «между сжатием и следующим ответом — чистая эвристика»; «до» первого прохода — с якорем сжатия (D8);
    - §9.8 — шаг 2 (`before` с якорем сжатия), шаг 9 (без `fit`), шаг 11 (транскрипт и якорь вместе, D3), шаг 13 (по `after`); выброс навыков по окну — по `after`;
    - §9.9 — CMP-5 без `max`, новый CMP-11 (design.md, D8);
    - §9.10 — обоснование якоря-смещения против поиска границы и калибровки (D1);
    - §9.11 — тесты задачи 1.1;
  - `docs/architecture/proposals/agent-core/08-sessions.md` §8.7 — обнуление usage до сжатия дополняется якорем сжатия; правило «операция, которая строит транскрипт из журнала, меняет и якорь» (D5);
  - `docs/architecture/proposals/agent-core/17-13-session-scale.md` — шаги 9 и 12 структурного прохода: порог по `after`, без `max`; дополнительно шаг 2 (`before` с якорем сжатия) и шаг 11 (транскрипт тем же методом, что якорь; запись `hide` якорем не служит);
  - `docs/architecture/proposals/agent-core/05-agent-loop.md` шаг 4 §5.2 — оценщик `estimateTokens` рантайм передаёт с якорем сжатия (без изменения сигнатуры).

## 1. Ядро (`codelab_agent_core`)

- [x] 1.1 `[agent]` Красные тесты:
  - `test/compaction/estimate_test.dart` (сценарии «Обнулённый usage без якоря сжатия», «Обнулённый usage после сжатия», «Некорректный tokensAfter», «Первый ответ с usage снимает якорь сжатия», «Ответ без usage не снимает якорь сжатия»; D1, D2, D6): табличный тест `estimateContextTokens(..., compaction: anchor)` — `max(0, tokens + H − raw)`; usage-якорь в сообщениях побеждает якорь сжатия; ответ только с `output` и ответ с нулевым usage не снимают якорь сжатия; без якоря — `H`; нижняя граница 0. `compactionAnchorOf`: `null` без `lastCompaction` и при `tokensAfter ≤ 0`; `raw` — `H` промпта, схем и первых `compactionCovered` сообщений.
  - `test/session/projections_test.dart` (D1, D4): `compactionCovered` — 0 без сжатия; резюме + сохранённые сообщения; резюме + сообщение навыков + сохранённые (с каталогом навыков); с хвостом после записи хвост не входит; две записи `compaction` подряд — считается по последней.
  - `test/compaction/compactor_test.dart`:
    - «Порог проверяется по согласованной оценке» (D8; заменяет тест D9 предшественника «Порог проверяется и по эвристике без якоря»): после первого прохода `after ≤ threshold`, `H(после) > threshold`, регион для второго прохода есть. Ожидается один вызов суммаризатора, одна запись, результат — `Compacted` первого прохода. На коде с D9 тест красный.
    - Выброс навыков по окну решает по `after` (D8): навык не выбрасывается, если `after` с навыками в пороге, даже когда `H(после)` с навыками выше порога.
    - «Сжатие сразу после сжатия» (D8): `compact(..., anchor: якорь первой записи)` на снимке после первой записи плюс одно сообщение пользователя — `tokensBefore == tokensAfter₁ + H(сообщения)`; без параметра — прежняя эвристика.
    - Равенство `raw` (D3): `compactionAnchorOf` проекции, переданной в `onCompacted`, даёт `raw == H(P_after)` пробной проекции, а `estimateContextTokens(p.messages, compaction: якорь) == tokensAfter` (CMP-11, сценарий «Оценка сразу после сжатия равна tokensAfter»).
  - `test/compaction/preflight_after_compaction_test.dart` (сценарии «Preflight после сжатия опирается на tokensAfter», «Аварийное сжатие и preflight на одной шкале», «Завышающая эвристика не завершает ход исчерпанием окна»): переписать тест D9 предшественника — тот же риг (usage заметно ниже эвристики, длинный `AGENTS.md`), но ожидается одна запись `compaction` и один запрос суммаризатора; `ModelRequested.estimatedTokens` повторного запроса — `tokensAfter` записи (плюс изменившаяся часть); `TurnEnded(completed)`, `contextExhaustedText` нет. Новый случай: эвристика проекции после сжатия выше окна, резать больше нечего — на коде предшественника ход `failed` с `context window exhausted` после трёх проходов; ожидается один проход и `completed`. Итоговую проверку «запрос не больше окна» считать через `ModelRequested.estimatedTokens`, а не `estimateLlmContext` без якоря.
  - `test/compaction/after_turn_test.dart` (D3, сценарий «Оценка сразу после сжатия равна tokensAfter»): после `afterTurn`-сжатия с `tokensAfter` в пороге и эвристикой выше порога следующий ход без ответа с usage (scripted-модель отвечает без usage) не запускает новое `afterTurn`-сжатие; `ModelRequested.estimatedTokens` первого запроса следующего хода — `tokensAfter + H(нового сообщения)`.
  - `test/compaction/skills_reattach_test.dart` (сценарий «Навыки после резюме не считаются дважды»; D4): после сжатия с приложенным сообщением навыков `ModelRequested.estimatedTokens` следующего запроса — `tokensAfter + H(нового сообщения)`.
  - `test/runtime/load_session_test.dart` (сценарии «Загрузка сессии после сжатия», «Несколько сжатий и ветки»; D5): сжатие последним событием ветки → закрыть → загрузить → `ModelRequested.estimatedTokens` первого запроса — `tokensAfter + H(нового сообщения)`; журнал с двумя ветками, где более поздняя запись `compaction` лежит на неактивной ветке, — якорь из записи активной; журнал с `tokensAfter: 0` — чистая эвристика.
  - Изменение схем после сжатия (сценарий «Изменение схем после сжатия»; D7): после сжатия сессия меняет набор инструментов (смена режима или агента с другим набором) — оценка следующего запроса отличается от `tokensAfter + H(хвоста)` ровно на разницу эвристик схем.
  - Отмена и ошибка (сценарии «Ошибка суммаризатора», «Отмена посреди генерации» в части якоря; R4): после неудачного и отменённого сжатия `ModelRequested.estimatedTokens` следующего запроса считается от прежнего якоря.
- [x] 1.2 `[agent]` Пересмотр существующих тестов, закрепивших D9 или эвристику после сжатия (характеризационный шаг, `AGENTS.md` ядра §2, исключение (а)): прогнать `fvm dart test` в `codelab_agent_core` на коде до 1.3 с тестами 1.1 и выписать падающие, кроме новых. Уже известны (по коду после merge `e954ee24`): тесты D9 в `compactor_test.dart` (группа с `(D1, D9)`, `(D3, D9)`, `(D9, CMP-5)`), выброс навыков по окну через `max` — `skills_reattach_test.dart` («D9: the window drop compares max(after, H(after))»); `preflight_after_compaction_test.dart` (две записи, два запроса суммаризатора, проверка `estimateLlmContext ≤ window`); возможно `long_session_test.dart` и `overflow_then_compact_test.dart`, если считают «после» через `estimateLlmContext` без якоря. Переписать с сохранением проверяемого поведения; каждую правку сопроводить комментарием со ссылкой на D8 или CMP-11.
- [ ] 1.3 `[agent]` Реализация оценки (1.1, первые два пункта; D1, D2, D6):
  - `lib/src/session/projections.dart`: поле `LlmContextProjection.compactionCovered` (число начальных сообщений, порождённых последней записью `compaction` и сохранённой частью до неё; 0 без сжатия) с doc-комментарием (почему, для чего, как; §8.7, D1);
  - `lib/src/compaction/estimate.dart`: `typedef CompactionAnchor = ({int tokens, int raw})`, параметр `CompactionAnchor? compaction` у `estimateContextTokens`, `compactionAnchorOf(projection, systemPrompt:, tools:)`; doc-комментарии по §15 корневого `AGENTS.md` со ссылками на D1, D2, D6; в барель не экспортируются.
- [ ] 1.4 `[agent]` Реализация компактора (1.1, `compactor_test.dart`; D8): параметр `CompactionAnchor? anchor` у `compact` для `before` первого прохода; сравнения с порогом (CMP-5, оба условия и цикл выброса навыков по окну) — по `after`; `raw` пробной проекции остаётся только для `estimateAfterCompaction`. Doc-комментарий `compact` и комментарии у порога и выброса навыков переписать (ссылка на D8 вместо D9).
- [ ] 1.5 `[agent]` Реализация сессии (1.1, тесты рантайма и загрузки; D3, D5): `lib/src/runtime/agent_runtime.dart` —
  - поле `_compactionAnchor` и один метод, который меняет транскрипт и якорь вместе; `onCompacted` для `afterTurn` и `manual` — через него; `_emergency` — якорь в `onCompacted` до возврата `LoopContext`;
  - оценщик сессии `(LlmContext c) => estimateContextTokens(..., compaction: _compactionAnchor)` для `AgentLoopConfig.estimateTokens` (только с capability `compaction`, как сейчас) и `contextEstimator`; `_compactAfterTurn` — тем же оценщиком; `_compact` передаёт `anchor: _compactionAnchor`;
  - `loadSession`: якорь фиксируется после `_restoreAgent` по проекции, которой восстановлен транскрипт, с промптом и схемами восстановленного агента (D5).
  Doc-комментарии полей и метода — почему, для чего, как (§15 корневого `AGENTS.md`), со ссылками на D3, D5, CMP-11.
- [ ] 1.6 `[agent]` Рефакторинг и сверка документов с кодом: имена и шаги `09-compaction.md` §9.3, §9.8, §9.9 и `08-sessions.md` §8.7 совпадают с кодом; упоминаний D9 и `max(after, raw)` в коде и комментариях не осталось; `estimateLlmContext` либо используется, либо удалён, если потребителей не осталось (без мёртвого кода).

## 2. Спецификация

- [ ] 2.1 `[agent]` Перед архивацией этого change убедиться, что `fix-compaction-estimate-and-no-gain` заархивирован и требования «Согласованная оценка после сжатия» и «Запись сжатия и пересборка» в его редакции есть в `openspec/specs/agent-compaction/spec.md`: MODIFIED этого change заменяет именно их. `openspec validate anchor-context-estimate-after-compaction --strict`.

## 3. Проверки

- [ ] 3.1 `[agent]` `fvm dart format --set-exit-if-changed` изменённых файлов; `fvm dart analyze` и `fvm dart test` в `packages/dart/codelab_agent_core`.
- [ ] 3.2 `[agent]` `fvm dart test` в `packages/dart/codelab_agent_acp` (снимки `_codelab/session/usage`: `usage_projection_test.dart`, `usage_bridge_test.dart`, `builtin_commands_bridge_test.dart`) и `fvm dart run melos run conformance:agent` (фикстуры `acp/slash-compact`, `acp/compact-usage-context`, `acp/compaction-long-session-continues`; ожидание по D10 — без правок фикстур). Если фикстура краснеет — остановиться и вернуть вопрос архитектору: правка фикстуры — задача `[protocol]` со ссылкой на D8.
- [ ] 3.3 `[agent]` `fvm dart run melos run web-compile` (изменён web-безопасный `codelab_agent_core`).
