## Context

Задача 9.11 вехи M4 — решение о песочнице ОС (P-13) по модели угроз, итог — ADR. В ADR-0004 (`docs/architecture/adr/0004-defer-os-sandbox-harden-workspace-boundary.md`) — модель угроз исполнения, цена бэкендов и рекомендация. Здесь — решения этого change и реализация той части, которая входит в 1.0.

Факты (сверено с кодом 2026-11-25):

- **Агент.**
  - `BoundedEnv` проверяет путь каждой операции через `realpath` самого длинного существующего префикса (ENV-2, ENV-3).
  - `exec` проверяет только `cwd`, содержимое команды не проверяется; команда работает с правами пользователя.
  - Окружение команд и stdio-серверов MCP строится по `hostEnvironmentAllowlist` (`codelab_agent_io/lib/src/env/host_variables.dart`: `PATH`, `HOME`, `USER`, `LANG`, `LC_ALL`, `TMPDIR`, `SHELL`) плюс явные переменные (ENV-6).
- **Клиент, `terminal/create`.**
  - `IoTerminalProcessRunner.start` (`codelab_client_io/lib/src/platform/terminal_process_runner.dart`) вызывает `Process.start(command, args, environment: env.isEmpty ? null : env)` без `includeParentEnvironment: false`.
  - Поэтому процесс наследует всё окружение клиента (REV-29).
- **Клиент, containment.** Containment лексический. Раскрытие ссылок реализует change `fix-acp-client-symlink-containment`: порт `PathCanonicalizer`, двухступенчатая проверка, семантика `realpath -m`, fail-closed с `-32602`, диагностика с `reason: outside | unresolvable`.
- **ACP.** `10-Terminal.md` не говорит, наследует ли процесс окружение клиента; `env` описан как «Environment variables for the command». `session/request_permission` перед `terminal/*` — решение агента (`MAY`).
- **Смежный change `add-agent-remote-exec`.** Добавляет `serve --local-exec`. В этом режиме команды исполняет процесс агента под `BoundedEnv` и ENV-6, и `terminal/create` клиенту не уходит. Код клиента этот change не трогает.

## Goals / Non-Goals

**Goals:**

- Оформить решение 9.11: модель угроз, варианты с ценой, рекомендация — ADR-0004; выбор — Q1.
- Не передавать окружение клиента в команды `terminal/create`, чтобы окружение было не шире, чем у команд агента.
- Исправить документы о песочнице: P-13, понятие 5, §16.3, M4.

**Non-Goals:**

- Раскрытие ссылок в containment клиента — change `fix-acp-client-symlink-containment`.
- Реализация песочницы ОС (при рекомендуемом ответе Q1).
- Окружение процесса внешнего агента (Q3), права файлов клиента (REV-46), окружение команд агента на Windows.
- Новые методы или поля ACP.

## Decisions

### D1. Решение 9.11 — ADR-0004, без песочницы в 1.0

ADR-0004 (Proposed) рекомендует:

- в 1.0 граница исполнения — граница папки, одобрение, критические шаблоны и ENV-6;
- две меры 1.0 закрывают дыры клиентской границы:
  - раскрытие ссылок — `fix-acp-client-symlink-containment`;
  - окружение `terminal/create` — этот change;
- для недоверенных репозиториев — контейнер или ВМ;
- P-13 становится Could на вехе M5, первый бэкенд — macOS Seatbelt.

ADR становится Accepted после одобрения change пользователем (`adr/README.md`, по образцу ADR-0003).

Почему сначала граница клиента: сценарии S4 (ссылка) и S5 (окружение) модели угроз касаются всех агентов, включая сторонние, и закрываются дёшево. Песочница процесса агента их не закрыла бы вовсе: `fs/*` и `terminal/*` исполняет клиент.

Альтернативы описаны в ADR-0004, раздел Alternatives: окончательный Won't, macOS в 1.0, три ОС, песочница для `terminal/*` клиента. Выбор — Q1.

### D2. Окружение `terminal/create` по allowlist

`IoTerminalProcessRunner.start` строит окружение явно и запускает процесс с `includeParentEnvironment: false`:

1. **Базовый набор** — значения хоста для имён из allowlist, если они заданы:
   - все платформы: `PATH`, `HOME`, `USER`, `LANG`, `LC_ALL`, `TMPDIR`, `SHELL` — тот же список, что `hostEnvironmentAllowlist` агента (ENV-6);
   - Windows дополнительно: `SystemRoot`, `SystemDrive`, `windir`, `ComSpec`, `PATHEXT`, `TEMP`, `TMP`, `USERPROFILE`, `USERNAME`, `HOMEDRIVE`, `HOMEPATH`, `APPDATA`, `LOCALAPPDATA`, `ProgramData`, `ProgramFiles`, `ProgramFiles(x86)`, `CommonProgramFiles`, `CommonProgramFiles(x86)`, `ProgramW6432`, `ALLUSERSPROFILE`, `COMPUTERNAME`, `PSModulePath`, `OS`, `PROCESSOR_ARCHITECTURE`, `NUMBER_OF_PROCESSORS`. Без `SystemRoot` и `ComSpec` многие программы на Windows не стартуют, без `PSModulePath` не грузятся модули PowerShell. Имена сравниваются без учёта регистра, как в ОС.
2. **`env` запроса ACP** поверх базового набора: агент МОЖЕТ передать любую переменную, в том числе перекрыть базовую. На Windows слияние идёт без учёта регистра: `Path` из запроса заменяет `PATH` хоста, и в окружении остаётся одна переменная (иначе `Process.start` получил бы два ключа, и какой из них увидит процесс, не определено).

Фиксированных переменных (`TERM=dumb`, `PAGER=cat`, `GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0`) клиент не добавляет: какие переменные нужны команде, решает агент, и для любого агента клиент ведёт себя одинаково.

Сейчас CodeLab-агент их через клиента **не** передаёт (сверено с кодом): `AcpClientExecutionEnv.exec` (`codelab_agent_acp/lib/src/acp_client_env.dart`) кладёт в `env` запроса только `ExecOptions.env`, а фиксированный набор добавляет лишь `LocalExecutionEnv` (`codelab_agent_io/lib/src/env/local_execution_env.dart`, `_fixedVariables`). Значит, одна и та же команда CodeLab-агента локально и через клиента видит разное окружение — и до этого change, и после. Расхождение — R2, кто добавляет фиксированный набор — Q4.

**Где живёт список.** В `codelab_client_io`, а не импортируется из `codelab_agent_io`: клиентам запрещён импорт `package:codelab_agent_*` (`AGENTS.md` §5). Совпадение со списком агента закрепляется тестом сторожа `codelab_architecture_tests` (D4) и ссылкой на ENV-6 в doc-комментарии. Тест в `codelab_client_io` не годится: dev_dependency на `codelab_agent_io` пересекла бы границу сторон (`AGENTS.md` §5, ADR-0002), и сторож её не поймал бы — правило импортов и allowlist проверяют только `dependencies`; а сверка литерала с литералом в одном пакете — тавтология. Общий пакет ради семи строк был бы лишним слоем (§13).

**Тестируемость.** Конструктор остаётся `const` и получает необязательные параметры: `const IoTerminalProcessRunner({Map<String, String>? hostEnvironment, bool? isWindows})`. `null` разрешается в `Platform.environment` и `Platform.isWindows` при каждом `start`, а не в конструкторе. Построение окружения — чистая функция адаптера (`buildTerminalEnvironment(host, request, isWindows:)`), её проверяют без запуска процесса. Проверка платформы остаётся в адаптере (`AGENTS.md` §11). Вызовы `const IoTerminalProcessRunner()` в `apps/codelab_desktop/lib/app/app_scope.dart` и `apps/codelab_cli/lib/src/composition_root.dart` не меняются.

**Почему политика в адаптере, а не в application.** Базовый набор зависит от платформы и окружения хоста, а это забота infrastructure. Так же устроен агент: базовый набор строит `LocalExecutionEnv` в `codelab_agent_io`. Правило «что передаётся» задаёт требование спецификации `acp-terminal-client`, а контракт `env` описан в doc-комментарии порта `TerminalProcessRunner`.

**Почему allowlist, а не снятие секретных имён.**

