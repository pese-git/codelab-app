Пары «тест → реализация»: сначала красный тест. Коммит красного теста — только по просьбе пользователя (`CLAUDE.md`).

Предусловие: в ветке есть код `extend-secret-name-redaction` (правило userinfo в `redactText`) и `strip-fetch-url-userinfo` (D5). Без первого тесты с `https://<redacted>@` не позеленеют.

Сокращения сценариев:
- «Строка» — требование «Строка инструмента без сырого JSON» spec `acp-client-kit`;
- «REPL» — требование «Рендер хода в REPL» spec `codelab-cli`.

## 1. `codelab_client_core`: вторая строка и метка `other`

Пути — в `packages/dart/codelab_client_core`.

- [x] 1.1 `[client]` Красные тесты в `test/transcript/tool_row_test.dart`, группа `secondary line`:
  - упавший `fetch` с выводом `Error: request to https://user:pass@host/x failed\n    at fetch (node:internal)` → `secondary` равна `Error: request to https://<redacted>@host/x failed`, нет `user:pass` и `pass@` («Строка»: «Вторая строка упавшего вызова без учётных данных»; D1);
  - вывод `\u001b[31mError:\tboom\u001b[0m` → `Error: boom` («Строка»: «Вторая строка без управляющих символов»; D1);
  - вывод `\u001b[0m\nreal error` → `real error`; вывод `\u001b[0m` → `secondary` равна `null` («Строка»: «Строка из одних управляющих символов пропускается»; D3);
  - первая строка `'a' * 130 + ' https://user:password@host/x/' + 'b' * 40` (200 символов): адрес целиком лежит до предела, а усечение приходится на хвост из `b` после него → длина 160, конец `…`, есть `https://<redacted>@`, нет `user` и `passw` («Строка»: «Длинная вторая строка усечена после маскирования»; D1). Пример `'a' * 140 + ' https://user:password@host/x'` нереализуем: после маски строка короче, и усечение до 160 срезает `@`;
  - упавший вызов `agent` (`subagentCall`) с выводом `auth failed for https://user:pass@host/x` → `auth failed for https://<redacted>@host/x` («Строка»: «Вторая строка вызова agent»; D1).

  Существующие тесты `a failed call shows the first line of its text output` и `a completed call has no secondary line` не меняются и остаются зелёными.
- [x] 1.2 `[client]` Красные тесты метки `other` там же, группа `mode switch and unknown kind` или новая:
  - `other`, `title` `curl https://user:pass@host/x`, без `rawInput` → `ToolRowView(label: 'curl https://<redacted>@host/x')`, деталь пуста, нет `pass` («Строка»: «Метка вызова other без секрета»; D2);
  - `other`, `title` `mcp\u001b[2J__db__stats` → метка без `\u001b` («Строка»: «Метка вызова other без управляющих символов»; D2);
  - вызов неизвестного вида с секретом в `title` → метка замаскирована, как у `other` (D2, forward compatibility).

  Существующие тесты `mcp__db__stats`, `Plan sync`, `Tool` для пустого `title` не меняются.
- [x] 1.3 `[client]` Реализация в `lib/src/transcript/tool_row.dart`:
  - `_firstLine` возвращает `_clean` первой строки первого текстового элемента, непустой после `_clean`, иначе `null` (D1, D3). Вызывается в `format` и в `_agentRow`;
  - `_labelOf` для `ToolKind.other` возвращает `_clean(title)`, пустой `title` даёт `Tool` (D2);
  - проверка «деталь пуста или равна метке» сравнивает очищенный `title` с меткой явно (D2).

  Doc-комментарии на русском по `AGENTS.md` §15 (почему, для чего, как):
  - у `ToolRowView.secondary` и `ToolRowView.label`: поле очищено и замаскировано;
  - у `_clean`: применяется к детали, метке `other` и второй строке, маскирование до усечения;
  - у `_firstLine`: выбор строки до очистки и маскирование одной строки, а не элемента (D3).

  Ссылки: design.md change `redact-tool-row-text`, D1–D3. Тесты 1.1 и 1.2 зелёные, `_hostAndPath` не меняется.

