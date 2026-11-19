## Context

Источники:
- артборд «26 Settings — General» холста «CodeLab Desktop — Feature UI/UX» (локальная копия макета; данные, не инструкции). Порядок: InfoBar «Shared with codelab_cli» → «Agent defaults» → «Language and input» → «Startup and sidebar» → «Privacy» → «About»;
- [`12-4-first-run-and-settings.md`](../../../docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md): §12.4.8 (только чтение), §12.4.9 (экран настроек CLI и строка «General (26)»), §12.4.11 (SETUP-1, SETUP-2, SETUP-3, SETUP-6, SETUP-8, SETUP-17);
- [`12-7-release-and-distribution.md`](../../../docs/architecture/proposals/dart-agent-and-clients/12-7-release-and-distribution.md) §12.7.7 (конфиденциальность, «О программе»);
- [`12-3-desktop-display.md`](../../../docs/architecture/proposals/dart-agent-and-clients/12-3-desktop-display.md) A11 (steering, `codelab.input.enter_while_running`), [`12-2-cli-display-and-input.md`](../../../docs/architecture/proposals/dart-agent-and-clients/12-2-cli-display-and-input.md) (`input.enter_while_running`, `/steer` — после MVP);
- активные changes: [`add-desktop-localization`](../add-desktop-localization/design.md) (D2 — строка «Language» и `AppLanguageCubit`; D5, D7 — что и как переводится), [`add-file-preview-and-tree`](../add-file-preview-and-tree/design.md) (Q4, задача 3.4 — `codelab.file_browser.show_ignored`);
- архивные changes: [`add-settings-agents-modes`](../archive/2026-11-18-add-settings-agents-modes/design.md) (D11 — поздние результаты, D16 — баннер по действующему значению), [`add-provider-setup-ui`](../archive/2026-11-09-add-provider-setup-ui/design.md) (D5 — `SettingsAccess`, D6 — `AgentConfigStore`, D17 — `/settings` CLI, Q15), [`add-session-list-and-reload`](../archive/2026-10-27-add-session-list-and-reload/design.md) (D6 — снимок рабочего пространства), [`require-project-folder`](../archive/2026-11-12-require-project-folder/design.md) (D10, D19 — старт без неявной папки);
- спецификации `app-settings`, `client-agent-setup`, `acp-client-kit`, `embedded-agent`, `licensing-and-attribution`, `agent-workbench-ui`;
- `AGENTS.md` (корень) и вложенные: `apps/codelab_desktop`, `packages/dart/codelab_setup`, `codelab_client_core`, `codelab_embedded`, `codelab_agent_core` (TDD, §2);
- `docs/architecture/`: `layers-and-dependencies.md`, `state-management.md`, `concurrency.md`, `platform-integration.md`, `observability.md`, `testing.md`, `technology-stack.md`, `l10n-glossary.md`.

Что есть в коде (сверено 2026-11-19 на ветке `feature/add-app-general-page` от `develop` a898b016):
- `general_page.dart` — одна строка «Language» в блоке «Interface» (`settingsGeneralSectionInterface`). Своего Cubit нет, владелец — `AppLanguageCubit` (D2 `add-desktop-localization`). Страница входит в `defaultSettingsPages`.
- Мост `codelab_setup`: `settingFieldsOf(snapshot)` → `SettingFieldView` (ключ, дескриптор, замаскированное значение, источник, `masked`, `editable`, `restartRequired`). Правила отказа и выбора слоя (`settingKeyRefusal`, `settingRowRefusal`, `isTrustBoundary`, `isSecretKey`, `isExternalSource`, `settingWriteLayerOf`, `applySetting`) живут в **`apps/codelab_cli/lib/src/setup/settings_rows.dart`** и возвращают английские строки CLI.
- Реестр ядра: 40 дескрипторов `scope: shared`. Из них со своей страницей — `agent.default_model`, `providers.*` (Providers), `permissions.mode`, `agent.effort` (Agents & modes), `mcp.servers` (MCP servers), `permissions.deny`, `permissions.tools` (будущая Permissions & tools). Граница доверия — `trusted_projects`. Остальные: `budget.*` (4), `compaction.enabled`, `subagents.*` (12), `logging.level` (`restartRequired`, слои `user` и `local`).
- Композер: Enter во время хода ставит сообщение в очередь (`add-prompt-queue`), Cmd/Ctrl+Enter — тоже отправка. **Steering в клиенте нет**: нет ни `SessionHandle.steer`, ни `PromptQueue.steer`, ни `pendingSteers`. В ACP-проекции агента (`codelab_agent_acp`) и в `codelab_acp_protocol` нет `_codelab/session/steer` и `_meta.codelab.steering`. Steering есть только внутри цикла ядра агента (`AgentLoop._pollSteering`).
- Старт app: `SettingsCubit` в конструкторе зовёт `ClientWorkspace.restoreProject()`. `WorkspaceRestorer.readProject()` читает снимок `codelab.workspace.snapshot` (проект, активная сессия, открытые сессии), а `restoreAfterConnect()` при первом подключении загружает активную сессию. Пока `readProject` не вызван, снимок не пишется. Отдельного экрана выбора проекта (`ProjectPickerDestination`) нет: без проекта сайдбар показывает недавние проекты и «Open folder…».
- Версии: `apps/codelab_desktop/pubspec.yaml` `version: 0.1.0`; в коде app версии нет, `clientInfo` app не отправляет. CLI держит `cliVersion = '0.1.0'` в `cli_args.dart`. `embeddedAgentVersion = '0.1.0'` объявлена в `codelab_embedded/lib/src/assemble.dart`, но из бареля не экспортирована. `package_info_plus` в стеке нет.
- `agentInfo` ответа `initialize` хранится в `codelab_client_acp` (`ConnectionReadyReceived`), но в `ConnectionView` ядра клиента его нет.
- Журналы app: `<applicationSupportDirectory>/logs` (`main.dart`, `CodeLabLoggingModule`). Порты `ExternalLinkOpener` и `LocalFolderOpener` есть в `core/platform/`, `homePathLabel` — тоже там.
- В корне репозитория есть `LICENSE` (MIT) и `THIRD_PARTY_NOTICES.md`, `PRIVACY.md` нет. Каталога `apps/codelab_desktop/assets/` нет.

