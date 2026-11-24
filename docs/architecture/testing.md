# Стратегия тестирования в CodeLab

Документ задаёт стратегию тестирования CodeLab — клиентов (desktop, CLI), встроенного Dart-агента и общих пакетов — и правила выбора уровня теста.

Цели:

* проверять корректность на минимально необходимом уровне;
* держать основную логику ACP и приложения тестируемой без Flutter;
* использовать `codelab_acp_testing` как переиспользуемую тестовую инфраструктуру;
* избегать чрезмерно тяжёлых интеграционных тестов;
* покрывать жизненный цикл, потоки, переподключение и гонки разрешений;
* дать AI coding agents и CI предсказуемую стратегию проверки.

Общие правила — корневой `AGENTS.md` (§2, §5, §9, §12, §17, §19, §20, §21), [`layers-and-dependencies.md`](layers-and-dependencies.md), [`acp-boundary.md`](acp-boundary.md), [`session-lifecycle.md`](session-lifecycle.md), [`streaming.md`](streaming.md), [`concurrency.md`](concurrency.md), [`permissions.md`](permissions.md), [`state-management.md`](state-management.md), [`platform-integration.md`](platform-integration.md), [`error-handling.md`](error-handling.md), [`observability.md`](observability.md). TDD ядра агента — `packages/dart/codelab_agent_core/AGENTS.md` §2 и [план миграции §9.0](proposals/dart-agent-and-clients/09-00-migration-plan.md); формат golden-фикстур ACP — [`proposals/agent-core/14-golden-fixtures.md`](proposals/agent-core/14-golden-fixtures.md).

Термины:

* **Уровень теста** — ступень пирамиды: протокол, транспорт, ядро клиента, Cubit, виджет, интеграция (§1, §90).
* **Модульный тест** (unit test) — тест одной единицы логики без реальной сети, процессов и файловой системы пользователя (§3, §51, §52).
* **Виджет-тест** (widget test) — тест виджетов через `testWidgets` из `flutter_test`, без настоящего окна (§28).
* **Интеграционный тест** (integration test) — тест нескольких реальных слоёв вместе: на Dart VM — тесты пакетов с реальными процессами и сокетами, на устройстве — `apps/codelab_desktop/integration_test/` (§5, §32, §36).
* **e2e** — приёмочный тест исполняемого файла целиком: PTY-e2e CLI (`test:e2e:cli:*`) и тесты app на macOS (`test:e2e:app:*`) (§36, §74).
* **Golden-фикстура ACP** — JSON-сценарий обмена кадрами между клиентом и агентом; корпус проверяет обе стороны протокола (§12).
* **Conformance** — прогон корпуса golden-фикстур против стороны протокола (§12, §74).
* **Двойник** (test double) — подмена зависимости в тесте: fake — упрощённая работающая реализация со своим состоянием, mock — запись и проверка вызовов (§64, §65).
* **Поддельные часы** (fake clock) — источник времени, который двигает тест (§54, §55).
* **Флейк** (flaky test) — тест, который на одном и том же коде то проходит, то падает (§61).
* **Сторож** — тестовый пакет `codelab_architecture_tests` (`melos run guard`), проверяющий границы пакетов (§71).
* **Затронутое** (affected) — изменённые пакеты и все пакеты, которые от них зависят; объём проверки pull request (§74, §75).
* **Полный прогон** — все шаги `melos run check`; в CI — все джобы (§74, §76).
* **Доказательство строки Must** — фикстура или тест, которые закрывают строку Must матрицы целей агента (§74.1).

Где в коде. Скрипты проверок — секция `melos:` корневого `pubspec.yaml`. `check` выполняет шаги `check-format`, `analyze`, `guard`, `prompts:check`, `l10n:check`, `test`, `test:e2e:cli:dart-agent`, `test:e2e:cli:embedded`, `protocol-conformance`, `conformance:client`, `conformance:agent`, `conformance:embedded`, `web-compile`. Вне `check`: `format`, `analyze:packages` (анализ по пакетам для суженного CI), `test:dart` (Dart-пакеты через `fvm dart test`), `test:e2e:cli` (CLI против scripted stdio-агента; эти тесты входят и в `test`), `test:e2e:cli:python-agent` (только локально), `build:agent`, `build:cli` и `test:e2e:app:*` — тесты app на macOS, только в `release/*`: по одному файлу (`stdio`, `permission`, `fs`, `open-project`, `terminal`, `plan-checklist`, `prompt-queue`, `multi-session`, `command-palette`, `transcript-rendering`, `language`, `appearance`, `onboarding`, `legal`, `usage` — два файла) и все файлы — `test:e2e:app:dart-agent` и `test:e2e:app:embedded`. Тесты каждого пакета и приложения — в его `test/`; двойники и обвязка — в `test/support/` (например, `FakeClientWorkspace`, `FakeSessionHandle` и `CodeLabTestBinding` в `apps/codelab_desktop/test/support/`). Интеграционные тесты desktop — `apps/codelab_desktop/integration_test/` (`*_flow_test.dart`, общая настройка `flutter_test_config.dart`, обвязка `support/`, сценарии модели `llm_scripts/`); `apps/codelab_desktop/test_driver/app.dart` — точка входа с расширением `flutter_driver` для управления запущенным app, тестов в ней нет. PTY-e2e CLI — `apps/codelab_cli/test/e2e/` (псевдотерминал `support/pty_process.dart`, выбор агента `support/e2e_agent.dart`, теги `scripted-only` и `python-agent` в `apps/codelab_cli/dart_test.yaml`). Общая ACP-инфраструктура — `packages/dart/codelab_acp_testing`: `FakeAcpTransport`, `FakeTerminalProcessRunner`, скриптовый stdio-агент (`writeCodelabCompatibleStdioAgent`), корпус golden-фикстур `fixtures/acp/` со схемой `_schema.json`, драйверы `runClientFixture`, `runAgentFixture`, `runAgentFixtureOver` и агент-повторитель `FixtureReplayAgent`. Тестовые барели агентской стороны: `package:codelab_agent_core/testing.dart` (`FakeClock`, `ScriptedStreamFunction`, `RecordingLogger`, `SequentialIdGenerator`), `package:codelab_agent_io/testing.dart` (сценарий модели), `package:codelab_agent_mcp/testing.dart` (поддельный MCP-сервер `FakeMcpServer`) и `package:codelab_embedded/testing.dart` (сценарный открыватель встроенного агента). Библиотек моков (`mockito`, `mocktail`) и `bloc_test` в репозитории нет: двойники пишутся вручную, часть — на базе `Fake` из `package:test`. Сторож — `packages/dart/codelab_architecture_tests` (`melos run guard`; правила импорта `test/support/rules.dart`, allowlist-ы `test/pubspec_allowlist_test.dart`). CI — `.github/workflows/ci.yml`: джобы `scope`, `checks` (матрица по джобам `format`, `analyze`, `test`, `conformance`, `guard`, `l10n`, `web-compile`, `e2e-cli-dart`, `e2e-cli-embedded`), `site`, `parity` и итоговый `ci`; матрицу считает `tool/ci/affected.dart`, логика выбора затронутого — `tool/ci/ci_scope.dart` (§74).

---

## 1. Основной принцип

Тест ДОЛЖЕН находиться на минимально необходимом уровне.

Предпочтительная пирамида:

```text
                Интеграционные / e2e
                         ▲
                         │
                   Виджет-тесты
                         ▲
                         │
                  Тесты BLoC/Cubit
                         ▲
                         │
          Тесты приложения / ядра клиента
                         ▲
                         │
     Протокольные / модульные тесты на чистом Dart
```

Чем ниже уровень, тем быстрее и детерминированнее ДОЛЖЕН быть тест.

В коде нижние уровни — тесты Dart-пакетов `codelab_acp_*`, `codelab_client_*`, `codelab_agent_*`, `codelab_setup`, `codelab_embedded` на `package:test`; уровень Cubit и виджетов — `apps/codelab_desktop/test/` и `packages/flutter/codelab_ui/test/` на `flutter_test`; верхний — интеграционные тесты пакетов на Dart VM, PTY-e2e CLI и `apps/codelab_desktop/integration_test/` (§36, §74).

---

## 2. Тестировать поведение, а не реализацию

Тест ДОЛЖЕН проверять наблюдаемую семантику.

СЛЕДУЕТ писать так (иллюстративный пример):

```text
дано:
  соединение потеряно

когда:
  переподключение удалось

тогда:
  сессия снова готова
```

а не так:

```text
метод _retryInternal вызван ровно 2 раза
```

если конкретный внутренний вызов не является частью контракта.

---

## 3. Сначала чистый Dart

Если поведение можно проверить без Flutter, СЛЕДУЕТ писать тест на чистом Dart.

Это особенно относится к:

* протоколу ACP;
* сериализации;
* абстракциям транспорта;
* `codelab_client_acp`;
* автоматам состояний;
* политике разрешений;
* логике переподключения;
* редьюсерам потоков;
* маппингу ошибок.

Поднимать Flutter binding без необходимости НЕ СЛЕДУЕТ.

В коде Dart-пакеты под `packages/dart/` тестируются на `package:test` без Flutter binding. Скрипт `melos run test` запускает их тем же раннером `fvm flutter test`, что и Flutter-пакеты; через `fvm dart test` их гоняет `melos run test:dart` (в `check` не входит). Общий клиентский слой `codelab_client_core` и протокольный клиент `codelab_client_acp` тестируются без Flutter, хотя их потребитель — app.

---

## 4. Flutter-тесты

`flutter_test` используется для:

* виджетов;
* поведения BLoC/Cubit, обслуживающего представление;
* отрисовки;
* связки навигации и представления;
* компонентов Fluent UI;
* `codelab_ui`.

Flutter-тест НЕ ДОЛЖЕН быть единственным способом проверки поведения ядра.

---

## 5. Интеграционные тесты

`integration_test` используется для сценариев, где важно проверить несколько реальных слоёв вместе.

Например (иллюстративные схемы):

```text
UI
  ↓
BLoC
  ↓
application
  ↓
поддельный ACP-агент
```

или:

```text
codelab_desktop
  ↓
ACP-клиент
  ↓
stdio-транспорт
  ↓
тестовый процесс
```

