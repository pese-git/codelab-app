Задачи идут парами «тест → реализация» (dart-agent-and-clients §9.0, правило 3; `packages/dart/codelab_agent_core/AGENTS.md` §2). В скобках — требование или сценарий спецификации этого change и решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[protocol]` — `codelab_acp_transports`, `codelab_acp_testing`, `codelab_agent_acp` (только тесты и `AGENTS.md`);
- `[agent]` — тесты `apps/codelab_agent`;
- `[docs]` — `docs/architecture/**`.

Задач `[client]` и `[desktop]` нет: `codelab_client_*`, `apps/codelab_cli` и `apps/codelab_desktop` не меняются (proposal, «Impact»).

Итерации:
- итерация 0 — группа 0: документы;
- итерация 1 — группы 1–2, **один PR** (design.md, D5): транспорт в `codelab_acp_transports`, удаление тестовой копии и перевод потребителей. После экспорта пары из бареля транспортов `agent_conformance.dart` и `fixture_replay_agent_test.dart` не компилируются, пока копия не удалена, поэтому группы 1 и 2 не разделяются на PR;
- итерация 2 — группа 3: документы и Definition of Done.

Копия делается всегда, без `copyMessages` (D9), буфер держится до первого подписчика (D4, п. 2) — решение пользователя 2026-11-01.

Проверки каждой задачи — по `AGENTS.md` §21, только для затронутого:
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` затронутых пакетов;
- `fvm dart test` затронутых пакетов;
- `fvm dart run melos run guard` — меняются импорты.

Полный `melos run check` — в CI pull request. `test:e2e:app:*` не запускаются (`AGENTS.md` §21).

## 0. Документы (итерация 0)

- [x] 0.1 `[docs]` `agent-core/13-acp-adapter.md` §13.11 — эскиз приведён к D2–D4: доставка и выдача буфера через микрозадачу, буфер до первого подписчика, `inbound` второго конца закрывается при закрытии первого, диагностика — только при открытом `events`, копия `error.data`, отказ на нечисловом `double`. Правила под эскизом дополнены. **Сделано при подготовке change (2026-11-01).**
- [x] 0.2 `[docs]` `dart-agent-and-clients/09-12-stage-7-embedded.md` — задача 7.1 и артефакт «`InProcessAcpLink`» ссылаются на §13.11 вместо третьей копии кода. Список тестов транспорта дополнен случаями D3–D4 (design.md, D2). **Сделано при подготовке change (2026-11-01).**
- [x] 0.3 `[docs]` Решения D9 и D4, п. 2 (решение пользователя 2026-11-01) отражены в §13.11. Из эскиза и правил убраны `copyMessages` и пометка OQ1. Буфер до первого подписчика записан как правило. В `09-12-stage-7-embedded.md` (7.8) отмечено, что сравнение без копии вводит change `add-embedded-agent-mode`. В `10-risks.md` и §13.16 убрано «по умолчанию». **Сделано 2026-11-01.**
- [x] 0.4 `[docs]` По ревью итерации 1 (решение пользователя 2026-11-01; D2): код эскиза из `agent-core/13-acp-adapter.md` §13.11 заменён ссылкой на `packages/dart/codelab_acp_transports/lib/src/in_process_acp_transport.dart`, четвёртой копии кода больше нет. Правила §13.11 обновлены по D3, пп. 5–6 (любая ошибка копирования — `sendFailed` с общим текстом), D4, пп. 2, 5–7 (буфер до первого подписчика, выброс буфера с диагностикой числа при закрытии второго конца, доставка на закрытый конец без диагностики) и риску неизменяемой копии. §13.16 сверен, добавлен пункт о тесте пары. В `09-12-stage-7-embedded.md` «эскиз кода» заменён ссылкой на файл, список тестов транспорта дополнен. **Сделано 2026-11-01.**

## 1. Транспорт в памяти в `codelab_acp_transports` (итерация 1)

- [x] 1.1 `[protocol]` Тест `packages/dart/codelab_acp_transports/test/in_process_acp_transport_test.dart`, только через основной барель (agent-transports «Пара транспортов в памяти», все сценарии; D3, D4). Случаи переносятся из `codelab_acp_testing/test/in_process_acp_link_test.dart` поимённо:
  - «delivers asynchronously in send order»;
  - «the peer gets a deep copy of the JSON tree»;
  - «a non-JSON value is sendFailed, as on the wire»;
  - «a message before start() of the receiver is buffered»;
  - «send before start() is sendFailed»;
  - «closing one end fails the other with disconnected»;
  - «after the peer closed, send is sendFailed».

  Новые случаи — по сценариям:
  - порядок 1000 сообщений;
  - доставка не реентерабельна;
  - сообщение до первого подписчика (D4, п. 2);
  - копия `error.data`;
  - `DateTime`: текст исключения без значения, `client.state` остаётся `connected`, следующий `send` доставлен;
  - ключ не строкой, `NaN`, `±Infinity`;
  - `send` после своего `close()`;
  - сообщения до `close()` — до done у второго конца;
  - повторный `close()`: ровно одно `failure` у второго конца;
  - последовательность `stateChanged`;
  - `close()` конца в `failed`, затем `start()` → `closed`;
  - доставка на закрытый конец без исключения у отправителя.

  Красный: барель не экспортирует `InProcessAcpLink`.
- [x] 1.2 `[protocol]` Тест `packages/dart/codelab_acp_transports/test/web_safe_barrel_test.dart`: третья точка входа `lib/src/in_process_acp_transport.dart` в цикле «does not reach dart:io» и проверка, что `InProcessAcpLink` и `InProcessAcpTransport` доступны из основного бареля (agent-transports «Web-безопасный публичный барель transport», сценарии «Основной барель не тянет dart:io» и «Пара в памяти доступна из основного бареля»; D6). Красный: файла нет.
- [x] 1.3 `[protocol]` Реализовать `packages/dart/codelab_acp_transports/lib/src/in_process_acp_transport.dart`:
  - основа — код тестовой копии (D2), плюс копия `error.data` и отказ на нечисловом `num` (D3), буфер до первого подписчика через `onListen` (D4, п. 2);
  - фабрика `InProcessAcpLink()` без параметров (D9);
  - приватный конструктор конца (D7);
  - импорты только `dart:async`, `dart:collection` (`Queue` буфера; web-безопасен, сторож его не запрещает) и `codelab_acp_protocol`;
  - doc-комментарии по-русски «почему / для чего / как» со ссылками на §13.11 и D3–D4.

  Добавить `export 'src/in_process_acp_transport.dart';` в `lib/codelab_acp_transports.dart` и обновить doc-комментарий бареля (`AGENTS.md` §15: комментарий меняется вместе с кодом). В doc-комментарии `AcpTransport` «пара в памяти тестов» заменить на `InProcessAcpLink`. 1.1 и 1.2 зелёные; `fvm dart analyze packages/dart/codelab_acp_transports`. Сразу за этой задачей — группа 2: до неё `codelab_acp_testing` не компилируется (D5).

## 2. Миграция потребителей (итерация 1, тот же PR)

Рефакторинг под защитой существующих тестов (D8): новых красных тестов нет, перечисленные прогоны зелёные до и после.

- [x] 2.1 `[protocol]` `codelab_acp_testing` (acp-golden-fixtures «Агентский драйвер фикстур», сценарий «Пара транспортов из codelab_acp_transports»; D5):
  - удалить `lib/src/in_process_acp_link.dart`, строку `export 'src/in_process_acp_link.dart';` в `lib/codelab_acp_testing.dart` и `test/in_process_acp_link_test.dart` (случаи перенесены в 1.1);
  - в `lib/src/fixtures/agent_conformance.dart` убрать `import '../in_process_acp_link.dart';`: пара приходит через уже импортированный барель `codelab_acp_transports`;
  - в `test/agent_conformance_test.dart` добавить импорт бареля транспортов (`fixture_replay_agent_test.dart` его уже импортирует);
  - doc-комментарии `fixture_replay_agent.dart` и `agent_conformance.dart` упоминают `InProcessAcpLink` без пакета — проверить и, где сказано «тестовая копия», исправить.

  Проверка: `fvm dart test packages/dart/codelab_acp_testing`; `grep -rn "class InProcessAcp" packages/dart/codelab_acp_testing/lib` пуст.
- [x] 2.2 `[protocol]` `codelab_agent_acp`, только тесты: `import 'package:codelab_acp_transports/codelab_acp_transports.dart';` в `test/support/client_channel.dart`, `test/support/server_harness.dart`, `test/contract/client_application_contract_test.dart`. Doc-комментарий contract test — «продуктовый `InProcessAcpLink` (`codelab_acp_transports`)». Проверка: `fvm dart test packages/dart/codelab_agent_acp`, включая `test/conformance_test.dart` (`melos run conformance:agent`).
- [x] 2.3 `[agent]` `apps/codelab_agent`, только тесты: импорт бареля транспортов в `test/agent_host_test.dart`, `test/agent_host_config_test.dart`, `test/agent_host_secrets_test.dart`. Проверка: `fvm dart test apps/codelab_agent`.
- [x] 2.4 `[protocol]` `packages/dart/codelab_agent_acp/AGENTS.md` §3: «пара транспортов в памяти `InProcessAcpLink` из `codelab_acp_transports`» вместо «из `codelab_acp_testing`» (D5).
- [x] 2.6 `[protocol]` Исправления по ревью итерации 1 (решения пользователя 2026-11-01), пары «тест → код» в `codelab_acp_transports`:
  - тест: сценарии «После отписки сообщения не буферизуются» и «Поздний подписчик при живом подписчике» (D4, п. 2) → код: признак «подписчик уже был» (`_hadListener`, ставится в `onListen`); на запущенном конце без подписчика после первой подписки сообщение выбрасывается;
  - тест: сценарий «Невыданный буфер при закрытии второго конца» в обоих вариантах — запущен без подписчика и `idle` (D4, п. 6) → код: в `_onPeerClosed` после выдачи остаток буфера считается и выбрасывается, при ненулевом числе одна `diagnostic(warning, source: in_process)` с числом и без содержимого до `failure(disconnected)`;
  - тест: сценарий «Доставка на закрытый конец» — нет `diagnostic` у закрытого получателя (D4, п. 7) → код: `_deliver` на закрытом конце выбрасывает сообщение без события;
  - тест: сценарий «Ошибка итератора при копировании» (`Map` с бросающим `entries`; текст исключения совпадает со случаем `DateTime`, `cause == null`) (D3, пп. 5–6) → код: `send` перехватывает любой брошенный объект при копировании (`on Object`, с `// ignore:` и причиной по-русски, если сработает `avoid_catching_errors`) и бросает `sendFailed` с общим текстом без `e.message`;
  - находки ревью по тестам 1.1: каждый сценарий требования «Пара транспортов в памяти» покрыт тестом с именем, по которому сценарий находится; doc-комментарии конца и `_deliver`/`_onPeerClosed` обновлены вместе с кодом (`AGENTS.md` §15).

  Проверка: `fvm dart test packages/dart/codelab_acp_transports`; `fvm dart analyze packages/dart/codelab_acp_transports`; затем прогоны группы 2 (`codelab_acp_testing`, `codelab_agent_acp` с `conformance:agent`, `apps/codelab_agent`) зелёные — новая семантика выброса не должна задеть обвязки.
- [x] 2.7 `[protocol]` Поиск мутаций полученного JSON (design.md, Risks «Неизменяемая копия против изменяемого `Map` на проводе»): в `lib/` пакетов `codelab_acp_protocol`, `codelab_client_acp`, `codelab_client_core`, `codelab_agent_acp` найти правку на месте `Map`/`List`, пришедших из `JsonRpcMessage` (`params`, `result`, `error.data`): `remove`, `[]=`, `addAll`, `clear`, `sort`, `removeWhere`, `putIfAbsent` и т. п. по значениям из декодеров. Результат — список мест в отчёте задачи. Найденное место — пара «красный тест через `InProcessAcpLink` → копия перед правкой»; правка в `codelab_client_*` выполняется исполнителем `[client]` по этому списку. Если мест нет — отметить в отчёте, кода нет.
- [x] 2.5 `[protocol]` Сторож и анализ: `fvm dart run melos run guard`; `fvm dart analyze` для `codelab_acp_transports`, `codelab_acp_testing`, `codelab_agent_acp`, `apps/codelab_agent`; `grep -rn "in_process_acp_link" packages apps` пуст (кроме `build/` и `.dart_tool/`).

## 3. Документы и Definition of Done (итерация 2)

- [x] 3.1 `[docs]` `agent-core/14-golden-fixtures.md` §14.9, шаг 4 алгоритма: убрать «на этапе 4 — тестовая копия из contract test…», указать `InProcessAcpLink` из `codelab_acp_transports`. Исторические абзацы этапа 4 (`09-09-stage-4-acp-adapter.md`, 4.7–4.8) не меняются.
- [x] 3.2 `[docs]` `dart-agent-and-clients/09-12-stage-7-embedded.md`: пометить 7.1–7.2 выполненными change `add-in-process-acp-transport`; DoD этапа — первый пункт (`in_process_acp_transport_test.dart`) выполнен.
- [x] 3.3 `[docs]` Проверить относительные ссылки изменённых документов (`docs/architecture/**`) — все цели существуют.
- [x] 3.4 Definition of Done (проверено 2026-11-01 на `develop` @ `eb713bc` после PR #209: тесты пары 31, `codelab_acp_testing` 268, `codelab_agent_acp` 198 (~3), `apps/codelab_agent` 193, `conformance:agent` 55, guard 68 — зелёные; в итерации 2 Dart-файлы не менялись; полный CI PR #209 зелёный):
  - `fvm dart test packages/dart/codelab_acp_transports/test/in_process_acp_transport_test.dart` и `web_safe_barrel_test.dart` зелёные;
  - `fvm dart test` для `codelab_acp_testing`, `codelab_agent_acp` (с `conformance:agent`) и `apps/codelab_agent` зелёный;
  - `fvm dart run melos run guard` зелёный;
  - `fvm dart format --set-exit-if-changed` по изменённым файлам;
  - `openspec validate add-in-process-acp-transport --strict` проходит;
  - определение пары в репозитории одно: `grep -rn "final class InProcessAcpLink" packages apps` находит только `codelab_acp_transports/lib/src/in_process_acp_transport.dart`.
