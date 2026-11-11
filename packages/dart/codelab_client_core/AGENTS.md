# AGENTS.md — codelab_client_core

Правила этого пакета дополняют корневой `AGENTS.md`. Источник архитектуры — `docs/architecture/proposals/dart-agent-and-clients/09-10-stage-5-client-kit.md` и `design.md` OpenSpec changes `extract-acp-client-kit`, `add-session-list-and-reload` (список, загрузка и восстановление сессий) и `add-command-palette-agent-commands` (каталог команд); поведение — spec `acp-client-kit`.

## 1. Назначение

Общий клиентский слой ACP без UI: рабочее пространство (`ClientWorkspace`), соединение (`ConnectionView`, профили и их разбор, резолверы транспорта, ссылка на токен профиля `ProfileTokenRef` и общий источник `ProfileSecretSource` (`env:<NAME>`), правила id профиля `isValidProfileId`, `reservedProfileIds`, `suggestProfileId` и `usableStoredProfiles` в `profile_ids.dart`, черновик профиля формы `ProfileDraft` с проверкой и выбором токена `ProfileTokenChoice`, проверка профиля `ProfileProbe` с исходами `ProfileProbeOutcome` и причиной `UnreachableReason`), сессии (`SessionHandle`, `SessionView`), транскрипт (`TranscriptProjector`), очередь промптов (`PromptQueue`), одобрения, опции и команды агента (`ConfigOptionView`, `AgentCommandView`), каталог команд палитры (`CommandCatalog`, `HostCommand`: слияние команд хоста и агента, конфликты имён, нечёткий поиск), инспектор (`InspectorProjection`), диагностика (`WorkspaceDiagnostic`, `describeFailure`), чтение папки проекта для панели Files (`lib/src/files/`: порт `ProjectFiles` и модели, чистые правила `normalizeRelativePath`, `classifyPreview`, `isMaybeSecretFileName`, `relativeToRoot`, `sortProjectEntries`; реализация на `dart:io` — `IoProjectFiles` в `codelab_client_io`; change `add-file-preview-and-tree`), восстановление после перезапуска хоста (`WorkspaceRestorer`, `WorkspaceSnapshot`), порты хранилищ (`ProfileStore`, `RecentProjectsStore`, `WorkspaceSnapshotStore`). Его используют `apps/codelab_desktop` (через Cubit-ы рабочего места и фасад `CodeLabShellCubit`) и `apps/codelab_cli` (этап 6). Хосты только отображают `WorkspaceState` и `SessionView`; политика — когда слать, как реагировать на сбой, что считать «сессия занята» — живёт здесь.

## 2. Границы

* Пакет — чистый Dart и web-безопасен: `lib/**` НЕ ДОЛЖЕН импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web`, `package:flutter`, `package:codelab_acp_transports/io.dart` (правило в `codelab_architecture_tests/test/support/rules.dart`, design D11).
* `dependencies` — только подмножество `{codelab_client_acp, codelab_acp_protocol, codelab_acp_transports, freezed_annotation, meta, collection, async}` (`pubspec_allowlist_test.dart`, design D2). Расширение — через OpenSpec change.
* Kit не открывает процессы и сокеты: транспорт из профиля строит `TransportResolver`, который регистрирует composition root. `dart:io`-адаптеры клиента — в `codelab_client_io`.
* Секреты не хранятся в профилях и состоянии: у `WebSocketProfile` только ссылка `tokenRef` (`ProfileTokenRef`: `env:<NAME>` — `EnvTokenRef`, `secret:<имя>` — `SecretTokenRef`; голое имя и `secret:` с недопустимым именем — `UnsupportedTokenRef` с маскированным `toString()`), значение даёт `SecretSource` — общий `ProfileSecretSource(environment, stored:)` для CLI и app, без кэша (design.md change `add-app-settings-shell`, D13, D15; change `add-provider-setup-ui`, D13).
* Хранилище секретов профилей — порт `ProfileSecrets` (бэкенд, `names`, `isSet`, `store`, `delete`, `read`; результаты `Stored`/`Exists`/`ReadOnly`/`Failed`/`Deleted`/`NotSet` без значений): kit не зависит от `codelab_setup` и пакетов агента, реализацию даёт composition root хоста. Значение нового токена в черновике, состоянии и проверке — только `SecretText` (`toString()` и JSON — `***`, `reveal()` лишь в адаптере хранилища и при открытии транспорта проверки); печатать и сохранять его иначе ЗАПРЕЩЕНО.
* `ProfileCommitter` — единственное место политики «токен ↔ профиль»: `save` — перечитать id → `store` секрета `codelab/profiles/<id>/token` (`Exists` → `tokenSecretExists` без записи) → `ProfileStore.save` → при отказе удалить созданный секрет; `remove` — сначала профиль, затем (только после успеха, только собственный `codelab/profiles/<id>/token` и только если на него не ссылается другой профиль) секрет; ошибка удаления секрета профиль не восстанавливает (SETUP-19, SETUP-24; change `add-provider-setup-ui`, D13). `ProfileProbe.probe(token:)` отдаёт транспорту новый токен из памяти через `SecretRebindableResolver.withSecrets`, ничего не записывая.
* `ProfileProbe` проверяет профиль одним `initialize` (без `session/new`), не трогает рабочее соединение и не бросает исключений; причину недоступности (`UnreachableReason`) определяет классификатор хоста по типам и кодам ошибок, не по тексту (D12). Текст `Unreachable.message` только для журнала, UI его не показывает.
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
* Сессии снимка принадлежат его проекту: если хост выбрал другой проект (через `selectProject` или папку в `connect`), восстановление отменяется, а неоткрытые сессии снимка в следующую запись не попадают.

## 5. Тесты

Тесты — `fvm dart test packages/dart/codelab_client_core`, на `FakeAcpTransport` из `codelab_acp_testing` (dev-зависимость). Поведение app на время переноса защищают характеризационные тесты `apps/codelab_desktop/test/features/workbench/application/shell_cubit_characterization/`: их текст не менялся до конца change `extract-acp-client-kit` (design D1); новое поведение меняет их только явно и с обоснованием в `design.md` — так в `add-session-list-and-reload` сужена проверка `reconnect_test.dart` из-за уведомления `detached`.