Интеграционный тест НЕ ДОЛЖЕН заменять модульное покрытие.

В коде пакет `integration_test` подключён только в `apps/codelab_desktop`; эти тесты идут на macOS и запускаются только в ветке `release/<version>` (корневой `AGENTS.md` §21). Интеграционные тесты на Dart VM — с реальными процессами, сокетами и временными каталогами — лежат в обычных `test/` пакетов (`codelab_acp_transports`, `apps/codelab_agent`, `codelab_embedded` и др.) и входят в `melos run test`.

---

## 6. `codelab_acp_testing`

Пакет

`packages/dart/codelab_acp_testing`

предназначен для переиспользуемой тестовой инфраструктуры, специфичной для ACP.

Он МОЖЕТ содержать:

* поддельные транспорты;
* поддельного ACP-агента;
* фикстуры;
* билдеры;
* фабрики протокольных сообщений;
* помощники для запросов и сессий;
* детерминированные контроллеры потоков;
* проверки жизненного цикла.

Рабочий код (production code) НЕ ДОЛЖЕН зависеть от `codelab_acp_testing`.

В коде пакет содержит `FakeAcpTransport`, `FakeTerminalProcessRunner`, скриптовый stdio-агент для тестов с реальным процессом, корпус golden-фикстур `fixtures/acp/`, их загрузчик и сравнение кадров, драйверы проигрывания против клиента и агента и агента-повторителя (`README.md` пакета). Сам пакет не web-безопасен: загрузчик фикстур и скрипты агентов используют `dart:io`.

---

## 7. Направление тестовых зависимостей

МОЖНО:

```text
тесты codelab_client_acp
    ↓
codelab_acp_testing
```

МОЖНО:

```text
тесты codelab_desktop
    ↓
codelab_acp_testing
```

ЗАПРЕЩЕНО:

```text
codelab_client_acp/lib
    ↓
codelab_acp_testing
```

Тестовая инфраструктура НЕ ДОЛЖНА проникать в API рабочего кода.

Единственное исключение — `apps/codelab_cli`: рабочая команда `codelab test-scenario` проигрывает
golden-фикстуры против агента, поэтому `codelab_acp_testing` — её обычная зависимость. Импорт
`package:codelab_acp_testing/` разрешён только из `apps/codelab_cli/lib/src/scenario/`, это
проверяет сторож `melos run guard` (design.md change `add-codelab-cli`, D3).

В коде исключение CLI держат правило `rules.dart` для `apps/codelab_cli/lib/src` (`exclude: ['scenario/']`) и `cliAllowlist`; у остальных пакетов `codelab_acp_testing` не пускают в `dependencies` allowlist-ы сторожа, но не у всех пакетов allowlist есть (`layers-and-dependencies.md` §42). Отдельно от `codelab_acp_testing` у агентской стороны есть тестовые барели `testing.dart` (ядро, `codelab_agent_io`, `codelab_embedded`): сценарий модели нужен рабочему бинарю `codelab-agent --llm-script` (`apps/codelab_agent/lib/src/host/`) и драйверу `test-scenario`, а сторож держит `package:codelab_agent_io/testing.dart` внутри слоя `lib/src/testing/` моста `codelab_embedded` и запрещает `package:codelab_embedded/testing.dart` в `lib/` desktop (корневой `AGENTS.md` §5).

---

## 8. Протокольные тесты

`codelab_acp_protocol` ДОЛЖЕН иметь сфокусированные тесты на:

* сериализацию;
* десериализацию;
* обязательные поля;
* необязательные поля;
* неизвестные поля;
* неверную форму;
* версию протокола;
* преобразование туда-обратно (round-trip);
* совместимость.

В коде — `packages/dart/codelab_acp_protocol/test/` (например, `json_rpc_codec_test.dart`, `acp_method_codec_test.dart`, `session_update_test.dart`, `response_tolerance_test.dart`, `session_update_tolerance_test.dart`, `initialize_test.dart`); их запускает и `melos run protocol-conformance`.

---

## 9. Тесты сериализации

Проверяют:

```text
модель
  ↓
представление на проводе
```

СЛЕДУЕТ проверять значимые поля контракта, а не случайный порядок ключей map.

---

## 10. Тесты десериализации

Проверяют:

```text
представление на проводе
  ↓
типизированная модель
```

ДОЛЖНЫ быть покрыты сценарии:

* корректный payload;
* отсутствует обязательное поле;
* неверный тип поля;
* неизвестное необязательное поле;
* неподдерживаемая форма.

---

## 11. Тесты туда-обратно

Для стабильных протокольных моделей полезна проверка:

```text
модель
  ↓
сериализация
  ↓
десериализация
  ↓
эквивалентная модель
```

Проверка туда-обратно не заменяет явных тестов схемы.

---

## 12. Golden-фикстуры протокола

Для крупных протокольных сообщений МОЖНО хранить JSON-фикстуры.

Фикстуры ДОЛЖНЫ:

* быть небольшими;
* отражать реальные протокольные случаи;
* не содержать секретов;
* иметь понятное имя.

Например (иллюстративная раскладка):

```text
test/fixtures/
├── session_update.json
├── tool_call_request.json
└── invalid_missing_id.json
```

В коде главный корпус — сценарии обмена кадрами, а не отдельные сообщения: `packages/dart/codelab_acp_testing/fixtures/acp/` — плоский каталог файлов `<область>-<сценарий>[-<исход>].json` с `id` `acp/<имя>`, формат — `fixtures/acp/_schema.json` и [`proposals/agent-core/14-golden-fixtures.md`](proposals/agent-core/14-golden-fixtures.md), требования — спецификация `acp-golden-fixtures` (`openspec/specs/acp-golden-fixtures/spec.md`). У каждой фикстуры поле `spec` содержит хотя бы одну ссылку `<файл>.md#<якорь>` на `docs/protocols/acp/protocol/`; существование файла и якоря проверяет `fixtures_load_test.dart` (FIX-1). Новая фикстура и изменение ожидаемого кадра сопровождаются ссылкой `spec`; менять кадр под поведение реализации без такой ссылки спецификация запрещает («Правила изменения фикстур»). Корпус играют `conformance:client`, `conformance:agent`, `conformance:embedded`, а транспортные фикстуры (`setup.transport`) — `apps/codelab_agent/test/transport_conformance_test.dart`; `protocol-conformance` корпус не проигрывает. Кроме корпуса, у пакетов есть свои фикстуры, например SSE-ответы провайдеров в `packages/dart/codelab_agent_core/test/fixtures/sse/`.

---

## 13. Тесты совместимости

Если совместимость поддерживается, ДОЛЖНЫ быть тесты на:

* более старую поддерживаемую версию;
* неизвестные необязательные поля;
* более новые поля расширений;
* поведение при неподдерживаемой версии.

В коде используется одна версия протокола — 1 (`AcpAgentServer` отвечает `ProtocolVersion(1)`, `FakeAcpTransport` по умолчанию — тоже), поэтому тестов более старой версии нет. Неподдерживаемую версию задаёт `FakeAcpTransport.initializeProtocolVersion`: `codelab_client_acp/test/application_use_cases_test.dart` (`ProtocolVersion(9999)` → `UnsupportedProtocolVersionException`) и `codelab_client_core/test/workspace/superseded_attempt_test.dart`. Неизвестные поля и виды проверяют `response_tolerance_test.dart`, `session_update_tolerance_test.dart` (`codelab_acp_protocol`), `unsupported_session_updates_test.dart`, `unknown_tool_kind_test.dart` (`codelab_client_acp`) и фикстуры корпуса.

---

## 14. Тесты транспорта

`codelab_acp_transports` СЛЕДУЕТ тестировать отдельно от семантики приложения.

СЛЕДУЕТ проверять:

* подключение;
* отправку;
* приём;
* кадрирование (framing);
* разрыв соединения;
* закрытие потока;
* выход процесса;
* ошибки транспорта.

Тесты транспорта НЕ ДОЛЖНЫ проверять Flutter UI.

В коде — `packages/dart/codelab_acp_transports/test/`: `in_process_acp_transport_test.dart`, `stdio_acp_transport_start_failure_test.dart`, `io/stdio_acp_transport_close_test.dart`, `stdio_server_transport_test.dart`, `websocket_server_transport_test.dart`, `websocket_handshake_rejection_test.dart`, `web_safe_barrel_test.dart`.

---

## 15. Поддельный транспорт

Поддельный транспорт ДОЛЖЕН позволять детерминированно:

* подать входящее событие;
* перехватить исходящее событие;
* закрыть соединение;
* выбросить ошибку;
* задержать завершение;
* повторить событие;
* отправить некорректные данные.

В коде поддельный транспорт — `FakeAcpTransport` (`packages/dart/codelab_acp_testing/lib/src/fake_acp_transport.dart`): входящий кадр — `emitInbound` (повтор — тот же кадр ещё раз), исходящие — `sentMessages`, поток `sent` и `drainSentMessages`, закрытие — `close`, сбой транспорта — `fail`, сбой одной отправки — `failNextSend`, событие и диагностика транспорта — `emitEvent`, `emitDiagnostic`; на `initialize` он отвечает сам (`autoRespondToInitialize`). Средства задержать завершение `send` нет: отправка завершается сразу. Битый JSON подать нельзя: `emitInbound` принимает только типизированный `JsonRpcMessage`, разбор неверного JSON проверяется на уровне кодеков `codelab_acp_protocol` и транспортов. Сообщение ACP неверной или неизвестной формы подать можно — через сырые `params` уведомления (помощник `emitUpdate(Map)` в `codelab_client_acp/test/unsupported_session_updates_test.dart`).

---

## 16. Тесты ядра клиента

`codelab_client_acp` ДОЛЖЕН нести основное поведенческое покрытие семантики ACP-клиента.

Ключевые области:

* жизненный цикл соединения;
* жизненный цикл сессии;
* жизненный цикл запроса;
* потоки;
* отмена;
* переподключение;
* отбрасывание устаревших событий;
* поток разрешений;
* нормализация ошибок.

