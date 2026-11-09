Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2; дорожная карта §9.1). В каждой итерации сначала пишутся красные тесты, затем код. В скобках — требование спецификации этого change (`capability` «Requirement», сценарий), решение design.md или строка Must матрицы. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[protocol]` — `codelab_acp_transports`, `codelab_acp_testing` (фикстуры), а также всё, что у таблицы зон без владельца и ближе всего к корпусу фикстур и conformance:
  - `codelab_architecture_tests` (`parity_evidence_test`);
  - `tool/ci/`;
  - `.github/workflows/ci.yml`;
  - скрипты Melos в корневом `pubspec.yaml`;
- `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `codelab_embedded`, `apps/codelab_agent`, документы агентской стороны;
- `[client]` — `codelab_client_core`, `apps/codelab_cli`, документы CLI;
- `[desktop]` — `apps/codelab_desktop`, документы app.

Итерации — каждая отдельным pull request в `develop` (design.md, D17):
- 0 — документы и ответы на вопросы;
- 1 — доказательства (9.1) и встроенное описание stdio-агента (9.3);
- 2 — закрытие пробелов Must (9.2);
- 3 — документация (9.5, 9.7);
- 4 — ворота MVP (не блокирует итерации 1–3).

Зависимости: 1 ← 0; 2 ← 1 (список по отчёту 1.14); 3 ← 0; 4 ← 1, 2, 3, change `add-agent-builtin-slash-commands` (задача 4.0, Q9) и политика заморозки `retire-python-agent` (D1).

