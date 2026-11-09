## Context

Этап 9 — последний этап вехи M3 (MVP). Источники:
- [план этапа 9](../../../docs/architecture/proposals/dart-agent-and-clients/09-14-stage-9-switch-default.md) — задачи 9.1–9.11, чек-лист Zed, Definition of Done, состав changes этапа;
- [матрица целей](../../../docs/architecture/proposals/agent-parity-goals.md) — §1.4 (виды критериев), §3 и §4.1 (строки Must), §6 (критерий вывода Python-агента);
- [дорожная карта](../../../docs/architecture/proposals/delivery-roadmap.md) — §4.4 (M3), §4.5 (M4), §8, §9.1 (TDD);
- [`docs/architecture/adr/README.md`](../../../docs/architecture/adr/README.md) — чек-листы §24 и §25 для 9.7;
- design.md change [`add-app-settings-shell`](../archive/2026-11-05-add-app-settings-shell/design.md) (D5, D7, D21) и [`add-provider-setup-ui`](../archive/2026-11-09-add-provider-setup-ui/design.md) (9.6);
- `docs/architecture/testing.md`, `acp-boundary.md`, `permissions.md`, `concurrency.md`, `observability.md`.

Что уже есть в коде (`develop` на 9d61ed64):
- **Профиль по умолчанию — встроенный агент** в app и CLI. `default` — алиас `embedded`, id `default` и `embedded` зарезервированы (`reservedProfileIds`), старая запись `default` в `profiles.json` игнорируется с предупреждением (D5, D21 change `add-app-settings-shell`). Страница «Connection» показывает встроенного агента и профили `profiles.json`; встроенной строки stdio нет.
- **`codelabAgentStdioProfile`** (`codelab_acp_transports/lib/src/transport_configs.dart`) — `Codelab Agent`, `codelab serve --stdio`, `CODELAB_LOG_LEVEL=DEBUG`. В рабочем коде app на него ссылаются только `app_scope.dart` (`stdioAgentProfile()`, `_createDefaultTransport`). В тестах — `widget_test.dart`, `test_app_scope.dart` и тест пакета. Пользователь его не видит. Черновик «Add profile» (`ProfileDraft`) держит свои литералы `codelab-agent` / `serve --stdio`.
- **Ночной прогон** `ci.yml`: `schedule` 03:00 и `workflow_dispatch` запускают полный набор `fullJobs` (`tool/ci/ci_scope.dart`). Артефактов нет, машинных отчётов нет.
- **Корпус фикстур** — 58 фикстур `acp/*`. Имя теста — id фикстуры в трёх наборах:
  - `codelab_agent_acp/test/conformance_test.dart` (`conformance:agent`);
  - `apps/codelab_agent/test/transport_conformance_test.dart` — фикстуры с `setup.transport`;
  - `codelab_client_acp/test/fixtures/client_fixture_conformance_test.dart` (`conformance:client`).
  `codelab test-scenario` против `embedded` и `codelab-agent` по спецификации пропускает фикстуры с `setup.config`, `setup.mcp`, `setup.sessions`, `setup.web`, `setup.transport` (cli-scenario-driver). Таких фикстур 19, из них 15 — доказательства строк Must.
- **Имена тестов.**
  - `cli/<id>` — имена тестов или групп в `apps/codelab_cli/test/e2e/` (testing-quality «PTY-e2e терминального клиента»).
  - `core/<id>` в имени теста — только у 3 из 10 id. У 6 id он есть только в комментарии, ещё одного нет совсем (оценка ниже).
- **`--junit`** у `test-scenario` заложен в §9.11 (`[--junit <out.xml>]`), но не реализован (cli-scenario-driver его не содержит).

Ограничения:
- корневой `AGENTS.md`:
  - §2 — безопасность и данные пользователя выше удобства;
  - §3.4 — ACP не придумывать;
  - §5 — клиенты не импортируют `codelab_agent_*`; `codelab_acp_transports` основной барель web-безопасен;
  - §13 — пропорциональность;
  - §16 — секреты не в логах и отчётах;
  - §21 — Flutter-тесты app только в `release/*`;
- `packages/dart/codelab_agent_core/AGENTS.md` §2 — TDD, пары «тест → реализация»;
- матрица §1.7 — строка закрыта, когда зелёный её критерий, а не когда закрыта задача.

## Goals / Non-Goals

**Goals:**
- проверяемый одной командой ответ на вопрос «все ли строки Must закрыты и чем»;
- отчёты ночного прогона, по которым этот ответ получается без ручного сбора;
- встроенное описание stdio-агента указывает на `codelab-agent`;
- список задач 9.2 из отчёта, а не из памяти;
- документация MVP и предупреждение о Python-сессиях;
- заготовки ворот MVP: §6, три ночи, три прогона app, Zed, подписи.

**Non-Goals:**
- поставка, установщики, подписанные сборки, политика конфиденциальности (9.4, D-16, D-18);
- заморозка и удаление Python-агента, алиас `codelab serve` (`retire-python-agent`);
- песочница ОС (9.11, ADR);
- новые строки матрицы, изменение приоритетов, изменения ACP;
- запуск Flutter-тестов app в GitHub CI (`AGENTS.md` §21).

## Decisions

### D1. Объём и распределение задач этапа 9