В коде — `packages/dart/codelab_client_acp/test/` (`application/` — гонки и жизненный цикл `AcpClientApplication`, например `superseded_connection_attempt_test.dart`, `approvals_dropped_on_replace_test.dart`, `request_timeout_test.dart`; `state_machines_test.dart`; `fixtures/` — прогон корпуса). Владелец переподключения и очереди промптов — `codelab_client_core`, его тесты — `packages/dart/codelab_client_core/test/` (например, `workspace/ensure_agent_test.dart`, `workspace/superseded_attempt_test.dart`).

---

## 17. Тесты автоматов состояний

Для явного автомата состояний СЛЕДУЕТ тестировать переходы.

Например (иллюстративные переходы):

```text
disconnected
  + connect
  → connecting
```

```text
running
  + cancel
  → cancelling
```

```text
reconnecting
  + success
  → ready/recovered
```

В коде автоматы — `ConnectionStateMachine`, `SessionStateMachine`, `PromptTurnStateMachine` (`codelab_client_acp/lib/src/domain/state_machines.dart`, исход перехода `StateTransitionResult`: `applied | ignored | rejected`), тесты — `state_machines_test.dart`. У протокольного состояния `ClientConnectionState` состояния `reconnecting` нет: `disconnected`, `connecting`, `initializing`, `ready`, `failed`. Оно есть у проекции рабочего пространства `ConnectionView` (`codelab_client_core/lib/src/connection/connection_view.dart`): `ConnectionView.reconnecting({attempt})`, переход `reconnect()` → `Reconnecting` → `Connected` | `ConnectionFailed`; попытка одна, поэтому `attempt` всегда 1. Переподключение ведёт `DefaultClientWorkspace` только по вызову `reconnect()`, автоматического нет (`session-lifecycle.md` §38, §39); тесты — `codelab_client_core/test/workspace/connection_lost_and_retry_test.dart`, `workspace/client_workspace_test.dart`, `sessions/reconnect_reload_test.dart`.

---

## 18. Тесты недопустимых переходов

Запрещённые переходы ДОЛЖНЫ проверяться.

Например (иллюстративно):

```text
disconnected
  + sendPrompt
  → rejected
```

или другой ожидаемый по API результат.

---

## 19. Тесты потоков

Тесты потоков ДОЛЖНЫ покрывать как минимум:

* один фрагмент;
* несколько фрагментов;
* завершение;
* повторный фрагмент;
* повторное завершение;
* поздний фрагмент;
* устаревшее поколение;
* событие не по порядку;
* повтор после переподключения;
* отмену во время потока.

---

## 20. Детерминированные тесты потоков

Использовать реальные задержки:

```dart
await Future.delayed(const Duration(milliseconds: 500));
```

для синхронизации теста НЕ СЛЕДУЕТ.

СЛЕДУЕТ использовать:

* `Completer`;
* управляемый `StreamController`;
* поддельные часы;
* явную подачу событий.

В коде поддельные часы ядра агента — `FakeClock` (`package:codelab_agent_core/testing.dart`); в desktop время приходит параметром `clock` (например, `CodeLabShellParts.build` → `ActiveSessionCubit`), а виджет-тесты двигают поддельное время `testWidgets` (`tester.pump(duration)`). `fake_async` не используется. Реальные задержки оставлены там, где по реальным часам работает сам проверяемый код, — с объяснением в комментарии теста (например, `packages/dart/codelab_acp_testing/test/client_conformance_test.dart`, группа `a late client frame`).

---

## 21. Тесты конкурентности

ДОЛЖНЫ быть покрыты сценарии гонок:

```text
завершение против отмены
разрыв против завершения
переподключение против ручного отключения
старый результат против нового запроса
закрытие (dispose) против callback
повторный connect
повторная отмена
```

---

## 22. Принудительный порядок

Полезный приём:

```text
старт A
старт B
завершение B
завершение A
```

и проверка, что устаревший A не перезаписал B.

В коде порядок задают `Completer`-ы двойников (например, резолвер транспорта в `codelab_client_core/test/workspace/superseded_attempt_test.dart`, гейт `test/support/gated_workspace.dart`).

---

## 23. Тесты разрешений

Политика разрешений ДОЛЖНА тестироваться на чистом Dart.

ДОЛЖНЫ быть покрыты сценарии:

* безопасное → разрешить;
* опасное → спросить пользователя;
* запрещённое → отказать;
* неизвестное опасное → отказать;
* устаревшее решение игнорируется;
* неверный id вызова инструмента отклоняется;
* отменённый запрос нельзя одобрить.

В коде политика разрешений агента — `PermissionPolicy` (`codelab_agent_core/lib/src/permissions/policy.dart`), её тесты — `packages/dart/codelab_agent_core/test/permissions/`; классификация риска на клиенте — `ApprovalPolicy` (`codelab_client_acp/lib/src/domain/approval_policy.dart`); связь запроса с вызовом инструмента на ACP-границе — `acp_permission_gate_test.dart` (`codelab_agent_acp`) и фикстуры `permission-*`, `prompt-tool-permission-*` корпуса. Подробнее — `permissions.md`.

---

## 24. Тесты UI разрешений

Виджет-тесты и тесты BLoC ДОЛЖНЫ проверять, что:

* запрос отображается;
* одобрение отправляет правильное решение;
* отказ отправляет правильное решение;
* повторный клик не создаёт повторного решения;
* устаревший запрос исчезает;
* секреты без необходимости не отображаются.

В коде — `apps/codelab_desktop/test/features/workbench/` (например, `application/shell_cubit_characterization/permission_test.dart`, `application/approval_shortcut_decision_test.dart`, `presentation/approval_shortcuts_test.dart`) и для CLI — `apps/codelab_cli/test/repl/approval_prompt_test.dart`.

---

## 25. Тесты BLoC

Тесты BLoC проверяют:

* намерение пользователя;
* взаимодействие с API приложения;
* итоговое состояние представления;
* маппинг ошибок;
* жизненный цикл подписок.

Они НЕ ДОЛЖНЫ повторно тестировать разбор протокола.

В коде в desktop нет `Bloc` с событиями, только `Cubit` (`state-management.md` §8); тесты Cubit-ов пишутся на `flutter_test` без `bloc_test`: тест вызывает метод и проверяет `cubit.state` или поток `cubit.stream`.

---

## 26. Тесты Cubit

Тесты Cubit ДОЛЖНЫ быть сфокусированными и быстрыми.

Если простому Cubit для теста нужен запуск транспорта или процесса, СЛЕДУЕТ проверить границу зависимостей.

---

## 27. Зависимости в тестах BLoC

В тестах BLoC СЛЕДУЕТ использовать поддельные зависимости или моки для API приложения.

Например (иллюстративные имена):

```text
FakeAcpClient
FakeSessionController
FakePermissionService
```

Запускать реальный внешний процесс без причины НЕ СЛЕДУЕТ.

В коде двойники Cubit-тестов desktop — `FakeClientWorkspace` и `FakeSessionHandle` (`apps/codelab_desktop/test/support/fake_client_workspace.dart`), двойники портов платформы `Fake*` в той же папке, `FixedAppStrings` и `TestAppStrings` (`test/support/app_strings.dart`) и `FakeAcpTransport` (`codelab_acp_testing`).

---

## 28. Виджет-тесты

Виджет-тесты предназначены для проверки поведения представления.

СЛЕДУЕТ проверять:

* правильную отрисовку;
* доступность и недоступность элементов управления;
* отправленные события и намерения;
* состояние ошибки;
* состояние загрузки;
* состояние разрешения;
* переиспользуемые компоненты `codelab_ui`.

---

## 29. Не тестировать пиксели без необходимости

Golden-тесты изображений СЛЕДУЕТ использовать только там, где визуальная регрессия действительно важна.

Обычное поведение предпочтительно проверять семантическими проверками виджетов.

В коде golden-тестов изображений (`matchesGoldenFile`) нет (`packages/flutter/codelab_ui/README.md`).

---

## 30. Тесты Fluent UI

Для компонентов `fluent_ui` СЛЕДУЕТ проверять:

* наличие нужного элемента управления;
* состояние;
* callback;
* текст и семантическое содержимое.

Привязывать тест к внутренней реализации Fluent UI без необходимости НЕ СЛЕДУЕТ.

### 30а. Локаль и язык интерфейса в тестах

Источник — change [`add-desktop-localization`](../../openspec/changes/archive/2026-11-20-add-desktop-localization/design.md), D3, D4, D9; правила текста — `layers-and-dependencies.md` §54.

**Локаль по умолчанию — `en`.** Эталон `en` каталогов совпадает с текстами спецификаций символ в символ, поэтому `find.text('…')` на английском остаётся верным и тесты под перевод не переписываются.

* `CodeLabTestBinding` принимает `locale` (по умолчанию `Locale('en')`) и передаёт начальный язык `AppLanguageStart` в шов `createCodeLabRootScope(language:)`. Выбор в начальном состоянии — `languagePreference` (по умолчанию `system`), начальный язык целиком с диагностикой чтения (события `app.language_preference_*`) — `languageStart`, двойник хранилища (сбой записи) — `languagePreferences`.
* Тестовый `FluentApp` в desktop без scope получает делегаты из одного помощника `test/support/l10n_app.dart` (`localizedFluentApp(child, locale: …)`); свой список делегатов в тесте не собирается.
* Тесты `codelab_ui` без делегата `CodeLabLocalizations` продолжают видеть английский (фолбэк кита); у каждого фиксированного словаря кита есть тест на `ru` с делегатом.
* Cubit-тесты получают `FixedAppStrings(AppLocalizationsEn())`; управляемый `TestAppStrings` (`hasListener` — проверка отписки) — для тестов смены языка. Оба двойника — в `test/support/app_strings.dart`.

**Обязательные тесты локализации.**

