## ADDED Requirements

### Requirement: Проверка доказательств матрицы целей
Тест `packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart` SHALL разбирать матрицу целей `docs/architecture/proposals/agent-parity-goals.md` и проверять доказательства каждой строки Must (задача 9.1; design.md change `switch-default-agent-to-dart`, D2–D5).

**Разбор.**
- Тест SHALL брать строки с приоритетом `Must` из таблиц §3 (заголовок с колонкой «Приоритет») и все строки таблицы §4.1.
- Строка таблицы, у которой число ячеек отличается от заголовка, SHALL быть ошибкой разбора с номером строки файла, какой бы ни был её приоритет. Ячейки делятся по `|`, не экранированному `\`.
- Число найденных строк Must SHALL совпадать с итогом Must сводки §7; расхождение — ошибка разбора.
- Доказательства строки SHALL извлекаться из фрагментов в обратных кавычках колонки «Критерий приёмки»:
  - `acp/<id>`;
  - `cli/<id>`;
  - `core/<id>`;
  - `app:<файл>`;
  - путь файла теста (`packages/…_test.dart`, `apps/…_test.dart`);
  - шаблоны `acp/*` и `app:*`.
  Строка Must без единого доказательства SHALL получать статус `missing`. Строка закрыта, только если закрыто каждое её доказательство.

**Существование** проверяется в каждом запуске, без отчётов.
- Правила:
  - `acp/<id>` — есть `packages/dart/codelab_acp_testing/fixtures/acp/<id>.json`;
  - `cli/<id>` — в `apps/codelab_cli/test/e2e/` есть вызов `test(` или `group(`, не вложенный в тело другого `group(`, первый строковый литерал которого начинается с `cli/<id>`, а за id идёт конец литерала, `:` или пробел (id — начало полного имени теста в отчёте; design.md, D3, уточнение 2026-11-10);
  - `core/<id>` — то же в тестах `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `codelab_agent_mcp`, `codelab_embedded` и `apps/codelab_agent`;
  - `app:<файл>` — есть `apps/codelab_desktop/integration_test/<файл>`;
  - путь файла теста — файл есть.
- Упоминание id в комментарии НЕ SHALL считаться тестом.
- Нарушение SHALL ронять тест строкой `<строка> <доказательство> missing`. Исключение — записи временного списка известных пробелов `knownGaps` с номером задачи: они печатаются строкой `known gap: …`.
- Запись `knownGaps`, доказательство которой существует, SHALL ронять тест строкой `stale known gap: …`.

**Статус** проверяется только при заданной переменной `CODELAB_PARITY_RESULTS` — каталоге отчётов (требование «Машинные отчёты прогонов»).
- Без переменной группа статуса SHALL пропускаться с причиной `CODELAB_PARITY_RESULTS is not set: status is checked by the nightly parity job`.
- Если переменная задана, а каталога или файла `meta.json` нет, тест SHALL падать.
- Статус доказательства SHALL быть одним из пяти:
  - `pass` — в обязательном источнике (design.md, D5) есть хотя бы один пройденный тест id, ни одного пропущенного и ни одного упавшего в любом источнике;
  - `failed` — тест id упал в любом источнике или упал набор, в котором он лежит;
  - `skipped` — тест id пропущен в обязательном источнике либо в дополнительном с причиной вне перечня `allowedSkips`; для доказательства-пути файла теста — пропущен тест файла с причиной вне перечня `allowedSkips` (пропуск по перечню строку не открывает, решение Q8);
  - `not-run` — в обязательном источнике нет ни одного теста id, в том числе исключённого тегом `scripted-only`;
  - `missing` — доказательство не существует; `knownGaps` на статус не действует.
- Тест принадлежит id, если его полное имя в отчёте начинается с id, а за id идёт конец, `:` или пробел.
- Без переменной `CODELAB_PARITY_APP_RESULTS` доказательства `app:` SHALL получать статус `deferred`: он печатается, но тест не роняет. С переменной они проверяются по отчётам app.
- Тест SHALL падать, если хотя бы одно доказательство строки Must не `pass` и не `deferred`. Сообщение — строки `<строка> <доказательство> <статус> [<источник>] [<причина>]`, отсортированные по id строки, а первой строкой — содержимое `meta.json`.

Логика разбора и свёртки SHALL проверяться модульными тестами на временном дереве: своя матрица, фикстуры и отчёты. Настоящая матрица для них не нужна.

#### Scenario: Нет файла фикстуры
- **WHEN** строка Must временной матрицы ссылается на `acp/slash-help`, файла фикстуры нет, а `knownGaps` пуст
- **THEN** проверка существования падает со строкой `R-08 acp/slash-help missing`

#### Scenario: Id только в комментарии
- **WHEN** id `core/x` встречается в тестах только в комментарии `// core/x`
- **THEN** доказательство `core/x` — `missing`

#### Scenario: Id во вложенном тесте
- **WHEN** `test('core/x: …')` вложен в `group('другое имя', …)`, а других вызовов с `core/x` нет
- **THEN** доказательство `core/x` — `missing`: полное имя в отчёте начинается с `другое имя`

#### Scenario: Id во внешней группе
- **WHEN** `group('core/x', …)` стоит на верхнем уровне `main`, а внутри него тесты с другими именами
- **THEN** доказательство `core/x` существует

#### Scenario: Известный пробел
- **WHEN** `acp/slash-help` нет, а пара (`R-08`, `acp/slash-help`) есть в `knownGaps`
- **THEN** проверка существования проходит и печатает `known gap: R-08 acp/slash-help`

#### Scenario: Устаревшая запись knownGaps
- **WHEN** пара из `knownGaps` указывает на существующую фикстуру
- **THEN** проверка существования падает со строкой `stale known gap: …`

#### Scenario: Сломанная строка таблицы
- **WHEN** строка таблицы §3 содержит неэкранированный `|` внутри обратных кавычек, и число ячеек больше, чем в заголовке
- **THEN** тест падает с ошибкой разбора и номером строки файла

#### Scenario: Число строк Must не совпадает со сводкой
- **WHEN** во временной матрице 3 строки Must, а итог сводки §7 — 4
- **THEN** тест падает с ошибкой разбора

#### Scenario: Без отчётов
- **WHEN** `fvm dart run melos run guard` выполняется без `CODELAB_PARITY_RESULTS`
- **THEN** группа статуса пропущена с причиной, а прогон зелёный, если существование в порядке

#### Scenario: Каталог отчётов без meta.json
- **WHEN** `CODELAB_PARITY_RESULTS` указывает на пустой каталог
- **THEN** тест падает с сообщением об отсутствии `meta.json`

#### Scenario: Тест scripted-only в режиме dart
- **WHEN** единственный тест `cli/x` имеет тег `scripted-only` и потому отсутствует в `cli-dart.json`
- **THEN** доказательство `cli/x` — `not-run`, тест падает

#### Scenario: Падение в дополнительном источнике
- **WHEN** фикстура `acp/x` проходит в отчёте `conformance:agent`, но в `scenario-embedded.xml` у неё `failure`
- **THEN** доказательство `acp/x` — `failed` с источником `scenario-embedded.xml`

#### Scenario: Пропуск по спецификации в дополнительном источнике
- **WHEN** фикстура `acp/mcp-stdio-tool-call` проходит в `conformance:agent`, а в `scenario-embedded.xml` пропущена с причиной `setup.mcp cannot be passed to the agent process`
- **THEN** доказательство — `pass`

#### Scenario: Отчёты app не переданы
- **WHEN** задана только `CODELAB_PARITY_RESULTS`, а строка Must ссылается на `app:fs_flow_test.dart`
- **THEN** доказательство печатается как `deferred`, и тест из-за него не падает

### Requirement: Машинные отчёты прогонов
Если переменная окружения `CODELAB_TEST_REPORT_DIR` задана и не пуста, Melos-скрипты SHALL дополнительно писать машинные отчёты в этот каталог (design.md change `switch-default-agent-to-dart`, D6):
- `test` и `test:dart` — JSON-отчёт `package:test` (`--file-reporter json:`) на каждый пакет: `flutter/<пакет>.json` и `dart/<пакет>.json`;
- `conformance:agent` и `conformance:client` — `dart/<пакет>.conformance.json`;
- `test:e2e:cli:dart-agent` и `test:e2e:cli:embedded` — `cli-dart.json` и `cli-embedded.json`;
- `conformance:embedded` — JUnit `scenario-embedded.xml` (`codelab test-scenario --junit`);
- `test:e2e:app:dart-agent` и `test:e2e:app:embedded` — `app/<режим>/<файл>.json` на каждый файл и `app/<режим>/meta.json` с коммитом, версией macOS и временем.

Скрипт SHALL создавать нужные подкаталоги. Без переменной команды скриптов, их вывод и коды выхода SHALL оставаться прежними. Упавший тест SHALL попадать в отчёт, а код выхода скрипта — оставаться ненулевым.

#### Scenario: Без переменной
- **WHEN** `fvm dart run melos run test:e2e:cli:dart-agent` выполняется без `CODELAB_TEST_REPORT_DIR`
- **THEN** ни одного файла отчёта не создано, вывод и код выхода прежние

#### Scenario: Отчёт e2e CLI
- **WHEN** тот же скрипт выполняется с `CODELAB_TEST_REPORT_DIR=<tmp>`
- **THEN** `<tmp>/cli-dart.json` содержит события `testStart` и `testDone` с именами, начинающимися с `cli/`, и событие `done`

#### Scenario: Отчёт пакета через melos exec
- **WHEN** `fvm dart run melos run test:dart` выполняется с `CODELAB_TEST_REPORT_DIR=<tmp>`
- **THEN** для каждого пакета с каталогом `test` есть `<tmp>/dart/<имя пакета>.json`, и ни один файл не называется `.json` без имени

#### Scenario: Упавший тест в отчёте
- **WHEN** один тест набора падает при заданной переменной
- **THEN** в отчёте у него `testDone` с `result` `failure` или `error`, а скрипт завершается с ненулевым кодом

### Requirement: Ночная проверка доказательств в CI
CI SHALL ночью публиковать машинные отчёты и проверять по ним доказательства матрицы целей. Для событий `schedule` и `workflow_dispatch` в `.github/workflows/ci.yml` (design.md change `switch-default-agent-to-dart`, D7):
- каждый джоб матрицы `checks` SHALL выполняться с `CODELAB_TEST_REPORT_DIR` и публиковать каталог отчётов артефактом `parity-results-<джоб>` даже при падении джоба, кроме случая утечки секрета: если проверка утечек, выполненная в окружении джоба перед загрузкой, нашла значение секрета, артефакт НЕ SHALL публиковаться, а джоб SHALL быть красным;
- джоб `parity` SHALL запускаться после `checks`, в том числе после красного `checks`;
- `parity` SHALL собрать артефакты в `parity-results/` и записать `parity-results/meta.json` с полями `commit`, `ref`, `event`, `run_id`, `run_attempt`, `created_at`;
- `parity` SHALL выполнить `fvm dart test packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart` с `CODELAB_PARITY_RESULTS=parity-results`;
- `parity` SHALL опубликовать `parity-results` артефактом со сроком хранения 90 дней и вывести итог в Step Summary; перед загрузкой он SHALL так же проверить утечки, и при утечке артефакт НЕ SHALL публиковаться.

Для `pull_request` и `push` переменная отчётов НЕ SHALL задаваться, а джоб `parity` НЕ SHALL запускаться. Агрегатор `ci` SHALL принимать результат `parity` `success` или `skipped`.

Правило охвата pull request (`tool/ci/ci_scope.dart`): изменение `docs/architecture/proposals/agent-parity-goals.md` SHALL добавлять джоб `guard`, даже если остальные изменённые файлы — только документация.

Проверка утечек (design.md change `switch-default-agent-to-dart`, D16) SHALL падать, если в файле каталога отчётов найдено значение длиной от 8 символов переменной окружения процесса из набора имён D16 (`TOKEN`, `KEY`, `SECRET` и другие, без учёта регистра; в сыром, JSON- и XML-экранированном виде), а также если в каталоге есть символическая ссылка. Маркер `sk-test-leak-` блокирует только в отчётах app; в отчётах CI он даёт предупреждение в логе. Само значение проверка НЕ SHALL печатать.

#### Scenario: Ночной запуск публикует отчёты
- **WHEN** CI запускается по `schedule`
- **THEN** у запуска есть артефакты `parity-results-<джоб>` для каждого джоба матрицы и итоговый артефакт `parity-results` с `meta.json`

#### Scenario: Pull request без parity
- **WHEN** CI запускается на pull request
- **THEN** джоб `parity` пропущен, артефактов `parity-results*` нет, а агрегатор `ci` зелёный при зелёных `checks`

#### Scenario: Красные checks ночью
- **WHEN** ночью падает джоб `e2e-cli-dart`
- **THEN** джоб `parity` всё равно выполняется и называет доказательства `cli/*` со статусом `failed` или `not-run`

#### Scenario: Правка только матрицы
- **WHEN** pull request меняет только `docs/architecture/proposals/agent-parity-goals.md`
- **THEN** `ciScope` возвращает джоб `guard`

#### Scenario: Секрет окружения в отчёте
- **WHEN** окружение содержит `FOO_TOKEN=sk-test-leak-0123456789`, и это значение встречается в файле `parity-results/`
- **THEN** `parity_evidence_test` падает с именем файла, а вывод не содержит `sk-test-leak-0123456789`