## Goals / Non-Goals

**Goals:**
- блок «Agent defaults» с теми же строками реестра, что `/settings` CLI, без ключей, у которых есть своя страница;
- одно правило «можно ли править строку» для CLI и app в мосте;
- переключатель «Reopen the last project and its tabs» с честной семантикой текущей сборки;
- строка «Show ignored files» без второго ключа и второго владельца;
- «About» с версиями, лицензией, уведомлениями и диагностикой без секретов и путей.

**Non-Goals:** steering и строка Enter во время хода (D8); канал и подпись сборки (D11); `PRIVACY.md` и «Send crash reports»; цель «This project only» для умолчаний (D4); имя внешнего агента в диагностике; изменения ACP.

## Decisions

### D1. Пакеты, слои и сторож

| Пакет (ADR-0002) | Что меняется | Исполнитель |
|---|---|---|
| `codelab_setup` (мост) | `lib/src/views/setting_edit_rules.dart`: `SettingEditRefusal`, `settingKeyEditRefusalOf`, `settingEditRefusalOf`; экспорт из основного бареля | `[agent]` |
| `codelab_embedded` (мост) | экспорт `embeddedAgentVersion` из основного бареля | `[agent]` |
| `codelab_client_core` | `ClientWorkspace.startWithoutRestore()`, `WorkspaceRestorer.skip()` | `[client]` |
| `apps/codelab_cli` | `settings_rows.dart` строит тексты по `SettingEditRefusal` | `[client]` |
| `apps/codelab_desktop` | `features/settings/application/` (`agent_defaults_rows.dart`, `agent_defaults_state.dart`, `agent_defaults_cubit.dart`, `startup_settings_cubit.dart`, `about_ports.dart`, `about_diagnostics.dart`, `license_summary.dart`, `settings_search_index.dart`), `presentation/` (`general_page.dart`, `about_section.dart`, `agent_setting_labels.dart`), `core/platform/` (`startup_preferences.dart`, `build_info.dart`), `lib/app/` (`app_scope.dart`, `about_ports_factory.dart`, `build_version.dart`), `features/workbench/application/settings_cubit.dart`, `assets/legal/`, ARB | `[desktop]` |

Направление зависимостей не меняется: `apps/codelab_desktop` → `codelab_setup`, `codelab_embedded`, `codelab_client_core`; `apps/codelab_cli` → `codelab_setup`. Новых пакетов и рёбер нет, граф в `README.md` не меняется. Allowlist ядра (PKG-2), `setupAllowlist`, `desktopAllowlist` не меняются.

Слои app:
- `application/` — Cubit-ы и чистые функции без Flutter-виджетов: классификация ключей, построение диагностики, подсказки формата;
- `presentation/` — виджеты страницы и вызов `Clipboard.setData`. Буфер обмена в presentation — уже принятый образец «Copy path» (D13 `add-file-preview-and-tree`), нового порта нет;
- `core/platform/` — `StartupPreferences` (`shared_preferences`) и `BuildInfo` (ОС и архитектура).

`presentation/` по-прежнему не импортирует `dart:io` и `codelab_setup/io.dart` (правило SETUP-9 уже в `rules.dart`).

**Новое правило сторожа — одно.** Архитектуру процесса даёт `Abi.current()` из `dart:ffi`. Правило в `rules.dart`: `dart:ffi` в `apps/codelab_desktop/lib` — только в `lib/core/platform/build_info.dart`. Почему правило, а не договорённость: платформенный код в app изолирован (AGENTS.md §11), а `dart:ffi` в feature-коде — первый шаг к нативным вызовам мимо порта. Альтернатива — разбирать хвост `Platform.version` (`on "macos_arm64"`). Отклонена: формат строки не контракт SDK.

### D2. Какие ключи на «General» и как они сгруппированы

**Решение.** Блок показывает `settingFieldsOf(snapshot)`, отфильтрованный таблицей классификации в `features/settings/application/agent_defaults_rows.dart`. Таблица относит каждый ключ реестра `scope: shared` (по шаблону дескриптора) к одному из владельцев:

| Владелец | Ключи |
|---|---|
| `general` | `budget.max_steps`, `budget.max_tokens`, `budget.max_cost`, `budget.max_duration`, `compaction.enabled`, `subagents.*` (12), `logging.level` |
| `providers` | `agent.default_model`, `providers.*` |
| `agentsAndModes` | `permissions.mode`, `agent.effort` |
| `mcpServers` | `mcp.servers` |
| `permissionsAndTools` | `permissions.deny`, `permissions.tools` |
| `trustBoundary` | `trusted_projects` |

Тест классификации обходит `SettingsRegistry.all` и падает на ключе `shared` без строки в таблице. Новый ключ реестра поэтому не появится на «General» без решения.

Группы — по `SettingDescriptor.section` в порядке Budget, Agent, Subagents, Logging. Внутри группы — порядок реестра, как у `/settings`.

Уточнение реализации (сверка задачи 6.3). Группы есть в состоянии (`AgentDefaultsGroup.section`), но страница выводит строки одним списком в этом порядке, без подписей разделов, как на артборде. Ключи `subagents.*` перечислены в таблице поимённо (`_generalKeys`), а не шаблоном: новый ключ раздела `subagents` без строки в таблице роняет тест полноты, а не появляется на странице. `providers.*` относится к «Providers» по префиксу шаблона `providers.*.`. Подпись и описание берут `agentSettingLabelOf` и `agentSettingDescriptionOf` (`presentation/agent_setting_labels.dart`); ключ без сообщения ARB показывается своим именем.

**Почему не все `scope: shared`, как буквально в §12.4.9:**
- `permissions.mode` на «General» обошёл бы подтверждение `bypass` (D15 `add-settings-agents-modes`) — это нарушение приоритета 1 ради полноты списка;
- `providers.*` и `mcp.servers` правятся мастерами с порядком «секрет → конфиг» и откатом (SETUP-24), а строчный редактор этого не умеет;
- `permissions.deny` и `permissions.tools` — правила разрешений. Ослабление политики через строчный редактор идёт мимо будущей страницы «Permissions & tools» и её подтверждений;
- `trusted_projects` — граница доверия, CLI её тоже не правит.

