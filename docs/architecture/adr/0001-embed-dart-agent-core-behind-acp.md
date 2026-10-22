# ADR-0001: Embed a pure-Dart agent core behind ACP for codelab-app and codelab_cli

Status: Proposed

Date: 2026-10-21

## Context

Сейчас CodeLab состоит из двух частей:

* **codelab-agent** — Python ACP-сервер (отдельный репозиторий);
* **ACP Client (codelab-app)** — этот репозиторий, Flutter Desktop клиент для macOS.

Текущее состояние и ограничения:

* модели ACP поддерживаются вручную дважды: Pydantic в агенте и freezed в `packages/dart/acp_protocol`. Из-за этого между своими же проектами есть несовместимости. Пример: агент отправляет статус tool call `cancelled`, которого нет в ACP, а строгий `ToolCallStatus` в `acp_protocol` отбрасывает такое обновление целиком;
* в агенте есть архитектурные дефекты безопасности:
  * проверку разрешений можно обойти, в том числе через MCP;
  * граница рабочей папки проверяется строковым префиксом;
  * `allow_always` запоминается по виду инструмента, а не по инструменту;
  * запрос разрешения приходит без аргументов вызова;
* ядро агента связано с протоколом, поэтому без отдельного ACP-процесса агентом пользоваться нельзя;
* нужен терминальный клиент **codelab_cli**, который работает с агентом по ACP так же, как codelab-app. Python TUI он заменяет;
* нужен запуск агента внутри процесса клиента, в перспективе и на iOS, Android и web;
* вся клиентская логика codelab-app сосредоточена в `CodeLabShellCubit` (`apps/codelab_app/lib/features/workbench/application/shell_cubit.dart`, 2264 строки). Он импортирует `acp_ui`, `fluent_ui` и `flutter_bloc`, поэтому CLI не может её переиспользовать.

Что уже есть:

* модели `acp_protocol` сериализуются в обе стороны (`fromJson`/`toJson`);
* `acp_client_core` и `acp_transports` написаны на чистом Dart;
* интерфейс `AcpTransport` позволяет добавить новый транспорт без изменения `AcpClientApplication`;
* App Sandbox у macOS-сборки выключен (`apps/codelab_app/macos/Runner/Release.entitlements`), поэтому встроенный агент может запускать процессы;
* для встраиваемого ядра агента на чистом Dart спроектирована собственная архитектура: ошибки провайдера как события, отмена `CancelToken`, порт `ExecutionEnv`, чистый цикл с хуками, проверка разрешений первым хуком, JSONL-дерево сессий, сборка ядра по профилям хостов;
* корпуса golden ACP-фикстур нет; есть `packages/dart/acp_protocol/test/protocol_conformance_test.dart` и `packages/dart/acp_testing`;
* в репозитории нет файлов LICENSE и NOTICE.

Затрагиваемые boundaries:

* package boundaries монорепозитория;
* ACP boundary;
* permission/security model;
* state management в `apps/codelab_app`;
* platform integration.

## Decision

0. **Архитектура ядра** — контракты, инварианты, алгоритмы, форматы и способы проверки — полностью описана в [`docs/architecture/proposals/agent-core-architecture.md`](../proposals/agent-core-architecture.md). Это единственный источник для реализации ядра. Сторонний код не копируется; если в коде воспроизводится внешний алгоритм, он получает атрибуцию и запись в `THIRD_PARTY_NOTICES.md` (proposal §7а).
1. Агент переписывается на Dart как **встраиваемое ядро** `codelab_agent_core`:
   * чистый Dart, без `dart:io`, `package:flutter` и ACP;
   * собственный API: `AgentRuntime`, `AgentSession`, sealed `AgentEvent`;
   * всё внешнее — порты хоста: `ExecutionEnv`, `PermissionGate`, `SessionStore`, `SecretStore`, HTTP-клиент, `Logger`.
2. ACP — отдельный адаптер `codelab_agent_acp` поверх ядра:
   * файлы и терминал ACP-клиента реализуют порт `ExecutionEnv` (`AcpClientExecutionEnv`);
   * одобрение через `session/request_permission` реализует порт `PermissionGate`;
   * бинарь агента `apps/codelab_agent` (`codelab-agent serve --stdio | --ws`).
3. `acp_protocol` становится **общим** пакетом для агента и клиентов. Отдельные модели ACP в агенте не заводятся.
4. Два клиента — **codelab-app** (Flutter) и **codelab_cli** (терминал, чистый Dart, команда `codelab`) — равноправные ACP-клиенты:
   * каждый работает с внешним агентом по stdio или WebSocket;
   * или со встроенным агентом через `InProcessAcpTransport` — реализацию `AcpTransport`, которая передаёт объекты `JsonRpcMessage` в памяти без JSON;
   * встроенного агента собирает общий пакет `codelab_embedded`.