- Список имён секретов неполон по определению: change `extend-secret-name-redaction` расширяет его как раз потому, что имена пропускались.
- Allowlist хоста совпадает с базовым набором агента (ENV-6): секреты окружения не уходят в команды ни на одной стороне. Полного совпадения окружений нет — фиксированный набор агент через клиента не передаёт (R2, Q4).
- Цена: сторонние агенты теряют переменные вне списка (`NVM_DIR`, `JAVA_HOME`, `VIRTUAL_ENV`, `SSH_AUTH_SOCK`). Выбор — Q2.

Альтернативы:

- **Снять только секретные имена** (`CODELAB_SECRET_*`, правило имён `SecretRedactor`). Совместимо со сторонними агентами, но пропускает секреты под несекретными именами (`DATABASE_URL` с паролем). Это Q2 (б).
- **Allowlist плюс список из профиля подключения.** Гибко, но меняет модель и UI профилей. Это follow-up при жалобах, Q2 (в).

**Наблюдаемость.** Построенное окружение процесса не логируется ни в каком виде: имена переменных для диагностики бесполезны, а значения — секреты (§16). Параметр `env` входящего `terminal/create` по-прежнему виден в журнале кадров протокола с маскированием `SecretRedactor`, как любой кадр; это не меняется. Новых событий и полей диагностики change не вводит. Схема `reason` отказов containment (`outside | unresolvable`) принадлежит `fix-acp-client-symlink-containment`, своей схемы этот change не добавляет.

### D3. Зависимость и порядок относительно `fix-acp-client-symlink-containment`

Оба change правят одни и те же места.

| Место | `fix-acp-client-symlink-containment` | этот change |
|---|---|---|
| `IoTerminalProcessRunner` (`terminal_process_runner.dart`) | не правит; используется в сквозном тесте `symlink_containment_test.dart` | окружение и конструктор |
| `acp_client_application.dart`, обработчик `terminal/create` | канонизация `cwd`, защита поколений | не правит |
| `apps/codelab_cli/lib/src/composition_root.dart`, `apps/codelab_desktop/lib/app/app_scope.dart` | привязка `PathCanonicalizer` | не правит: значения конструктора по умолчанию |
| `docs/architecture/permissions.md` | исключение `fs/*` и `terminal/*`, §29–30 | исключение `fs/*` и `terminal/*`: абзац об окружении `terminal/create` |
| `docs/architecture/platform-integration.md` | §16, §71 | §53 «Окружение процессов»: абзац «В коде» об `IoTerminalProcessRunner` |
| `codelab_client_acp/doc/execution-on-client.md` (строка «символическая ссылка… проверка лексическая») и глава 03 (`03-agent-requests-fs-terminal.md`, «Что проверка не покрывает») | **не правит**: в его `tasks.md` таких задач нет, файлы появились позже базы его worktree | строки про окружение и, после влития того change, строки про ссылки (задача 4.2) |
| ADR-0004, матрица P-13 | — | этот change; ссылается на тот как на меру 1.0 |

Порядок: этот change реализуется **после** влития `fix-acp-client-symlink-containment` в `develop`. Ветка `feature/add-os-sandbox-decision` создаётся от `develop` с ним.

Причины:

- сквозной тест того change создаёт настоящий `IoTerminalProcessRunner()` — после него проверяется, что изменение конструктора без аргументов его не ломает;
- общий абзац `permissions.md` правится поверх уже принятого текста о ссылках, без конфликта слияния;
- строки документации клиента о ссылках описывают поведение того change, и обновить их можно только после его влития.

Владелец строк о ссылках в `execution-on-client.md` и главе 03 `codelab_client_acp` — этот change (задача 4.2). В `permissions.md` и `platform-integration.md` §16 и §71 этот change меняет только абзацы об окружении.

ADR-0004 и документы матрицы от того change не зависят. Их МОЖНО принять раньше, со ссылкой на `fix-acp-client-symlink-containment` как на меру 1.0.

### D4. Пакеты, зависимости, сторож

| Пакет | Изменение | Слой |
|---|---|---|
| `codelab_client_io` | окружение `IoTerminalProcessRunner`, конструктор для тестов | infrastructure |
| `codelab_client_acp` | doc-комментарий контракта `env` порта `TerminalProcessRunner` | domain (порт) |
| `codelab_architecture_tests` | тест-сверка: POSIX-часть allowlist клиента (`codelab_client_io`) совпадает с `hostEnvironmentAllowlist` агента (`codelab_agent_io`); тест читает оба исходника как текст, без импорта пакетов | сторож |