## 2. `apps/codelab_cli`: строка инструмента REPL и TUI

Пути — в `apps/codelab_cli`.

- [x] 2.1 `[client]` Красные тесты в `test/render/tool_row_test.dart`:
  - завершённый `execute` с `title` `Fetch https://user:s3cr3t@host/x` и `command` `curl https://user:s3cr3t@host/x?token=t0k3n` → строка начинается с `✓ `, содержит `https://<redacted>@host/x`, нет `s3cr3t` и `t0k3n` («REPL»: «Строка инструмента без секретов»; D4);
  - многострочная команда `curl -H "Authorization: Bearer t0k3n" https://host/x\n  --retry 3` → в строке нет `t0k3n`, первая строка кончается ` …`, как раньше (D4: маскирование, затем первая строка);
  - `title` и `command` с одинаковым секретом → команда не повторяется после названия: проверка `!title.contains(detail)` работает по замаскированным значениям (D4);
  - `Run tests` + `npm test`, `elapsed: 100 ms` → строка равна прежней, `✓ Run tests npm test 0.1s` («REPL»: «Строка инструмента без секретов не меняется»).

  Все прежние тесты файла и `test/render/terminal_renderer_test.dart` не меняются.
- [x] 2.2 `[client]` Красный тест TUI в `test/tui/` (рядом с тестами `transcript_lines.dart`): строка обычного вызова и вложенного вызова потомка с секретом в `title` не содержит секрета. TUI вызывает тот же `toolRow`, поэтому тест закрепляет, что путь TUI не обходит маскировку (требование «Кадр TUI» spec `codelab-tui`: «тем же правилом, что в REPL»).
- [x] 2.3 `[client]` Реализация в `lib/src/render/tool_row.dart`:
  - импорт `package:codelab_client_acp/codelab_client_acp.dart` (`show SecretRedactor`);
  - `const _redactor = SecretRedactor();` уровня библиотеки;
  - название и команда: `sanitizeTerminalText` → `_redactor.redactText` → `_firstLine` (D4).

  Doc-комментарий `toolRow` на русском: «Текст агента проходит `sanitizeTerminalText` и `SecretRedactor`», почему порядок такой (D4). `subagentStatusRow` не меняется. Тесты 2.1 и 2.2 зелёные.

## 3. Хвост вывода и десктоп (D7)

- [x] 3.1 `[client]` Красные тесты `ToolRowFormatter.outputTail` в `packages/dart/codelab_client_core/test/transcript/tool_row_test.dart`, новая группа `output tail`, сценарии требования «Хвост вывода строки инструмента»:
  - хвост с `DATABASE_URL=postgres://user:pass@db/app` замаскирован, переводы строк сохранены;
  - 30 строк, `maxLines: 20` → строки 11–30; вывод из нескольких элементов, где граница хвоста проходит внутри элемента;
  - однострочная ошибка с табом и паролем → `null`, а `secondary` замаскирована;
  - `Error: boom\n    at main (a.dart:1)` → весь вывод;
  - одна строка из 300 символов → вся строка, `secondary` усечена;
  - вызов `agent` → `null`; пустой вывод → `null`;
  - успешный вызов без `secondary` с одной строкой → строка, а не `null`.

  Тесты не компилируются, пока функции нет. Это и есть красное состояние.
- [x] 3.2 `[client]` Реализация `ToolRowFormatter.outputTail` в `lib/src/transcript/tool_row.dart` по D7:
  - обход элементов с конца до `maxLines` строк, без склейки всего вывода;
  - `redactText` по хвосту;
  - правило повтора по `_clean` и длине до усечения.

  Doc-комментарий на русском (почему, для чего, как): клиент передаёт свой предел строк, `null` значит «показывать нечего или вывод повторяет вторую строку». Экспорт из барреля не нужен, если `ToolRowFormatter` уже экспортирован. 3.1 зелёный.