| Задача | Где | Почему |
|---|---|---|
| 9.1 | этот change, итерация 1 | даёт отчёт для 9.2 |
| 9.2 | этот change, итерация 2 | задачи — из отчёта 9.1, пары «тест → реализация» по строке Must |
| 9.3 (вторая половина) | этот change, итерация 1 | первая половина — change `add-app-settings-shell` (D5, D21) |
| 9.4 | `add-release-pipeline-and-installer` | веха M4, Should |
| 9.5 | этот change, итерация 3 | scope этого change по плану этапа 9 |
| 9.6 | `add-provider-setup-ui` (архив) | сделано |
| 9.7 | этот change, итерация 3, без установки и `PRIVACY.md` | установка зависит от 9.4, политика — от D-18 (D12) |
| 9.8 | этот change, итерация 4 (таблица в этом файле) | проводит ответственный за релиз |
| 9.9 | `retire-python-agent` | по плану этапа 9 scope этого change — «заморозка, сроки удаления, алиасы команд» |
| 9.11 | ADR вехи M4 | не OpenSpec |

Заморозка Python-агента — пункт ворот MVP. Поэтому итерация 4 этого change ссылается на опубликованную политику заморозки из `retire-python-agent`. Сам этот change Python-агента не меняет: его код живёт вне monorepo.

*Альтернатива:* взять политику заморозки сюда отдельным документом. Тогда scope `retire-python-agent` пришлось бы делить, а план этапа 9 прямо относит заморозку к нему. Решение пользователя Q3 (б) подтвердило это распределение.

### D2. Где живёт проверка и как разбирается матрица

`packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart`. Логика — в `test/support/parity/`, как `import_scanner.dart` у сторожа:
- `matrix_parser.dart` — разбор матрицы;
- `evidence.dart` — доказательства и проверка их существования;
- `reports.dart` — чтение отчётов;
- `verdict.dart` — свёртка статусов.

Пакет только тестовый, `dart:io` в нём разрешён, новых зависимостей нет.

Разбор:
- источник — `docs/architecture/proposals/agent-parity-goals.md`;
- берутся таблицы §3, где в заголовке есть колонка «Приоритет» (строки с `Must`), и таблица §4.1 (все строки Must по тексту §4.1; в заголовке колонки «Приоритет» нет). Подтаблицы «Дано / Когда / Тогда» и §4.2 пропускаются: §4.2 закрывается строками §3 и §4.1 (матрица §7);
- ячейки делятся по `|` вне `\|`. В GFM `|` внутри обратных кавычек тоже делит ячейку, поэтому такой символ в матрице экранируется. Строка P-12 (`set|delete`) нарушала это правило, экранирование сделано задачей 0.3;
- строка с числом ячеек, отличным от заголовка, — ошибка разбора с номером строки, **какой бы ни был приоритет**: по сломанной строке нельзя надёжно понять, Must ли она;
- контрольная сумма: число строк Must должно совпадать с итогом сводки §7 («**Итого** | **77**»). Расхождение — ошибка. Так случайно потерянная строка не проходит молча.

*Альтернатива:* машинный файл матрицы (YAML) рядом с Markdown. Это два источника истины для одного каталога, и документ перестал бы быть единственным местом правки.

### D3. Доказательства строки

Из ячейки «Критерий приёмки» берутся фрагменты в обратных кавычках:

| Вид | Образец | Существует, если |
|---|---|---|
| `acp/<id>` | `acp/prompt-streaming-text` | есть `packages/dart/codelab_acp_testing/fixtures/acp/<id>.json` |
| `cli/<id>` | `cli/esc-cancels-turn` | в `apps/codelab_cli/test/e2e/**/*_test.dart` есть вызов `test(` или `group(`, первый аргумент которого — строковый литерал, начинающийся с `cli/<id>`; дальше конец строки, `:` или пробел |
| `core/<id>` | `core/overflow-triggers-compaction` | то же в `test/` пакетов `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `codelab_agent_mcp`, `codelab_embedded` и `apps/codelab_agent` |
| `app:<файл>` | `app:fs_flow_test.dart` | есть `apps/codelab_desktop/integration_test/<файл>` |
| путь теста | `packages/…/watchdog_test.dart` | файл есть; в статусе — все тесты файла `pass` (Q4) |
| шаблон | `acp/*`, `app:*` | `acp/*` — все фикстуры корпуса с ролью `agent`; `app:*` — все `integration_test/*_test.dart` (Q4) |

- Литерал имени может быть разбит на соседние литералы (`'cli/x: a ' 'b'`): берётся первый литерал после `test(` или `group(`.
- Упоминание id в комментарии тестом **не считается**: в отчёте `dart test` его не найти.
- Пути без каталога (`diagnostics/diagnostics_test.dart` в R-23) дополняются по пакету, указанному в той же ячейке выше. Если пакет не указан — это ошибка разбора с просьбой написать полный путь. Единственный такой путь (R-23) дописан задачей 0.3.
- Строка закрыта, только если закрыто **каждое** её доказательство. Повтор одного доказательства в ячейке (U-06) считается один раз.
- Пометки «закрыто change …», «новый», спецификации и разделы документов доказательствами не являются.

### D4. Два слоя проверки и храповик `knownGaps`

**Существование** — группа `matrix evidence exists`. Она не требует отчётов и идёт в каждом прогоне сторожа (`guard`, `test`). Сторож ловит, когда фикстуру переименовали, а строку матрицы — нет.

До конца 9.2 часть пробелов известна заранее, а красный сторож блокировал бы все pull request. Поэтому в тесте есть константа `knownGaps`: список пар «строка, доказательство» с номером задачи 9.2. Правила:
- пробел из списка не роняет группу, а печатается одной строкой `known gap: <строка> <доказательство> (task 2.x)`;
- запись, доказательство которой уже существует, роняет группу как устаревшая: `stale known gap: …, remove it`. Список может только уменьшаться;
- новый пробел вне списка роняет группу;
- задача 2.11 — список пуст. Сама константа удаляется, а вместе с ней проверка устаревания.

**Статус** — группа `matrix evidence passed`. Она идёт только при заданной `CODELAB_PARITY_RESULTS`:
- без переменной группа помечается пропущенной с причиной `CODELAB_PARITY_RESULTS is not set: status is checked by the nightly parity job`. Сторож и `test` остаются зелёными;
- переменная задана, но каталога нет или в нём нет `meta.json` — ошибка, а не пропуск: ночной джоб не должен молча проверить пустоту;
- `knownGaps` на статус **не действует**: пробел из списка в статусе — `missing`.

*Альтернативы:*
- (а) проверять существование только ночью — переименование фикстуры, сломавшее строку Must, жило бы до ночи и маскировалось бы её общим красным;
- (б) исключить `parity_evidence_test` из `guard` тегом — тогда до 9.2 ничего не проверяется на pull request.

### D5. Статус доказательства и источники

Статус доказательства считается по набору **обязательных** источников и набору **дополнительных** источников. Упавший тест в любом источнике — `failed`.

| Вид | Обязательный источник (нужен `pass`) | Дополнительные (падение — `failed`) |
|---|---|---|
| `acp/<id>` | агентский прогон корпуса: `conformance:agent` (`dart/codelab_agent_acp.json`) или для фикстуры с `setup.transport` — `dart/codelab_agent.json` (`transport_conformance_test`) | `scenario-embedded.xml` (`conformance:embedded`), клиентский корпус (`dart/codelab_client_acp.json`) |
| `cli/<id>` | `cli-dart.json` (`test:e2e:cli:dart-agent`) | `cli-embedded.json`, scripted-прогон в `dart/codelab_cli.json` |
| `core/<id>` | `dart/<пакет>.json` пакета, где найден тест | — |
| путь теста | `dart/<пакет>.json` или `flutter/<пакет>.json` пакета файла: все тесты файла | — |
| `app:<файл>` | `app/dart-agent/<файл>.json` | `app/embedded/<файл>.json` |

Правила сопоставления (D6):
- тест принадлежит id, если его полное имя (группы и тест через пробел, как в отчёте `package:test`) начинается с `<id>` и дальше идёт конец, `:` или пробел;
- у одного id может быть несколько тестов (`cli/headless-print-basic` — 8). Нужен хотя бы один `pass`, и ни один тест id в обязательном источнике не должен быть `skipped`;
- **`not-run`** — в обязательном источнике нет ни одного теста id. Сюда же попадает тест `scripted-only` в режиме `dart`: его исключает `--exclude-tags`, в отчёт он не попадает (9.1);
- **`skipped`** — в обязательном источнике есть тест id с `skip` (`markTestSkipped`, причина из отчёта печатается);
- **`missing`** — доказательство не существует (D3);
- **`failed`** — тест упал (`error` или `failure`) в любом источнике или упал весь набор (`done.success == false`, тест загрузки файла с ошибкой).

Пропуск в **дополнительном** источнике по правилу его спецификации (`setup.mcp cannot be passed to the agent process` у `test-scenario`; `fs_flow_test` и `terminal_flow_test` у встроенного агента app) строку не открывает. Но причина такого пропуска должна быть в явном перечне `allowedSkips` теста: шаблон причины и ссылка на требование спецификации. Неизвестная причина пропуска в дополнительном источнике — `skipped`. Правило принято решением пользователя Q5 (б). План 9.1 буквально считает любой `skip` незакрытым, и его текст уточнён (задача 0.2).

### D6. Отчёты и каталог `parity-results/`

**Переменная `CODELAB_TEST_REPORT_DIR`.** Если она задана и не пуста, Melos-скрипты добавляют к своим командам машинный репортёр. Без переменной команды прежние: локальный вывод и коды выхода не меняются.

| Скрипт | Добавка | Файл |
|---|---|---|
| `test` | `--file-reporter json:$DIR/flutter/$MELOS_PACKAGE_NAME.json` у `fvm flutter test` в каждом пакете | `flutter/<пакет>.json` |
| `test:dart` | то же у `fvm dart test` | `dart/<пакет>.json` |
| `conformance:agent` | `--file-reporter json:$DIR/dart/codelab_agent_acp.conformance.json` | |
| `conformance:client` | `--file-reporter json:$DIR/dart/codelab_client_acp.conformance.json` | |
| `conformance:embedded` | `--junit $DIR/scenario-embedded.xml` | |
| `test:e2e:cli:dart-agent` | `--file-reporter json:$DIR/cli-dart.json` | |
| `test:e2e:cli:embedded` | `--file-reporter json:$DIR/cli-embedded.json` | |
| `test:e2e:app:dart-agent`, `test:e2e:app:embedded` | `--file-reporter json:$DIR/app/<режим>/<файл>.json` на каждый файл цикла | |

Подробности реализации:
- `$MELOS_PACKAGE_NAME` в команде `melos exec` экранируется (`\$MELOS_PACKAGE_NAME`), иначе внешняя оболочка подставит пустое значение;
- добавка пишется формой `${CODELAB_TEST_REPORT_DIR:+…}`;
- каталог создаётся `mkdir -p` в начале скрипта;
- источник «агентский прогон корпуса» (D5) ищется сначала в `*.conformance.json`, затем в `dart/<пакет>.json`, потому что ночной `test` уже гоняет те же файлы.

Ночной джоб `test` запускает `fvm flutter test` и для чистых Dart-пакетов, поэтому Dart-тесты в ночном прогоне лежат в `flutter/`. Чтение ищет пакет в обоих каталогах.

**Форматы.**
- JSON — события репортёра `package:test` (`testStart`, `testDone` с `result` и `skipped`, `error`, `done`, `suite.path`). Читаются только эти поля, неизвестные события пропускаются.
- JUnit — только формат `test-scenario` (cli-scenario-driver «JUnit-отчёт test-scenario»): `testsuite`, `testcase` с атрибутами `name`, `failure`, `skipped`. Узкого чтения по этой схеме достаточно, потому что пишем его мы сами. Пакет `xml` не добавляется. Разбор неожиданной разметки — ошибка с файлом, а не молчаливое `not-run`.

**`meta.json`** пишет джоб `parity`: `commit`, `ref`, `event`, `run_id`, `run_attempt`, `created_at`. Тест печатает его первой строкой итога. При `run_attempt > 1` печатается предупреждение `rerun attempt: does not count for the three nights`: правило DoD «без ручного перезапуска» видно в отчёте.

### D7. CI: артефакты и джоб `parity`

- В `checks` для событий `schedule` и `workflow_dispatch`:
  - выставляется `CODELAB_TEST_REPORT_DIR=$GITHUB_WORKSPACE/parity-results`;
  - шаг `actions/upload-artifact@v4` с `if: always()` публикует `parity-results-${{ matrix.job }}`.
  На pull request и push переменная не задаётся: отчёты там не нужны, а вывод и время не меняются.
- Новый джоб `parity`:
  - `needs: [scope, checks]`;
  - `if: always() && needs.scope.result == 'success' && (github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')`;
  - шаги: checkout, prepare (FVM), `actions/download-artifact@v4` с `pattern: parity-results-*` и `merge-multiple: true` в `parity-results/`, запись `meta.json`, `fvm dart test packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart` с `CODELAB_PARITY_RESULTS=parity-results`, загрузка `parity-results` (`retention-days: 90`) с `if: always()`.
  - Итог печатается и в `$GITHUB_STEP_SUMMARY`: таблица `строка | доказательство | статус | источник`.
- `ci` (агрегатор) добавляет `parity` в `needs` и принимает `success|skipped`. На pull request джоб `parity` — `skipped`, и branch protection не меняется.
- `parity` идёт и после красного `checks`: отчёт о том, какие строки Must упали, нужен именно тогда.
- **Правка матрицы в pull request.** В `ci_scope.dart` путь `docs/architecture/proposals/agent-parity-goals.md` — исключение из «только документация»: его изменение добавляет джоб `guard`, даже если других джобов нет. Иначе pull request, который правит только матрицу, мог бы сломать разбор (D2), и это обнаружилось бы лишь ночью. Тест — `ci_scope_test.dart`.

*Альтернативы:*
- (а) отдельный ночной джоб, который сам перезапускает все наборы с репортёрами, — двойное время и расхождение с тем, что реально прогнали обязательные джобы. DoD требует, чтобы «три ночи» и отчёт были одним прогоном;
- (б) коммитить ночные отчёты в репозиторий ботом — запись в `develop` в обход pull request (`AGENTS.md` §22).

### D8. `codelab test-scenario --junit <файл>`

- Флаг регистрируется у подкоманды `test-scenario` (`cli_args.dart`).
- Путь открывается на запись **до** запуска первого агента. Если открыть нельзя — код `64` и `codelab: cannot write --junit <путь>: <текст ОС>`, агент не запускается. Ошибка пути не должна стоить прогона корпуса.
- Файл пишется после последней фикстуры, в том числе при `FAIL`, при «не сыграна ни одна фикстура» (пустой `testsuite`) и при сбое запуска агента. Прерывание сигналом файл не дописывает: частичный отчёт хуже отсутствующего, потому что parity увидит в нём `not-run`.
- Схема:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <testsuites><testsuite name="codelab test-scenario" tests="N" failures="F" skipped="S" time="T">
    <testcase classname="acp" name="acp/prompt-streaming-text" time="0.412"/>
    <testcase classname="acp" name="acp/x" time="0.101"><failure message="frame 3 differs">дифф</failure></testcase>
    <testcase classname="acp" name="acp/y" time="0"><skipped message="setup.mcp cannot be passed to the agent process"/></testcase>
  </testsuite></testsuites>
  ```
- `&`, `<`, `>`, `"`, `'` и управляющие символы экранируются. Недопустимые в XML 1.0 символы заменяются на `U+FFFD`.
- Текст причины и дифф берутся из тех же строк, что stdout. Правило «аргументы stdio-профиля не попадают в вывод» (cli-scenario-driver «Ошибка запуска агента в test-scenario без аргументов») действует и для файла — тест с маркером `sk-test-leak-0123456789`.
- Запись — функция в `lib/src/scenario/` рядом с `test_scenario_command.dart`, без нового пакета и без `xml`.

### D9. Отчёты Flutter-тестов app

Flutter-тесты app в GitHub CI не запускаются (`AGENTS.md` §21). Их отчёты появляются только из локального прогона в `release/<version>`: `CODELAB_TEST_REPORT_DIR=<каталог> fvm dart run melos run test:e2e:app:dart-agent` и `…:embedded`. Скрипт `test:e2e:app:*` (прогон по одному файлу) пишет `app/<режим>/<файл>.json` и `app/meta.json` с коммитом, версией macOS (`sw_vers -productVersion`) и временем.

Поэтому статус `app:<файл>` проверяется отдельно:
- без `CODELAB_PARITY_APP_RESULTS` доказательства `app:` получают статус `deferred`. Он печатается, но тест не роняет: ночной прогон на `develop` проверяет всё, кроме app;
- с `CODELAB_PARITY_APP_RESULTS` — по таблице D5. Ворота MVP — прогон теста с обеими переменными (задача 4.5): отчёт третьей ночи плюс отчёты app.

Отчёты app лежат в каталоге этого change `evidence/app/run-<n>/` (решение Q6), если суммарно меньше ~5 МБ, иначе — сводка (имя теста, статус, файл). Так требует план 9.1 («приложен к `proposal.md`»), и при архивировании отчёты уезжают в архив вместе с change. Перед коммитом отчёты проверяются на абсолютные пути домашнего каталога: `flutter test` пишет `suite.path` абсолютным, поэтому пути заменяются на относительные от корня репозитория.

### D10. Встроенное описание stdio-агента (9.3)

- `codelabAgentStdioProfile` становится `StdioAcpAgentProfile(name: 'codelab-agent (stdio)', command: 'codelab-agent', args: ['serve', '--stdio'], env: {'CODELAB_LOG_LEVEL': 'DEBUG'})`.
  - `CODELAB_LOG_LEVEL=DEBUG` бинарь понимает в любом регистре (`serve_args.dart`). Переменная оставлена, чтобы stderr внешнего агента в диагностике app был подробным, как раньше.
  - Константа остаётся в основном бареле `codelab_acp_transports` — он web-безопасен, `const` без IO.
- `ProfileDraft` (`codelab_client_core`) берёт значения по умолчанию `command` и `args` из этого описания. Сегодня это свои литералы: два источника одного значения. `codelab_client_core` уже зависит от `codelab_acp_transports`, нового ребра нет.
- App: `app_scope.dart` по-прежнему отдаёт описание как `StdioAcpAgentProfile` для фасада тестов. Начальный `AcpTransport` графа строится из него, но соединение окна идёт через профиль по умолчанию — встроенный агент (D6 change `add-app-settings-shell`). Видимого изменения нет.
- **Встроенной строки «codelab-agent (stdio)» на странице «Connection» нет.** Решение пользователя Q1 (б):
  - встроенный агент уже по умолчанию и не требует бинаря (цель 9.3);
  - свой stdio-агент сохраняется один раз через «Add profile», черновик которого уже `codelab-agent serve --stdio`;
  - вторая встроенная строка потребовала бы ещё одного зарезервированного id (`codelab-agent`) и правила для пользователей, у которых профиль с таким id уже есть в `profiles.json`. Это то же, что D21 сделал для `default`, только ради строки, которая дублирует «Add profile»;
  - у CLI встроенного stdio-профиля нет, правило для двух клиентов остаётся одним.
- Требование `agent-transports` «Референсный профиль codelab-agent» устарело и после change `add-app-settings-shell`: оно говорит, что настройка соединения «предлагает» `Codelab Agent`. Дельта описывает текущее поведение. Строка Purpose спецификации `agent-transports` правится при архивировании (задача 4.8).

### D11. Сохранённые профили и скрипты с `codelab serve`

- `profiles.json` с записью `command: codelab`, `args: [serve, --stdio]` может появиться только из Dart-клиентов: форма подключения app до change `add-app-settings-shell` не сохранялась (D7 там). Такая запись, по-видимому, редка.
- Этот change такие записи **не переписывает**: файл пользователя меняется только его действием (D7 change `add-app-settings-shell`; `AGENTS.md` §2, п. 3).
- Подключение к такому профилю после переключения даёт обычную ошибку запуска stdio. Это либо `codelab` не найден, либо Dart CLI отвечает `64` на неизвестный флаг. Причина видна в диагностике (`Starting stdio ACP agent: codelab.`), а пользовательская документация (задача 3.3) говорит, на что заменить команду.
- Алиас `codelab serve` → `codelab-agent serve` — это scope `retire-python-agent` (D1). Он нужен не позже первого выпуска, который ставит Dart CLI под именем `codelab` (9.4). До установщика Dart CLI под общим именем не ставится (`10-risks.md`), так что конфликт имени сейчас не возникает.

Так решил пользователь: Q2 (а), Q3 (б). Предупреждения в строке профиля и в `codelab profiles list` нет, дельт `app-settings` и `codelab-cli` нет.

### D12. Пользовательская документация MVP

Новый каталог `docs/user/`. Пользовательской документации в репозитории сегодня нет, а `docs/architecture/` — для разработчиков.

| Файл | Содержание | Строки матрицы |
|---|---|---|
| `docs/user/README.md` | что такое CodeLab, два клиента и агент, оглавление | — |
| `docs/user/run-from-source.md` | сборка `codelab` и `codelab-agent` из исходников (`build:cli`, `build:agent`), запуск app; явная пометка «установщик — с выпуском 1.0» | — |
| `docs/user/configuration.md` | `config.yaml` (пользовательский и проектный слои), секреты, `codelab config check`, LiteLLM Proxy как `baseUrl` | R-14 |
| `docs/user/migrating-from-python-agent.md` | что изменилось (`codelab` — клиент, `codelab-agent` — агент), сессии Python-агента не переносятся, мигратора нет; ручной перенос `codelab.toml` → `config.yaml` по таблице §15.7; профили и скрипты с `codelab serve` (D11) | R-16, 9.5 |
| `docs/user/zed.md` | подключение `codelab-agent serve --stdio` к Zed | 9.8 |

- Таблица соответствия ключей не копируется, а ссылается на §15.7 ядра. Пользовательский документ даёт примеры и предупреждения. Два источника одной таблицы разошлись бы.
- Установка (§12.7.5), `docs/release/verify.md` и `PRIVACY.md` в этот change не входят (D1, решение Q7 (а)). `README.md` получает ссылку на `docs/user/README.md` в «Начало работы».
- Язык пользовательских документов — русский, как остальная документация репозитория. Команды и тексты интерфейса — как в продукте (английские).

### D13. Архитектурные документы 9.7

По чек-листу плана 9.7 и `adr/README.md` §25. Документы приводятся к состоянию после переключения, без истории решений:
- корневой `AGENTS.md` §5 — итоговый состав пакетов, роль `codelab` и `codelab-agent`. Сверка: §5 уже перечисляет все пакеты, нужна строка о профиле по умолчанию и о Python-агенте;
- `layers-and-dependencies.md` — агентские пакеты и мосты;
- `acp-boundary.md` — агентская сторона (`codelab_agent_acp`);
- `permissions.md` — разрешения на стороне агента и клиентский показ;
- `testing.md`:
  - правило TDD §9.0 п. 3 с исключениями (а)–(д);
  - правило итераций §9.0 п. 8;
  - `parity_evidence_test`, `CODELAB_TEST_REPORT_DIR`, ночной `parity` (D4–D7);
- `platform-integration.md` — встроенный агент в процессе app, `codelab-agent` как процесс;
- `technology-stack.md` — `args`, `yaml`, `yaml_edit`; `toml` нет.

Каждый документ правит исполнитель своей стороны (tasks.md, итерация 3).

### D14. Ворота MVP — отдельная итерация

Пункты DoD, которым нужны люди и календарное время, не блокируют итерации 1–3:
- три ночи подряд;
- три прогона app на macOS в `release/<version>`;
- чек-лист Zed;
- подписи владельца продукта и ответственного за релиз;
- политика заморозки из `retire-python-agent`.

Они собраны в итерации 4, и их результаты записываются в таблицы `proposal.md` и в «Чек-лист Zed» ниже. Change архивируется только после итерации 4: это ворота MVP, а не только задачи кода.

Счёт «трёх ночей» начинается после итерации 2 (`knownGaps` пуст, ночной `parity` зелёный). Прогоны app идут в ветке `release/<version>`, созданной после трёх ночей.

### D15. Пакеты, зависимости, сторож, граф

- Новых пакетов нет, новых зависимостей нет: ни у пакетов, ни у `codelab_architecture_tests` (`path` и `test` уже есть).
- Нового правила в `test/support/rules.dart` нет. Импорт `package:codelab_acp_testing/` в `apps/codelab_cli` по-прежнему только из `lib/src/scenario/`, и запись JUnit живёт там же.
- Граф `README.md` не меняется. Ребро `codelab_client_core → codelab_acp_transports` уже есть.
- Web-безопасность: меняется только `const` в основном бареле `codelab_acp_transports` и литералы в `codelab_client_core`. `web-compile` нужен по правилу §21.
- Allowlist ядра (PKG-2) не затрагивается.

### D16. Безопасность и наблюдаемость отчётов

- Отчёты `package:test` содержат печать тестов (`print`-события) и тексты ошибок. В тестах используются только вымышленные секреты (маркер `sk-test-leak-0123456789`), поэтому публикация артефактов допустима.
- Тест `parity` сам проверяет, что ни один файл `parity-results/` не содержит значений длиной от 8 символов из окружения процесса с именами `*_TOKEN`, `*_KEY`, `*_SECRET`: CI-секретов в ночном прогоне нет, но проверка дешёвая. При совпадении — ошибка, значение не печатается.
- Trace Zed (`acp-trace.jsonl` с `trace_payload: true`) содержит тексты промптов и файлов. Проверка Zed проводится на тестовом проекте без секретов. Фрагменты trace в `evidence/zed/` редактируются по правилу `observability.md` до коммита (задача 4.3).
- Итог `parity` печатается строками `<строка> <доказательство> <статус> [<источник>] [<причина>]`, отсортированными по id строки, и в Step Summary. По одному запуску видно, что именно открыто.

### D17. Итерации

Каждая итерация — отдельный pull request в `develop`:
- **0 — документы:** решения Q1–Q7, правки плана, матрицы и дорожной карты;
- **1 — доказательства и профиль:** 9.1 (проверка, отчёты, `--junit`, CI) и 9.3. В конце — первый ночной прогон вручную (`workflow_dispatch`) и список задач 9.2 по его отчёту;
- **2 — закрытие пробелов Must (9.2):** известные пробелы (оценка ниже) и всё, что показал отчёт; `knownGaps` пуст;
- **3 — документация:** 9.5, 9.7 без установки, `AGENTS.md` §5;
- **4 — ворота MVP:** три ночи, `release/<version>` и три прогона app, Zed, подписи, архивирование.

Зависимости: 2 ← 1; 3 независима от 2, но R-14 (документ LiteLLM) закрывается вместе с тестом 2.x; 4 ← 1, 2, 3 и `retire-python-agent` (политика заморозки).

## Оценка масштаба 9.2

Предварительная сверка 2026-11-09 на `develop` 9d61ed64. Тесты не запускались. Разбор матрицы скриптом по правилам D2–D3: 77 строк Must, что совпадает с итогом §7, плюс одна сломанная строка Should (P-12). Проверены существование файлов фикстур и app и наличие id в первом аргументе `test(` / `group(`.

**Пробелы существования (10 строк):**

| Строка | Доказательство | Что не так | Предварительная задача |
|---|---|---|---|
| K-02 | `acp/slash-compact` | фикстуры нет | фикстура `/compact` (`SummaryRequest.focus`, §9.2 ядра) |
| R-08 | `acp/slash-help`, `acp/slash-mode-plan`, `acp/mcp-prompt-command` | фикстур нет. Рядом есть `slash-mcp-list`, `prompt-template-command`, `available-commands-no-tools`, но это другие сценарии | три фикстуры или, если сценарий R-08 ими уже покрыт, правка строки матрицы со ссылкой на сценарий |
| R-14 | `core/litellm-proxy-base-url` | теста нет | тест ядра: `baseUrl` LiteLLM Proxy, OpenAI-совместимый адаптер; документ D12 |
| C-01 | `core/pairing-survives-cancel` | id только в комментарии `codelab_agent_core/test/scenarios/read_edit_exec_test.dart:194` | имя теста или группы |
| P-01 | `core/no-tool-bypasses-gate` | только в doc-комментарии `permissions/no_bypass_test.dart` | имя группы |
| P-16 | `core/mcp-tool-cannot-declare-trusted` | только в комментарии `tools/fence_test.dart:91` | имя теста |
| E-05 | `core/mcp-tool-name-sanitized` | только в комментарии `mcp/mcp_tool_name_test.dart:11` | имя группы |
| R-15 | `core/agent-definition-markdown-frontmatter` | только в doc-комментарии `agents/agent_select_test.dart` | имя группы |
| R-16 | `core/config-legacy-found-warning` | только в doc-комментарии `codelab_agent_io/test/config/config_legacy_found_test.dart` | имя группы |
| U-03 | `cli/slash-menu-merges-agent-commands` | единственный тест с тегом `scripted-only`, поэтому в режиме `dart` — `not-run` | вариант теста против Dart-агента: агент объявляет свои команды (`/compact`, `/config`, `/mcp`) |

**Строки, закрываемые правилом Q4 (7 строк):**
- только пути файлов тестов, без id: L-06, T-05, P-08, R-17, R-23. Все файлы существуют. Неполный путь R-23 дописан задачей 0.3;
- шаблоны: H-04 (`acp/*` против встроенного и внешнего агента) и D-04 (`app:*` в режиме встроенного агента).

**Пропуски по спецификации в дополнительных источниках (правило Q5, `allowedSkips`):**
- `test-scenario` против `embedded` пропускает 15 фикстур, на которые ссылаются строки Must. Все они проходят в обязательном источнике `conformance:agent` или в транспортном драйвере:
  - `setup.config`: `available-commands-no-tools` (R-07), `compaction-long-session-continues` (K-01), `prompt-max-turn-requests` (C-02), `session-new-modes-config` (R-02), `set-config-option-agent` (R-15), `set-config-option-model` (R-06);
  - `setup.mcp`: `mcp-http-tool-call` (E-03), `mcp-stdio-tool-call` (E-02), `mcp-result-fenced` (P-16), `mcp-tool-permission` (P-01), `set-mode-plan-rejects-mcp-write` (P-01), `session-new-with-mcp` (R-24);
  - `setup.sessions`: `session-load-interrupted-turn` (S-13);
  - `setup.transport`: `stdio-framing-large-line` (R-13), `ws-auth-bearer-required` (R-12);
- `fs_flow_test` (T-01) и `terminal_flow_test` (T-08) в режиме встроенного агента app пропускают себя по testing-quality «Встроенный режим в e2e и conformance».

**Только app (9 строк):** D-01, D-02, D-03, D-04, R-18–R-22 — плюс app-часть строк C-05, T-01, T-08, P-02, K-02, U-06, R-11, R-12, R-13. До прогона в `release/*` их статус — `deferred` (D9).

**Остальные ~60 строк.** Доказательства существуют, статус неизвестен до первого ночного отчёта (задача 1.14).

Масштаб 9.2 до отчёта:
- 4 фикстуры;
- 1 новый тест ядра;
- 6 переименований тестов ядра;
- 1 вариант PTY-e2e;
- правка 1–2 строк матрицы (P-12, R-23).

Это маленькая итерация. Риск — в статусах: что упадёт или пропустится в первом отчёте.

## Чек-лист Zed (9.8)

Заполняет и подписывает ответственный за релиз (план этапа 9, «Чек-лист Zed»). Версия Zed фиксируется до начала и не меняется во время проверки.

- Версия Zed: —
- Дата проверки: —
- Сборка `codelab-agent`: коммит —, `build:agent`, debug-сборка для сверки полей с `logging.trace_payload: true`
- ОС: —
- Тестовый проект: — (без секретов, D16)
- Агент для сверки trace: не выбран / имя и версия —
- Доказательства: `evidence/zed/<шаг>-*.png`, `evidence/zed/<шаг>-trace.jsonl` (фрагменты `$CODELAB_HOME/logs/acp-trace.jsonl`, отредактированные по `observability.md`)

| № | Шаг | Пройдено, если | Итог | Скриншот | Фрагмент trace | Примечание |
|---|---|---|---|---|---|---|
| 1 | подключение | Zed показывает агента готовым; `initialize` с ответом `protocolVersion: 1` | — | — | — | — |
| 2 | возможности | ответ `initialize` содержит `loadSession`, `promptCapabilities`, `mcpCapabilities`; Zed не сообщает о несовместимости | — | — | — | — |
| 3 | промпт и стриминг | текст приходит частями до ответа на `session/prompt`; все `session/update` хода — раньше ответа | — | — | — | — |
| 4 | инструмент и одобрение «разрешить» | `tool_call` → `session/request_permission` → после «allow» — `tool_call_update` `completed` | — | — | — | — |
| 5 | одобрение «отклонить» | после «reject» — `tool_call_update` `failed`, ход завершается `end_turn` | — | — | — | — |
| 6 | файлы | чтение и правка через `fs/read_text_file` и `fs/write_text_file` Zed; правка видна в буфере | — | — | — | — |
| 7 | терминал | команда через `terminal/create` и `terminal/output`, вывод виден в Zed | — | — | — | — |
| 8 | отмена | `session/cancel`; ход завершается `stopReason: cancelled` за 5 с | — | — | — | — |
| 9 | `session/load` | после перезапуска Zed сессия открывается; реплей до ответа на `session/load` восстанавливает историю | — | — | — | — |
| 10 | режим и модель | `session/set_config_option` (или `session/set_mode`); следующий ход в новом режиме | — | — | — | — |
| 11 | отключение | процесс `codelab-agent` завершается за 5 с, журнал сессии дописан | — | — | — | — |

Сверка с другим ACP-агентом (если выбран): шаги 3–5 и 8 на одном промпте. Trace нормализуются по id, времени и текстам модели и сравниваются по порядку методов и форме сообщений.

| Шаг | Порядок «все `session/update` до ответа» | Отказ не завершает ход | Лишние поля не ломают Zed | Итог |
|---|---|---|---|---|
| 3 | — | — | — | — |
| 4 | — | — | — | — |
| 5 | — | — | — | — |
| 8 | — | — | — | — |

Подпись ответственного за релиз: — (дата —)

## Risks / Trade-offs

- **Ночной `parity` красный до конца 9.2.** Агрегатор `ci` на `schedule` тоже красный. *Смягчение:* это и есть сигнал ворот, pull request он не блокирует (`parity` там `skipped`); `knownGaps` и Step Summary показывают, что именно открыто.
- **Эвристика поиска имён тестов (D3).** Имя, собранное из переменной или интерполяции, существование не найдёт. *Смягчение:* статус всё равно идёт по отчёту. Существование — ранний сигнал, а не истина, и правило «первый литерал — id» записывается в `testing.md`.
- **Хрупкость разбора Markdown (D2).** *Смягчение:* громкие ошибки на любую неожиданную строку, контрольная сумма с §7, `guard` на каждую правку матрицы (D7).
- **Срок хранения артефактов.** 90 дней покрывают три ночи и подготовку `release/*`. Ссылки в `proposal.md` на запуски, отчёт третьей ночи и отчёты app хранятся по Q6.
- **`--fail-fast` у `test`.** Упавший пакет останавливает следующие, и их тесты станут `not-run`. *Смягчение:* в ночном прогоне это и так красный запуск, а `parity` называет первопричину по `failed`.
- **Гонки и поздние события** (`AGENTS.md` §9, §12) этот change не затрагивает. Запись JUnit идёт после последней фикстуры в одном async-потоке команды, а прерывание сигналом файл не пишет (D8). Новых подписок и долгоживущих операций нет.
- **Permissions и containment** (§10) не меняются. Описание stdio-агента — только значения по умолчанию, запуск идёт тем же `StdioAcpTransport`.
- **Forward compatibility ACP** не затрагивается: изменений протокола нет. Чек-лист Zed проверяет совместимость с чужим клиентом, но ничего не меняет в протоколе.

## Migration Plan

1. Итерация 1 меняет описание stdio-агента. Сохранённые профили и `config.yaml` не трогаются (D11).
2. Ночной CI получает артефакты с первого `workflow_dispatch` после итерации 1. Branch protection не меняется.
3. Откат: вернуть константу и удалить джоб `parity`. Данные пользователя не затронуты.

## Решения пользователя 2026-11-09

Все вопросы решены по рекомендации архитектора. Спецификации и задачи написаны под эти ответы.

- **Q1** — (б): отдельной встроенной строки «codelab-agent (stdio)» на странице «Connection» нет. Описание `codelabAgentStdioProfile` — значения по умолчанию «Add profile» и внутреннее описание app (D10).
- **Q2** — (а): сохранённые профили `codelab serve` в коде не трогаются и не переписываются. Замена команды описана в пользовательской документации (D11, задача 3.3).
- **Q3** — (б): алиас `codelab serve` → `codelab-agent serve` делает `retire-python-agent` вместе с заморозкой, не позже первого выпуска с установщиком, ставящего `codelab` под общим именем (9.4) (D1, D11).
- **Q4** — (а): путь файла теста — доказательство: все тесты файла в отчёте `pass`. Шаблон `acp/*` — все фикстуры корпуса с ролью `agent` закрыты по D5. `app:*` — все файлы `integration_test/*_test.dart` в отчёте нужного режима с разрешёнными пропусками D5 (D3).
- **Q5** — (б): `skip` считается по источникам. В обязательном источнике он открывает строку, в дополнительном допустим только по перечню `allowedSkips` со ссылкой на требование спецификации (D5).
- **Q6:**
  - ночные отчёты — артефакты GitHub CI (90 дней) со ссылками на запуски в `proposal.md`; отчёт третьей ночи перед архивированием сохраняется в `evidence/nightly/` этого change;
  - отчёты app — сырые JSON трёх прогонов в `evidence/app/run-<n>/` с относительными путями, если суммарно меньше ~5 МБ, иначе сводка (имя теста, статус, файл);
  - прочтение DoD подтверждено: ночная проверка отмечает `app:` как `deferred`, а ворота MVP — итоговый прогон с отчётами app (D9, задача 4.5).
- **Q7** — (а): в этом change пользовательская документация MVP без установки, `docs/release/verify.md` и `PRIVACY.md`. Они уходят в `add-release-pipeline-and-installer` и `add-privacy-policy`, а для MVP есть «сборка из исходников» (D12).

## Open Questions

Открытых вопросов нет.