**Почему таблица, а не список только разрешённых или только запрещённых ключей.** При одном списке «разрешённых» новый ключ молча пропадал бы со страницы, при одном списке «запрещённых» — молча появлялся бы на ней, в том числе ключ разрешений. Таблица с тестом полноты заставляет решать явно.

**Почему таблица в app, а не в мосте.** Раскладка ключей по страницам — решение экрана app, CLI показывает все строки `/settings`. Общее правило «можно ли править» при этом — в мосте (D6).

Подписи: app переводит подпись строки по ключу (`agentSettingLabel_budget_max_steps` и т. п. в ARB `en` и `ru`). Описание дескриптора показывается как вторая строка, тоже из ARB. Реестр прямо допускает локализацию по ключу (`SettingDescriptor.label`: «клиент МОЖЕТ локализовать по [key]»). Английский текст ARB совпадает с `label` и `description` реестра. Тест сверки сравнивает их для всех ключей `general`, чтобы подпись app не разошлась с CLI. Шаблон `subagents.*` даёт одну пару сообщений на ключ, а не на шаблон.

Альтернатива — показывать английские подписи реестра при любом языке. Отклонена: тогда строки агента по-английски стояли бы среди русских строк app. Ни одно правило D7 `add-desktop-localization` не относит подписи настроек к «тексту от агента».

### D3. Почему страница группы «App» пишет конфиг агента

- §12.4.9 прямо относит `SettingsRegistry` `scope: shared` к «General (26)» с записью `ConfigWriter (shared)`. E-15 требует, чтобы общие настройки CLI и app были одними строками, а не двумя копиями.
- Разделение «App/Agent» в навигации — про то, *чьё* это значение по смыслу (умолчания работы агента одинаковы для CLI и app), а не про то, где оно хранится. Значения app (`shared_preferences`) и значения агента (`config.yaml`) на странице разведены по блокам. InfoBar `settings-general-shared-info` прямо называет файл и CLI.
- Блок подчиняется тем же правилам, что страницы группы «Agent»: `SettingsAccess` (SETUP-2), одна запись через `AgentConfigStore` (SETUP-6, SETUP-8). Если агент окна удалённый, блок только читает, а остальная страница работает.

Альтернатива — вынести умолчания на отдельную страницу группы «Agent» («Agent defaults»). Отклонена: это расходится с утверждённой таблицей §12.4.9 и артбордом, а выигрыш только в названии группы.

### D4. Цель записи — только `user`

**Решение.** Запись — в `ConfigLayer.user` (`$CODELAB_HOME/config.yaml`), подпись блока `Changes are saved for all projects.`. Строка с источником `project` или `local` остаётся редактируемой с подписью `This project overrides it (<source>).`. После записи баннер строится по действующему значению перечитанного снимка: `Saved to all projects; <source> overrides it: the agent uses <effective>.` (образец — D16 `add-settings-agents-modes`).

Почему: блок — «умолчания». Явная цель в подписи — то же, что `ctrl+u` экрана настроек TUI (`settingWriteLayerOf(toUser: true)`): пользователь сам выбрал `user`, поэтому отказ CLI «ключ слоя `local` без цели» здесь не нужен, а перекрытие честно показывает баннер.

Альтернатива (б) — переключатель «All projects / This project only», как `agents-modes-target`. Отклонена: удваивает число состояний блока из 18 строк, а потребности нет — пользователь выбрал запись только в `user` (решение пользователя Q2). Слой `project` и `--config` не пишутся ни в одном варианте (SETUP-3).

### D5. Редакторы, разбор и отказы

- Тип → редактор: `bool` — `ToggleSwitch`, `enumeration` — `ComboBox` по `enumValues`, `int`, `float`, `duration` — `TextBox`. Других типов среди ключей `general` нет. Тест классификации проверяет, что у каждого ключа `general` тип из этого набора.
- Поле применяется по Enter и при потере фокуса. Разбор — `SettingsRegistry.parseCliValue(descriptor, raw)`: одно правило с `config set` и `/settings`. Текст `ConfigValueException.expected` (английский, из ядра) не показывается. Подсказку строит app по `SettingType`, `min`, `max` из ARB: `Enter a whole number of 1 or greater.`, `Enter a whole number from 1 to 3.`, `Enter a number.`, `Enter a duration like 500ms, 30s, 2m or 1h.`. Введённое значение в подсказку и журнал не попадает (CFG-10).
- Пустое поле: ключ задан в `user` — `UnsetValue` (как `/settings <key> --reset`), иначе возврат к показанному значению без записи.
- `budget.max_cost` и `budget.max_duration` валидатор требует строго больше нуля, а `parseCliValue` этого не знает (комментарий реестра). Запись тогда даёт `ConfigRejected`, и баннер показывает текст писателя как есть. Отдельного правила в app нет.
- Отказы — по ветке `SettingEditRefusal` (D6): секрет, маска, `config`/`env`. Среди ключей `general` секретных нет. Отказ всё равно обрабатывается, чтобы новый ключ классификации не стал редактируемым случайно.
- `restartRequired` → пометка `(applies after restart)` у строки и хвост баннера `Applies after Restart agent.` по `ConfigSaved.restartRequiredKeys` (единственный источник — реестр, R0-1).

Уточнения реализации (сверка задачи 6.3), тексты которых spec не задаёт:
- у ключа `int` без `min` подсказка — `Enter a whole number.` (`settingsGeneralHintInt`). Среди ключей `general` такой подсказки нет, это защита от нового ключа;
- отказы `UnknownSetting` и `TrustBoundarySetting` дают подпись `This setting cannot be changed here.` (`settingsGeneralRefusalOther`). Ключей `general` с такими отказами нет, ветка нужна, чтобы `switch` был полным;
- `ConfigRejected` без проблем писателя и отсутствие слоя `user` в снимке дают баннер уровня `error` `The config was not saved.` (`settingsGeneralRejected`); с проблемами — их текст как есть;
- баннеры `Saved.` и `Saved to <home>/config.yaml.` — уровня `success`, конфликт и перекрытие — `warning`;
- у редактируемой строки значение показывает сам редактор: текст поля — `SettingFieldView.effectiveValue`, у пустого поля подсказка `Not set` (`settingsGeneralNotSet`). Строка с отказом показывает значение текстом (`Not set`, если значения и умолчания нет).