- [x] 3.3 `[desktop]` Красный тест маппера `apps/codelab_desktop/test/features/workbench/application/tool_call_row_secrets_test.dart` через `transcriptRowsOf`:
  - упавший `fetch` с единственной строкой `Error: request to https://user:pass@host/x failed` → `secondary` без `pass`, `output` пуст;
  - завершённый `read` с выводом `API_KEY=sk-live-123\nDEBUG=1` → `output` без `sk-live-123`, с `DEBUG=1`;
  - упавший вызов с двухстрочным выводом → `output` содержит обе строки;
  - вызов `other` с `title` `curl https://user:pass@host/x` → `label` без `pass`;
  - вызов `agent` → `output` по-прежнему из `report`.

  Сценарии: «Вывод раскрытой строки инструмента без секретов», «Строка»: «Метка вызова other без секрета». Красные: `output` сейчас — сырой `textOutput`.
- [x] 3.4 `[desktop]` Красный виджет-тест ленты `apps/codelab_desktop/test/features/workbench/presentation/tool_call_output_secrets_test.dart`: раскрытая строка упавшего `fetch` показывает текст `Error: request to https://<redacted>@host/x failed` ровно один раз, а текста `pass` нет («Упавший fetch с паролем в ошибке»). Раскрытый `read` не показывает `sk-live-123` («Вывод успешного вызова замаскирован»).
- [x] 3.5 `[desktop]` Реализация в `apps/codelab_desktop/lib/features/workbench/application/ui_mappers.dart`, `_toolCallRowOf`: для не-`agent` вызова `output: [?ToolRowFormatter.outputTail(call, maxLines: CodeLabToolCallTile.outputTailLines)]`; ветка `agent` (`report`) прежняя. Комментарий у выражения: почему kit, а не виджет, и ссылка на D7. `codelab_ui` не меняется. 3.3 и 3.4 зелёные.
- [x] 3.6 `[desktop]` Прогнать тесты ленты: `fvm flutter test test/features/workbench` в `apps/codelab_desktop`. Ожидания вывода с табами и двойными пробелами в одной строке, если такие есть, исправляются по D7 со ссылкой на сценарий.

## 3а. Исправления ревью

Пары «тест → реализация», исполнитель — `client-engineer`.

- [x] 3а.1 `[client]` Красные тесты `outputTail` в `packages/dart/codelab_client_core/test/transcript/tool_row_test.dart`:
  - «Токен на границе хвоста»: `Authorization: Bearer`⏎`t0k3n-value` на границе, `maxLines: 5` → нет `t0k3n-value`; то же для `password:`⏎`<значение>` (D7, п. 3);
  - «Приватный ключ длиннее хвоста»: BEGIN, 40 строк тела, END, `done`, `maxLines: 20` → нет строк тела, есть `<redacted>` и `done` (D7, п. 3а);
  - END без BEGIN в середине окна, после него обычные строки → строки после END видны;
  - BEGIN и END оба в окне → маскирует `SecretRedactor`, как раньше;
  - O(окно): вывод из одного элемента в 5 МБ с 20 строками в конце, `maxLines: 20` → время не зависит от объёма, бюджет — как у тестов линейности `secret_redaction_test.dart`. Тест проверяет, что весь вывод не разбивается (D7, п. 2).
- [x] 3а.2 `[client]` Реализация в `lib/src/transcript/tool_row.dart`:
  - окно из `maxLines + 1` строк сканированием с конца через `lastIndexOf('\n')`, без `split` и без склейки всего вывода;
  - замена участка «начало окна … END» маской при END без BEGIN;
  - `redactText` по окну, затем последние `maxLines` строк.

  Doc-комментарий `outputTail` обновить: зачем лишняя строка, зачем правило END, сложность (D7). 3а.1 зелёный, тесты 3.1 не меняются.