5. Клиенты **не используют прямой API ядра**:
   * возможности сверх ACP передаются расширениями протокола (`_meta`, методы `_codelab/*`, см. `docs/acp/protocol/15-Extensibility.md`). Так они работают и со встроенным, и с удалённым агентом. Каждое расширение вводится через OpenSpec change (`AGENTS.md` §3.4);
   * прямой API остаётся для тестов ядра, ACP-адаптера и сторонних Dart-приложений;
   * в `acp_client_kit` резервируется внутренний порт `AgentBackend`, чтобы прямой путь можно было добавить без изменения UI.
6. Клиентская логика выносится из `CodeLabShellCubit` в пакеты на чистом Dart:
   * `acp_client_kit` — проекция транскрипта, очередь промптов, сессии, команды, профили подключения;
   * `acp_client_io` — адаптеры fs, terminal и хранилищ из `apps/codelab_app/lib/core/platform/`.

   Cubit-ы app и REPL CLI только отображают состояние.
7. Разрешения проверяет **агент**:
   * approval — первый хук `beforeToolCall` для любого инструмента, включая MCP и плагины; `AcpPermissionGate` — его UI-часть через `session/request_permission`;
   * `allow_always` хранится по инструменту и шаблону аргументов;
   * граница рабочей папки — декоратор `BoundedEnv` с нормализацией пути;
   * агент (встроенный и внешний) запрашивает одобрение через `session/request_permission` перед записью файлов и перед командами.

   Модель разрешений клиента не меняется (`AGENTS.md` §10): для `fs/*` и `terminal/*` клиент не вводит собственного одобрения и только ограничивает пути рабочей папкой.
8. **Эталон поведения** — спецификация ACP, корпус golden ACP-фикстур (общий для агента и клиентов) и интеграционные тесты codelab-app и codelab_cli. Дифференциальный паритет с Python-агентом не требуется.
9. **Цели** — каталог целевых возможностей в охвате «ядро + CLI и десктоп» с приоритетами, этапами и сценариями приёмки: [`docs/architecture/proposals/agent-parity-goals.md`](../proposals/agent-parity-goals.md), включая блок «не регрессировать» для функций текущего CodeLab.
10. Наработки Python-агента — **второй источник решений** (proposal §7б): берутся по необходимости, только при условиях из §7б. Он работает параллельно, пока не закрыты цели уровня Must, затем удаляется вместе с Python TUI.
11. **Конфигурация агента — YAML** (`config.yaml`, строгий профиль YAML 1.2; разбор и запись — в `codelab_agent_io`, agent-core-architecture §15). Устаревший `codelab.toml` Python-агента читается только для чтения, пока нет YAML-конфига, и переводится командой `codelab config migrate`; чтение удаляется отдельным OpenSpec change после этапа 9 (agent-core-architecture §15.7).

Новые пакеты и направления зависимостей:

```text
codelab_agent_core      → (только чистый Dart)
codelab_agent_io        → codelab_agent_core, dart:io
codelab_agent_mcp       → codelab_agent_core
codelab_agent_acp       → codelab_agent_core, acp_protocol, acp_transports
acp_client_kit          → acp_client_core
acp_client_io           → acp_client_core, acp_client_kit, dart:io
codelab_embedded        → codelab_agent_acp, codelab_agent_io, codelab_agent_mcp, acp_transports
codelab_setup           → codelab_agent_core (io.dart — codelab_agent_io, dart:io)
apps/codelab_app        → acp_client_kit, acp_client_io, acp_ui, codelab_embedded, codelab_setup
apps/codelab_cli        → acp_client_kit, acp_client_io, codelab_embedded, codelab_setup
apps/codelab_agent      → codelab_agent_acp, codelab_agent_io, codelab_agent_mcp
```

Запрещено:

* клиентам импортировать агентские пакеты напрямую — только через `codelab_embedded` и `codelab_setup` (общая логика настройки агента для обоих клиентов: мастер провайдера, модели представления настроек, реэкспорт чистых типов конфига и секретов ядра; dart-agent-and-clients §4.1);
* `acp_client_kit` импортировать Flutter или `dart:io`;
* `codelab_agent_core` импортировать `dart:io`, Flutter или `acp_protocol`.

Подробный design: [`docs/architecture/proposals/dart-agent-and-clients.md`](../proposals/dart-agent-and-clients.md).

---

## Alternatives

### Alternative 1 — Взять готовое стороннее ядро агента как зависимость или форк

Подключить существующую open-source библиотеку агента и добавить к ней ACP-адаптер.

Почему не выбран:

* зависимость от чужого, быстро меняющегося кода или сотни тысяч строк чужого кода на сопровождении;
* такие ядра не рассчитаны на ACP: у них собственный внешний протокол и обычно одна сессия на процесс;
* модель разрешений и безопасности пришлось бы переделывать внутри чужого кода.