### D6. Правило «можно ли править» — в мосте

**Решение.** В `codelab_setup/lib/src/views/setting_edit_rules.dart`:

```dart
sealed class SettingEditRefusal { const SettingEditRefusal(); }
final class UnknownSetting extends SettingEditRefusal { … }
final class TrustBoundarySetting extends SettingEditRefusal { … }
final class SecretSetting extends SettingEditRefusal { … }
final class ExternalSourceSetting extends SettingEditRefusal {
  final ConfigSourceView source; … }
final class MaskedSetting extends SettingEditRefusal { … }

SettingEditRefusal? settingKeyEditRefusalOf(String key);
SettingEditRefusal? settingEditRefusalOf(SettingFieldView row);
```

`apps/codelab_cli/lib/src/setup/settings_rows.dart` оставляет `settingKeyRefusal`, `settingRowRefusal` и `applySetting` с прежними текстами, но строит текст по ветке моста. `isTrustBoundary`, `isSecretKey`, `isExternalSource` уходят из CLI. `settingWriteLayerOf` и `applySetting` остаются в CLI: выбор слоя по `ctrl+u` и `--local` — правило экрана CLI, app его не использует (D4).

Почему: без переноса app повторил бы правило (SETUP-8) или разбирал бы английские строки CLI, что запрещено D5 `add-desktop-localization` («типизированные данные, а не английская строка»). Тексты CLI не меняются, регрессию ловят существующие тесты `/settings` и сценарий client-agent-setup «Тексты CLI не меняются».

### D7. `AgentDefaultsCubit`: состояние, жизненный цикл, поздние результаты

По образцу `AgentsModesCubit` (D11 `add-settings-agents-modes`):
- закрытая иерархия `AgentDefaultsState` (`agent_defaults_state.dart`):
  - `AgentDefaultsLoading` — страница показывает `ProgressRing` с ключом `settings-general-agent-loading`;
  - `AgentDefaultsReadOnly(kind: remote | notManaged, subject)` — `subject` — `scheme://host:port` или имя агента;
  - `AgentDefaultsUnreadable(reason, problems, banner?, configHome)` — заголовок InfoBar `The agent config cannot be read.` (`settingsGeneralUnreadable`). Под заголовком — текст по причине `AgentDefaultsUnreadableReason`: `loader` — проблемы загрузчика ядра как есть (`problems`, только у этой причины); `homeUnavailable` (папка `$CODELAB_HOME` неизвестна), `cannotRead` (сессия настроек или снимок не открылись, текст исключения не хранится), `userLayerUnreadable` (пользовательский `config.yaml` не читается, а загрузчик проблем не назвал) — сообщения ARB, которые строит страница. Так английский текст app в состоянии не хранится. `banner` — только `savedUnverified`: запись прошла, а перечитанный конфиг не разбирается;
  - `AgentDefaultsReady(groups, banner?, saving, fieldErrors, configHome)`.

  `configHome` — метка `$CODELAB_HOME` с `~` (`homePathLabel`) для текстов `<home>/config.yaml`; её считает Cubit, страница путей не вычисляет;
- Cubit создаётся на каждое открытие страницы (`CodeLabDependencies.createAgentDefaultsCubit`), страница его закрывает. Единственная подписка на `ClientWorkspace.state` (профиль, фокус, папка) — у Cubit, `close()` её отменяет (AGENTS.md §9);
- номер загрузки: снимок, пришедший после нового `reload`, смены доступа или папки либо `close()`, отбрасывается (`agent_defaults.load_discarded`). Пока идёт новая загрузка, правка не записывается (`save_failed` с `outcome: stale`);
- одна запись за раз (`Ready.saving`), повторные правки игнорируются; `ConfigConflict` — баннер и перечитывание без автоповтора (SETUP-6);
- источник снимка и записи — `ProviderSettingsOpener` сессии страницы (тот же адаптер `lib/app/provider_settings_session.dart`, что у Providers и Agents & modes). Cubit `FileAgentConfigStore` не видит;
- текст в состоянии не хранится: баннер и ошибки — типизированные данные (`AgentDefaultsBanner.saved(restart: …, overriddenBy: …)`), текст строит страница из ARB. Поэтому Cubit не входит в список Cubit-ов D5 `add-desktop-localization`.

Почему не расширять `AgentsModesCubit`: у той страницы своя цель записи, токен `bypass` и таблица определений. Общий Cubit смешал бы два автомата. Общее у них — порт сессии и правило номера загрузки, а они уже переиспользуются.

### D8. «When I press Enter during a turn» — не в этом change

**Факт.** Enter во время хода ставит сообщение в очередь — это единственное поведение. Второе действие (steer) по A11 требует `SessionHandle.steer` и `PromptQueue.steer` в ядре клиента, расширения `_codelab/session/steer` и признака `agentCapabilities._meta.codelab.steering` в ACP-проекции агента. Ничего из этого в коде нет. В документах это «после MVP» (C-03, agent-core-architecture §17.7.6).

**Решение.** Строка скрыта (SETUP-17), ключ `codelab.input.enter_while_running` не вводится. Ctrl+Shift+Enter не назначается.

Альтернативы:
- (а) строка с одним вариантом «Queue the message» — отклонена: строка без поведения;
- (б) ввести steer в этом change — отклонена: это ACP-расширение CodeLab с собственной semantics. Его объём (агент, протокол, ядро клиента, композер, CLI) больше всей страницы. AGENTS.md §3.4 требует для него отдельного решения, а не попутной реализации (решение пользователя Q1).

§12.3 A11 и строка «General (26)» §12.4.9 получают пометку «строка появится с change steering» (задача 0.1).

### D9. «Reopen the last project and its tabs»

