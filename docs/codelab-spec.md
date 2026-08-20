# Спецификация проекта CodeLab

Статус: черновик
Проект: CodeLab
Домен: ACP-клиент для взаимодействия с AI agent
Стек: Dart, Flutter, FVM, Melos, monorepo

## 1. Назначение

CodeLab — клиентское приложение для работы с AI agent через ACP
(Agent Client Protocol). Приложение отвечает за клиентскую сторону
взаимодействия: подключение к agent, создание и возобновление сессий, отправку
prompts, получение streaming-обновлений, отображение активности agent, запрос
подтверждения пользователя для рискованных действий, отмену работы и
восстановление после разрывов соединения.

CodeLab не реализует LLM-инференс на стороне клиента. Выполнение модели,
рассуждение agent и запуск инструментов выполняются внешним agent-процессом или
сервисом, если отдельный модуль явно не задает иное поведение.

## 2. Продуктовые цели

CodeLab должен предоставить надежный, наблюдаемый и безопасный интерфейс для
работы с agent. Пользователь должен видеть, что делает agent, понимать, когда
agent запрашивает разрешение, прерывать долгие операции и продолжать работу
после сбоев транспорта без потери уже полученного клиентом контекста сессии.

MVP должен поддерживать:

- подключение к ACP-совместимому agent;
- инициализацию протокола и согласование capabilities;
- создание новой сессии;
- отправку prompt в активную сессию;
- отображение streamed assistant messages, status updates, tool calls и errors;
- явное подтверждение пользователя для рискованных действий;
- отмену активного prompt или задачи;
- состояния disconnect, reconnect, failure, completed и cancelled;
- сохранение неизвестных полей протокола для forward compatibility.

## 3. Не-цели

MVP не включает:

- локальный LLM-инференс;
- логику планирования agent внутри Flutter-клиента;
- прямое выполнение shell, network или file actions UI-компонентами;
- скрытые расширения протокола без обновления спецификации;
- multi-agent orchestration за пределами отображения событий, полученных от
  agent;
- cloud account sync, если это не введено отдельной спецификацией.

## 4. Пользователи и основные сценарии

Основные пользователи — разработчики и технические операторы, которые запускают
AI agents или подключаются к ним. Им нужен клиент, делающий работу agent
наблюдаемой и управляемой.

Основные сценарии:

1. Запустить CodeLab и подключиться к локальному или удаленному agent.
2. Инициализировать протокол и показать capabilities соединения.
3. Создать сессию и отправить prompt.
4. Наблюдать streamed output, tool calls, status changes и errors.
5. Подтвердить, отклонить или изучить рискованное действие agent.
6. Отменить выполняемую работу и получить финальное состояние `cancelled`.
7. Восстановиться после disconnect и продолжить сессию или явно показать
   ошибку.

## 5. Архитектура

CodeLab использует layered monorepo. Нижние слои являются platform-neutral и не
должны зависеть от Flutter.

```text
.
├── apps/
│   └── codelab_app/
├── packages/
│   ├── dart/
│   │   ├── acp_protocol/
│   │   ├── acp_transports/
│   │   ├── acp_client_core/
│   │   └── acp_testing/
│   └── flutter/
│       └── acp_ui/
├── docs/
│   ├── codelab-spec.md
│   ├── acp/
│   │   └── spec.md
│   └── adr/
└── openspec/
```

### 5.1. Ответственность пакетов

`packages/dart/acp_protocol` определяет типизированные ACP-сообщения, codecs,
validation, errors, обработку версии схемы и forward-compatible сохранение
неизвестных полей. Пакет не должен импортировать Flutter, UI-код, transport-код
или `dart:io`.

`packages/dart/acp_transports` определяет заменяемые transport adapters:
stdio, WebSocket, SSE и fake transports. Пакет отвечает за transport framing и
маппинг transport failures в типизированные transport errors.

`packages/dart/acp_client_core` владеет состоянием клиента: sessions, messages,
connection lifecycle, approvals, cancellation и logs. Пакет принимает
типизированные protocol events и предоставляет состояние для UI.

`packages/dart/acp_testing` предоставляет mock agents, fake transports, fixtures
и protocol conformance tests. Это test-only пакет, он не должен быть production
dependency приложения.

`packages/flutter/acp_ui` предоставляет переиспользуемые Flutter-виджеты для
chat, status, approval prompts, tool call display, errors и connection state.
Пакет должен использовать `fluent_ui` как обязательный UI framework и не должен
напрямую парсить raw ACP JSON.