Выбрано вместо этого: собственное ядро по архитектуре из `agent-core-architecture.md` (Decision 0).

### Alternative 2 — ACP как внутренний API ядра

Ядро говорит только ACP-моделями, а встроенный режим — это loopback.

Почему не выбран:

* протокол становится внутренним контрактом ядра;
* хосты без ACP платят за протокол;
* событий ACP меньше, чем нужно ядру.

### Alternative 3 — Прямой API ядра в клиентах

Клиенты работают со своим ядром через `AgentEvent`, а с остальными агентами — через ACP.

Почему не выбран:

* в каждом клиенте два пути кода;
* возможности прямого API пропадают, когда агент внешний;
* codelab-app и codelab_cli быстрее расходятся.

### Alternative 4 — Отдельная клиентская логика в codelab_cli

Написать CLI без выделения `acp_client_kit`.

Почему не выбран:

* логика транскрипта, очереди, команд и переподключения дублируется и расходится между клиентами.

### Alternative 5 — Доработать Python-агента без смены языка

Почему не выбран:

* не даёт встраивания в клиентский процесс, мобильные и web;
* не устраняет двойные модели ACP.

### Alternative 6 — Переписать Python-агента на Dart 1:1 с дифференциальным паритетом

Одни сценарии на обоих агентах, сравнение ACP-транскриптов.

Почему не выбран:

* переносит в новое ядро архитектуру и дефекты Python-агента;
* эталоном становится реализация, а не спецификация ACP.

### Alternative 7 — Проектировать ядро по ходу реализации, без полной спецификации

Писать код этапами и уточнять архитектуру по мере появления проблем.

Почему не выбран:

* ключевые инварианты (ошибки провайдера как события, парность tool calls, проверка разрешений первым хуком, дерево сессий, продолжение прерванного хода) трудно добавить задним числом: их нарушение расползается по всему коду;
* без спецификации нельзя распараллелить работу и проверить её тестами приёмки.

---

## Consequences

### Positive

* одна копия моделей ACP для агента и клиентов: несовместимости ловятся компилятором и общими тестами;
* contract test агент ↔ клиенты в одном CI;
* встроенный режим без отдельного процесса в обоих клиентах;
* одинаковое поведение со встроенным, внешним и сторонним агентом;
* дефекты безопасности агента исключены устройством точки исполнения и `BoundedEnv`;
* `acp_client_kit` тестируется без Flutter.

### Negative

* на время миграции два агента;
* переписываются LLM-провайдеры, MCP-клиент и сжатие контекста;
* теряется прямая интеграция LiteLLM; заменяется LiteLLM Proxy как OpenAI-совместимым `baseUrl`;
* в Dart нет зрелых tree-sitter и токенайзеров, поэтому Context Manager откладывается;
* рефакторинг `CodeLabShellCubit` до начала разработки CLI;
* корпус golden ACP-фикстур нужно написать с нуля;
* дисциплина атрибуции: проверка лицензий и `THIRD_PARTY_NOTICES.md` для воспроизведённых алгоритмов;
* до удаления читателя `codelab.toml` агент поддерживает два входных формата конфига (YAML и устаревший TOML только для чтения) и зависимость `package:toml`.

* после принятия ADR нужно обновить:
  * `AGENTS.md` — §5 структура monorepo уже устарела: указаны `core/` и `ui_kit/` вместо `acp_client_core` и `acp_ui`;
  * `docs/architecture/technology-stack.md`;
  * `docs/architecture/layers-and-dependencies.md`;
  * `docs/architecture/state-management.md`.

  Название проекта «ACP Client» расширяется до монорепо агента и клиентов.

### Risks

* объём работ недооценён. Снижение: работа разбита на ступени с проверяемыми критериями выхода ([дорожная карта](../proposals/delivery-roadmap.md)): PoC — срез P0 за 2–3 недели; первый полезный результат — первая рабочая версия Dart-агента и CLI (этапы 4 и 6 плана); MVP — все Must-строки матрицы целей зелёные и переключение по умолчанию (этап 9), без публичного релиза;
* выделение `acp_client_kit` ломает поведение app. Снижение: чистый рефакторинг под защитой 8 интеграционных тестов;
* «чистота» ядра и kit нарушится ради удобства. Снижение: тест-сторож импортов и сборка ядра под web в CI;
* перенос лишней сложности (супервизоры, большое число возможностей профиля, структурное сжатие) раньше, чем она нужна. Снижение: в MVP — только подсистемы с пометкой MVP (proposal §4.0);
* фикстуры закрепляют неверное прочтение спецификации ACP. Снижение: ссылка на раздел спецификации в каждой фикстуре, ручная проверка с Zed;
* функция текущего CodeLab потеряется. Снижение: блок «не регрессировать» в целях паритета.

---

