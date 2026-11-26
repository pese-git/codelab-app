Задачи идут парами «тест → реализация» там, где у удаления есть новое наблюдаемое поведение (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). Красный тест — отдельный коммит до кода; коммит — только по просьбе пользователя. В скобках — сценарий spec или решение design.md.

Метки исполнителей:
- `[desktop]` — `apps/codelab_desktop`;
- `[client]` — `codelab_client_io` (только doc-комментарий, D3);
- `[protocol]`, `[agent]` — задач нет.

Документы: `docs/architecture/**` и `openspec/**` — `codelab-architect` (без метки); `README.md`, `doc/` приложений и пакетов — `docs-writer` (метка — сторона документа).

**Срок реализации — Q1 (в), решение пользователя 2026-11-22.** Change активен, но сейчас не реализуется: итерации 1–3 ждут задачи 9.4 (смена идентификатора бандла) и выполняются вместе с ней или сразу после неё, до первого `stable`. Перед итерацией 1 сверить Context design.md с кодом, если перенос или его тесты менялись.

## 0. Решение о сроке (итерация 0)

- [x] 0.1 Решение пользователя Q1 (в) (2026-11-22) внесено в design.md («Решения пользователя 2026-11-22»), proposal и вводную tasks.md; условие «вместе с идентификатором бандла 9.4» добавлено в `delivery-roadmap.md` §4.5 (критерий M4 и вопрос о постоянном идентификаторе) и §10.4 (строка «Удаление переноса недавних проектов»).

## 1. Новое поведение: ключ игнорируется (итерация 1)

- [ ] 1.1 `[desktop]` Красный тест `test/app/app_scope_recent_projects_test.dart` (agent-workbench-ui «Recent projects persist across app restarts», сценарий «The key of earlier builds is ignored»; D1, D4 п. 1): `SharedPreferences.setMockInitialValues({'codelab.recent_projects': <список с /work/old>})`, временный `CODELAB_HOME` без файла; `load()` — пустой список, `recent_projects.json` не создан, ключ с прежним значением. Сейчас красный: перенос создаёт файл и удаляет ключ.
- [ ] 1.2 `[desktop]` Тест недопустимого `CODELAB_HOME` там же (сценарий «Invalid CODELAB_HOME»): проверка «ключ сохранён» и подстановка ключа убираются (D4 п. 2); импорт заглушки — из `recent_projects_unavailable.dart` (красный по компиляции до 2.1).

## 2. Удаление переноса (итерация 2)

- [ ] 2.1 `[desktop]` Реализация 1.1–1.2 (D1, D2, D5): `lib/core/platform/recent_projects_unavailable.dart` с `UnavailableRecentProjectsStore` и `RecentProjectsUnavailableException` (doc-комментарии по §15 корневого `AGENTS.md`, ссылки на D8 change `share-recent-projects-store` и D2 этого change); удаление `recent_projects_migration.dart` и `test/core/platform/recent_projects_migration_test.dart`; в `CodeLabPlatformModule` — `JsonFileRecentProjectsStore(p.join(home, 'recent_projects.json'))` напрямую; логгер компонента `recent_projects` удалён. Страж — остальные тесты app (`app_scope_recent_projects_test.dart`, `settings_cubit_recent_projects_test.dart`, `test/flutter_test_config.dart`) без изменения ожиданий.
- [ ] 2.2 `[desktop]` `integration_test/open_project_flow_test.dart`: убрать проверку отсутствия ключа `codelab.recent_projects` (D4 п. 4); в `feature/*` — только `fvm flutter analyze` (§21).
- [ ] 2.3 `[client]` Doc-комментарий `JsonFileRecentProjectsStore.merge` (`codelab_client_io/lib/src/stores/json_file_recent_projects_store.dart`): без «нужен одному потребителю — переносу»; назначение — слияние внешнего списка с файлом, в порт не входит (D3).
- [ ] 2.4 `[desktop]` `apps/codelab_desktop/AGENTS.md`, пункт «Недавние проекты»: без `MigratingRecentProjectsStore`; ключ прежних сборок игнорируется; заглушка — `recent_projects_unavailable.dart`.

## 3. Документация и закрытие (итерация 3)

- [ ] 3.1 `[desktop]` `apps/codelab_desktop/doc/operations.md` (абзац о недавних проектах: без переноса и событий; ключ предвыпускных сборок не читается), `doc/01-overview.md` (строка `lib/core/platform/` карты кода) и `doc/06-platform-and-appearance.md` — `docs-writer` (D6).
- [ ] 3.2 `[client]` `packages/dart/codelab_client_core/README.md`, строка `RecentProjectsStore` таблицы реализаций — `docs-writer` (D6).
- [ ] 3.3 `docs/architecture/platform-integration.md` §28 (история порта: перенос удалён этим change); `delivery-roadmap.md` §4.5 (критерий M4 выполнен) и §10.4 (строка закрыта) (D6).
- [ ] 3.4 `openspec validate remove-recent-projects-migration --strict`; проверки затронутого по `AGENTS.md` §21: `fvm dart format --set-exit-if-changed` изменённых файлов; `fvm flutter analyze` и `fvm flutter test` в `apps/codelab_desktop`; `fvm dart analyze` в `codelab_client_io` (doc-комментарий); `melos run guard` (удалён файл с импортами `shared_preferences` и `codelab_client_io` в `lib/core/platform/`); `cd site && npm ci && npm run verify` — СЛЕДУЕТ при установленном Node (изменены опубликованные `doc/` и README). `web-compile`, `test:e2e:cli:*`, conformance — не нужны: web-безопасные пакеты, CLI и ACP не меняются. Полный `melos run check` — только по просьбе пользователя.
