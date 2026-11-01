## Why

Этап 7 (встроенный режим) соединяет клиента (`AcpClientApplication`) и `AcpAgentServer` в одном процессе через тот же ACP-код, что и внешний агент (ADR-0001, `agent-core-architecture` §13.11, `dart-agent-and-clients` §9.12). Для этого нужен продуктовый транспорт в памяти — пара `InProcessAcpTransport`, реализаций существующего порта `AcpTransport`.

Такая пара уже есть, но как тестовая копия: `packages/dart/codelab_acp_testing/lib/src/in_process_acp_link.dart` (change `add-dart-agent-acp-server`, D9). Её используют contract test клиента и агента, агентский драйвер фикстур, тесты `codelab_agent_acp` и `apps/codelab_agent`. `codelab_acp_testing` — только `dev_dependency` (`AGENTS.md` §5), поэтому будущий `codelab_embedded` (change `add-embedded-agent-mode`, задачи 7.3–7.9) взять её не может. D9 того change зафиксировал: окончательная версия переезжает в `codelab_acp_transports` на этапе 7, копия удаляется в том же PR.

Этот change — задачи 7.1–7.2 плана: публичный API `codelab_acp_transports`, правила копирования и закрытия. Встроенный агент, профили хостов и клиентские профили подключения в него не входят.

## What Changes

- **`InProcessAcpLink` и `InProcessAcpTransport` в `codelab_acp_transports`** (`lib/src/in_process_acp_transport.dart`), экспорт из основного web-безопасного бареля `package:codelab_acp_transports/codelab_acp_transports.dart`. Основа — проверенная этапами 4–6 тестовая копия, а не эскиз §13.11 (design.md, D2).
- **Правила доставки и закрытия** закрепляются требованием спецификации. Доставка асинхронная, в порядке `send`, без реентерабельности. Сообщение до `start()` получателя или до первого подписчика его `inbound` буферизуется; после первой подписки сообщения без подписчика выбрасываются. Закрытие одного конца переводит другой в `failed` с кодом `disconnected` и закрывает его `inbound` после уже отправленных сообщений; невыданный буфер выбрасывается с диагностикой `warning`, в которой только число сообщений. Повторный `close()` идемпотентен; `send` вне `connected` даёт `sendFailed`, `start()` после закрытия — `closed` (D4).
- **Правила копирования.** Каждое сообщение копируется как дерево JSON, результат неизменяемый. Этот change дополняет копию тестовой версии двумя правилами, нужными для паритета с проводом:
  - копируется и `error.data` ответа;
  - нечисловые `double` (`NaN`, `±Infinity`) дают `sendFailed`, как `jsonEncode` проводного транспорта.

  Не-JSON значение (`DateTime`, объект домена, ключ `Map` не строкой) и любая другая ошибка копирования дают `sendFailed` на отправляющей стороне с общим текстом без значения. Получатель ничего не получает, соединение живёт (D3).
- **Миграция потребителей (7.2).** Тестовая копия и её тест удаляются из `codelab_acp_testing`. Барель `codelab_acp_testing` её не реэкспортирует. Драйвер `agent_conformance.dart`, тесты `codelab_agent_acp` (contract test, `client_channel`, `server_harness`), тесты `codelab_acp_testing` и `apps/codelab_agent` импортируют пару из `codelab_acp_transports`. Все потребители уже зависят от этого пакета напрямую (D5).
- **Документы.** §13.11 документа ядра ссылается на файл реализации и держит только правила (задача 0.4, D2), план этапа 7 ссылается на §13.11 вместо третьей копии кода. Это сделано при подготовке change, задачи 0.1–0.2. Правится строка §14.9 о тестовой копии и правило тестов во вложенном `AGENTS.md` `codelab_agent_acp`.

## Не входит

- пакет `codelab_embedded`, `createEmbeddedAgent`, профили хостов `embedded-*`, `EmbeddedProfile` и `EmbeddedTransportResolver` в app и CLI, scripted-провайдер для e2e, замер 7.8 и `IsolateAcpLink` — change `add-embedded-agent-mode` (задачи 7.3–7.9);
- проверка формы сообщения на стороне получателя: например, `params` строкой вместо объекта. Это работа кодека `codelab_acp_protocol`, а сообщения строят типизированные кодеки (D3);
- web-компиляция бареля `codelab_acp_transports` в `melos run web-compile`. Web-безопасность проверяют сторож и `web_safe_barrel_test.dart`, сборку для web даст `codelab_embedded` (D6);
- изменения ACP: методов, полей, `_meta` и состояний не добавляется. Порт `AcpTransport`, `AcpTransportState`, `AcpTransportEvent` и `AcpTransportErrorCode` не меняются;
- изменения правил сторожа и allowlist зависимостей (D6).

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-transports`: новое требование «Пара транспортов в памяти». Требование «Web-безопасный публичный барель transport» дополнено: основной барель экспортирует `InProcessAcpLink` и `InProcessAcpTransport`, файл реализации не тянет `dart:io`.
- `acp-golden-fixtures`: в требовании «Агентский драйвер фикстур» агент поднимается на агентском конце продуктового `InProcessAcpLink` из `codelab_acp_transports`, а не тестовой копии.

## Impact

- **Пакеты:**
  - `codelab_acp_transports` — новый `lib/src/in_process_acp_transport.dart`, строка `export` в `lib/codelab_acp_transports.dart`, тест `test/in_process_acp_transport_test.dart`, новая точка входа в `test/web_safe_barrel_test.dart`. `pubspec.yaml` не меняется: нужны только `dart:async`, `dart:collection` и `codelab_acp_protocol`;
  - `codelab_acp_testing` — удаляются `lib/src/in_process_acp_link.dart`, его `export` и `test/in_process_acp_link_test.dart`; `lib/src/fixtures/agent_conformance.dart` импортирует пару из `codelab_acp_transports`;
  - `codelab_agent_acp` — только тесты (`test/support/client_channel.dart`, `test/support/server_harness.dart`, `test/contract/client_application_contract_test.dart`) и `AGENTS.md` §3; `lib/` не меняется;
  - `apps/codelab_agent` — только тесты (`agent_host_test.dart`, `agent_host_config_test.dart`, `agent_host_secrets_test.dart`).
- **Граф зависимостей** не меняется: новых рёбер нет, все потребители уже зависят от `codelab_acp_transports`. Сторож (`rules.dart`) и `pubspec_allowlist_test.dart` прежние. Существующее правило web-безопасности `codelab_acp_transports` покрывает новый файл.
- **Public API** `codelab_acp_transports` — только добавления: `InProcessAcpLink` (фабрика, геттеры `client` и `agent`) и `InProcessAcpTransport` (без публичного конструктора). Параметра `copyMessages` нет, копия делается всегда (design.md, D9). Из публичного API `codelab_acp_testing` пара уходит; потребители вне репозитория отсутствуют.
- **Клиенты** (`codelab_client_*`, `apps/codelab_desktop`, `apps/codelab_cli`) не меняются.