* **Согласованность каталогов** — `l10n_catalogs_test.dart` в каждом пакете с каталогом: наборы ключей `en` и `ru` равны, плейсхолдеры совпадают, у `ru`-сообщений с `plural` есть формы `one`, `few`, `many`, `other`. `gen-l10n` такие расхождения фатальными не считает.
* **Смена языка у Cubit-а с текстом** (каждый из списка D12 change): новое состояние с производным текстом на `ru`; кэши не возвращают старый язык; разовые сообщения остаются типизированными; после `close` подписка отменена (`hasListener == false`) и событие языка не даёт `emit`.
* **`AppLanguageCubit`**: `select` применяет язык до записи; сбой записи оставляет язык и ставит `saveFailed`; при двух быстрых выборах сохраняется последний (управляемое завершение записи, без задержек — §22); после `close` ничего не применяется, `close` не виснет на подписчике на паузе и ждёт запись в полёте не дольше `closeWriteTimeout` (управляемая длительность в тесте); число подписчиков `changes` не растёт после переподключения (`concurrency.md` §47а). Порт `AppLanguagePreferences.load()` не бросает: незнакомое, нестроковое значение и сбой открытия хранилища дают `system` с диагностикой в `AppLanguageLoad`.
* **Смесь языков** — помощник `test/support/l10n_mix.dart`, `expectNoStaleLanguage(tester, from:, to:)`: собирает видимые строки дерева (`Text`, `RichText`, `placeholder`, `Tooltip.message`, `Semantics.label`) и падает, если среди них осталось сообщение каталога `from` без плейсхолдеров, чей перевод в `to` отличается. Сценарий: экран в `en` с данными → `AppLanguageCubit.select(ru)` → `pumpAndSettle` → помощник; затем обратно. Каждая итерация экрана прогоняет его на своих экранах, включая состояния с InfoBar, ошибкой и открытым диалогом.
* **Точечная пересборка**: уже показанная заметка, тег статуса вызова, текст ошибки пересобраны; ввод композера, черновик диалога, фокус и прокрутка сохранены.
* **Раскладка `ru`**: в узких местах (навигация настроек 760 px, строка статуса, теги вызовов, кнопки диалогов) — виджет-тест без переполнения (`tester.takeException()` пуст).
* **Литералы мимо каталога** — `ui_literals_test.dart` сторожа (§71); исключения — в allowlist с причиной у каждой строки.

**Интеграционные тесты** (`integration_test/`, только `release/*`, §32) не зависят от языка машины: `integration_test/flutter_test_config.dart` в `setUp` каждого теста кладёт `codelab.app.language = en` в подменённое хранилище `SharedPreferences`. `E2eLaunch` для этого не подходит: он готовит агента и `CODELAB_HOME`, а app не запускает. Приёмка смены языка — `settings_language_flow_test.dart`.

**Сгенерированный код локализации** отдельно не тестируется (§80); его совпадение с ARB проверяет `melos run l10n:check` — в затронутых проверках при правке ARB или `l10n.yaml` (§75) и в CI-джобе `l10n` (§74).

---

## 31. Тесты навигации

Тесты навигации ДОЛЖНЫ проверять семантику маршрутов, а не приватную реализацию роутера.

Например (иллюстративно):

```text
когда выбрана сессия
тогда показан маршрут рабочего места
```

В коде навигация desktop — `NavigationCubit` (`apps/codelab_desktop/lib/app/navigation/`), тест — `test/app/navigation/navigation_cubit_test.dart`; приёмка переходов по страницам настроек — `integration_test/settings_navigation_flow_test.dart`.

---

## 32. Интеграционные тесты

Интеграционные тесты покрывают критические пути пользователя.

Минимальные кандидаты:

```text
запуск
подключение
создание сессии
отправка промпта
приём потока
завершение
```

В коде такие пути покрывают `apps/codelab_desktop/integration_test/` (например, `stdio_connect_flow_test.dart`, `prompt_queue_flow_test.dart`, `session_list_load_flow_test.dart`); на устройстве они идут только в `release/<version>` (корневой `AGENTS.md` §21), в feature-ветке они только проходят статический анализ `fvm dart analyze` (`melos run analyze`). На Dart VM тот же путь проходят PTY-e2e CLI (§36) и контрактный тест `packages/dart/codelab_agent_acp/test/contract/client_application_contract_test.dart` (настоящий `AcpClientApplication` против `AcpAgentServer` через `InProcessAcpLink`).

---

## 33. Интеграционный тест переподключения

Если переподключение — критическое поведение продукта, сценарий:

```text
подключение
отправка промпта
транспорт потерян
переподключение
восстановление
```

ДОЛЖЕН иметь интеграционное покрытие.

В коде автоматического переподключения нет (`session-lifecycle.md` §38); ручной `Reconnect` посреди хода проверяет `apps/codelab_desktop/integration_test/session_list_load_flow_test.dart` в режиме `CODELAB_E2E_AGENT=dart` (спецификация `testing-quality`, «Интеграционный тест Reconnect посреди хода»).

---

## 34. Интеграционный тест разрешений

Критический путь:

```text
агент запрашивает инструмент
показан запрос разрешения
пользователь одобряет
решение отправлено
инструмент продолжает работу
```

и вариант с отказом.

В коде — `apps/codelab_desktop/integration_test/permission_flow_test.dart` и e2e CLI `apps/codelab_cli/test/e2e/repl_interaction_test.dart` (тесты `cli/repl-permission-*`).

---

## 35. Интеграционные тесты платформы

Платформенные адаптеры СЛЕДУЕТ тестировать отдельно.

Например:

* файловую систему;
* защищённое хранилище;
* запуск процессов;
* API окна.

Тесты приложения ДОЛЖНЫ использовать поддельный адаптер.

В коде адаптеры платформы desktop лежат в `apps/codelab_desktop/lib/core/platform/`, их тесты — в `test/core/platform/`; тесты приложения получают двойники `Fake*` из `test/support/` через `CodeLabTestBinding` (например, `FakeExternalLinkOpener`, `FakeUserShellLauncher`, `FakeThemeFilePicker`).

---

## 36. Тесты с реальным процессом

Интеграционные тесты с реальным процессом МОЖНО писать для `codelab_acp_transports`, если stdio-транспорт или транспорт процесса критичен.

СЛЕДУЕТ использовать управляемый тестовый исполняемый файл или процесс, а не внешний рабочий агент.

Для терминального клиента `apps/codelab_cli` реальный процесс — приёмочный уровень (e2e
`test/e2e/`, имена тестов — id строк матрицы `cli/*`):

* бинарь CLI запускается kernel-файлом против scripted stdio-агента из `codelab_acp_testing`;
* интерактивные сценарии REPL идут через псевдотерминал `test/e2e/support/pty_process.dart`
  (системная утилита `script` BSD или util-linux; если её нет, тест пропускается с сообщением);
* ожидание — по содержимому вывода, а не по паузам; одиночный Esc подаётся отдельной записью с
  паузой больше таймаута декодера клавиш;
* прогон — `melos run test:e2e:cli` (входит в `melos run test`), только Dart VM.

Логика REPL, рендера, редактора строки и headless проверяется модульными тестами поверх портов
без процессов и терминала; e2e их не заменяют (design.md change `add-codelab-cli`, D2, D11).

В коде агента для e2e CLI выбирает переменная `CODELAB_E2E_AGENT` (`test/e2e/support/e2e_agent.dart`): `scripted` — по умолчанию, скриптовый stdio-агент; `dart` — `codelab-agent serve --stdio` из kernel со сценарием `--llm-script` (`melos run test:e2e:cli:dart-agent`); `embedded` — CLI из тестовой точки входа `test/e2e/support/embedded_cli_main.dart` со встроенным агентом (`melos run test:e2e:cli:embedded`); `python` — Python-агент, только локально (`test:e2e:cli:python-agent`). В режимах `dart` и `embedded` тесты с тегом `scripted-only` исключаются. Тесты с реальным процессом есть и вне e2e: `codelab_acp_transports/test/` (§14) и `apps/codelab_agent/test/*_process_test.dart`.

---

## 37. Тестовый агент

Полезно иметь поддельного или тестового ACP-агента, который умеет:

* принять соединение;
* вернуть ответ сессии;
* передать фрагменты потоком;
* запросить инструмент;
* разорвать соединение;
* повторить события;
* вернуть некорректное сообщение.

Он ДОЛЖЕН быть детерминированным.

В коде тестовых агентов три вида: скриптовый stdio-агент `codelabCompatibleStdioAgentSource` с режимами `CodelabCompatibleStdioAgentMode` (`normal`, `withPermissionRequest`, `withFsAccess`, `promptError` и др.), агент-повторитель фикстуры `FixtureReplayAgent` (`codelab_acp_testing`) и настоящий Dart-агент со сценарием модели вместо LLM (`ScriptedStreamFunction`, `codelab-agent --llm-script`, сценарный открыватель `codelab_embedded/testing.dart`).

---

## 38. Тесты ошибок

СЛЕДУЕТ проверять не только успешный путь.

Минимальные классы сбоев:

* протокольная ошибка;
* ошибка транспорта;
* отказ в разрешении;
* таймаут;
* исчерпаны попытки переподключения;
* недопустимый переход состояния.

---

## 39. Тесты наблюдаемости

СЛЕДУЕТ проверять поведение журнала, критичное для безопасности:

* токен замаскирован;
* полный payload не пишется в журнал в release;
* идентификаторы корреляции присутствуют;
* диагностика устаревшего события содержит причину.

В коде — например, `structured_logging_test.dart` и `secret_redaction_test.dart` (`codelab_client_acp`), `apps/codelab_desktop/test/app_scope_logging_test.dart`, `apps/codelab_cli/test/cli_logger_test.dart`, `embedded_logger_test.dart`. Правила журнала — `observability.md`.

---

## 40. Тесты секретов

Если код маскирования выделен отдельно, у него ДОЛЖНЫ быть прямые модульные тесты.

Например (иллюстративно):

```text
вход:
Authorization: Bearer abc123

выход:
Authorization: ***redacted***
```

В коде — например, `config_redact_test.dart` и `mask_url_test.dart` (`codelab_agent_core/test/config/`), `secret_redaction_test.dart` (`codelab_client_acp`), `config_get_masking_test.dart` (`codelab_agent_io`); утечки секретов в машинные отчёты тестов ловит `report_leaks_test.dart` сторожа (§74.1).

---

## 41. Тесты хранения

Если есть хранение, СЛЕДУЕТ проверять:

* чтение и запись;
* миграцию;
* повреждённые данные;
* конкурентную запись;
* защиту от устаревшей ревизии;
* семантику восстановления.