## Migration

ADR принимается (Status: Accepted) **до начала этапа 0**: по `docs/architecture/adr/README.md` §8 реализация начинается только после принятого решения. Порядок ступеней и вех — в [дорожной карте](../proposals/delivery-roadmap.md).

1. **Этап 0.**
   * Melos-монорепо расширяется только пакетами `codelab_agent_core` (нужен сторожу и web-сборке) и `codelab_architecture_tests`; остальные пакеты создаются на этапе, где в них появляется код.
   * Появляется CI, которого сейчас нет.
   * Тест-сторож импортов.
   * Корпус golden ACP-фикстур (`packages/dart/acp_testing/fixtures/acp/`) и первые фикстуры по спецификации.
   * Лицензия репозитория — MIT (`LICENSE` в корне) и `THIRD_PARTY_NOTICES.md`.
   * `AGENTS.md`: правила агентских пакетов и TDD (задача 0.11) — раздел §5 корневого `AGENTS.md` и вложенные `AGENTS.md` в `packages/dart/codelab_agent_*`; окончательно дописывается в задаче 9.7.
2. **Этапы 1–4** (агентская ветка; до их полного объёма допускается срез P0 — PoC по stdio без этапа 3): LLM-слой и scripted `StreamFunction` на Dart (задача 1.4), цикл и инструменты, сессии и сжатие, ACP-адаптер и `codelab-agent`. После этапа 4 codelab-app без изменений работает с Dart-агентом по stdio.
3. **Этапы 5–6** (клиентская ветка, параллельно):
   * выделение `acp_client_kit` и `acp_client_io`;
   * первая версия `codelab_cli`, которая работает с Python-агентом.
4. **Этап 8** (после этапа 4). MCP, единая конфигурация (`config.yaml`; `codelab.toml` — только чтение до `codelab config migrate`), хранилище секретов, `AGENTS.md`.
5. **Этап 7** (после этапов 6 и 8: нужны загрузка конфига и хранилище секретов). `codelab_embedded` и `InProcessAcpLink` в обоих клиентах.
6. **Этап 9 (MVP).** Цели уровня Must закрыты:
   * профиль по умолчанию в обоих клиентах — Dart-агент;
   * Python-агент и Python TUI замораживаются, затем удаляются;
   * сохранённые сессии Python-агента не переносятся (agent-core-architecture §16.1);
   * публичный релиз (задача 9.4) в MVP не входит — он открывает продукт 1.0.
7. **Этап 10.** Сборки для iOS, Android и web.

Совместимость: на протяжении миграции оба клиента работают с Python-агентом. Откат: профиль
подключения по умолчанию возвращается на Python-агента.

---

## Validation

* тест-сторож импортов для `codelab_agent_core` и `acp_client_kit`; сборка ядра `dart compile js` в CI;
* conformance Dart-агента и проверка обоих клиентов на общем корпусе golden ACP-фикстур. Драйвер — режим `codelab test-scenario` в codelab_cli;
* у каждой цели уровня Must в `agent-parity-goals.md` есть доказательство: id фикстуры и/или тест клиента;
* применимые из 8 интеграционных тестов codelab-app проходят во внешнем и встроенном режимах (таблица применимости — dart-agent-and-clients §9.9, §9.12);
* тест: ни один инструмент не исполняется в обход проверки разрешений, включая MCP;
* тест: `/proj_evil` не проходит при `cwd=/proj`;
* ручная проверка с Zed на этапе 9 по чек-листу задачи 9.8 (11 шагов, правило «прошёл / не прошёл», ACP-трасса как доказательство).

---

## Related

### Architecture

* `docs/architecture/proposals/dart-agent-and-clients.md` — подробный design
* `docs/architecture/proposals/agent-core-architecture.md` — архитектура ядра агента
* `docs/architecture/proposals/agent-parity-goals.md` — цели паритета
* [`docs/architecture/proposals/delivery-roadmap.md`](../proposals/delivery-roadmap.md) — дорожная карта PoC → MVP → продукт
* `docs/architecture/acp-boundary.md`
* `docs/architecture/layers-and-dependencies.md`
* `docs/architecture/permissions.md`
* `docs/architecture/state-management.md`
* `docs/architecture/platform-integration.md`
* `docs/architecture/testing.md`

### OpenSpec

* будет создан после принятия ADR: change на выделение `acp_client_kit` (этап 5) и change на `codelab_cli` (этап 6)

### ADR

* codelab-agent: ADR-005 (ACP-независимое ядро), ADR-008 (журнал и проекции), ADR-009 (граница авторизации) — их цели реализуются в новом ядре

### Code

* `packages/dart/acp_protocol`
* `packages/dart/acp_transports/lib/src/acp_transport.dart`
* `packages/dart/acp_client_core`
* `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart`
* `apps/codelab_app/lib/core/platform/`
