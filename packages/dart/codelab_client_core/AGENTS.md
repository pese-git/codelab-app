# AGENTS.md — codelab_client_core

Правила этого пакета дополняют корневой `AGENTS.md`. Источник архитектуры — `docs/architecture/proposals/dart-agent-and-clients/09-10-stage-5-client-kit.md` и `design.md` OpenSpec change `extract-acp-client-kit`; поведение — spec `acp-client-kit`.

## 1. Назначение

Общий клиентский слой ACP без UI: рабочее пространство (`ClientWorkspace`), соединение (`ConnectionView`, профили и их разбор, резолверы транспорта), сессии (`SessionHandle`, `SessionView`), транскрипт (`TranscriptProjector`), очередь промптов (`PromptQueue`), одобрения, опции и команды агента (`ConfigOptionView`, `AgentCommandView`), инспектор (`InspectorProjection`), диагностика (`WorkspaceDiagnostic`, `describeFailure`), порты хранилищ (`ProfileStore`, `RecentProjectsStore`). Его используют `apps/codelab_desktop` (через Cubit-ы рабочего места и фасад `CodeLabShellCubit`) и `apps/codelab_cli` (этап 6). Хосты только отображают `WorkspaceState` и `SessionView`; политика — когда слать, как реагировать на сбой, что считать «сессия занята» — живёт здесь.

## 2. Границы

* Пакет — чистый Dart и web-безопасен: `lib/**` НЕ ДОЛЖЕН импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web`, `package:flutter`, `package:codelab_acp_transports/io.dart` (правило в `codelab_architecture_tests/test/support/rules.dart`, design D11).
* `dependencies` — только подмножество `{codelab_client_acp, codelab_acp_protocol, codelab_acp_transports, freezed_annotation, meta, collection, async}` (`pubspec_allowlist_test.dart`, design D2). Расширение — через OpenSpec change.
* Kit не открывает процессы и сокеты: транспорт из профиля строит `TransportResolver`, который регистрирует composition root. `dart:io`-адаптеры клиента — в `codelab_client_io`.
* Секреты не хранятся в профилях и состоянии: у `WebSocketProfile` только ссылка `tokenRef`, значение даёт `SecretSource`.
* Источник данных — порт `AgentBackend`; реализация `AcpClientBackend` поверх `AcpClientApplication`. Use case-ы `codelab_client_acp` kit не использует (design D3).
* Членов, помеченных в плане «после MVP», и заглушек для них в коде нет.

## 3. Модели и потоки

* Неизменяемые модели — freezed, как в `codelab_client_acp`; после изменения моделей — `fvm dart run build_runner build --delete-conflicting-outputs`, сгенерированные `*.freezed.dart` в git не хранятся (`.gitignore`), CI создаёт их шагом `Generate code` (`.github/actions/prepare`).
* Состояние соединения — закрытая иерархия `ConnectionView`, а не набор флагов (`AGENTS.md` §8).
* Поздние события старого соединения не меняют состояние: их отбрасывает бэкенд, kit на это опирается и проверяет тестом (`AGENTS.md` §9).
* `ClientWorkspace.dispose` отписывается от бэкенда и закрывает потоки kit; бэкенд и `AcpClientApplication` закрывает их владелец.

## 4. Тесты

Тесты — `fvm dart test packages/dart/codelab_client_core`, на `FakeAcpTransport` из `codelab_acp_testing` (dev-зависимость). Поведение app на время переноса защищают характеризационные тесты `apps/codelab_desktop/test/features/workbench/application/shell_cubit_characterization/`: их текст не меняется до конца change (design D1).
