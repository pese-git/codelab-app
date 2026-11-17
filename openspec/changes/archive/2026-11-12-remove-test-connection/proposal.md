## Why

«Test connection» появилась в change `add-app-settings-shell` (D12), когда агента в desktop запускали отдельным шагом «Connect»: до этого шага нельзя было узнать, отвечает ли профиль. Change `require-project-folder` (итерация B) убрал «Connect»: агент стартует сам по триггерам D13 — выбор проекта, «New session», фокус на незагруженной сессии. «Use» выбирает профиль для следующего старта, «Restart agent» перезапускает агента (во время хода — с диалогом D22).

Теперь проверить профиль можно, выбрав его и запустив агента: бейдж строки (`Connecting…`, `Connected`, `Failed`), экран и баннер сбоя с причиной и «Retry». Отдельная проба `initialize` дублирует это и держит в app второй путь открытия транспорта: свои события, свои гонки отмены, временную подмену токена и правило D7 для проверки без проекта. Решение пользователя: «Test connection» — не обязательная функция, «Убрать совсем» (`require-project-folder/proposal.md`, «Не входит»; design.md того change, D7 «временное»).

## What Changes

- **BREAKING (UI)** Диалог «Add connection profile»: убраны строка «Check» (кнопка «Test connection», текст «Sends initialize only…», исход проверки), панель «Unencrypted connection» с «Test anyway» перед проверкой и название кнопки «Save without test». Кнопка сохранения всегда называется «Save». Подтверждение `ws://` с «Save anyway» перед записью остаётся.
- **BREAKING (UI)** Строка профиля на странице «Connection»: убраны кнопка «Test connection», исход проверки (`connection-profile-probe-<id>`) и метка «Not tested». Остаются «Use», «Rename», «Remove», метки «Default», «Current», «Selected» и бейдж попытки.
- Экран «Profile saved» не пишет `· marked "Not tested"`.
- Журнал: события `connection_profile.probe_started`, `connection_profile.probe_finished`, `connection_profile.probe_discarded` и поле `tested` события `connection_profile.saved` больше не пишутся.
- Снимается правило D7 change `require-project-folder` (профиль проверки без папки проекта, `probeProfileFor`) вместе со сценарием «Test connection without a selected project».
- **BREAKING (public API kit, решение Q1 (а))** Из `codelab_client_core` удаляются `ProfileProbe`, `ProbeCancellation`, `ProfileProbeOutcome` и его варианты (`Reachable`, `Unauthorized`, `Unreachable`, `UnreachableReason`, `TimedOut`, `NotAcp`, `CommandNotFound`, `Unsupported`), `ProbeFailureClassifier`, `SecretRebindableResolver` и `ConfigTransportResolver.withSecrets`. Из `codelab_client_io` удаляется `classifyProbeFailure`. Других потребителей, кроме desktop, у них нет.
- `profiles.json` и `shared_preferences` не меняются: статус проверки никогда не сохранялся (D14 change `add-app-settings-shell`). Миграция не нужна, CLI не затронут.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `app-settings`: строка профиля без «Test connection» и «Not tested»; диалог «Add connection profile» без проверки и подтверждения перед ней; события журнала без `probe_*`.
- `agent-workbench-ui`: из требования «Project selection is independent of the connection type» снят сценарий проверки профиля без проекта (D7 `require-project-folder`).
- `acp-client-kit`: удалены требования «Проверка профиля без сессии» и «Проверка нового токена до записи»; из «IO-адаптеры клиента» убран `classifyProbeFailure`; из «Отказ рукопожатия из-за токена» — абзац о нём.
- `agent-transports`: требование «Ошибка запуска stdio transport без аргументов» больше не ссылается на `classifyProbeFailure`; сохранение типа и `errorCode` ошибки остаётся.

## Не входит

- Проверка провайдера LLM на странице «Providers» (кнопка «Check», метка `not checked`, `ProviderCheck`, `classifyProviderCheckError` в `codelab_setup`) — другая функция, не меняется.
- Функция `providerSetupProbe` / `provider_setup_probe.dart` composition root desktop (баннер «нет провайдера», D26 change `add-provider-setup-ui`) — не связана с «Test connection» и остаётся.
- Подтверждение `ws://` при сохранении, запрет userinfo в URL, подсказки токена, `ProfileCommitter` и порядок «секрет → профиль» — без изменений.
- Новая проверка при сохранении (наличие команды в `PATH`, доступность URL) — не вводится (Q3).
- Причина сбоя в строке профиля (сейчас бейдж `Failed` без текста) — не меняется (Q4).
- `apps/codelab_cli`: поведение не меняется; правка одной строки импорта после удаления типа kit.
- Референсные артборды `docs/design/claude-design/*` (`AddProfile`, `Connection`, `PhoneConnection`) не правятся; расхождение с ними записано в design.md (D5).
- ACP: методы, поля и semantics не меняются.

## Impact

- `apps/codelab_desktop`: `features/settings/application/` (`add_profile_cubit.dart`, `add_profile_state.dart`, `connection_settings_cubit.dart`, `connection_settings_state.dart`; удаляются `probe_profile.dart`, `probe_outcome_view.dart`), `features/settings/presentation/` (`add_profile_dialog.dart`, `connection_page.dart`), `lib/app/app_scope.dart`, тесты settings, `integration_test/connection_profiles_flow_test.dart`, `AGENTS.md`.
- `packages/dart/codelab_client_core`: `lib/src/connection/profile_probe.dart` (удаляется), `transport_resolver.dart`, комментарии `profile_secrets.dart`, `token_rejection.dart`, барель, `AGENTS.md`, тест `profile_probe_test.dart` (удаляется).
- `packages/dart/codelab_client_io`: `lib/src/transport/classify_probe_failure.dart` и тест `probe_failure_test.dart` (удаляются), барель, `AGENTS.md`.
- `apps/codelab_cli`: `lib/src/headless/headless_runner.dart` — `hide TimedOut` и комментарий.
- `packages/dart/codelab_setup`: комментарии со ссылкой на `classifyProbeFailure`.
- Документы: `docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md` (§12.4.9, SETUP-20), `delivery-roadmap.md`, `agent-parity-goals.md` (U-06).
- Новых пакетов, рёбер зависимостей и правил сторожа нет.