Новых пакетов, зависимостей pubspec и импортов между пакетами нет. Правило в `rules.dart` не нужно, allowlist зависимостей не меняется. Сторож получает новый тест, а матрица целей, которую разбирает `parity_evidence_test`, правится (D5) — поэтому `melos run guard` обязателен. Граф в `README.md` не меняется. `codelab_client_acp` остаётся web-безопасным.

### D5. Документы

- **Матрица целей:**
  - P-13 — по ответу Q1. Рекомендация: Could, этап 9+, «Как видно клиенту» — не видно, критерий — ADR-0004 и будущий change.
  - Обоснование P-13.
  - Строка §8 «Песочница ОС» — «решено ADR-0004».
  - Сводка §7 «Итого»: при ответе Q1 (а) — «Could — 78, Won't — 24» вместо «77» и «25», запись «Пересчёт 2026-11-…: P-13 Won't → Could, ADR-0004». Матрицу разбирает `parity_evidence_test` сторожа (`tool/ci/ci_scope.dart`, `_parityMatrix`), поэтому после правки — `melos run guard`.
- **`00-six-concepts.md`**, «Чего нет сознательно»: ссылка на ADR-0004, контейнер как изоляция 1.0.
- **Документ ядра**, §16.1 и §16.3: вопрос закрыт ADR-0004.
- **`delivery-roadmap.md`**: §4.5 — вопрос до вехи закрыт, критерий выхода — ссылка на ADR; §4.6 (M5) и §6.2 (пул 1.x) — P-13 Could, первый бэкенд macOS. В `09-14` (пункт 11) — отметка.
- **Другие места, где песочница записана как Won't или «не берём»:** `agent-core/17-12-loop-and-security.md` (пункт 5 запрета чтения: «P-13 — Won't»), `dart-agent-and-clients/04-target-architecture.md` (строка «декларативная песочница ОС … не берём»), `packages/dart/codelab_agent_core/doc/01-overview.md` (абзац «Песочницы уровня ОС…» — ссылка на ADR-0004, это `docs-writer`).
- **`permissions.md`**, исключение `fs/*` и `terminal/*`: окружение `terminal/create` по allowlist (D3: только этот абзац).
- **`platform-integration.md` §53**: абзац «В коде» — `IoTerminalProcessRunner` больше не наследует окружение клиента; `StdioAcpTransport` — по-прежнему (Q3).
- **`docs/architecture/README.md` §3**: ADR-0004 внесён в перечень вместе с файлом (раздел «На рассмотрении»); после одобрения переносится в «Принятые решения».
- **Документация пакетов и пользователя** — задача 4 (`docs-writer`).

## Risks / Trade-offs

- **R1. Сторонний агент теряет переменные окружения.** Команда без `JAVA_HOME` или `SSH_AUTH_SOCK` падает с понятной ошибкой в выводе. → Агент передаёт переменные в `env`; изменение описывается в разделе выпуска `CHANGELOG.md`; Q2 (в) — follow-up.
- **R2. Расхождение окружений клиента и агента.** (1) Списки дублируются, потому что импорт `codelab_agent_*` клиентам запрещён → тест-сверка в стороже (D4), Windows-часть агента — запись в backlog. (2) Команда CodeLab-агента через клиента не получает фиксированный набор `TERM=dumb`, `PAGER=cat`, `GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0`, который добавляет только `LocalExecutionEnv`: `git log` через клиента может звать пейджер, `git fetch` — ждать пароль до таймаута. Это расхождение существует и сейчас (клиент отдаёт всё окружение, но этих значений в нём обычно нет), этот change его не создаёт и не закрывает → Q4.
- **R3. Race и cancellation (§9, §12).** Построение окружения синхронно, нового `await` в обработчике `terminal/create` нет. Защита поколений и канонизация `cwd` — в зоне `fix-acp-client-symlink-containment`.
- **R4. Forward compatibility ACP.** Коды ошибок и формы ответов прежние, новых полей нет.
- **R5. Web-безопасность.** `dart:io` — только в `codelab_client_io`.
- **R6. Allowlist ядра агента (PKG-2).** Не затрагивается: код агента не меняется.
- **R6a. Процесс стороннего агента.** Сторонний stdio-агент по-прежнему получает всё окружение клиента и может исполнять команды своим процессом, минуя `terminal/create` (ADR-0004, S5b). Change закрывает утечку в команды `terminal/create`, но не в агента → Q3; пользовательская документация называет это ограничение (задача 4.3).
- **R7. Permissions и containment (§10).** Исключение `fs/*` и `terminal/*` из client-side approval сохраняется; утечка секретов в команды закрыта. Терминал пользователя не затронут.
- **R8. Реализация раньше зависимости.** Если этот change влить до `fix-acp-client-symlink-containment`, будет конфликт в общих абзацах документов. → Порядок D3.

