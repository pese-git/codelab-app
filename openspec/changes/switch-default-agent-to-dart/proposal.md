## Why

Этап 9 (веха M3, MVP) переключает CodeLab на Dart-агента по умолчанию и закрывает критерий вывода Python-агента ([матрица целей §6](../../../docs/architecture/proposals/agent-parity-goals.md#6-критерий-вывода-python-агента-и-переключения-по-умолчанию); [план этапа 9](../../../docs/architecture/proposals/dart-agent-and-clients/09-14-stage-9-switch-default.md); [дорожная карта §4.4](../../../docs/architecture/proposals/delivery-roadmap.md#44-m3--mvp)). Сегодня этого нельзя ни сделать, ни доказать:

- **Нет автоматической проверки доказательств.** Ворота MVP требуют, чтобы у каждой из 77 строк Must был зелёный критерий приёмки, но `parity_evidence_test.dart` нет. Ночной прогон CI (`schedule`, 03:00) не публикует машинных отчётов: ни `dart test` с JSON-отчётом, ни JUnit `codelab test-scenario --junit` (флага `--junit` нет, хотя он заложен в §9.11), ни артефакта `parity-results/`. Статус строки сегодня устанавливается только глазами.
- **Предварительная сверка матрицы с репозиторием** (без запуска тестов; design.md, «Оценка масштаба 9.2») уже нашла пробелы. У 3 строк Must нет файла или теста: 4 фикстуры `acp/*` и 1 тест `core/*`. У 6 строк id `core/<id>` есть только в комментарии, а не в имени теста, поэтому в отчёте его не найти. 1 строка закрыта только `scripted-only`-тестом, который в режиме `dart` не запускается. Ещё у 7 строк нет id критерия: только путь файла теста (5 строк) или «все `acp/*`» / «все `app:*`» (2 строки).
- **Встроенное описание stdio-агента указывает на Python-агента.** `codelabAgentStdioProfile` (`codelab_acp_transports`) — по-прежнему `codelab serve --stdio`, а требование `agent-transports` «Референсный профиль codelab-agent» описывает именно его. После переключения команда `codelab` принадлежит CLI, у которого `serve` нет. Профиль по умолчанию «встроенный агент» в app и CLI уже сделан change `add-app-settings-shell` (D5, D21): этот change закрывает вторую половину задачи 9.3.
- **Пользователь не предупреждён**, что сессии Python-агента не переносятся (9.5, agent-core-architecture §16.1). Нет пользовательской документации MVP по конфигурации, LiteLLM Proxy (R-14) и ручному переносу настроек из `codelab.toml` (R-16, §15.7).

## What Changes

- **9.1. Проверка доказательств** (`packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart`, testing-quality «Проверка доказательств матрицы целей»):
  - разбирает таблицы §3 и §4.1 матрицы и извлекает доказательства строк Must: `acp/<id>`, `cli/<id>`, `core/<id>`, `app:<файл>` и пути файлов тестов;
  - **существование** проверяется в каждом прогоне сторожа: файл фикстуры, тест с именем `cli/<id>` или `core/<id>`, файл интеграционного теста app. Временный список известных пробелов `knownGaps` работает как храповик (design.md, D4): пробел из списка не роняет сторож, а устаревшая запись роняет. К концу 9.2 список пуст;
  - **статус** проверяется только при заданном каталоге отчётов `CODELAB_PARITY_RESULTS`: `pass`, иначе `missing` / `not-run` / `failed` / `skipped` со строкой матрицы и источником.
- **Машинные отчёты** (testing-quality «Машинные отчёты прогонов»): при непустой `CODELAB_TEST_REPORT_DIR` Melos-скрипты тестов, e2e CLI, conformance и app-приёмки дополнительно пишут JSON-отчёт `--file-reporter json:<файл>`, а `conformance:embedded` — JUnit. Без переменной команды прежние.
- **`codelab test-scenario --junit <файл>`** (cli-scenario-driver «JUnit-отчёт test-scenario»): JUnit XML по фикстурам с `failure` и `skipped`. Аргументы агента в файл не попадают. Коды выхода и stdout прежние.
- **Ночная проверка в CI** (testing-quality «Ночная проверка доказательств в CI»): по `schedule` и `workflow_dispatch` каждый джоб матрицы публикует свой отчёт артефактом. Новый джоб `parity` собирает артефакты в `parity-results/`, пишет `meta.json` (коммит, запуск), прогоняет `parity_evidence_test` и публикует итог. На pull request и push джоба `parity` нет. Правка матрицы целей в pull request запускает `guard`, даже если больше ничего не изменено.
- **9.3. Встроенное описание stdio-агента** (agent-transports «Референсный профиль codelab-agent», MODIFIED): `codelabAgentStdioProfile` — `codelab-agent (stdio)`, `codelab-agent serve --stdio`. Оно же — единственный источник значений по умолчанию черновика «Add profile» (`ProfileDraft`). Отдельной встроенной строки stdio на странице «Connection» нет (design.md, D10; решение Q1). Профиль по умолчанию не меняется: в app и CLI это встроенный агент (change `add-app-settings-shell`, D5, D21).
- **9.2. Закрытие пробелов Must** — механизм и предварительный список (tasks.md, итерация 2). Точный список задач 9.2 даёт первый отчёт 9.1 (задача 1.14). Каждая задача 9.2 — пара «тест → реализация» со ссылкой на строку Must. Строки K-02, R-08 и U-03 закрывает change `add-agent-builtin-slash-commands` (решение Q9).
- **9.5 и часть 9.7 — документация** (design.md, D12, D13):
  - пользовательская документация MVP в `docs/user/`: запуск из исходников, `config.yaml`, LiteLLM Proxy как `baseUrl`, ручной перенос настроек из `codelab.toml` по таблице §15.7, предупреждение о Python-сессиях;
  - архитектурные документы по чек-листу 9.7;
  - корневой `AGENTS.md` §5 приводится к итоговому составу пакетов.
- **9.8. Чек-лист Zed** — заготовка таблицы результатов в design.md («Чек-лист Zed»). Проводит и подписывает ответственный за релиз.
- **Ворота MVP** — отдельная последняя итерация (tasks.md, итерация 4). Она не блокирует итерации 1–3: три ночи CI подряд, три прогона Flutter-тестов на macOS в `release/<version>`, чек-лист Zed, подписи. Заготовки таблиц — ниже.

**BREAKING:** нет для данных пользователя. `profiles.json` и `config.yaml` не меняются, профиль по умолчанию уже встроенный агент. Изменения, видимые пользователю:
- описание stdio-агента в коде и спецификации теперь называет `codelab-agent serve --stdio` вместо `codelab serve --stdio`;
- у `codelab test-scenario` новый флаг `--junit`.

## Не входит

- **9.4 — поставка** (`release.yml`, установщики, каналы U-29, подписанные `SHA256SUMS`). Это change `add-release-pipeline-and-installer`, веха M4. Вместе с ним в 9.7 входят инструкция установки и `docs/release/verify.md`.
- **Подписанные дистрибутивы app (D-16)** — change `add-signed-app-distributions`. **Политика конфиденциальности (D-18)**, `PRIVACY.md` и ссылка на неё в README — change `add-privacy-policy`.
- **9.6 — онбординг** — сделан change `add-provider-setup-ui` (архив `2026-11-09`). Onboarding app (D-11) — отдельный change после `add-app-navigation-shell`.
- **9.9 — заморозка и удаление Python-агента, алиас `codelab serve`** — change `retire-python-agent`: по плану этапа 9 в его scope входят «заморозка, сроки удаления, алиасы команд». Заморозка входит в ворота MVP, поэтому итерация 4 этого change зависит от того, что `retire-python-agent` хотя бы опубликовал политику заморозки (design.md, D1; решение Q3).
- **9.11 — решение о песочнице ОС (P-13)** — ADR вехи M4.
- **Смена `ui.mode` CLI по умолчанию** с `line` на `tui` — отдельный change (§12.2.1).
- **Новые строки матрицы и изменение приоритетов.** Матрица меняется только там, где это нужно для разбора: экранирование `|` в строке P-12, полные пути в строках R-23 и H-04 и правило доказательств в §1.4. По решению Q4 новых id не вводится. Исключение — решение Q10 (2026-11-10): `acp/mcp-prompt-command` убран из R-08, MCP prompts вынесены в строку Should E-24 (этап 9+).
- **Встроенные слэш-команды Dart-агента** (`/compact`, `/help`, `/mode`, `/model`, `/status`, ответ на неизвестную команду) — change `add-agent-builtin-slash-commands` (решение Q9, design.md). Строки K-02, R-08 и U-03 закрывает он; ворота MVP (итерация 4) ждут его merge.
- **Изменения ACP:** новых методов, полей, `_meta` и `_codelab/*` нет. Чек-лист Zed проверяет только стандартный ACP.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `testing-quality`:
  - ADDED — проверка доказательств матрицы целей (`parity_evidence_test`);
  - ADDED — машинные отчёты прогонов (`CODELAB_TEST_REPORT_DIR`);
  - ADDED — ночная проверка доказательств в CI (артефакты, джоб `parity`, `guard` на правку матрицы).
- `cli-scenario-driver` — ADDED: JUnit-отчёт `test-scenario --junit`.
- `agent-transports` — MODIFIED: «Референсный профиль codelab-agent» описывает `codelab-agent serve --stdio` и общий источник значений по умолчанию черновика профиля.

## Impact

- **Код:**
  - `packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart` и `test/support/parity/` (разбор матрицы, чтение отчётов, свёртка статусов);
  - `tool/ci/ci_scope.dart` — правка матрицы запускает `guard`;
  - `.github/workflows/ci.yml` — артефакты отчётов и джоб `parity`;
  - корневой `pubspec.yaml` — `CODELAB_TEST_REPORT_DIR` в скриптах;
  - `apps/codelab_cli/lib/src/scenario/` и `cli_args.dart` — `--junit`;
  - `packages/dart/codelab_acp_transports/lib/src/transport_configs.dart` — `codelabAgentStdioProfile`;
  - `packages/dart/codelab_client_core/lib/src/connection/profile_draft.dart` — значения по умолчанию из описания;
  - тесты `apps/codelab_desktop`, которые сверяют описание.
- **Зависимости:** новых нет. `parity_evidence_test` читает JSON (`dart:convert`) и JUnit своего формата узким чтением без пакета `xml` (design.md, D6). Граф `README.md` не меняется. Нового правила сторожа в `rules.dart` нет (D15).
- **Данные пользователя:** не меняются. Сохранённые профили с `codelab serve` не переписываются (D11; решение Q2).
- **CI:** ночной прогон дольше на сбор артефактов и джоб `parity`. Пока 9.2 не закрыт, ночной `parity` красный — это ожидаемый сигнал ворот, а не сбой (design.md, «Risks»).
- **Документы:**
  - `09-14-stage-9-switch-default.md` (распределение 9.7 и 9.9 по changes, правило статусов 9.1);
  - `agent-parity-goals.md` (§1.4 — правило доказательств, P-12, R-23, ссылки на change в закрытых строках);
  - `delivery-roadmap.md` §4.4, §10.3;
  - `docs/architecture/testing.md`, `layers-and-dependencies.md`, `acp-boundary.md`, `permissions.md`, `platform-integration.md`, `technology-stack.md`;
  - корневой `AGENTS.md` §5, `README.md` («Начало работы» — ссылка на `docs/user/`);
  - новый каталог `docs/user/`.

## Ворота MVP: таблицы доказательств

Заполняются в итерации 4 (tasks.md). До заполнения стоит «—».

### Критерий вывода Python-агента (матрица §6)

| № | Условие | Доказательство | Итог |
|---|---|---|---|
| 1 | все строки Must §3 и §4.1 зелёные | отчёт `parity_evidence_test` третьей ночи (артефакт `parity-results`) и прогон с отчётами app (`CODELAB_PARITY_APP_RESULTS`) | — |
| 2 | дефекты §4.2 закрыты | соответствующие фикстуры в отчёте `parity_evidence_test` | — |
| 3 | клиенты проходят тесты с Dart-агентом | отчёты `test:e2e:app:dart-agent` и `test:e2e:app:embedded` (×3), `test:e2e:cli:dart-agent`, `test:e2e:cli:embedded` | — |
| 4 | совместимость с Zed | design.md, «Чек-лист Zed», 11 шагов | — |
| 5 | документация обновлена | `docs/user/`, документы 9.7 (tasks.md, итерация 3) | — |
| 6 | пользователи предупреждены о Python-сессиях | `docs/user/` (задача 3.4) | — |

### Три ночи подряд (`schedule`, ветка `develop`)

| № | Дата | Коммит | Запуск | Обязательные джобы, `parity` | Итог |
|---|---|---|---|---|---|
| 1 | — | — | — | — | — |
| 2 | — | — | — | — | — |
| 3 | — | — | — | — | — |

Красный, пропущенный или вручную перезапущенный запуск обнуляет счёт.

### Flutter-тесты приложения на macOS (`release/<version>`, один коммит)

| № | Коммит | macOS | `test:e2e:app:*` | `test:e2e:app:dart-agent` | `test:e2e:app:embedded` | Отчёты | Итог |
|---|---|---|---|---|---|---|---|
| 1 | — | — | — | — | — | — | — |
| 2 | — | — | — | — | — | — | — |
| 3 | — | — | — | — | — | — | — |

Упавшие тесты не перезапускаются (`AGENTS.md` §21). Место хранения отчётов — по решению Q6 (design.md, D9).

### Подписи

| Роль | Решение | Имя | Дата |
|---|---|---|---|
| Владелец продукта | переключение по умолчанию | — | — |
| Ответственный за релиз | доказательства, сборка, чек-лист Zed | — | — |