В коде — например, `jsonl_session_store_test.dart`, `usage_ledger_store_test.dart`, `secrets/file_secret_store_test.dart` (`codelab_agent_io`), `shared_preferences_workspace_snapshot_store_test.dart` и `features/workbench/application/workspace_restore_test.dart` (`apps/codelab_desktop`).

---

## 42. Тесты миграции

Для миграции хранимых данных ДОЛЖНА быть фикстура старой версии данных.

СЛЕДУЕТ проверить:

```text
старые данные
  ↓ миграция
текущая модель
```

В коде — например, `secrets/secret_migrator_test.dart` и `cli/secret_migrate_command_test.dart` (`codelab_agent_io`).

---

## 43. Имена тестов

Имена тестов ДОЛЖНЫ описывать поведение.

СЛЕДУЕТ писать так (иллюстративно):

```text
ignores late completion from previous connection generation
```

а не так:

```text
test reconnect 3
```

Имя теста — доказательства строки Must начинается с id строки по правилу §74.1.

---

## 44. Дано / Когда / Тогда

Сложным тестам полезна структура:

```text
Given
When
Then
```

или:

```text
Arrange
Act
Assert
```

Формально размечать её комментариями не обязательно.

---

## 45. Одно поведение на тест

У теста ДОЛЖНА быть одна понятная причина падения.

Создавать огромный тест, проверяющий весь жизненный цикл приложения от запуска до завершения, НЕ СЛЕДУЕТ, если это не интеграционный сценарий.

---

## 46. Тестовые фикстуры

Фикстура ДОЛЖНА быть минимальной.

Создавать полный объект сессии ACP НЕ СЛЕДУЕТ, если тест проверяет только один идентификатор.

---

## 47. Билдеры

Тестовые билдеры полезны для сложных неизменяемых моделей.

Например (иллюстративные имена):

```text
aSession()
aToolCall()
anAcpMessage()
```

Билдеры ДОЛЖНЫ иметь разумные значения по умолчанию и позволять переопределить нужные поля.

---

## 48. Случайные данные

Случайность по умолчанию использовать НЕ СЛЕДУЕТ.

Если используется property- или fuzz-тестирование, начальное значение генератора (seed) ДОЛЖНО быть воспроизводимым.

В коде случайность в тестах ядра агента задаётся генератором с фиксированным seed (`Random(1)`, `Random(42)`; например, `codelab_agent_core/test/llm/decorators_test.dart`).

---

## 49. Фаззинг

Особенно полезен для:

* парсера протокола;
* кадрирования;
* некорректного payload;
* порядка событий;
* обработки повторных событий.

Но фаззинг дополняет, а не заменяет детерминированные тесты.

---

## 50. Инварианты для property-тестов

Полезные инварианты:

```text
повторное событие не меняет итоговое состояние
```

```text
старое поколение никогда не меняет состояние текущего поколения
```

```text
терминальный запрос никогда не возвращается в running
```

---

## 51. По умолчанию без реальной сети

Модульные тесты НЕ ДОЛЖНЫ зависеть от реальной сети.

СЛЕДУЕТ использовать поддельный транспорт или сетевой адаптер.

В коде HTTP провайдеров и MCP подменяется `MockClient` из `package:http` и поддельными серверами `codelab_agent_mcp/testing.dart`; сокеты появляются только в интеграционных тестах на `localhost` (§58).

---

## 52. По умолчанию без реальной файловой системы

Модульные тесты логики приложения НЕ ДОЛЖНЫ писать в реальную файловую систему пользователя.

СЛЕДУЕТ использовать временный каталог или поддельную абстракцию.

В коде поддельная файловая система ядра агента — `MemoryExecutionEnv` (`codelab_agent_core/lib/src/env/memory_env.dart`).

---

## 53. Временные каталоги

Если тесту действительно нужна файловая система, СЛЕДУЕТ использовать изолированный временный каталог и удалять его после теста; использовать реальные пути пользователя ЗАПРЕЩЕНО.

В коде тесты агента и клиентов, которым нужен каталог настроек, получают временный `CODELAB_HOME` (например, `apps/codelab_agent/test/stdio_profile_boundary_test.dart`, интеграционные тесты desktop через `E2eLaunch`).

---

## 54. Время

Логика, зависящая от времени, ДОЛЖНА получать внедряемые тестируемые часы, если время существенно влияет на поведение.

Это особенно относится к:

* повторам;
* таймаутам;
* истечению срока;
* истечению области действия разрешения.

В коде порт часов ядра агента — `Clock` (`codelab_agent_core/lib/src/util/clock.dart`, реализация `SystemClock`, двойник `FakeClock`).

---

## 55. Поддельные часы

Поддельные часы позволяют проверить:

```text
повтор через 1 с
повтор через 2 с
повтор через 4 с
```

без ожидания реальных секунд.

---

## 56. Изоляция тестов

У каждого теста ДОЛЖНО быть независимое состояние.

Общий изменяемый singleton между тестами без сброса использовать ЗАПРЕЩЕНО.

---

## 57. Параллельные тесты

Тесты ДОЛЖНЫ по возможности быть безопасны для параллельного запуска.

НЕ СЛЕДУЕТ использовать:

* общее имя временного файла;
* фиксированный порт;
* глобальное изменяемое состояние.

В коде `melos run test` идёт по пакетам последовательно (`melos exec -c 1`), `test:dart` — по четыре пакета (`-c 4`); внутри пакета файлы тестов параллельны по умолчанию раннера.

---

## 58. Порты

Если интеграционному тесту нужен сокет, СЛЕДУЕТ брать динамический свободный порт.

Хардкодить порт, который может быть занят, НЕ СЛЕДУЕТ.

В коде тесты WebSocket запускают агента с `--port 0` (например, `apps/codelab_agent/test/agent_host_skills_test.dart`).

---

## 59. Очистка процессов

Интеграционный тест ДОЛЖЕН завершать дочерние процессы даже при падении.

Очистка ДОЛЖНА находиться в `tearDown`.

В коде очистку процесса регистрирует `addTearDown` сразу после запуска; временный каталог удаляют `tearDown` или `addTearDown` — обе формы выполняются и при падении теста.

---

## 60. Очистка подписок

Тесты ДОЛЖНЫ закрывать:

* `StreamController`;
* подписки;
* BLoC;
* клиента;
* транспорт.

Висящие асинхронные ресурсы приводят к флейкам.

---

## 61. Флейки

Флейк считается дефектом.

Исправлять флейк увеличением произвольной задержки ЗАПРЕЩЕНО.

ДОЛЖНА быть найдена проблема гонки или владения.

---

## 62. Повтор тестов в CI

Автоматически повторять любой упавший тест, скрывая нестабильное поведение, НЕ СЛЕДУЕТ.

Повтор МОЖНО использовать только как временную диагностическую меру.

В коде автоматических повторов нет: ни `retry` в `dart_test.yaml`, ни повторов шагов в `.github/workflows/ci.yml`. Ручной перезапуск ночного прогона помечается в итоге `parity` и в счёт трёх ночей не идёт (§74.1).

---

## 63. Обновление снимков и golden-файлов

AI-agent НЕ ДОЛЖЕН массово обновлять golden-файлы и снимки только ради того, чтобы тесты позеленели.

Сначала ДОЛЖНО быть проверено, ожидаемо ли изменение.

В коде главный набор эталонов — корпус golden-фикстур ACP: изменение ожидаемого кадра без ссылки `spec` на раздел спецификации ACP запрещено спецификацией `acp-golden-fixtures`, а расхождение клиента со спецификацией исправляется в клиенте, а не в фикстуре (§12).

---

## 64. Моки

Если библиотека моков утверждена проектом, её СЛЕДУЕТ использовать последовательно.

Добавлять второй фреймворк моков без причины НЕ СЛЕДУЕТ.

Для протоколов с состоянием и транспортов СЛЕДУЕТ предпочитать fake там, где он даёт более реалистичное поведение.

В коде библиотеки моков нет (абзац «Где в коде» в начале документа): двойники — рукописные fake, часть из них реализует только нужные методы через `Fake` из `package:test`.

---

## 65. Fake или mock

Fake лучше подходит для:

* транспорта;
* ACP-агента;
* хранилища;
* компонента с богатым жизненным циклом.

Mock лучше подходит для:

* простого взаимодействия;
* проверки одного вызова;
* зависимости без состояния.

---

## 66. Не злоупотреблять моками

Если тест состоит из десятков `verify`, он часто проверяет связку реализации, а не поведение.

СЛЕДУЕТ проверить архитектуру или API.

---

## 67. Контрактные тесты

Для портов и адаптеров полезны общие контрактные тесты.

Например (иллюстративно):

```text
контракт FileStore:
  запись → чтение того же содержимого
  отсутствующий файл → ожидаемый сбой
```

Каждая реализация проходит один и тот же набор тестов.

В коде так устроены `executionEnvContract` (`codelab_agent_core/test/env/execution_env_contract.dart`; его проходят `MemoryExecutionEnv`, локальное окружение `codelab_agent_io` и окружение поверх ACP-клиента в `codelab_agent_acp`) и `sessionStoreContract` (`codelab_agent_core/test/session/session_store_contract.dart`; память ядра и `JsonlSessionStore`). Общий контракт обеих сторон протокола — корпус golden-фикстур (§12).

---

## 68. Контрактные тесты транспортов

Если ACP-транспортов несколько, полезен общий контракт:

* подключение;
* отправка;
* приём;
* разрыв соединения;
* семантика ошибок.

В коде общего набора тестов для всех реализаций `AcpTransport` нет: у каждого транспорта свои тесты (§14). Транспортных фикстур корпуса две, каждая для своего транспорта: `acp/stdio-framing-large-line` и `acp/ws-auth-bearer-required` (`apps/codelab_agent/test/transport_conformance_test.dart`). Одни и те же проверки через `--stdio` и `--ws` гоняют отдельные тесты хоста агента: `initialize` в `apps/codelab_agent/test/agent_host_test.dart` и ключ провайдера в `agent_host_secrets_test.dart`.

---

## 69. Тесты публичного API