**Что такое «its tabs» в этой сборке.** Вкладок сессий в app нет. Есть открытые сессии снимка рабочего пространства (`WorkspaceSnapshot.openSessions`) и активная сессия, которые kit восстанавливает при первом подключении. Строка относится именно к ним. Раскладка дока (`codelab.dock.*`) от проекта не зависит, восстанавливается всегда, и строка её не трогает.

**Ключ.** `codelab.workspace.reopen_last_project` (`bool`), рядом с `codelab.workspace.snapshot`. По умолчанию включено, это текущее поведение: включённое значение удаляет ключ, выключенное пишет `false`.

**Поведение при выключенной настройке:**
1. `SettingsCubit` (workbench) до восстановления читает `StartupPreferences.load()` (`core/platform/startup_preferences.dart`, образец — `AppLanguagePreferences`: `load` не бросает, сбой — значение по умолчанию и `readFailure`).
2. Выключено → `ClientWorkspace.startWithoutRestore()` вместо `restoreProject()`. Проект не выбирается, `projectRestored` завершается сразу, `startOnLaunch` без проекта агента не стартует (D19 `require-project-folder`), сайдбар показывает недавние проекты и «Open folder…».
3. Снимок этого запуска пишется как обычно. Поэтому включение настройки и следующий старт открывают проект *последнего* запуска, а не снимок двухдневной давности. Без нового метода kit снимок при выключенной настройке не писался бы вовсе (`WorkspaceRestorer` пишет только после `readProject`), и включение настройки вернуло бы устаревший проект.

**Почему метод kit, а не «прочитать снимок и не выбрать проект».** Прочитанный снимок оставил бы `_restoring`. Если пользователь затем выбрал бы тот же проект из недавних, первое подключение загрузило бы сессии снимка без его действия. При выключенной настройке это ровно то, чего он не хотел. Отмену восстановления правильно держать в kit, рядом с правилом «другой проект отменяет восстановление».

**Сбой чтения** — как при включённой настройке (не меняет привычное поведение) и событие `app.reopen_last_project_unreadable`. **Сбой записи** — переключатель остаётся в выбранном положении, InfoBar с «Retry» (образец — `settings-language-save-failed`).

Уточнение реализации (сверка задачи 6.3). `StartupPreferences.load()` возвращает `StartupLoad(reopenLastProject, storedValueInvalid, readFailure)`: небулево значение и сбой хранилища различаются, но оба дают «включено». Порт в `SettingsCubit` необязателен (`null` — «включено»); шов тестов — `createCodeLabRootScope(startupPreferences:)`. InfoBar сбоя записи — ключ `settings-general-reopen-last-project-save-failed` над строкой, кнопка `settings-general-reopen-last-project-retry` с тем же сообщением `Retry`, что у строки «Language» (`settingsLanguageSaveRetry`). Поздний итог записи после нового выбора состояние не меняет (номер выбора в `StartupSettingsCubit`).

Уточнение реализации kit (исправления по ревью). `WorkspaceRestorer` запоминает первое подключение запуска (`_connectedOnce`). Если снимок дочитан уже после первого подключения, `restoreProject()` отдаёт его проект хосту, но сессии снимка не восстанавливаются: ни `session/load`, ни `session/new`, в том числе при последующих `reconnect()`. В список и в следующую запись снимка они тоже не попадают. Это следует из правила spec acp-client-kit «Восстановление после перезапуска» («при первом успешном подключении в запуске»): восстановление — один раз за запуск и только на первом подключении. Сценарий — в delta acp-client-kit «Снимок, дочитанный после первого подключения».

**Владелец значения на странице** — `StartupSettingsCubit` (на открытие страницы: загрузка, запись, `saveFailed`). Значение читается только при старте, поэтому живой подписки workbench на него нет.

Альтернатива — хранить настройку в `profiles.json` или `config.yaml`. Отклонена: это поведение окна app, CLI его не знает.

### D10. «Show ignored files» и порядок с `add-file-preview-and-tree`

**Решение.**
- Ключ, порт и владельца значения вводит задача 3.4 change `add-file-preview-and-tree`. Этот change уточнил её документы: порт `FileBrowserPreferences` в `core/platform/`, владелец значения — `ShowIgnoredFilesCubit` в root scope (образец — `AppLanguageCubit`). `ProjectFilesCubit` получает поток значения, переключатель панели вызывает `set` владельца.
- Строка «General» читает и пишет того же владельца. Второго ключа, порта и Cubit нет.
- **Порядок.** Итерация 4 этого change (строка «Show ignored files») зависит от итерации 3 `add-file-preview-and-tree`. До её слияния строка скрыта (SETUP-17), остальные итерации этого change от неё не зависят.

Почему владелец в root scope, а не `ProjectFilesCubit`: тот создаётся лениво при первом показе Files и сразу читает папку. Страница «General» не должна создавать Cubit панели и ходить в файловую систему ради флажка, а второй владелец разошёлся бы с первым.

### D11. «About»: откуда каждое значение

| Значение | Источник | Почему так |
|---|---|---|
| `CodeLab <version>` | константа `codelabDesktopVersion` в `lib/app/build_version.dart`; тест сверяет её с `version` в `pubspec.yaml` | образец — `cliVersion` CLI. `package_info_plus` не добавляется: новая зависимость ради одной строки при уже принятом образце (AGENTS.md §4, §14) |
| ОС и архитектура | `BuildInfo` (`core/platform/build_info.dart`): `Platform.operatingSystem` → `macOS`, `Linux`, `Windows`; `Abi.current()` → `arm64`, `x64` | платформа изолирована портом (§11), D1 |
| embedded agent | `embeddedAgentVersion` из основного бареля `codelab_embedded` (экспорт добавляется, spec embedded-agent) | одна строка с `agentInfo` агента; запускать агента ради версии не нужно |
| License | `assets/legal/LICENSE`: первая строка (`MIT License` → `MIT`) и строка `Copyright (c) …` | без копии строки в коде, D13 |
| Config folder | `$CODELAB_HOME` из `ConnectionEnvironment` composition root через `homePathLabel` | те же правила `~`, что в «Add connection profile» |
| Channel | **скрыт** | признака канала в сборке нет; каналы §12.7 — про обновление CLI (решение пользователя Q3) |
| Signed by | **скрыт** | проверки подписи во время работы нет; на Linux её нет вовсе (решение пользователя Q4) |