## Migration Plan

Данные и конфигурация не меняются. Изменение поведения для сторонних агентов (окружение `terminal/create`) описывается в разделе выпуска `CHANGELOG.md`. Откат — возврат прежнего `IoTerminalProcessRunner`; данные не затрагиваются.

## Open Questions

Ответы пользователя 2026-11-26: по всем вопросам принята рекомендация design.md (Q1 (а), Q2 (а), Q3 (а), Q4 (а)). Вопросы ниже закрыты, текст сохранён как обоснование.

- **Q1. Решение 9.11 (окончательный выбор).**
  - (а) **Рекомендуется:** в 1.0 — граница папки, одобрение, меры 1.0 (этот change и `fix-acp-client-symlink-containment`) и контейнер для недоверенных репозиториев. P-13 → Could, веха M5. Первый бэкенд — macOS Seatbelt, отдельный change `add-exec-sandbox-macos` по опорному дизайну ADR-0004, п. 5.
  - (б) Окончательный Won't: снять «сейчас», пересмотр только по событию (инцидент, запрос пользователей).
  - (в) Песочница macOS в 1.0: до одобрения этот change получает спецификацию `agent-execution-env` и задачи бэкенда Seatbelt, веха M4 растёт.
  - (г) Песочница на трёх ОС: отдельный ADR о нативном помощнике, объём этапа.

  Рекомендация — (а): дыры S4 и S5 касаются всех и закрываются дешевле, M4 — веха выпуска, а профиль песочницы выиграет от опыта 1.0. Триггер пересмотра при (а) и (б): инцидент с исполнением команды или MCP-сервера либо планирование вехи M5 — что раньше. При любом ответе пользовательская документация предупреждает о режиме `bypass`: команды идут без вопроса, кроме критических шаблонов, и с недоверенным репозиторием он допустим только в контейнере или ВМ (ADR-0004, Decision п. 3).
- **Q2. Окружение `terminal/create`.**
  - (а) **Рекомендуется:** allowlist как ENV-6 плюс `env` запроса (D2).
  - (б) Всё окружение без секретных имён.
  - (в) (а) плюс список дополнительных имён в профиле подключения — follow-up.

  Рекомендация — (а).
- **Q3. Окружение процесса внешнего агента (вторая половина REV-29).**
  - (а) **Рекомендуется:** вне этого change; issue #506 остаётся открытым с пометкой «команды закрыты, процесс агента — отдельное решение». Агент — программа пользователя, ему нужны свои ключи; Dart-агент по `--stdio` читает `CODELAB_SECRET_*`.
  - (б) Снимать `CODELAB_SECRET_*` для профилей, которые не являются `codelab-agent`: эвристика по команде профиля ненадёжна.
  - (в) Allowlist плюс `env` профиля: ломает сторонних агентов, которые читают ключи из окружения.

  Рекомендация — (а).
- **Q4. Кто добавляет фиксированный набор окружения команды (`TERM=dumb`, `PAGER=cat`, `GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0`) при исполнении через клиента.**
  - (а) **Рекомендуется:** агент — `AcpClientExecutionEnv.exec` кладёт набор в `env` запроса `terminal/create` под `ExecOptions.env` (`[agent]`, отдельный change или запись backlog). Тогда окружение команды CodeLab-агента одинаково на обеих сторонах, а клиент остаётся одинаковым для всех агентов.
  - (б) Клиент добавляет набор сам — меняет поведение команд сторонних агентов (например, глушит пейджер, которого они ждут) без основания в ACP.
  - (в) Вне scope, расхождение остаётся задокументированным.

  Рекомендация — (а), вне этого change: он остаётся клиентским.