`apps/codelab_app` собирает Flutter-приложение, dependency injection, routing,
platform-specific transport selection и финальные пользовательские workflows.

### 5.2. Правила зависимостей

- `acp_protocol` зависит только от pure Dart dependencies.
- `acp_transports` может зависеть от `acp_protocol`.
- `acp_client_core` может зависеть от `acp_protocol` и `acp_transports`.
- `acp_ui` может зависеть от `acp_client_core` и `acp_protocol`.
- `codelab_app` может зависеть от всех production packages.
- `fpdart` используется для typed functional primitives в pure Dart слоях.
- `freezed` используется для immutable state, DTO и union/sealed моделей там,
  где это уменьшает boilerplate и повышает типобезопасность.
- Пакеты не должны образовывать cyclic dependencies.
- UI-код не должен проникать в pure Dart packages.

## 6. ACP-контракт

Wire contract ACP определяется официальной документацией в `docs/acp/protocol/`
и схемой в `docs/acp/protocol/17-Schema.md`. Типизированные схемы в
`packages/dart/acp_protocol` должны соответствовать этим документам.

Если в документации ACP и реализации возникает расхождение, приоритет имеет
официальная ACP-документация. Изменение wire contract без обновления
документации и тестов запрещено.

### 6.1. Модель сообщений

CodeLab использует JSON-RPC 2.0:

- request: содержит `id`, `method` и опциональный `params`;
- response: содержит `id`, а также `result` или `error`;
- notification: содержит `method` и опциональный `params`;
- notifications не получают response;
- successful responses содержат `result`;
- error responses содержат `error.code` и `error.message`.

Входящие сообщения должны проходить runtime validation. Invalid messages должны
превращаться в типизированные protocol errors и не должны ронять приложение.
Расширения должны использовать `_meta`; custom methods должны начинаться с `_`.
Нельзя добавлять произвольные custom fields в корень типов, описанных ACP spec.

### 6.2. Lifecycle

```text
connect
  -> initialize
  <- initialize result
  -> authenticate, if required by agent
  -> session/new or session/load
  -> session/prompt
  <- session/update notifications: plan, message chunks, tool calls, tool updates
  <- session/request_permission request, if requested by agent
  -> session/request_permission response
  -> session/cancel notification, if requested by user
  <- session/prompt response with stopReason
```

### 6.3. Официальные методы и notifications

| Direction | Method | Назначение |
| --- | --- | --- |
| client -> agent | `initialize` | Handshake и capability negotiation |
| client -> agent | `authenticate` | Authentication, если требуется agent |
| client -> agent | `session/new` | Создать новую session |
| client -> agent | `session/load` | Загрузить session, если agent поддерживает `loadSession` |
| client -> agent | `session/prompt` | Отправить user message в session |
| client -> agent | `session/cancel` | Notification для отмены текущего prompt turn |
| agent -> client | `session/update` | Notification для plan, message chunks, tool calls, mode/config/session info updates |
| agent -> client | `session/request_permission` | Request authorization у пользователя для tool call |
| agent -> client | `fs/read_text_file` | Прочитать text file, если client capability включена |
| agent -> client | `fs/write_text_file` | Записать text file, если client capability включена |
| agent -> client | `terminal/create` | Создать terminal, если client capability включена |
| agent -> client | `terminal/output` | Получить terminal output |
| agent -> client | `terminal/wait_for_exit` | Дождаться завершения terminal command |
| agent -> client | `terminal/release` | Освободить terminal |
| agent -> client | `terminal/kill` | Остановить terminal command |

Baseline для agent: `session/new`, `session/prompt`, `session/cancel` и
`session/update`. `session/load` доступен только при `agentCapabilities.loadSession`.

### 6.4. Capabilities

Во время `initialize` CodeLab должен отправлять последнюю поддерживаемую major
версию ACP как integer `protocolVersion`, а также `clientCapabilities` и
`clientInfo`.

CodeLab должен учитывать:

- omitted capabilities считаются unsupported;
- prompt content ограничивается `agentCapabilities.promptCapabilities`;
- `session/load` можно вызывать только при `agentCapabilities.loadSession`;
- `fs/read_text_file`, `fs/write_text_file` и `terminal/*` доступны agent
  только если CodeLab явно объявил соответствующие client capabilities;
- custom capabilities объявляются через `_meta`.

## 7. Состояние сессии

Core layer должен явно моделировать состояние session.

```text
idle
  -> connecting
  -> initializing
  -> ready
  -> running
  -> awaitingApproval
  -> running
  -> completed | failed | cancelled | disconnected
```