`AboutInfo` (неизменяемые данные) собирает composition root один раз. Своего Cubit у блока нет: состояние — только развёрнут ли `Expander` (эфемерный UI) и заметка об исходе действия.

Уточнение реализации (сверка задачи 6.3). Страница получает не `AboutInfo`, а набор `AboutPorts` (`features/settings/application/about_ports.dart`) из `CodeLabDependencies.aboutPorts`:
- `info` — `Future<AboutInfo>`: ресурсы `assets/legal/` читаются лениво при первом открытии страницы, результат кэшируется, повторные вызовы дают то же значение;
- `window` — снимок окна для диагностики в момент нажатия «Copy diagnostics» (D12);
- `externalLinks` и `folders` — порты `ExternalLinkOpener` и `LocalFolderOpener`;
- `logger` — события `settings.about_action`.

Собирает их `buildAboutPorts` (`lib/app/about_ports_factory.dart`); параметр `fixed` — шов тестов с готовым `AboutInfo` без чтения ресурсов. Строку «License» разбирает `licenseSummaryOf` (`application/license_summary.dart`): имя — первая строка без слова `License`, права — первая строка, начинающаяся с `Copyright`; разбор не бросает. Виджет — `AboutSection` (`presentation/about_section.dart`): блок с заголовком «About», внутри свёрнутый `Expander` с ключом `settings-general-about` на обёртке `KeyedSubtree`. `GeneralPage(about: null)` раздел не показывает — так тесты блоков «Agent defaults» обходятся без портов.

### D12. «Copy diagnostics»

Текст строит чистая функция `diagnosticsReportOf(AboutInfo, DiagnosticsContext)` в `features/settings/application/about_diagnostics.dart`. `DiagnosticsContext` — вид подключения окна (`embedded | stdio | websocket`), его состояние, вид доступа к настройкам агента, язык и выбор языка, признак «`CODELAB_HOME` задан». Состав — в spec app-settings «Диагностика для отчёта без секретов и путей».

Почему фиксированный набор полей, а не дамп состояния: в состоянии окна есть URL, id профилей, папка проекта, команды stdio-профилей. Маскирование задним числом ненадёжно: оно ловит только известные виды секретов, а пути пользователя не маскирует вовсе. Отбор по белому списку закрывает утечку по построению (AGENTS.md §16; приоритет 1). Тест кладёт маркеры (`sk-test-leak-…`, имя пользователя в пути, порт, id профиля) во все входы и проверяет, что их нет в тексте.

Текст английский при любом языке интерфейса: это диагностика для отчёта, как содержимое «Debug log» (D7 `add-desktop-localization`).

Уточнение реализации (сверка задачи 6.3). `DiagnosticsContext` собирается в момент нажатия: язык — из `AppLanguageCubit`, остальное — из `AboutPorts.window()`. Профиль — профиль текущего состояния окна, без него — профиль по умолчанию. Вид доступа: встроенный агент — `editable`, WebSocket — `remote-read-only`, stdio — по `resolveSettingsAccess`. Состояние `ConnectionLost` показывается как `disconnected`. «Config folder: custom» — переменная `CODELAB_HOME` непуста.

### D13. Лицензия и «Third-party notices»

- `apps/codelab_desktop/assets/legal/LICENSE` и `assets/legal/THIRD_PARTY_NOTICES.md` — копии корневых файлов, объявленные в `pubspec.yaml` как ресурсы. Тест `test/app/legal_assets_test.dart` сверяет их побайтно с корнем. Образец сверки копии — `.fvm/fvm_config.json` и `.fvmrc`. Flutter не принимает ресурсы вне каталога пакета, поэтому ссылка `../../THIRD_PARTY_NOTICES.md` невозможна.
- Диалог `settings-general-third-party-dialog`: текст `THIRD_PARTY_NOTICES.md` (markdown-виджет `codelab_ui`, уже есть в ленте), затем список лицензий пакетов из `LicenseRegistry.licenses` — свёрнутые `Expander` по имени пакета. `showLicensePage` (Material) не используется: app на Fluent, и страница Material требует своих локализаций и темы.
- В диалоге под уведомлениями — заголовок `Package licenses` и кнопка `Close` (сообщения ARB). Сбой `LicenseRegistry` не мешает показать уведомления: остаётся то, что успело собраться.
- Почему офлайн, а не ссылка на репозиторий: запись про шрифт OFL-1.1 в `THIRD_PARTY_NOTICES.md` относится к распространяемой сборке, и уведомление должно быть доступно в самой сборке. Ссылка на сайт без сети не работает.

### D14. «Release notes» и «Open log folder»

- «Release notes» — `ExternalLinkOpener.open(Uri)` с константой `kCodeLabReleaseNotesUrl` = `<repo>/blob/master/CHANGELOG.md`. `<repo>` — тот же адрес, что `repoUrl` в `site/src/site.config.ts`. Константа в app (`lib/app/build_version.dart`) сверяется тестом с `site.config.ts`. Страница новостей сайта не используется, пока не выбран хостинг (H1 [`add-astro-site`](../archive/2026-11-18-add-astro-site/design.md); решение пользователя Q5). Политика ссылок порта (`http`/`https`) уже есть.
- «Open log folder» — `LocalFolderOpener.open(logDirectory, create: false)`. `logDirectory` — тот же путь, что получает `CodeLabLoggingModule`, его передаёт composition root. Ввода пути нет. Исходы `failed` и `missing` → InfoBar без пути.
- Журналы встроенного агента и сессий лежат в `$CODELAB_HOME` и этой кнопкой не открываются. Подпись кнопки говорит «log folder» app — это журнал, о котором просит отчёт об ошибке.
- Уточнение реализации (сверка задачи 6.3). Исходы `failed` и `rejectedScheme` у ссылки дают тот же InfoBar `settings-general-about-open-failed`. Подтверждение копирования — отдельный InfoBar уровня `success` `settings-general-about-copied` (`Diagnostics copied.`). Показана одна заметка — об исходе последнего действия.
- Сбои раздела (исправления по ревью; spec app-settings «Раздел «About» страницы «General»»). Ни в одном InfoBar нет текста исключения и пути:
  - сбой «Copy diagnostics» (данные окна, построение текста или `Clipboard.setData`) — InfoBar уровня `warning` `settings-general-about-copy-failed`: `Couldn't copy the diagnostics.` (`settingsGeneralAboutCopyFailed`); событие `settings.about_action` с `outcome: failed`; текст в буфер не кладётся;
  - сбой `AboutPorts.info()` (ресурсы `assets/legal/`) — вместо `Expander` в блоке «About» InfoBar уровня `warning` `settings-general-about-load-failed`: `Couldn't load the About section.` (`settingsGeneralAboutLoadFailed`); событие `settings.about_load_failed`. Раздел не прячется молча: пустое место без объяснения скрыло бы сбой сборки.

