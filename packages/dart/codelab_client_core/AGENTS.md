# AGENTS.md — codelab_client_core

Правила этого пакета дополняют корневой `AGENTS.md`. Источник архитектуры — `docs/architecture/proposals/dart-agent-and-clients/09-10-stage-5-client-kit.md` и `design.md` OpenSpec changes `extract-acp-client-kit` и `add-session-list-and-reload` (список, загрузка и восстановление сессий); поведение — spec `acp-client-kit`.

## 1. Назначение

Общий клиентский слой ACP без UI: рабочее пространство (`ClientWorkspace`), соединение (`ConnectionView`, профили и их разбор, резолверы транспорта), сессии (`SessionHandle`, `SessionView`), транскрипт (`TranscriptProjector`), очередь промптов (`PromptQueue`), одобрения, опции и команды агента (`ConfigOptionView`, `AgentCommandView`), инспектор (`InspectorProjection`), диагностика (`WorkspaceDiagnostic`, `describeFailure`), восстановление после перезапуска хоста (`WorkspaceRestorer`, `WorkspaceSnapshot`), порты хранилищ (`ProfileStore`, `RecentProjectsStore`, `WorkspaceSnapshotStore`). Его используют `apps/codelab_desktop` (через Cubit-ы рабочего места и фасад `CodeLabShellCubit`) и `apps/codelab_cli` (этап 6). Хосты только отображают `WorkspaceState` и `SessionView`; политика — когда слать, как реагировать на сбой, что считать «сессия занята» — живёт здесь.

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
* Список сессий проекта — часть `WorkspaceState`: открытые сессии, затем сессии агента со статусом `notLoaded`; курсор `session/list` живёт только в kit и не сохраняется (ACP), следующую страницу даёт `loadMoreSessions` (design D3 `add-session-list-and-reload`).
* `reconnect` загружает открытые сессии через `session/load`, сначала активную; без `loadSession` или при ошибке загрузки сессия становится `detached` с уведомлением, а не подменяется новой (design D5). `session/cancel` перед заменой транспорта kit не шлёт.

## 4. Восстановление и снимок

* Восстановление включает `ClientWorkspace(snapshots: …)`; алгоритм — `WorkspaceRestorer` в `lib/src/restore/`, его закрытые операции — через внутренний `RestoreHost`, не экспортируемый из бареля (design D6).
* Снимок содержит только проект, активную сессию и открытые сессии `(id, cwd)`. Курсоры, транскрипты, очереди, профили и секреты в снимок НЕ ДОЛЖНЫ попадать; тест `test/restore/workspace_snapshot_test.dart` это проверяет.
* Формат снимка кодирует и разбирает kit (`WorkspaceSnapshot.encode`/`decode`, `version`); хранилище видит только строку. Изменение формата — новая версия и OpenSpec change.
* Порядок: `restoreProject()` при старте хоста, шаги восстановления — внутри первого успешного `connect()` и один раз за запуск. До `restoreProject()` снимок не пишется.
* Записи не накладываются и идут без таймера: серия синхронных изменений — одна запись, изменения во время записи — одна следующая; `dispose` и `flushSnapshot()` дожидаются последней. Ошибка чтения или записи — `WorkspaceDiagnostic`, а не отказ операции.
* Восстановление ничего не отправляет агенту само: ни промптов, ни ответов на одобрения.

## 5. Тесты

Тесты — `fvm dart test packages/dart/codelab_client_core`, на `FakeAcpTransport` из `codelab_acp_testing` (dev-зависимость). Поведение app на время переноса защищают характеризационные тесты `apps/codelab_desktop/test/features/workbench/application/shell_cubit_characterization/`: их текст не менялся до конца change `extract-acp-client-kit` (design D1); новое поведение меняет их только явно и с обоснованием в `design.md` — так в `add-session-list-and-reload` сужена проверка `reconnect_test.dart` из-за уведомления `detached`.