State updates должны быть идемпотентными. Повторные streamed events не должны
дублировать видимые messages, заново открывать resolved approvals или переводить
completed session обратно в `running`.

Каждая persisted session record должна включать:

- session id;
- connection id или agent identity, если доступны;
- protocol version;
- capabilities;
- текущий status;
- messages и event ids, полученные клиентом;
- pending approval requests;
- last error;
- timestamps для creation, update и completion.

## 8. Approval и политика безопасности

Agent output, tool arguments, file content, web pages, commit messages и logs
считаются недоверенным контентом. CodeLab должен разделять data и instructions
и не должен выполнять действия только потому, что agent output попросил это
сделать.

ACP permission flow выполняется через agent request `session/request_permission`.
Ответ CodeLab должен выбрать один из предоставленных agent вариантов
`PermissionOption` или вернуть outcome `cancelled`, если текущий prompt turn
отменен.

Каждый tool call получает отображаемый risk level на стороне CodeLab:

| Risk | Примеры | Политика по умолчанию |
| --- | --- | --- |
| `readOnly` | file read, code search | может быть auto-approved, только если policy это разрешает |
| `localWrite` | edit local files | требуется explicit approval |
| `network` | HTTP calls, API usage | требуется explicit approval |
| `shell` | command execution | требуется explicit approval |
| `destructive` | delete, reset, force push, migrations | требуется explicit approval с точной command или diff |

UI должен показывать:

- action title;
- `toolCallId`;
- tool kind: `read`, `edit`, `delete`, `move`, `search`, `execute`, `think`,
  `fetch` или `other`;
- точную command, path, URL, diff или target resource, если доступны;
- risk level;
- options, предоставленные agent;
- consequences или irreversible parts, если известны;
- controls для approve и reject.

UI-компоненты не должны обходить approval service.
Auto-approval допускается только как явная user setting и только если выбранная
policy совместима с risk level и предоставленными `PermissionOption`.

## 9. Cancellation

Cancellation — first-class workflow. Когда session находится в `running`, UI
должен предлагать cancellation. Core layer отправляет `session/cancel`
notification через активный transport и затем ожидает response на исходный
`session/prompt`.

Если transport падает или agent не подтверждает cancellation за заданный
timeout, клиент может пометить локальную operation как `cancelled`, записав, что
remote acknowledgement не был получен.

Сразу после отправки `session/cancel` CodeLab должен:

- preemptively mark все non-finished tool calls текущего turn как `cancelled`;
- ответить на все pending `session/request_permission` requests outcome
  `cancelled`;
- продолжать принимать late `session/update` notifications до response на
  исходный `session/prompt`;
- считать успешным подтверждением отмены `session/prompt` response со
  `stopReason: cancelled`.

Cancellation должна быть протестирована для:

- cancellation выполняемого prompt;
- cancellation во время awaiting approval;
- повторных cancellation requests;
- cancellation после disconnect;
- late streamed updates после local cancellation.

## 10. Требования к transport

Все transports реализуют общий interface и предоставляют inbound messages как
stream.

Transport implementations должны поддерживать:

- открытие и закрытие connections;
- отправку typed outbound messages;
- streaming inbound messages;
- маппинг failures в typed errors;
- graceful shutdown;
- test fakes.

Платформенные ожидания:

- desktop может поддерживать stdio и WebSocket transports;
- web должен использовать WebSocket или SSE и не должен зависеть от `dart:io`;
- mobile должен по умолчанию использовать remote transports и не должен
  выполнять shell actions локально.

## 11. Наблюдаемость

CodeLab должен логировать protocol и connection activity в structured form.
Logs должны содержать достаточно context для отладки session без раскрытия
secrets.

Обязательный log context:

- session id;
- connection id, если доступен;
- message id, если доступен;
- protocol version;
- direction: inbound или outbound;
- method или event type;
- status transition;
- error code и category.

Logs должны редактировать:

- API keys;
- tokens;
- passwords;
- private keys;
- sensitive prompts, если debug mode явно не разрешает их логирование.

## 12. Требования к UI

Первый экран приложения — рабочий клиент, а не marketing page.

Flutter UI должен строиться на `fluent_ui`. Использование Material или
Cupertino как базового design framework запрещено. Material/Cupertino imports
допустимы только точечно, если Flutter или third-party package требуют
технический compatibility wrapper, и такой import должен быть изолирован от
публичных UI-компонентов CodeLab.

Виджеты в `packages/flutter/acp_ui` должны храниться по Atomic Design слоям:

```text
lib/
└── src/
    ├── atomics/
    ├── molecules/
    └── organisms/
```

`atomics` содержит минимальные переиспользуемые элементы: buttons, badges,
status indicators, text primitives, icons и progress indicators.

`molecules` содержит составные элементы из нескольких atomics: prompt composer,
tool call summary, connection status row, approval option group.

`organisms` содержит крупные блоки workflow: transcript panel, approval panel,
session sidebar, debug log panel, connection screen.

UI должен поддерживать:

- connection status;
- session list или current session indicator;
- prompt composer;
- streamed transcript;
- assistant messages;
- tool call display;
- pending approval panel;
- cancellation control;
- error и reconnect states;
- доступ к debug/protocol log в debug builds.

Long transcripts должны рендериться эффективно и не должны требовать повторного
парсинга raw ACP JSON в widgets.

## 13. Требования к тестированию

Обязательные unit tests:

- protocol encode/decode round trips;
- unknown field preservation;
- invalid message validation;
- protocol error mapping;
- transport connect/disconnect и framing;
- fake transport behavior;
- session state transitions;
- duplicate streaming event handling;
- approval policy;
- cancellation paths.

Обязательные conformance tests:

- initialize lifecycle;
- session creation;
- prompt streaming;
- permission request and response;
- cancellation;
- version mismatch;
- invalid message recovery.

Обязательные Flutter tests:

- connection states;
- prompt composer behavior;
- streaming transcript rendering;
- approval controls;
- cancellation button visibility;
- error presentation.

## 14. Инструменты и команды

Все Dart и Flutter commands должны выполняться через FVM. Melos является
workspace orchestrator.

Обязательные root files:

- `.fvm/fvm_config.json`;
- `pubspec.yaml`;
- `melos.yaml`;
- `analysis_options.yaml`;
- `.gitignore`;
- `docs/codelab-spec.md`;
- `docs/acp/protocol/01-Overview.md`;
- `docs/acp/protocol/17-Schema.md`;
- `openspec/config.yaml`.

Обязательные Melos scripts:

- `bootstrap`;
- `format`;
- `check-format`;
- `analyze`;
- `test`;
- `protocol-conformance`;
- `check`.

Перед завершением implementation work выполнить:

```bash
fvm dart run melos run check
```

Если protocol behavior изменилось, также выполнить:

```bash
fvm dart run melos run protocol-conformance
```

## 15. Definition of Done

Change считается complete, когда:

- implementation соответствует этой specification и активным OpenSpec changes;
- protocol changes соответствуют `docs/acp/protocol/` и
  `docs/acp/protocol/17-Schema.md`;
- pure Dart packages не импортируют Flutter;
- Flutter UI использует `fluent_ui`, а не Material/Cupertino как базовый
  framework;
- виджеты разложены по `atomics`, `molecules` и `organisms`;
- модели и state используют `freezed`, когда нужна immutable data или union
  state;
- pure Dart слой использует `fpdart` для typed results/options вместо
  неструктурированных nullable/error flows;
- UI не парсит raw ACP JSON;
- для новых inbound messages есть validation;
- approval policy не ослаблена без explicit specification;
- cancellation behavior протестировано;
- disconnect и reconnect states представлены;
- logs редактируют secrets;
- affected tests проходят;
- `fvm dart run melos run check` проходит, когда monorepo bootstrapped.

## 16. MVP-решения

Для первого релиза CodeLab принимает следующие архитектурные решения:

- first-class platform: desktop;
- transports: stdio для local agents и WebSocket для remote agents;
- SSE transport не входит в MVP;
- session state хранится in memory;
- `session/load` используется только если agent объявил
  `agentCapabilities.loadSession`;
- local transcript persistence не входит в MVP;
- Flutter state management: Bloc/Cubit в UI-слое;
- Flutter UI framework: `fluent_ui`;
- Material/Cupertino не используются как базовый design framework;
- UI widgets организуются по слоям `atomics`, `molecules`, `organisms`;
- дополнительные стандартные библиотеки: `fpdart` и `freezed`;
- `acp_client_core` остается pure Dart и не зависит от Bloc, Flutter или UI;
- read-only operations внутри workspace могут auto-approve только после явной
  user setting;
- read-only operations вне workspace или sensitive paths требуют explicit
  approval;
- write, terminal, network и destructive operations всегда требуют explicit
  approval;
- local stdio agents не требуют authentication;
- remote WebSocket agents в MVP допускаются только с configured token/header;
- полноценный ACP `authenticate` workflow выносится за пределы MVP.