### D15. Локализация

- Все новые строки — ключи ARB `en` и `ru` с `@description`. Ключи конфигурации, значения, источники, команды (`codelab /settings`, `codelab config set`, `codelab secret set`), `CodeLab`, `MIT`, пути и версии — плейсхолдеры или неизменяемые части (глоссарий §2).
- Новые термины глоссария (задача 0.2): «Agent defaults» — «Умолчания агента», «Shared» (тег) — «Общая», «Startup and files» — «Запуск и файлы», «Reopen the last project» — «Открывать последний проект», «Show ignored files» — «Показывать игнорируемые файлы», «About» — «О программе», «Copy diagnostics» — «Копировать диагностику» (уточнено решением пользователя 2026-11-19, ниже), «Third-party notices» — «Сторонние уведомления», «Release notes» — «Заметки о выпуске», «Open log folder» — «Открыть папку журналов». Подписи ключей реестра (D2) — по глоссарию: «ход», «шаг», «субагент».
- Поиск «Find a setting» (решение пользователя 2026-11-19; заменяет D5 п. 8 change `add-desktop-localization` в редакции 2026-11-18). Ключевые слова всех страниц настроек, а не только «General», лежат в ARB: `settingsSearchKeywords<Page>` в `app_en.arb` и `app_ru.arb`, список через запятую. Статического списка `SettingsSearchIndex.keywords` больше нет. Поиск — `SettingsSearchIndex.search(visible, query, titlesOf:, localizedKeywordsOf:)`: `titlesOf` даёт заголовок на языке интерфейса и английский, `localizedKeywordsOf` — ключевые слова на языке интерфейса и английские. На русском интерфейсе страницу находят русские и английские слова, на английском — только английские. Для поиска на английском это изменение поведения относительно `develop`. Почему ARB: слова переводятся вместе с остальными текстами страницы и проверяются `l10n:check`, а не живут вторым словарём в коде.
  - Правило для переводчика: значение сообщения — слова или фразы через запятую. Запятой внутри слова нет, пробелы по краям отбрасываются. Перевод — по глоссарию: одно понятие — одно слово, как в подписях страницы. Слово, которое уже есть у другой страницы (`restart`, `token`, `profile`), странице не добавляется: его охраняют тесты поиска.
  - Слова «General»: `language`, `budget`, `steps`, `compaction`, `subagent`, `log level`, `startup`, `reopen`, `ignored`, `about`, `version`, `license`, `diagnostics`; на русском — `язык`, `бюджет`, `шаги`, `сжатие`, `субагент`, `уровень журнала`, `запуск`, `открывать`, `игнорируемые`, `о программе`, `версия`, `лицензия`, `диагностика`.
- Сверка ARB с глоссарием (задача 6.3) добавила в подраздел «Страница «General»» термины, которые появились при реализации: `Not set`, `Saved`, `overrides`, `(applies after restart)`, `License`, `Config folder`, `Package licenses`, `Close` и подписи ключей реестра.
- Решения пользователя 2026-11-19 по переводу (сверка задачи 6.3; глоссарий, подраздел «Страница «General»»):
  - `Max …` подписей ключей реестра — «Лимит …»: «Лимит шагов», «Лимит токенов», «Лимит стоимости», «Лимит длительности», «Лимит глубины», «Лимит одновременных», «Лимит за ход». «Макс. …» нарушало правило глоссария о сокращениях с точкой;
  - «Copy diagnostics» — «Копировать диагностику», несовершенный вид, как «Copy» и «Copy path» кита;
  - «Config folder» — «Папка настроек» остаётся;
  - все «Applies …» страницы — совершенным видом «Применится …», в том числе «Применится при следующем запуске» в подписи «Reopen the last project and its tabs».
- Cubit-ы change текста в состоянии не держат (D7, D9), подписка на смену языка им не нужна. Тест смены языка (`expectNoStaleLanguage`) — на всю страницу «General» с открытым «About» и баннером записи.

### D16. Наблюдаемость

Логгер `codelab_desktop.settings`, события — в spec app-settings «События журнала страницы «General»». Значения ключей конфигурации, пути, URL и тексты исключений в событиях не пишутся (CFG-10; AGENTS.md §16). Ключ конфигурации (`budget.max_steps`) — не секрет и пишется. Запись умолчаний дополнительно журналирует сам `ConfigWriter` агента, здесь это не дублируется.

Уточнение реализации (сверка задачи 6.3) — имена полей, которые spec называет «имя типа исключения»:
- `error_type` — у `agent_defaults.unreadable` (тип исключения открытия или чтения, `ConfigIssue` — проблемы загрузчика), `agent_defaults.save_failed` с `outcome: error` и `settings.reopen_last_project_save_failed`. Так называют поле остальные Cubit-ы страниц настроек;
- `error_class` — у `app.reopen_last_project_unreadable` (логгер компонента `app`, как `app.language_preference_read_failed`). Поле есть только при сбое хранилища; при небулевом значении событие пишется без поля.

`settings.about_load_failed` несёт `error_type` — имя типа исключения чтения данных «About», без пути и текста.