Проверки каждой задачи — только для затронутого (`AGENTS.md` §21):
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` / `fvm flutter analyze` пакета;
- тесты пакета;
- `guard` — при правке `codelab_architecture_tests`, `tool/ci/` и матрицы;
- `conformance:agent` и `conformance:embedded` — при правке фикстур;
- `test:e2e:cli:dart-agent` — при правке `apps/codelab_cli`;
- `web-compile` — при правке `codelab_acp_transports` и `codelab_client_core`.

Для `openspec/` — `openspec validate switch-default-agent-to-dart --strict`. Интеграционные тесты app в `feature/*` только компилируются, на устройстве они идут в итерации 4 (`release/*`).

## 0. Документы и решения (итерация 0)

- [x] 0.1 `[protocol]` Ответы пользователя на Q1–Q7 (2026-11-09, все по рекомендации) внесены в design.md («Решения пользователя 2026-11-09», D1, D3, D5, D9, D10, D11, D12), `proposal.md` и задачи; спецификации уже написаны под рекомендации и не менялись.
- [x] 0.2 `[protocol]` `09-14-stage-9-switch-default.md` (2026-11-09):
  - 9.1 — правило статусов по источникам (D5, Q5), `deferred` для `app:` в ночной проверке (D9, Q6), храповик `knownGaps` (D4);
  - 9.3 — вторая половина закрыта этим change, отдельной встроенной строки stdio нет (D10, Q1);
  - 9.7 — состав по D12 и Q7, установка — с 9.4;
  - 9.9 — заморозка, удаление и алиас `codelab serve` — `retire-python-agent` (D1, Q3);
  - «OpenSpec change» — ссылка на этот change.
- [x] 0.3 `[protocol]` `agent-parity-goals.md` (2026-11-09):
  - §1.4 — правило доказательств и статусов (D3, D5) со ссылкой на `parity_evidence_test`;
  - строка P-12 — `|` в обратных кавычках экранирован (`secret set\|delete`, D2); после правки разбор даёт 77 строк Must и ни одной сломанной строки;
  - строка R-23 — полный путь `packages/dart/codelab_client_core/test/diagnostics/diagnostics_test.dart` (D3);
  - по решению Q4 (а) новых id нет.
- [x] 0.4 `[protocol]` `delivery-roadmap.md` §4.4: этот change, состав итераций и ворота как итерация 4. В §10.3 строки нет: таблица перечисляет changes экранов, а этот change экранов не вводит (2026-11-09).

## 1. Доказательства и встроенное описание stdio-агента (итерация 1)

### 1a. Разбор матрицы и существование доказательств (9.1)

- [x] 1.1 `[protocol]` Тест (testing-quality «Проверка доказательств матрицы целей»: «Сломанная строка таблицы», «Число строк Must не совпадает со сводкой»): `test/support/parity/matrix_parser_test.dart` на временной матрице. Проверяет:
  - выбор строк Must из таблиц §3 по колонке «Приоритет» и всех строк §4.1;
  - пропуск подтаблиц «Дано / Когда / Тогда» и §4.2;
  - `\|` в ячейке;
  - ошибку с номером строки на лишнюю ячейку;
  - сверку с итогом §7.
  Красный.
- [x] 1.2 `[protocol]` Реализация: `test/support/parity/matrix_parser.dart` (D2).
- [x] 1.3 `[protocol]` Тест («Нет файла фикстуры», «Id только в комментарии», «Известный пробел», «Устаревшая запись knownGaps»): `evidence_test.dart` на временном дереве. Проверяет:
  - извлечение всех видов доказательств из ячейки (D3), включая повтор, шаблоны и пути;
  - поиск `cli/<id>` и `core/<id>` по первому литералу `test(` и `group(`, в том числе разбитому на соседние литералы;
  - игнорирование комментариев;
  - работу храповика.
  Красный.
- [x] 1.4 `[protocol]` Реализация: `test/support/parity/evidence.dart` и группа `matrix evidence exists` в `parity_evidence_test.dart` на настоящей матрице. `knownGaps` заполняется по оценке design.md («Оценка масштаба 9.2», 10 строк) с номерами задач итерации 2. `fvm dart run melos run guard` зелёный. U-03 — пробел статуса (`not-run` из-за `scripted-only`), не существования, в `knownGaps` не входит; он закрывается change `add-agent-builtin-slash-commands` (задача 2.8 перенесена туда решением Q9, 2026-11-10).

### 1b. Отчёты и статусы (9.1)

- [x] 1.5 `[protocol]` Тест («Без отчётов», «Каталог отчётов без meta.json», «Тест scripted-only в режиме dart», «Падение в дополнительном источнике», «Пропуск по спецификации в дополнительном источнике», «Отчёты app не переданы»): `reports_test.dart` и `verdict_test.dart` на временных отчётах. Проверяет:
  - чтение событий JSON-репортёра `package:test` (`testStart`, `testDone`, `error`, `done`, `suite.path`) и JUnit `test-scenario` (D6);
  - сопоставление полного имени с id;
  - все статусы D5, `allowedSkips` и `deferred`;
  - сортировку и формат строк итога;
  - `run_attempt > 1` с предупреждением.
  Красный.
- [x] 1.6 `[protocol]` Реализация: `reports.dart`, `verdict.dart`, группа `matrix evidence passed` в `parity_evidence_test.dart` (D4–D6, D9).
- [x] 1.7 `[protocol]` Тест («Секрет окружения в отчёте»): значение `FOO_TOKEN` найдено в файле отчёта, тест падает с именем файла без значения; значения короче 8 символов не проверяются. Красный.
- [x] 1.8 `[protocol]` Реализация: проверка утечки в `parity_evidence_test.dart` (D16).

### 1c. `test-scenario --junit` (9.1)

- [x] 1.9 `[client]` Тест (cli-scenario-driver «JUnit-отчёт test-scenario»: все шесть сценариев): `apps/codelab_cli/test/scenario/junit_report_test.dart` — модульный тест записи и экранирования. Дополнение `test_scenario_command_test.dart` — прогон против `FixtureReplayAgent` и `embedded`, `FAIL`, пустой фильтр, неоткрываемый путь (`64` до запуска агента), маркер `sk-test-leak-0123456789`. Красный.
- [x] 1.10 `[client]` Реализация: флаг `--junit` в `cli_args.dart`, запись в `lib/src/scenario/junit_report.dart`, открытие до первого агента и запись после последней фикстуры в `test_scenario_command.dart` (D8). Справка `codelab test-scenario --help` и `apps/codelab_cli/AGENTS.md` (раздел драйвера фикстур).

### 1d. Машинные отчёты и ночной CI (9.1)

- [x] 1.11 `[protocol]` Тест (testing-quality «Ночная проверка доказательств в CI», «Правка только матрицы»): `ci_scope_test.dart` — изменение только `docs/architecture/proposals/agent-parity-goals.md` даёт джоб `guard`, а изменение другого документа по-прежнему не даёт джобов. Красный.
- [x] 1.12 `[protocol]` Реализация: `tool/ci/ci_scope.dart` (D7).
- [x] 1.13 `[protocol]` Скрипты Melos (testing-quality «Машинные отчёты прогонов»: все сценарии) и `.github/workflows/ci.yml` (D6, D7):
  - добавки `${CODELAB_TEST_REPORT_DIR:+…}` в `test`, `test:dart`, `conformance:agent`, `conformance:client`, `conformance:embedded`, `test:e2e:cli:dart-agent`, `test:e2e:cli:embedded`, `test:e2e:app:dart-agent`, `test:e2e:app:embedded`;
  - экранирование `\$MELOS_PACKAGE_NAME`;
  - `app/<режим>/meta.json` в скриптах app (на режим: режимы пишут в один каталог по очереди);
  - загрузка артефактов в `checks` только для `schedule` и `workflow_dispatch`;
  - джоб `parity`, `meta.json`, Step Summary;
  - `parity` в `needs` агрегатора `ci`.
  Проверка вручную: сценарии «Без переменной», «Отчёт e2e CLI», «Отчёт пакета через melos exec», «Упавший тест в отчёте» выполнены локально, а команды и результат записаны в описание pull request. Workflow — критерий «Ночной запуск публикует отчёты» и «Pull request без parity» на первом запуске (1.14).
  До 2.11 ночной `ci` красный ожидаемо (`knownGaps`, статусы `missing` и `not-run`, D4): это сигнал ворот, а не поломка.
  Итог (2026-11-09): локальные сценарии выполнены (описание pull request #268); «Pull request без parity» — в CI pull request #268 `parity` пропущен, `ci` зелёный; «Ночной запуск публикует отчёты» — запуск 1.14 опубликовал `parity-results-<джоб>` и `parity-results`, шаги `leaks` зелёные.
- [x] 1.14 `[protocol]` Первый ночной прогон вручную (`workflow_dispatch` на ветке итерации или на `develop` после merge): артефакт `parity-results` получен. Итог `parity` перенесён в итерацию 2 списком задач «строка → доказательство → статус → задача» с исполнителем по пакету теста. Запуск указан в описании pull request итерации 2.
  Итог (2026-11-09): `workflow_dispatch` на ветке `feature/switch-default-agent-to-dart`, коммит `a284fa10`, запуск https://github.com/pese-git/codelab-app/actions/runs/42635311880. Все джобы `checks` зелёные, `parity` красный ожидаемо. Из 157 доказательств: `pass` 125, `deferred` 18 (`app:`), `missing` 11 (ровно `knownGaps`), `not-run` 2, `skipped` 1. Новые относительно оценки — E-01 и R-17 (задачи 2.12–2.15).

### 1e. Встроенное описание stdio-агента (9.3)

- [x] 1.15 `[protocol]` Тест (agent-transports «Референсный профиль codelab-agent»: «Описание указывает на Dart-агента», «Нет умолчаний Python-агента»): `codelab_acp_transports_test.dart` ожидает `codelab-agent (stdio)`, `codelab-agent`, `['serve', '--stdio']`, `CODELAB_LOG_LEVEL=DEBUG`. Красный.
- [x] 1.16 `[client]` Тест («Черновик «Add profile» совпадает с описанием», «Нет умолчаний Python-агента»): `profile_draft_test.dart` — команда и аргументы stdio-черновика по умолчанию равны `codelabAgentStdioProfile.command` и `args`. Красный до 1.17, потому что описание ещё `codelab serve`.
- [x] 1.17 `[protocol]` Реализация: `codelabAgentStdioProfile` в `transport_configs.dart` (D10). Doc-комментарий константы — почему, для чего, как использовать (`AGENTS.md` §15). Тесты 1.15 и 1.16 зелёные.
- [x] 1.18 `[client]` Рефакторинг под зелёным 1.16: `ProfileDraft` берёт значения по умолчанию из описания вместо своих литералов — один источник (D10).
- [x] 1.19 `[agent]` Приёмочный тест границы («Описание подключается»; исключение TDD для интеграционных тестов, дорожная карта §9.1): тест бинаря в `apps/codelab_agent/test/` запускает процесс с `codelabAgentStdioProfile.args` и `env` и `--llm-script test/llm_scripts/hello.json` и получает ответ `initialize` с `protocolVersion: 1`. Кода агента не требует.
- [x] 1.20 `[desktop]` Сверка app: `widget_test.dart` и `test/support/test_app_scope.dart` работают с новым описанием. Метка stdio-профиля в тестах, которые проверяют текст (`label`), обновлена явно, с обоснованием D10 в комментарии теста. `fvm flutter test` app зелёный, `fvm flutter analyze` интеграционных тестов зелёный.
- [x] 1.21 `[protocol]` `fvm dart run melos run web-compile` зелёный.

## 2. Закрытие пробелов Must (итерация 2, 9.2)

Список ниже — по отчёту 1.14 (задача 2.0) и шагу красных тестов (design.md, «Оценка масштаба 9.2», итог 2026-11-10). Каждая пара закрывает строку Must; её запись удаляется из `knownGaps` в той же задаче. Встроенные слэш-команды агента (K-02, R-08, U-03) перенесены в change `add-agent-builtin-slash-commands` (решение Q9): задачи 2.1–2.4 и 2.8–2.9 здесь **не выполняются**, а их красные тесты (фикстуры `slash-compact`, `slash-help`, `slash-mode-plan`, вариант e2e U-03) переходят в тот change.

- [x] 2.0 `[protocol]` Список задач итерации обновлён по отчёту 1.14 (2026-11-09). `missing` 11 — задачи 2.1–2.7 (как в оценке); `not-run` U-03 `cli/slash-menu-merges-agent-commands` — 2.8; `not-run` E-01 `core/project-context-agents-md-leaf-first` — 2.12–2.13; `skipped` R-17 `packages/dart/codelab_agent_acp/test/conformance_test.dart` — 2.14–2.15; `failed` нет.
- [ ] 2.1 `[protocol]` ~~Тест (K-02, `acp/slash-compact`)~~ — **перенесено** в `add-agent-builtin-slash-commands` (Q9, 2026-11-10), не выполняется в этом change.
- [ ] 2.2 `[agent]` ~~Реализация для 2.1~~ — **перенесено** в `add-agent-builtin-slash-commands` (Q9).
- [ ] 2.3 `[protocol]` ~~Тест (R-08, `acp/slash-help`, `acp/slash-mode-plan`, `acp/mcp-prompt-command`)~~ — **перенесено** в `add-agent-builtin-slash-commands` (Q9); `acp/mcp-prompt-command` убран из R-08 решением Q10 (задача 2.18).
- [ ] 2.4 `[agent]` ~~Реализация для 2.3~~ — **перенесено** в `add-agent-builtin-slash-commands` (Q9).
- [x] 2.5 `[agent]` Тест (R-14, `core/litellm-proxy-base-url`): адаптер OpenAI-совместимого API с `baseUrl` LiteLLM Proxy (`MockClient`): путь `/chat/completions` от `baseUrl`, заголовок ключа, стриминг (§2.7 ядра). Приёмочный: зелёный сразу, поведение уже есть — `packages/dart/codelab_agent_core/test/llm/litellm_proxy_base_url_test.dart`, внешняя группа `core/litellm-proxy-base-url` (5 тестов, 2026-11-10). Запись `knownGaps` R-14 удалена.
- [x] 2.6 `[agent]` Реализация для 2.5 — не требуется: 2.5 зелёный без изменений кода.
- [x] 2.7 `[agent]` Имена тестов (C-01, P-01, P-16, E-05, R-15, R-16): id становится первым литералом **внешнего** `test(` или `group(` (D3, уточнение 2026-11-10). Поведение тестов не меняется; комментарии рядом переведены, если менялась сущность (`AGENTS.md` §15):
  - C-01 — `packages/dart/codelab_agent_core/test/scenarios/read_edit_exec_test.dart:196` → `test('core/pairing-survives-cancel: …')`;
  - P-01 — `packages/dart/codelab_agent_core/test/permissions/no_bypass_test.dart:15` → `test('core/no-tool-bypasses-gate: …')`;
  - P-16 — `packages/dart/codelab_agent_core/test/tools/fence_test.dart:93` → `test('core/mcp-tool-cannot-declare-trusted: …')`;
  - E-05 — `packages/dart/codelab_agent_core/test/mcp/mcp_tool_name_test.dart` — тесты файла обёрнуты в `group('core/mcp-tool-name-sanitized', …)`;
  - R-15 — `packages/dart/codelab_agent_core/test/agents/agent_select_test.dart:147` → `group('core/agent-definition-markdown-frontmatter: select and return (R-15)', …)`;
  - R-16 — `packages/dart/codelab_agent_io/test/config/config_legacy_found_test.dart` — тесты файла обёрнуты в `group('core/config-legacy-found-warning', …)`.
  Записи `knownGaps` C-01, P-01, P-16, E-05, R-15, R-16 удалены; группа `matrix evidence exists` зелёная.
- [ ] 2.8 `[client]` ~~Тест (U-03, `cli/slash-menu-merges-agent-commands`) против Dart- и встроенного агента~~ — **перенесено** в `add-agent-builtin-slash-commands` (Q9): красный по той же причине, что K-02 и R-08.
- [ ] 2.9 `[client]` ~~Реализация для 2.8~~ — **перенесено** в `add-agent-builtin-slash-commands` (Q9).
- [x] 2.10 `[protocol]` Строки по Q4 (а): правило путей и шаблонов (D3, D5) покрыто тестом `verdict_test.dart` (группа «правило путей и шаблонов на строках Must (Q4, задача 2.10)», 27 тестов) для L-06, T-05, P-08, R-17, R-23, H-04 и D-04; новых id нет. Проверено 2026-11-10: `fvm dart test test/support/parity/verdict_test.dart` — все тесты группы зелёные (красные в файле только тесты 2.14 до 2.15).
- [ ] 2.11 `[protocol]` `knownGaps` содержит только записи K-02 (`acp/slash-compact`) и R-08 (`acp/slash-help`, `acp/slash-mode-plan`); вместо номера задачи — ссылка `add-agent-builtin-slash-commands` (Q9, D4). Записи R-14, C-01, P-01, P-16, E-05, R-15, R-16 и `acp/mcp-prompt-command` удалены. `workflow_dispatch` даёт `parity`, где открыты только K-02, R-08 и U-03 (`not-run`) со ссылкой на новый change, а `app:` — `deferred`; запуск указан в описании pull request. Пустой список и удаление константы — после merge `add-agent-builtin-slash-commands` (задача 4.0).
- [ ] 2.12 `[agent]` Тест (E-01, `core/project-context-agents-md-leaf-first`, `not-run`). Причина найдена (2026-11-10): тест вложен в `group('search from cwd up to the git root')` (`packages/dart/codelab_agent_io/test/project/project_context_loader_test.dart:62`), полное имя в отчёте начинается с имени группы, а статическая проверка D3 смотрела литерал `test(` отдельно. Красный тест на причину — задача 2.16 (уточнение D3: E-01 становится `missing` в группе `exists`).
- [x] 2.13 `[agent]` Реализация для 2.12: тест вынесен в собственную внешнюю группу `group('core/project-context-agents-md-leaf-first', …)` на верхнем уровне `main` (поведение теста не меняется); группа `exists` после 2.17 зелёная, повторный прогон даёт E-01 `pass`.
- [ ] 2.14 `[protocol]` Тест (R-17, путь `packages/dart/codelab_agent_acp/test/conformance_test.dart`, `skipped`; решение Q8, 2026-11-10): перечень `allowedSkips` применяется и к доказательству-пути. В файле пропущена фикстура с ролями `[client]` без `agent` (`acp/errors-unknown-session-update-tolerated`) — пропуск по роли задан спецификацией корпуса. `verdict_test.dart` проверяет на временных отчётах:
  - пропуск файла с причиной из `allowedSkips` не открывает строку: `pass`;
  - пропуск с причиной вне перечня — `skipped`;
  - на настоящем перечне (`allowed_skips.dart`) R-17-подобный случай (`has roles [client] without "agent"`) даёт `pass`.
  Красный до 2.15.
- [ ] 2.15 `[protocol]` Реализация по Q8 в `verdict.dart` (`_fold` для вида «путь теста»: пропуск из `allowedSkips` не открывает строку); R-17 `pass`; D3 и D5 уже уточнены (2026-11-10).
- [ ] 2.16 `[protocol]` Тест (testing-quality «Проверка доказательств матрицы целей», сценарии «Id во вложенном тесте», «Id во внешней группе»; D3, уточнение 2026-11-10): `evidence_test.dart` на временном дереве проверяет:
  - `test('core/x: …')` внутри `group('другое имя', …)` — `core/x` `missing`;
  - `group('core/x', …)` на верхнем уровне `main` с вложенными тестами других имён — существует;
  - `test('core/x')` на верхнем уровне внутри цикла `for` или локальной функции `main` — существует;
  - вложенный `group('core/x')` внутри другой группы — `missing`;
  - соседние литералы и комментарии — как прежде.
  На настоящем дереве до 2.13 E-01 — `missing`. Красный.
- [ ] 2.17 `[protocol]` Реализация уточнения D3 в `test/support/parity/evidence.dart`: учёт вложенности вызовов `group(` (по скобкам тела, с пропуском строк и комментариев) при поиске первого литерала. Вместе с 2.13 группа `matrix evidence exists` зелёная без записи E-01 в `knownGaps`.
- [ ] 2.18 `[protocol]` Матрица `docs/architecture/proposals/agent-parity-goals.md` (решения Q9, Q10; 2026-11-10):
  - R-08 — без `acp/mcp-prompt-command`, пометка о change `add-agent-builtin-slash-commands`;
  - новая строка Should E-24 «MCP prompts как слэш-команды» (§3.6, этап 9+);
  - H-04 — полный путь `apps/codelab_cli/test/scenario/codelab_agent_corpus_test.dart`;
  - K-02, U-03 — пометка о change `add-agent-builtin-slash-commands`;
  - итоги §7 пересчитаны (Must 77, Should 81).
  Разбор матрицы (`matrix_parser`) даёт 77 строк Must; `guard` зелёный. Выполнено в документах 2026-11-10; проверка `guard` — вместе с 2.11.

## 3. Документация (итерация 3, 9.5, 9.7)

- [ ] 3.1 `[client]` `docs/user/README.md` и `docs/user/run-from-source.md` (D12): сборка `codelab` и `codelab-agent`, запуск app, пометка «установщик — с выпуском 1.0»; ссылка из `README.md` («Начало работы»).
- [ ] 3.2 `[agent]` `docs/user/configuration.md` (D12; R-14): `config.yaml` по слоям, секреты, `codelab config check`, LiteLLM Proxy как `baseUrl` с примером. Ссылка на документ — в критерии R-14 матрицы.
- [ ] 3.3 `[agent]` `docs/user/migrating-from-python-agent.md` (D12; R-16):
  - роли `codelab` и `codelab-agent`;
  - ручной перенос `codelab.toml` → `config.yaml` со ссылкой на таблицу §15.7, без копии таблицы;
  - профили и скрипты с `codelab serve` (D11).
- [ ] 3.4 `[agent]` Предупреждение о Python-сессиях (9.5): в `migrating-from-python-agent.md` — отдельный раздел «Сессии Python-агента не переносятся» (чистый лист, мигратора нет, agent-core-architecture §16.1); короткая ссылка — в `docs/user/README.md`.
- [ ] 3.5 `[agent]` `docs/user/zed.md`: подключение `codelab-agent serve --stdio` к Zed (9.8).
- [ ] 3.6 `[protocol]` Корневой `AGENTS.md` §5 — итоговый состав пакетов, профиль по умолчанию — встроенный агент, роль `codelab` и `codelab-agent`, Python-агент вне monorepo и заморожен (D13).
- [ ] 3.7 `[protocol]` `docs/architecture/testing.md`: TDD §9.0 п. 3 с исключениями (а)–(д), итерации §9.0 п. 8, `parity_evidence_test`, правило имени теста «первый литерал — id», `CODELAB_TEST_REPORT_DIR`, ночной `parity` (D3–D7).
- [ ] 3.8 `[agent]` `layers-and-dependencies.md` (агентские пакеты и мосты), `acp-boundary.md` (агентская сторона), `permissions.md` (разрешения агента и клиентский показ), `platform-integration.md` (встроенный агент в процессе app и `codelab-agent` как процесс), `technology-stack.md` (`args`, `yaml`, `yaml_edit`; без `toml`) — по D13.
- [x] 3.9 `[desktop]` `apps/codelab_desktop/AGENTS.md`: описание stdio-агента по D10, если раздел «Профили подключения» его упоминает. Правка не потребовалась: раздел уже описывает stdio-`codelab-agent` (проверено 2026-11-09, итерация 1).

## 4. Ворота MVP (итерация 4; не блокирует итерации 1–3)

Проводят ответственный за релиз и владелец продукта. Результаты записываются в таблицы `proposal.md` («Ворота MVP») и design.md («Чек-лист Zed»).

- [ ] 4.0 `[protocol]` Условие ворот (Q9, D4, D14): change `add-agent-builtin-slash-commands` слит в `develop`, его записи удалены из `knownGaps`, константа `knownGaps` и проверка устаревания удалены (если это не сделал сам тот change), строки K-02, R-08 и U-03 в ночном `parity` — `pass` (кроме `deferred` у `app:`). Счёт трёх ночей (4.1) начинается после этого.
- [ ] 4.1 `[protocol]` Три ночи подряд на `develop`: обязательные джобы и `parity` зелёные в трёх последовательных запусках по `schedule` без ручного перезапуска (`run_attempt` 1). Красный или пропущенный запуск обнуляет счёт. Ссылки, коммиты и даты — в `proposal.md`. Отчёт третьей ночи сохранён в `evidence/nightly/` этого change (Q6).
- [ ] 4.2 `[desktop]` Ветка `release/<version>` от `develop` после 4.1. Три последовательных зелёных прогона на одном коммите на macOS без перезапуска упавших тестов: `test:e2e:app:*`, `test:e2e:app:dart-agent`, `test:e2e:app:embedded` с `CODELAB_TEST_REPORT_DIR`. Отчёты, версия macOS и коммит — в `proposal.md`; сырые JSON — в `evidence/app/run-<n>/` этого change, если суммарно меньше ~5 МБ, иначе сводка (Q6, D9; пути относительные).
- [ ] 4.3 `[agent]` Чек-лист Zed (9.8): все 11 шагов. Версия Zed, сборка, доказательства в `evidence/zed/` (trace отредактирован по `observability.md`, D16) и подпись ответственного за релиз — в design.md. Сверка с другим агентом — только если он выбран.
- [ ] 4.4 `[protocol]` Политика заморозки Python-агента опубликована change `retire-python-agent` (D1); ссылка — в `proposal.md`, условие ворот «Python-агент заморожен».
- [ ] 4.5 `[protocol]` Итоговый прогон: `CODELAB_PARITY_RESULTS=<отчёт третьей ночи> CODELAB_PARITY_APP_RESULTS=<отчёты app> fvm dart test packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart` зелёный. У каждой строки Must `pass`, `deferred` нет. Вывод — в `proposal.md`, условия 1–3 таблицы §6.
- [ ] 4.6 `[protocol]` Таблица условий §6 в `proposal.md` заполнена (условия 4–6 — ссылки на 4.3, итерацию 3) и подписана владельцем продукта (решение о переключении) и ответственным за релиз (доказательства и сборка).
- [ ] 4.7 `[protocol]` `agent-parity-goals.md`: пометка «закрыто change `switch-default-agent-to-dart`» в строках, закрытых итерацией 2; `delivery-roadmap.md` §4.4 — M3 достигнута, со ссылкой на `proposal.md`.
- [ ] 4.8 `[protocol]` Архивирование change — только по просьбе пользователя. При слиянии дельт: строка Purpose `agent-transports` («встроенный референсный профиль `Codelab Agent`») приведена к D10.