Публичный API пакета СЛЕДУЕТ проверять через публичные импорты.

Это помогает убедиться, что нужный API действительно экспортирован.

В коде, например, `codelab_acp_transports/test/web_safe_barrel_test.dart` проверяет, что основной барель не тянет `dart:io`, а точки `test/web_smoke/main.dart` ядра агента, `codelab_embedded` и `codelab_setup` собирает `melos run web-compile`.

---

## 70. Внутренние тесты

Внутреннюю реализацию МОЖНО тестировать напрямую внутри пакета, но тесты пакетов-потребителей НЕ ДОЛЖНЫ импортировать `src/`.

В коде в тестах есть два межпакетных импорта `src/` (`layers-and-dependencies.md` §26); сторож их не проверяет.

---

## 71. Архитектурные тесты

Критические правила зависимостей СЛЕДУЕТ автоматизировать.

СЛЕДУЕТ проверять, что:

* пакет на чистом Dart не импортирует Flutter;
* рабочий код не импортирует `codelab_acp_testing`;
* пакет не импортирует `src` другого пакета;
* `codelab_ui` не зависит от `codelab_desktop`;
* запрещённых циклов зависимостей нет.

Отдельная проверка того же пакета — `parity_evidence_test`: у каждой строки Must матрицы целей агента
(`docs/architecture/proposals/agent-parity-goals.md`) есть доказательство, которое существует и проходит.
Правила и статусы — §74.1.

В коде сторож — `packages/dart/codelab_architecture_tests` (`melos run guard`): импорты (`import_guard_test.dart` по таблице `rules`), allowlist-ы зависимостей (`pubspec_allowlist_test.dart`), имена пакетов (`package_naming_test.dart`), сборка ядра через `buildAgentCore` (`host_assembly_guard_test.dart`), литералы интерфейса (`ui_literals_test.dart`), правовые документы (`legal_documents_test.dart`), доказательства матрицы целей (`parity_evidence_test.dart`), выбор затронутого CI (`ci_scope_test.dart`), утечки в отчётах (`report_leaks_test.dart`). Из пунктов списка выше сторож покрывает Flutter в части пакетов и `codelab_acp_testing` через allowlist-ы; общего запрета Flutter для всех `packages/dart/`, проверки `src` другого пакета, зависимости `codelab_ui` от `codelab_desktop` и циклов нет. Что сторож проверяет и чего нет — таблица `layers-and-dependencies.md` §42.

---

## 72. Статический анализ как часть стратегии тестирования

`dart analyze` не заменяет тесты, но ДОЛЖЕН входить в проверку изменения.

Анализатор и линтер ловят:

* ошибки типов;
* неверные импорты;
* мёртвый код;
* небезопасные паттерны.

В коде набор правил — `package:lints/recommended.yaml` с дополнениями корневого `analysis_options.yaml` (`avoid_print`, `prefer_final_locals`, `require_trailing_commas`, `sort_pub_dependencies`); desktop — `package:flutter_lints/flutter.yaml` (`apps/codelab_desktop/analysis_options.yaml`).

---

## 73. Форматирование

Форматирование — не тест, но часть Definition of Done.

Изменённые Dart-файлы ДОЛЖНЫ соответствовать `dart format`.

---

## 74. CI levels

CI разделён на два уровня: полный прогон и прогон затронутого (`.github/workflows/ci.yml`). Нормы — требования spec [`testing-quality`](../../openspec/specs/testing-quality/spec.md):

* «Непрерывная интеграция» — события запуска, все джобы на `ubuntu-latest` (джобов на macOS и `test:e2e:app:*` нет), когда прогон полный, что запускает «только документация», какие джобы и для каких пакетов идут в затронутом, итоговый джоб `ci`;
* «Проверки workspace» — полный прогон CI выполняет те же скрипты, что `melos run check`.

Их проверяет `codelab_architecture_tests/test/ci_scope_test.dart`, в том числе тесты «Полный прогон CI совпадает с check» и «Джобов на macOS нет». Этот раздел состав джобов не пересказывает: ниже — устройство, обоснования и то, чего спека не задаёт. Что запускать локально перед pull request — `AGENTS.md` §21.

Сужение по затронутому действует для любого pull request, кроме pull request в `master` и из `release/*`: причину полного прогона (`FULL_REASON`) `ci.yml` передаёт для любого события, кроме `pull_request`, и для этих двух видов pull request. По git flow (`AGENTS.md` §22) в `develop` идут pull request из `feature/*` и `hotfix/*`, поэтому на практике суженный прогон — это они (change `align-cross-cutting-specs`, D7).

Матрицу считает `tool/ci/affected.dart` (логика — `tool/ci/ci_scope.dart`). Затронутые пакеты — пакеты pub workspace с
изменёнными файлами и их зависимые по `dependencies` и `dev_dependencies`.
Внутри пакетов документацией считаются только `AGENTS.md`, `README.md` и `CHANGELOG.md`, а не любые
`*.md`: остальные `*.md` там — данные, например промпты ядра агента. Файлы каталогов локализации для джоба `l10n`
определяют `_l10nPackages` и `_isL10nFile` в `ci_scope.dart`; правка самого `tool/l10n_check.dart`
лежит вне пакетов и даёт полный прогон (change `add-desktop-localization`, D3).

Сайт (`site/`, ADR-0003) проверяет отдельный джоб `site` на Node: `npm ci --ignore-scripts` и
`npm run verify` в `site/`, параллельно с Dart-джобами (change `add-astro-site`, D13). Запускает его
признак `site`, который `ci_scope.dart` считает независимо от Dart-матрицы (`CiScope.site`, предикат
`_affectsSite`), а `affected.dart` пишет в `$GITHUB_OUTPUT` как `site=true|false`. Признак включают
файлы `site/**`, `docs/**`, `openspec/**`, `apps/*/README.md`, `apps/*/doc/**`,
`packages/**/README.md` и `packages/**/doc/**`, а также любой полный прогон. Весь `openspec/**`, а не
только файлы, на которые ссылаются опубликованные документы: точный разбор ссылок на Dart был бы
второй реализацией плагина ссылок сайта (D13). Классификацию для Dart-матрицы признак не меняет:
`docs/**` и `openspec/**` по-прежнему документация, а файл `site/` не считается «вне пакетов» и не
попадает в матрицу, поэтому правка только `site/` Dart-джобов не запускает.

Связь, которой нет в графе пакетов (тест читает файл другого пакета по пути), суженный прогон может
пропустить; её ловит полный прогон после merge в `develop` и ночной запуск. Полный прогон ветки по
запросу — `gh workflow run ci --ref <ветка>`.

Новый push или обновление pull request отменяет идущий прогон того же ref: проверять имеет смысл
только последний коммит. Ночной запуск и `workflow_dispatch` в отдельных группах concurrency и не
отменяются — ни push в `develop`, ни друг другом: отменённая ночь обнуляла бы счёт трёх ночей ворот
MVP (change `switch-default-agent-to-dart`, задача 4.1), а запуск по запросу нужен для доказательств.
Ночь по `cron` стартует с задержкой GitHub, иногда на часы, поэтому окно «без merge» не задаётся.

Обязательной проверкой в защите ветки СЛЕДУЕТ делать только итоговый джоб `ci`: пропущенные джобы
матрицы НЕ ДОЛЖНЫ блокировать merge. Джоб `site` обязательный, но отдельным статусом в защиту ветки не
добавляется: итоговый `ci` ждёт его вместе с `checks` и `parity` и принимает только `success` или
`skipped`, поэтому красный `site` при зелёных Dart-джобах делает `ci` красным. Обязательный статус
по-прежнему один.

В ночном запуске и в `workflow_dispatch` к полному прогону добавляются машинные отчёты тестов
(`CODELAB_TEST_REPORT_DIR`) и джоб `parity` — статус доказательств строк Must (§74.1; change
`switch-default-agent-to-dart`, D6, D7). На pull request и push отчёты не пишутся: вывод и время прежние,
а `parity` пропускается (`skipped`), поэтому защита ветки не меняется. Правка самой матрицы в pull request
добавляет джоб `guard` даже в «только документации» (`ci_scope.dart`, `ci_scope_test.dart`): иначе
сломанный разбор матрицы нашла бы только ночь.

В коде условие `web-compile` в суженном прогоне — изменён `codelab_agent_core` или пакет, от которого
он зависит (`_webSmoke` и `_withDependencies` в `ci_scope.dart`). Скрипт `web-compile` при этом
собирает ещё точки `codelab_embedded` и `codelab_setup`, но их правка сама по себе джоб `web-compile`
не запускает — их проверяет полный прогон.

### 74.1. Доказательства строк Must: `parity_evidence_test`

Почему: этап 9 закрыт, только когда у каждой строки Must матрицы целей есть доказательство, которое
существует и проходит. Вручную сверить 77 строк с фикстурами и тестами не получается: переименование
ломает матрицу молча (design.md change `switch-default-agent-to-dart`, D2).

Проверка — `packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart`, логика — в
`test/support/parity/` (`matrix_parser.dart`, `evidence.dart`, `reports.dart`, `verdict.dart`,
`allowed_skips.dart`). Пакет тестовый, новых зависимостей нет. Доказательства берутся из ячейки «Критерий
приёмки» (фрагменты в обратных кавычках, D3):

