## Why

Задача 9.11 вехи M4 требует решения о песочнице ОС по модели угроз. Итог задачи — ADR, а строку P-13 матрицы целей нужно исправить до первого `stable` (`delivery-roadmap.md` §4.5, критерии выхода M4; `dart-agent-and-clients/09-14-stage-9-switch-default.md`, пункт 11). Сейчас P-13 стоит как Won't «сейчас», а модели угроз нет. `00-six-concepts.md` (понятие 5) объясняет отсутствие песочницы тем, что её роль выполняют `BoundedEnv`, одобрение и профили хостов.

Модель угроз (ADR-0004) показала две вещи.

1. **В существующей границе клиента есть дыры, и песочница их не закрывает.**
   - Containment `fs/*` и `cwd` `terminal/create` лексический: символическая ссылка внутри рабочей папки, ведущая наружу, проходит проверку. Эту дыру закрывает отдельный change `fix-acp-client-symlink-containment`. Он идёт параллельно, и этот change от него зависит (design.md, D3).
   - Процесс `terminal/create` получает всё окружение клиента, включая `CODELAB_SECRET_*` и `*_API_KEY`. Причина — `IoTerminalProcessRunner` вызывает `Process.start` без `includeParentEnvironment: false` (REV-29, issue #506). У агента окружение команд режется allowlist ENV-6, у клиента — нет. Эту дыру закрывает этот change.
2. **Песочница ОС — единственная мера против двух угроз:** код проекта, который запускает одобренная команда, и вредный stdio-сервер MCP. Но её цена высока:
   - нужны три разных бэкенда, и два из них требуют нативного помощника;
   - закрытая сеть ломает установку пакетов.

   Для недоверенных репозиториев уже есть изоляция уровня ОС без нового кода: агент в контейнере или ВМ (`codelab-agent serve --local-exec`, change `add-agent-remote-exec`).

## What Changes

- **ADR-0004** (`docs/architecture/adr/0004-defer-os-sandbox-harden-workspace-boundary.md`, Proposed). В нём:
  - модель угроз исполнения и цена бэкендов;
  - рекомендация: граница папки и одобрения в 1.0, песочница ОС в 1.x, первый бэкенд — macOS Seatbelt;
  - меры 1.0: раскрытие ссылок у клиента (change `fix-acp-client-symlink-containment`) и окружение `terminal/create` (этот change);
  - опорный дизайн песочницы для будущего change.

  Окончательный выбор варианта — Q1 design.md.
- **Окружение `terminal/create` по allowlist.** Процесс получает переменные хоста из allowlist и `env` запроса поверх них; остальное окружение клиента не наследуется.
  - Allowlist тот же, что ENV-6 у агента.
  - На Windows к нему добавляются системные переменные, без которых не работают программы.
- **Документы.**
  - Матрица и архитектура: строка P-13 и её обоснование, §8 матрицы, `00-six-concepts.md`, §16.3 документа ядра, критерии и вопросы M4 в `delivery-roadmap.md`, задача 9.11.
  - `permissions.md` и `platform-integration.md` §53: только окружение `terminal/create`.
  - Остальные места, где песочница записана как Won't или «не берём» (design.md, D5).
  - Документация клиента и ядра: окружение терминала, пределы секретов.
  - Пользовательская страница о границе исполнения и изоляции контейнером.

ACP не меняется: методов, полей, состояний и кодов ошибок не добавляется. ACP не определяет окружение процесса `terminal/create` (`docs/protocols/acp/protocol/10-Terminal.md`), поэтому allowlist — политика клиента в пределах протокола.

## Не входит

- **Раскрытие символических ссылок в containment клиента** — change `fix-acp-client-symlink-containment`, зависимость этого change.
- **Песочница ОС** (Seatbelt, bubblewrap, Landlock, seccomp, AppContainer).
  - При рекомендуемом ответе на Q1 — change вехи M5 `add-exec-sandbox-macos`; опорный дизайн — ADR-0004, п. 5.
  - При ответе Q1 (в) или (г) этот change до одобрения расширяется спецификацией и задачами первого бэкенда.
- **Окружение процесса внешнего агента** — вторая половина REV-29: `StdioAcpTransport` передаёт агенту всё окружение клиента. Это решение — Q3.
- **Права файлов клиента** (REV-46, issue #529).
- **Окружение команд агента на Windows**: в `hostEnvironmentAllowlist` нет `SystemRoot`, `PATHEXT` и подобных переменных. Запись в backlog — задача 4.3.
- **Фиксированный набор окружения команды** (`TERM=dumb`, `GIT_TERMINAL_PROMPT=0` и др.) для команд CodeLab-агента через клиента: сейчас его добавляет только `LocalExecutionEnv`; кто должен добавлять — Q4 (рекомендация — агент, отдельно).
- **Подтверждение доверия при изменении проектного конфига** (ADR-0004, S9): доверие привязано к корню проекта, а не к содержимому; запись в backlog.
- **Терминал пользователя** (панель Terminal desktop): это не действие агента.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `acp-terminal-client`: новое требование «Окружение процесса terminal/create по allowlist».

## Impact

- `codelab_client_io`: `IoTerminalProcessRunner` строит окружение по allowlist и запускает процесс с `includeParentEnvironment: false`. Конструктор получает необязательные `hostEnvironment` и `isWindows` для тестов. Значения по умолчанию сохраняют вызовы без аргументов, поэтому composition root app и CLI не меняются.
- `codelab_client_acp`: в коде без изменений; меняется doc-комментарий контракта `env` порта `TerminalProcessRunner`.
- `codelab_architecture_tests`: тест-сверка allowlist клиента с `hostEnvironmentAllowlist` агента по исходникам (design.md, D4). Новых пакетов, зависимостей и импортов между пакетами нет; `melos run guard` обязателен (новый тест и правка матрицы целей, которую разбирает `parity_evidence_test`). Граф в `README.md` не меняется.
- Агент (`codelab_agent_*`, `apps/codelab_agent`), `codelab_acp_protocol`, `codelab_acp_transports`, фикстуры ACP — без изменений кода.
- Порядок реализации — после `fix-acp-client-symlink-containment` (design.md, D3).