`agent_defaults.loaded` у блока только для чтения несёт `access: remote | not_managed` без `rows`, у редактируемого — `access: editable` и `rows`. `settings.about_action` для `third_party` всегда даёт `outcome: opened`. Итог записи, пришедший после закрытия страницы, пишется в журнал (`agent_defaults.saved` с `overridden: false`): перечитывания уже нет, а запись не должна пропасть из журнала.

### D17. Отступления от артборда

- **Порядок.** Как на артборде: InfoBar и «Agent defaults» первыми, затем «Interface» со строкой «Language». Фраза §12.4.9 и D2 `add-desktop-localization` «Language — первое содержимое страницы» относилась к странице из одной строки. §12.4.9 правится задачей 0.1. D2 того change это не ломает: требование spec «Язык интерфейса app» места строки не задаёт.
- **Заголовки блоков.** «Language and input» → «Interface» (существующий заголовок; строки ввода нет, D8). «Startup and sidebar» → «Startup and files» («Sidebar opens on» нет).
- **«Privacy»** и «Privacy policy» не показываются (proposal, «Не входит»).
- **InfoBar shared.** `Shared with codelab_cli … written to ~/.codelab/config.yaml — codelab_cli /settings shows the same rows (E-15)` → `Shared with the codelab CLI. … saved to <home>/config.yaml; codelab /settings shows them too.`. Бинарь CLI называется `codelab`, путь — действительный `$CODELAB_HOME`, а на «General» показано подмножество строк `/settings` (D2). Коды целей (`E-15`, `R-22`, `D-16`, `C-03`) в тексты интерфейса не выносятся.
- **Подпись «Step limit per turn».** На странице — подпись реестра (`Max steps`, перевод по D2), чтобы CLI и app называли ключ одинаково.
- **«About».** Без «Stable channel» и «Signed by» (D11). Обновления — InfoBar без кодов целей.
- **Подписи разделов реестра** (Budget, Agent, Subagents, Logging) над строками «Agent defaults» не выводятся, как на артборде: порядок разделов сохраняется, строки идут одним списком (D2).
- **«Show ignored files».** До итерации 3 `add-file-preview-and-tree` строки нет (D10, SETUP-17). Блок «Startup and files» при этом виден: в нём есть строка «Reopen the last project and its tabs».

### D18. Итерации

| Итерация | Что | Зависит от |
|---|---|---|
| 0 | документы: §12.4.9, A11, глоссарий | — |
| 1 | правила моста и CLI (`[agent]`, `[client]`) | — |
| 2 | блок «Agent defaults» (`[desktop]`) | 1 |
| 3 | «Reopen the last project» (`[client]`, `[desktop]`) | — |
| 4 | «Show ignored files» (`[desktop]`) | итерация 3 `add-file-preview-and-tree` |
| 5 | «About» (`[agent]`, `[desktop]`) | — |
| 6 | документация и приёмка | 1–5 (4 — если слита) |

Итерации 1, 3, 5 независимы. Каждая итерация — отдельный PR, `develop` между ними рабочий: невидимые строки скрыты.

## Risks / Trade-offs

- **[Расхождение подписей app и реестра]** Перевод по ключу может отстать от реестра. → Тест сверки английских ARB с `label`/`description` реестра для всех ключей `general` (D2).
- **[Новый ключ реестра]** Без решения ключ не попадает на страницу. → Тест классификации падает и называет ключ. Цена — лишний шаг для автора ключа, принята ради приоритета 1.
- **[Поздние результаты]** Снимок или исход записи после смены подключения, папки или закрытия страницы. → Номер загрузки и `isClosed` (D7), тест на каждую гонку (AGENTS.md §9, §12).
- **[Перекрытие проектом]** Пользователь пишет значение, а действует другое. → Баннер по действующему значению перечитанного снимка (D4), а не по записанному.
- **[Старт без проекта]** Выключенная настройка меняет первый экран, и пользователь может подумать, что проект потерян. → Подпись строки объясняет поведение, недавние проекты в сайдбаре на месте, снимок не удаляется до первой записи нового запуска.
- **[Копии юридических файлов]** Копия отстаёт от корня. → Тест побайтной сверки (D13).
- **[Утечка в диагностике]** → Отбор полей по белому списку и тест маркеров (D12).
- **[Зависимость от `add-file-preview-and-tree`]** Итерация 4 ждёт чужую итерацию 3. → Строка скрыта до её слияния, остальной change от неё не зависит (D10).
- **[`dart:ffi` в app]** Единственное место — `build_info.dart`, закреплено правилом сторожа (D1).

## Migration Plan

Миграции данных нет. Новый ключ `shared_preferences` — `codelab.workspace.reopen_last_project`. Отсутствие ключа даёт текущее поведение. Формат снимка рабочего пространства, `config.yaml` и `profiles.json` не меняется. Откат — удалить ключ: app вернётся к восстановлению проекта.

## Решения пользователя 2026-11-19

Пользователь одобрил change и на все вопросы выбрал рекомендованный вариант (а).

- **Q1. Enter во время хода и steering** — (а): строка «When I press Enter during a turn» скрыта, ключ `codelab.input.enter_while_running` не вводится. Steering — отдельный change после MVP (C-03) с ACP-расширением, ядром клиента, композером и CLI (D8).
- **Q2. Цель записи умолчаний** — (а): только слой `user`, перекрытие проектным слоем — баннером по действующему значению (D4). Переключатель «All projects / This project only» не вводится.
- **Q3. Канал сборки в «About»** — (а): строка скрыта до change релизного конвейера (§12.7), `--dart-define=CODELAB_CHANNEL` не вводится (D11).
- **Q4. «Signed by»** — (а): строка скрыта, статическое значение по платформе не показывается (D11).
- **Q5. Адрес «Release notes»** — (а): `CHANGELOG.md` на `master` репозитория (`kCodeLabReleaseNotesUrl`, D14). Переход на новости сайта — в change хостинга сайта.
- **Q6. Состав строк «Subagents»** — (а): все 12 ключей `subagents.*`, как в `/settings` CLI, чтобы CLI и app совпадали по E-15 (D2).

## Open Questions

Нет.