| Вид | Образец | Существует, если |
|---|---|---|
| `acp/<id>` | `acp/prompt-streaming-text` | есть `packages/dart/codelab_acp_testing/fixtures/acp/<id>.json` |
| `cli/<id>` | `cli/esc-cancels-turn` | в `apps/codelab_cli/test/e2e/` есть тест с таким id (правило имени ниже) |
| `core/<id>` | `core/overflow-triggers-compaction` | то же в `test/` пакетов `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `codelab_agent_mcp`, `codelab_embedded` и `apps/codelab_agent` |
| `app:<файл>` | `app:fs_flow_test.dart` | есть `apps/codelab_desktop/integration_test/<файл>` |
| путь теста | `packages/…/watchdog_test.dart` | файл есть |
| шаблон | `acp/*`, `app:*` | `acp/*` — все фикстуры с ролью `agent`; `app:*` — все `integration_test/*_test.dart` |

**Правило имени теста: id — первый литерал невложенного `test(` или `group(`.** Id `cli/<id>` и `core/<id>`
ДОЛЖЕН быть началом **полного** имени теста в отчёте `package:test`, а оно начинается с имени самой
внешней группы. Поэтому доказательством считается только вызов `test(` или `group(`, который лексически не
вложен в другой `group(`, и его первый строковый литерал начинается с id; дальше идёт конец строки, `:`
или пробел. Литерал, разбитый на соседние литералы, читается целиком. Вложенный
`test('core/x: …')` внутри `group('другое имя', …)` попадает в отчёт как `другое имя core/x: …` и
доказательством **не является**; упоминание id в комментарии — тоже (D3, уточнение 2026-11-10). Для нового
теста строки Must: имя `cli/<id>: …` или `core/<id>: …` — первым литералом внешнего `test(`/`group(`.

**Два слоя проверки (D4).**

* Существование — группа `matrix evidence exists`. Не требует отчётов, идёт в каждом прогоне `guard` и
  `test`. Ловит переименование фикстуры или теста без правки матрицы. Число строк Must ДОЛЖНО совпадать с
  итогом сводки §7 матрицы. Список известных пробелов (`knownGaps`) удалён: любое отсутствующее
  доказательство — `missing`, группа красная.
* Статус — группа `matrix evidence passed`. Идёт только при `CODELAB_PARITY_RESULTS=<каталог отчётов>`;
  без переменной она пропущена с причиной `CODELAB_PARITY_RESULTS is not set: status is checked by the
  nightly parity job`. Каталог без `meta.json` — ошибка, а не пропуск. Статус доказательства (D5):
  `pass`, `failed` (упал тест или набор в любом источнике), `skipped` (пропуск не из `allowedSkips`),
  `not-run` (в обязательном источнике нет теста id), `missing` (доказательства нет), `deferred`
  (доказательство `app:` без отчётов app). Открытыми считаются все статусы, кроме `pass` и `deferred`.

**Источники статуса (D5).** Каждому виду соответствует обязательный источник (нужен `pass`) и
дополнительные (падение — `failed`, пропуск не из перечня — `skipped`):

| Вид | Обязательный | Дополнительные |
|---|---|---|
| `acp/<id>` | `dart/codelab_agent_acp.conformance.json` (для фикстуры с `setup.transport` — `dart/codelab_agent.json`) | `scenario-embedded.xml`, отчёты `codelab_client_acp` |
| `cli/<id>` | `cli-dart.json` | `cli-embedded.json`, `dart/codelab_cli.json` |
| `core/<id>`, путь теста | отчёт пакета: `dart/<пакет>.json` или `flutter/<пакет>.json` | — |
| `app:<файл>` | `app/dart-agent/<файл>.json` | `app/embedded/<файл>.json` |

Тест принадлежит id, если полное имя в отчёте (группы и тест через пробел) начинается с id и дальше идёт
конец, `:` или пробел. Нужен хотя бы один `pass`, и ни один тест id в обязательном источнике не `skipped`.
Доказательство `app:` без `CODELAB_PARITY_APP_RESULTS` — `deferred`: ночной прогон на `develop`
проверяет всё, кроме app; полный статус app собирают ворота MVP по отчётам прогона на macOS из
`release/<version>` (D9).

**`allowedSkips` (Q5, Q8).** В обязательном источнике любой пропуск открывает строку. В
дополнительном источнике и в доказательстве-пути допустим только пропуск, причина которого есть в
перечне `test/support/parity/allowed_skips.dart`: шаблон причины и ссылка на требование спецификации
(например, `setup.mcp` у `test-scenario`; `fs/*` и `terminal/*`, которых нет у встроенного агента;
фикстура с ролью только `client` в агентском прогоне). Пропуск по перечню не считается ни `pass`, ни
открытием строки: файл-доказательство, все тесты которого пропущены по перечню, — `not-run`. Расширять
перечень МОЖНО только записью со ссылкой на требование спецификации; пропуск «чтобы позеленело» — `skipped`.

**Отчёты: `CODELAB_TEST_REPORT_DIR` (D6).** Если переменная задана и не пуста, скрипты Melos добавляют
машинный репортёр; без неё команды, вывод и коды выхода прежние. Значение — **абсолютный** путь: `melos exec`
и цикл app запускаются из каталогов пакетов. Раскладка каталога:

| Файл | Скрипт |
|---|---|
| `flutter/<пакет>.json` | `test` (`fvm flutter test` в каждом пакете, в том числе в чистых Dart-пакетах) |
| `dart/<пакет>.json` | `test:dart` (в `check` не входит) |
| `dart/codelab_agent_acp.conformance.json`, `dart/codelab_client_acp.conformance.json` | `conformance:agent`, `conformance:client` |
| `scenario-embedded.xml` (JUnit `test-scenario --junit`) | `conformance:embedded` |
| `cli-dart.json`, `cli-embedded.json` | `test:e2e:cli:dart-agent`, `test:e2e:cli:embedded` |
| `app/<режим>/<файл>.json` (`fs_flow_test.dart.json`) и `app/<режим>/meta.json` (коммит, версия macOS, время) | `test:e2e:app:dart-agent`, `test:e2e:app:embedded` — только `release/<version>` (`AGENTS.md` §21) |
| `meta.json` | пишет джоб `parity` (`commit`, `ref`, `event`, `run_id`, `run_attempt`, `created_at`) |

Форматы: JSON — события репортёра `package:test` (читаются `testStart`, `testDone`, `error`, `done`,
`suite.path`, остальные пропускаются); JUnit — только формат `codelab test-scenario`. Источник «агентский
прогон корпуса» ищется сначала в `*.conformance.json`, затем в отчёте пакета.

**Ночной джоб `parity` и `workflow_dispatch` (D7).** В `schedule` и `workflow_dispatch` джоб `checks`
задаёт `CODELAB_TEST_REPORT_DIR=$GITHUB_WORKSPACE/parity-results` и публикует `parity-results-<job>`.
Джоб `parity` (`needs: [scope, checks]`, идёт и после красного `checks`) собирает артефакты, пишет
`meta.json`, запускает `parity_evidence_test` с `CODELAB_PARITY_RESULTS`, печатает итог в
`$GITHUB_STEP_SUMMARY` и публикует объединённый артефакт на 90 дней. Итог — строки
`<строка> <доказательство> <статус> [<источник>] [<причина>]` по id строки; при `run_attempt > 1`
печатается `rerun attempt: does not count for the three nights` (правило «три ночи без ручного
перезапуска»). Агрегатор `ci` принимает `parity` в состоянии `success` или `skipped`. Ручной запуск полного
прогона любой ветки — `gh workflow run ci --ref <ветка>`; он же даёт отчёт `parity` до ночи.

**Утечки в отчётах (D16).** Отчёты содержат печать тестов и тексты ошибок, поэтому перед публикацией
артефакта `report_leaks_test.dart` (`CODELAB_REPORT_LEAKS_DIR`) запускается в окружении того джоба, который
отчёт породил, и артефакт грузится только при его зелёном результате. Тест падает на значениях секретов из
окружения (имена, оканчивающиеся на `TOKEN`, `KEY`, `SECRET`, `PASSWORD` и подобные; значения от 8
символов, в сыром, JSON- и XML-экранированном виде) и на символических ссылках в каталоге. Секреты, которые
получают тесты, задаются на уровне **джоба**, иначе шаг проверки их не видит. В тестах — только вымышленные
секреты (маркер `sk-test-leak-…`): в отчётах CI маркер даёт предупреждение, в отчётах app — ошибку. Отчёты
app, попадающие в репозиторий, проверяются ещё и на домашний каталог и пути `/Users/<имя>/`, `/home/<имя>/`.

---

## 75. Точечная проверка

Для локального изменения агент МОЖЕТ запускать точечные тесты.

Например:

```bash
fvm flutter test test/features/chat/
```

или команду уровня пакета через Melos.

Но изменения общих пакетов и уровня пакета ДОЛЖНЫ проверяться шире.

В коде состав проверки перед pull request из `feature/*` и `hotfix/*` задаёт корневой `AGENTS.md` §21 («Проверка перед pull request»): формат изменённых файлов, `fvm dart analyze` и тесты изменённых пакетов, при изменении публичного API — ещё и пакетов-потребителей, и скрипты Melos изменённой границы (`guard`, `protocol-conformance`, `conformance:*`, `test:e2e:cli:*`, `prompts:check`, `l10n:check`, `web-compile`).

---

## 76. Когда запускать весь monorepo

Полный `melos test` СЛЕДУЕТ запускать прежде всего при изменении:

* публичного API пакета;
* `codelab_acp_protocol`;
* `codelab_client_acp`;
* общих тестовых утилит;
* графа зависимостей;
* генерации кода;
* моделей, общих для нескольких пакетов.

В коде перед pull request из `feature/*` и `hotfix/*` полный `melos run check` агент запускает только по просьбе пользователя, а при изменении публичного API обязательны тесты пакетов, которые используют изменённые элементы; полностью репозиторий проверяет CI после merge в `develop` и ночью, а в `release/<version>` полный `check` идёт перед pull request в `master` всегда (корневой `AGENTS.md` §21).

---

## 77. Честность проверки

AI-agent НЕ ДОЛЖЕН писать:

```text
all tests pass
```

если тесты не запускались.

Если команду выполнить невозможно, агент ДОЛЖЕН сообщить:

* что не запускалось;
* почему;
* что осталось непроверенным.

---

## 78. Покрытие тестами

Числовой порог покрытия сам по себе не цель, если проект его не задал.

Приоритет — покрытие критического поведения.

Особенно:

* жизненного цикла;
* безопасности;
* протокола;
* переподключения;
* отмены;
* устаревших событий.

В коде числового порога покрытия нет, и CI покрытие не измеряет.

---

## 79. Критический код

Для кода, критичного для безопасности и протокола, ожидаемое покрытие ДОЛЖНО быть выше, чем у обычного связующего кода UI.

Например:

* политика разрешений;
* разбор протокола;
* автомат состояний сессии;
* переподключение;
* отбрасывание устаревших событий.

---

## 80. Сгенерированный код

Отдельные тесты сгенерированных файлов, как правило, не нужны.

Тестируется поведение исходной абстракции, которая их использует.

В коде сгенерированы `*.freezed.dart`, модуль Cherrypick `apps/codelab_desktop/lib/app/app_scope.module.cherrypick.g.dart`, константы промптов `codelab_agent_core/lib/src/prompts/prompts.g.dart` и код локализации (`app_localizations*.dart` desktop, `codelab_localizations*.dart` в `codelab_ui`); анализатор исключает `*.g.dart` и `*.freezed.dart` (`analysis_options.yaml`). Совпадение промптов с `prompts/**/*.md` проверяет `melos run prompts:check`, кода локализации с ARB — `melos run l10n:check` (§30а).

---

## 81. Тесты состояний Freezed

Тестировать, что Freezed правильно реализовал `copyWith`, НЕ СЛЕДУЕТ.

Переходы состояния приложения ДОЛЖНЫ тестироваться.

---

## 82. Тесты Cherrypick

Связку DI СЛЕДУЕТ проверять дымовыми или интеграционными тестами, а не модульным тестом на каждую привязку.

ДОЛЖНО быть проверено, что composition root может построить граф.

В коде root scope desktop `createCodeLabRootScope` строят тесты `apps/codelab_desktop/test/app/` (например, `protocol_composition_test.dart`, `app_scope_embedded_test.dart`, `app_scope_profiles_test.dart`) и любой виджет-тест через `CodeLabTestBinding`; composition root CLI `buildCliRuntime` — тесты `apps/codelab_cli/test/`.

---

## 83. Дымовой тест сборки зависимостей

Полезен тест:

```text
построить граф зависимостей приложения
  → нет отсутствующих привязок
