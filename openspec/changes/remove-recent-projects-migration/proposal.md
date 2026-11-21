## Why

Change [`share-recent-projects-store`](../archive/2026-11-22-share-recent-projects-store/design.md) перенёс недавние проекты app из `shared_preferences` (ключ `codelab.recent_projects`) в общий с CLI файл `$CODELAB_HOME/recent_projects.json`. Он же добавил одноразовый перенос прежнего ключа (`MigratingRecentProjectsStore`, D4). По решению пользователя Q2 (б) от 2026-11-22 перенос живёт только в предвыпускных сборках и удаляется до первого `stable` 1.0 (D9). Это критерий выхода вехи M4 ([`delivery-roadmap.md`](../../../docs/architecture/proposals/delivery-roadmap.md) §4.5) и строка backlog §10.4 «Удаление переноса недавних проектов».

Причина удаления — смена идентификатора бандла. 1.0 выходит с постоянным идентификатором вместо `com.example.codelabApp` (задача 9.4). Под новым идентификатором `shared_preferences` читает другой домен настроек, где ключа прежних сборок нет. Перенос там ничего не найдёт, и в первом `stable` он был бы мёртвым кодом с тремя событиями журнала и тестами.

**Срок реализации — вместе со сменой идентификатора бандла (задача 9.4) или сразу после неё, до первого `stable`** (решение пользователя 2026-11-22, design.md, Q1 (в)). Перенос влит в `develop` 2026-11-22 (PR #423), распространяемых сборок с ним не было: тегов нет, `gh release list` пуст, workflow выпуска нет, в `CHANGELOG.md` «Выпусков пока нет». Пока идентификатор прежний, перенос нужен любой сборке, в том числе `beta`. Change остаётся активным и сейчас не реализуется: итерации 1–3 `tasks.md` ждут задачи 9.4.

## What Changes

- **App, удаление переноса:**
  - класс `MigratingRecentProjectsStore`;
  - чтение и удаление ключа `codelab.recent_projects`;
  - шов тестов `legacyKeyRemover`;
  - события `recent_projects.migrated`, `recent_projects.legacy_unreadable` и `recent_projects.migration_failed` и логгер компонента `recent_projects` в `app_scope.dart`;
  - тест `test/core/platform/recent_projects_migration_test.dart`.
- **Прямая привязка.** При допустимом `CODELAB_HOME` в `CodeLabPlatformModule` привязан сам `JsonFileRecentProjectsStore`. Ключ `codelab.recent_projects`, если он остался в домене настроек, app не читает, не удаляет и не переносит.
- **Заглушка остаётся.** `UnavailableRecentProjectsStore` и `RecentProjectsUnavailableException` переезжают из `recent_projects_migration.dart` в `lib/core/platform/recent_projects_unavailable.dart`. Имя файла повторяет `profiles_unavailable.dart` (D2). Поведение не меняется.
- **Spec `agent-workbench-ui`, требование «Recent projects persist across app restarts»** (MODIFIED):
  - убраны абзац о переносе и сценарий «Recents from an earlier version are moved once»;
  - из сценариев «An unreadable recents file is kept» и «Invalid CODELAB_HOME» убраны упоминания ключа;
  - добавлен сценарий «The key of earlier builds is ignored».
- **Тесты:**
  - `app_scope_recent_projects_test.dart` проверяет, что ключ игнорируется, а не сохраняется;
  - `integration_test/open_project_flow_test.dart` больше не проверяет отсутствие ключа.
- **Документация:**
  - для `docs-writer`: `apps/codelab_desktop/doc/operations.md` и `doc/development.md`, README `codelab_client_core`;
  - для `codelab-architect`: `apps/codelab_desktop/AGENTS.md`, `docs/architecture/platform-integration.md` §28, `delivery-roadmap.md` §4.5 и §10.4 — отметить выполненным.

## Не входит

- **`JsonFileRecentProjectsStore.merge` и `mergeRecentProjects`.** Это публичный API kit из spec `acp-client-kit`; `record` работает на `mergeRecentProjects`. Метод `merge` остаётся без вызывающих в app; правится только его doc-комментарий, где сказано «нужен одному потребителю — переносу» (design.md, D3).
- **Удаление ключа `codelab.recent_projects` из домена настроек.** Сделать это без кода `shared_preferences` нельзя, а новый идентификатор бандла этот домен не читает (D1).
- **Смена идентификатора бандла** (задача 9.4) и перенос остальных ключей `shared_preferences`.
- **CLI, `codelab_client_io`, `codelab_client_core`, ACP, агентская сторона** — без изменений.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-workbench-ui` — «Recent projects persist across app restarts»: переноса из прежнего хранилища нет, ключ прежних сборок игнорируется.

## Impact

- **Пакеты:** код — только `apps/codelab_desktop` (`lib/app/app_scope.dart`, `lib/core/platform/`, тесты); в `codelab_client_io` — doc-комментарий `merge`. Новых зависимостей нет: `shared_preferences` остаётся, им пользуются другие настройки app. Правила сторожа и граф пакетов не меняются.
- **Данные пользователя.** Сборка app из `develop` после этого change не перенесёт ключ. Кто последний раз запускал app до PR #423 и обновится сразу на сборку без переноса, увидит пустой список недавних. Проекты, открытые в `codelab`, останутся в списке. Ключ в домене настроек сохранится, и данные можно восстановить вручную (design.md, Risks).