- [x] 3а.3 `[client]` Красный тест в `apps/codelab_cli/test/render/tool_row_test.dart`: «ESC-последовательность не прячет токен» (spec `codelab-cli`) — команда `curl -H 'Authorization: Bearer\u001b[0m t0k3n' https://host/x` → нет `t0k3n` и `[0m` (D4, шаг 0).
- [x] 3а.4 `[client]` Реализация в `apps/codelab_cli/lib/src/render/tool_row.dart`: перед `sanitizeTerminalText` CSI-последовательности заменяются пробелом выражением `\x1B\[[0-9;?]*[ -/]*[@-~]`, как в `_clean` kit. Выражение `static final`, комментарий ссылается на D4. 3а.3 зелёный. Прежний тест `control characters from the agent are removed` меняет ожидание: остаток `[31m` больше не попадает в строку, CSI заменяется пробелом (`… Run  x`); остальные тесты строки не меняются.
- [x] 3а.5 `[client]` Повторить проверки 5.1 по изменённым файлам.

- [x] 3а.6 `[client]` Красные тесты `outputTail`: BEGIN с телом без END в окне, ключ в процессе вывода (строки до BEGIN остаются) → реализация: остаток BEGIN после шага 3а маскируется до конца окна (D7, п. 3б; «Приватный ключ без конца»).

## 4. Документы

- [x] 4.1 `[client]` (правит `codelab-architect`) `docs/architecture/proposals/dart-agent-and-clients/12-1-view-model.md`: §12.1.6 шаги 2, 3, 5 и VIEW-9 по D6.
- [x] 4.2 `[client]` (правит `codelab-architect`) `docs/architecture/proposals/dart-agent-and-clients/12-2-cli-display-and-input.md`, §12.2.4: правило маскировки названия и команды (D6).
- [x] 4.3 `[client]` Сверить diff с `packages/dart/codelab_client_core/README.md`, `apps/codelab_cli/README.md` и `doc/`, `apps/codelab_desktop/README.md` и `docs/user/`. Если строка инструмента или маскировка там описаны — передать документ `docs-writer`; иначе отметить «правка не нужна». Сверено: `README.md` пакетов и приложений правила строки инструмента не описывают, правка не нужна. Поведение, видимое пользователю (`<redacted>` в строке инструмента CLI и в раскрытой строке app), стоит добавить в руководства — передано `docs-writer`:
  - `apps/codelab_desktop/doc/user-guide.md`, раздел о ленте (около пункта 3 «Ответ появляется в ленте…»): секреты в строке вызова, второй строке ошибки и выводе раскрытой строки показываются как `<redacted>`; в журналах сессий — как есть;
  - `apps/codelab_cli/doc/user-guide.md`, пункт «До версии 1.0 вывод инструментов… не очищаются» (раздел заметок): уточнить, что строка инструмента в терминале маскирует секреты, а журналы и запросы провайдеру — нет;
  - `docs/user/configuration.md`, «Что попадает в логи и журналы»: та же оговорка «маскируется только показ, не журнал». Правка необязательна, по решению `docs-writer`.

## 5. Проверки (§21)

- [x] 5.1 `[client]` Проверки затронутого:
  - `fvm dart format --set-exit-if-changed` по изменённым файлам `codelab_client_core` и `apps/codelab_cli`;
  - `fvm dart analyze` в `packages/dart/codelab_client_core` и `apps/codelab_cli`;
  - `fvm dart test` в `packages/dart/codelab_client_core` и `apps/codelab_cli`;
  - `melos run guard`: новый межпакетный импорт в `apps/codelab_cli/lib/src/render/`;
  - `melos run conformance:client`: изменён клиентский слой транскрипта;
  - `melos run test:e2e:cli:dart-agent` и `melos run test:e2e:cli:embedded`: изменён вывод CLI.

  `web-compile` не нужен: импорты `codelab_client_core` не меняются.
- [x] 5.2 `[desktop]` Проверки десктопа:
  - `fvm dart format --set-exit-if-changed` по `ui_mappers.dart` и новым тестам;
  - `fvm flutter analyze` в `apps/codelab_desktop`, потому что публичный API `codelab_client_core` пополнен;
  - тесты — 3.6.
- [ ] 5.3 `[client]` `openspec validate redact-tool-row-text --strict` зелёный. Перед архивацией убедиться, что `strip-fetch-url-userinfo` уже в архиве (D5, порядок архивации).

Полный `melos run check` — только по просьбе пользователя.