```

если Cherrypick позволяет это без запуска реальных разрушающих ресурсов.

---

## 84. Не запускать внешнего агента в модульных тестах

Модульные тесты НЕ ДОЛЖНЫ зависеть от установленного рабочего AI-агента.

СЛЕДУЕТ использовать поддельного или тестового агента.

В коде единственный прогон против внешнего установленного агента — `melos run test:e2e:cli:python-agent`, только локально и вне `check`; без Python-агента тесты пропускаются с причиной.

---

## 85. Матрица совместимости версий

Если ACP поддерживает несколько версий протокола, полезны параметризованные тесты:

```text
фикстура v1
фикстура v2
фикстура с будущими полями
```

---

## 86. Регрессионные тесты

При исправлении ошибки СЛЕДУЕТ по возможности сначала добавить тест, который её воспроизводит.

Особенно для:

* гонки;
* устаревшего события;
* повтора;
* несовместимости протокола.

---

## 87. Ошибка без теста

Если регрессионный тест добавить невозможно или нецелесообразно, это СЛЕДУЕТ объяснить в задаче или change.

---

## 88. OpenSpec и тесты

Поведенческие тесты ДОЛЖНЫ соответствовать `openspec/specs/`.

При изменении поведения продукта:

```text
спецификация
  ↓
тесты
  ↓
реализация
```

Менять тесты только ради подгонки под случайное текущее поведение НЕ СЛЕДУЕТ.

Когда задача считается выполненной и что проверить перед pull request — процесс, а не норма спеки: корневой `AGENTS.md` §17–§21 (OpenSpec, проверка затронутого, полный `check` только в `release/*` или по просьбе) и TDD вложенных `AGENTS.md` пакетов. Требование `testing-quality` «Соблюдение Definition of Done» удалено, потому что его проверяет ревью, а не тест (change `align-cross-cutting-specs`, D8).

### TDD и итерации ([план миграции §9.0](proposals/dart-agent-and-clients/09-00-migration-plan.md), п. 3 и п. 8)

**TDD (п. 3).** Каждая задача начинается с красного теста из критерия приёмки матрицы целей или из
раздела «Как проверить» документа ядра; затем минимальный код до зелёного; затем рефакторинг. В `tasks.md`
пункты идут парами «тест → реализация» со ссылкой на критерий; в PR красный тест виден в истории
коммитов до кода (коммит — по явной просьбе, `AGENTS.md` §19) или PR ссылается на критерий, который
закрывает. Уровень теста — минимально необходимый (§1). Исключения:

* (а) рефакторинг существующего кода — сначала характеризационные тесты, фиксирующие текущее поведение;
* (б) интеграционные тесты app и PTY-e2e CLI — приёмочные ворота, а не цикл разработки: пишутся до
  закрытия этапа, но не до каждой задачи. PTY-e2e CLI идёт на Dart VM в CI; тесты app на устройстве
  или симуляторе (`test:e2e:app:*`) запускаются только в `release/<version>` (`AGENTS.md` §21);
* (в) UI — test-first для Cubit и модели отображения, widget-тесты проверяют поведение, а не вёрстку;
* (г) реальные провайдеры, keychain, процессы ОС — test-first на фейках, реальные проверки — отдельными
  интеграционными тестами;
* (д) разведка (выбор библиотеки, бенчмарк isolate) — spike с ограничением по времени без тестов; код по
  его итогам пишется по TDD.

**Итерации (п. 8).** Работа идёт тонкими сквозными срезами одной функции (строки матрицы или её части)
через все нужные слои, обычно 1–3 PR. По тестам итерация завершена, когда:

* **unit-тесты** покрывают каждое новое поведение и каждый новый публичный элемент (по TDD);
* **интеграционные тесты** есть для каждой границы, которую итерация пересекает (кадры ACP, файловая
  система, процессы, HTTP, хранилище) — на фейках или в процессе: `InProcessAcpLink`, `MockClient`,
  `MemoryExecutionEnv`, временный каталог, scripted-агент; где интеграционный тест невозможен, PR говорит
  почему и чем это закрыто;
* критерии строк матрицы, которые закрывает итерация, зелёные, а доказательство строки Must названо по
  правилу имени из §74.1.

---

## 89. Приёмочные тесты

Для OpenSpec change полезно связывать задачи и сценарии спецификации с тестами.

Например (иллюстративно):

```text
Спецификация:
Когда соединение теряется во время потока,
клиент переподключается и игнорирует устаревшие события.

Тесты:
- reconnect_restores_stream_test
- stale_generation_ignored_test
```

В коде связь задаётся именами: доказательства строк Must называются по id строки матрицы (`cli/<id>`, `core/<id>`, фикстура `acp/<id>`; §74.1), а пункты `tasks.md` ссылаются на сценарий или критерий (§88).

---

## 90. Основные уровни тестов

### Уровень 1 — протокол

Проверяет корректность на проводе.

### Уровень 2 — транспорт

Проверяет ввод-вывод и кадрирование.

### Уровень 3 — ядро клиента

Проверяет семантику ACP-клиента.

### Уровень 4 — BLoC/Cubit

Проверяет оркестрацию представления.

### Уровень 5 — виджеты

Проверяет отрисовку UI и взаимодействие.

### Уровень 6 — интеграция

Проверяет критический сквозной путь.

---

## 91. Нежелательные паттерны

### Всё тестируется интеграционным тестом

Медленно, трудно диагностировать.

### `Future.delayed` для синхронизации

Порождает флейки.

### Реальная сеть в модульном тесте

Нестабильно.

### Реальная файловая система пользователя

Опасно.

### Рабочий агент в тестах

Невоспроизводимо.

### Тесты деталей реализации

Ломаются при любом рефакторинге.

### Массовые моки

Признак слишком тесной связанности.

---

## 92. Чек-лист для новой функции

Перед завершением функции СЛЕДУЕТ проверить:

1. Есть ли логика на чистом Dart?
2. Нужны ли модульные тесты?
3. Есть ли BLoC/Cubit?
4. Нужны ли тесты BLoC?
5. Есть ли новое поведение виджета?
6. Нужен ли виджет-тест?
7. Есть ли интеграция с платформой?
8. Нужен ли тест адаптера?
9. Затронут ли ACP?
10. Нужны ли тесты совместимости?
11. Есть ли конкурентность или гонка?
12. Нужен ли регрессионный или интеграционный тест?

Порядок работы над задачей и проверки перед pull request — корневой `AGENTS.md` §17–§21 (§88).

---

## 93. Чек-лист для исправления ошибки

При исправлении ошибки:

1. Воспроизвести проблему.
2. Определить уровень, где нарушен инвариант.
3. Добавить регрессионный тест, если возможно.
4. Исправить минимальный компонент-владелец.
5. Запустить точечные тесты.
6. Запустить анализ.
7. При изменении общего кода — расширить проверку.

---

## 94. Главные инварианты

### TEST-001 — Поведение ядра тестируется без Flutter

Логика протокола, клиента и автоматов состояний остаётся тестируемой на чистом Dart.

### TEST-002 — Тесты гонок детерминированы

Произвольные паузы не служат основным способом синхронизации.

### TEST-003 — Интеграционные тесты дополняют модульные

И не заменяют их.

### TEST-004 — Рабочий код не зависит от тестовой инфраструктуры

`codelab_acp_testing` — только `dev_dependency`. Исключение — `apps/codelab_cli` с импортом только
из `lib/src/scenario/` (§7). Тестовые барели агентской стороны — отдельный случай, тоже описанный в §7: бинарь
`codelab-agent` осознанно импортирует `package:codelab_agent_io/testing.dart` ради флага `--llm-script`.

### TEST-005 — У поведения безопасности есть прямые тесты

Отказ в разрешении по умолчанию и устаревшее решение покрыты тестами.

### TEST-006 — Совместимость протокола проверяется

У неизвестных, необязательных и версионированных данных есть покрытие.

### TEST-007 — Тесты соответствуют спецификациям

Тест сам по себе не является источником нового поведения продукта.

---

## 95. Основная модель

Хорошая стратегия тестирования выглядит так:

```text
Корректность протокола
        ↓
Корректность транспорта
        ↓
Корректность жизненного цикла клиента
        ↓
Оркестрация представления
        ↓
Поведение виджетов
        ↓
Критические сквозные пути
```

Если большинство ошибок можно поймать только тяжёлым интеграционным тестом desktop, СЛЕДУЕТ пересмотреть границы нижних уровней и их тестируемость.
