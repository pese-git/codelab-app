## Why

Страница «Settings › General» (экран 26, цели E-15, D-18, D-19; `dart-agent-and-clients` §12.4.9) сейчас показывает одну строку «Language» (change `add-desktop-localization`, D2). Остальное содержимое артборда «26 Settings — General» в app недоступно:

- **Общие умолчания агента** (E-15). Лимит шагов хода, автоматическое сжатие контекста, бюджеты субагентов и уровень журнала агента меняются только правкой `config.yaml` вручную или командой `/settings` в CLI. В app их не видно, хотя `/settings` CLI и страница «General» по §12.4.9 должны показывать одни и те же строки реестра `SettingsRegistry`.
- **Старт без прошлого проекта** (R-22). App всегда открывает проект прошлого запуска и его сессии из снимка рабочего пространства. Начать с выбора проекта, не загружая прежние сессии, нельзя.
- **«Show ignored files»** (§12.6.8). Ключ `codelab.file_browser.show_ignored` вводит итерация 3 change `add-file-preview-and-tree`. Его должна показывать и страница «General» (§12.4.9), а не только переключатель панели Files.
- **«About»** (§12.7.7, D-16). В app нет места, где видны версия сборки и встроенного агента, лицензия и сторонние уведомления. Нет и способа скопировать диагностику для отчёта об ошибке без секретов и путей.

Объём одобрен пользователем 2026-11-19: агентские умолчания, Enter во время хода, открытие последнего проекта, «Show ignored files» и «About». Разведка кода сузила два пункта; объяснение — в разделе «Не входит». Решения пользователя по вопросам Q1–Q6 от того же дня — в design.md, раздел «Решения пользователя 2026-11-19».

## What Changes

- **Блок «Agent defaults»** на «General», перед ним InfoBar `Shared with the codelab CLI`. Строки — ключи реестра `scope: shared`, у которых нет своей страницы настроек и которые не являются границей доверия: `budget.*`, `compaction.enabled`, `subagents.*`, `logging.level`. Ключи «Providers», «MCP servers», «Agents & modes», будущей страницы «Permissions & tools» и `trusted_projects` здесь не показываются (design.md, D2). Строки сгруппированы по разделу реестра.
- **Источник и запись умолчаний — мост `codelab_setup`**: доступ `resolveSettingsAccess`, снимок `AgentConfigStore` сессии страницы, строки `settingFieldsOf`, разбор `SettingsRegistry.parseCliValue`, запись одним `AgentConfigStore.apply` в слой `user` (`$CODELAB_HOME/config.yaml`). Это тот же путь, что у `/settings` CLI и других страниц. Для `RemoteReadOnly` и `NotManaged` — InfoBar «только для чтения», локальный конфиг не читается (SETUP-2). Секретные, замаскированные и заданные извне (`config`, `env`) значения не редактируются. Пометка `(applies after restart)` ставится по `restartRequired`. Если значение перекрыто проектным слоем, баннер после записи предупреждает об этом, как на «Agents & modes» (D16 того change).
- **Мост `codelab_setup`** (ADDED): типизированные правила «можно ли править строку» (`settingEditRefusalOf`) переезжают из `apps/codelab_cli/lib/src/setup/settings_rows.dart` в мост. CLI переходит на них, тексты `/settings` не меняются (SETUP-8).
- **«Reopen the last project and its tabs»** — переключатель `codelab.workspace.reopen_last_project` (`shared_preferences`, по умолчанию включён: это текущее поведение). «Its tabs» в текущей сборке — открытые сессии снимка рабочего пространства. Выключенный переключатель: при следующем старте проект и сессии снимка не восстанавливаются, агент при запуске не стартует, app показывает сайдбар с недавними проектами и «Open folder…». Для этого ядро клиента получает `ClientWorkspace.startWithoutRestore()`: снимок пишется по ходу работы, но прошлый не восстанавливается.
- **«Show ignored files»** — строка той же настройки `codelab.file_browser.show_ignored` с тем же владельцем значения, что у переключателя панели Files. Ключ, порт и владельца вводит задача 3.4 change `add-file-preview-and-tree` (уточнена этим change). Строка появляется только после неё (SETUP-17).
- **«About»** — Fluent `Expander`:
  - `CodeLab <версия>`, ОС и архитектура, версия встроенного агента;
  - лицензия `MIT` со строкой авторского права из `LICENSE`;
  - папка конфигурации (`$CODELAB_HOME` с `~`);
  - кнопки «Copy diagnostics», «Third-party notices», «Release notes», «Open log folder»;
  - InfoBar `Updates come from the installer or your package manager — the app does not update itself.`

  Версию app даёт константа сборки, сверенная тестом с `pubspec.yaml`. Версию агента даёт `embeddedAgentVersion` из основного бареля `codelab_embedded`. Сторонние уведомления читаются офлайн из ресурсов app, ссылки открываются через существующие порты `ExternalLinkOpener` и `LocalFolderOpener`.
- **Локализация**: все новые тексты — ключи ARB `en` и `ru` по глоссарию `l10n-glossary.md` (spec app-settings «Локализация интерфейса app»). Подписи ключей реестра app переводит по ключу. Ключи конфигурации, значения и текст диагностики не переводятся.

## Не входит

- **«When I press Enter during a turn»** (`codelab.input.enter_while_running`, §12.3 A11). У строки нет поведения в этой сборке. Enter во время хода уже ставит сообщение в очередь (change `add-prompt-queue`). Второго действия нет: в клиентском ядре нет `SessionHandle.steer` и `PromptQueue.steer`, ACP-проекция агента не объявляет `_meta.codelab.steering` и не обрабатывает `_codelab/session/steer`. Это расширение «после MVP» (C-03, agent-core-architecture §17.7.6), и придумывать его поведение здесь нельзя (AGENTS.md §3.4). Строка с единственным вариантом «Queue the message» ничего бы не меняла, поэтому она скрыта (SETUP-17), а ключ не вводится (design.md, D8; решение пользователя Q1).
- **«Sidebar opens on»** (`codelab.sidebar.tab`): ключ убран change `add-file-preview-and-tree`.
- **«Send crash reports» и «Privacy policy»**: сознательно исключены. Отчётов о сбоях нет и не будет (E-21: телеметрии нет). `PRIVACY.md` в репозитории ещё нет (§12.7.7), а строк без поведения быть не должно (SETUP-17). Ссылку на политику добавит change, который введёт `PRIVACY.md`.
- **Канал сборки и «Signed by»** в «About»: в сборке нет ни признака канала, ни проверки подписи во время работы. Значения не выдумываются, строки скрыты (D11; решения пользователя Q3, Q4).
- **Имя и версия подключённого внешнего агента** в диагностике: `agentInfo` ответа `initialize` не выходит из `codelab_client_acp` в `ConnectionView` ядра клиента. Расширение ядра ради «About» в объём не входит.
- **Ключи с собственной страницей.** Режим, effort, модель, провайдеры, MCP, `permissions.deny` и `permissions.tools` остаются на своих страницах. На «General» нет строки, которая обошла бы подтверждение `bypass` или правила «Permissions & tools».
- **Цель «This project only»** для умолчаний агента: запись идёт только в `user` (D4; решение пользователя Q2).
- **Изменения ACP**: новых методов, полей и `_meta` нет.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `app-settings` — ADDED «Страница «General»: состав и порядок», «Умолчания агента на странице «General»: доступ и строки», «Умолчания агента на странице «General»: запись», «Открытие последнего проекта при запуске», «Показ игнорируемых файлов на странице «General»», «Раздел «About» страницы «General»», «Диагностика для отчёта без секретов и путей», «События журнала страницы «General»».
- `client-agent-setup` — ADDED «Правила правки строк настроек агента».
- `acp-client-kit` — ADDED «Старт без восстановления рабочего пространства».
- `embedded-agent` — ADDED «Версия встроенного агента для клиентов».
- `licensing-and-attribution` — ADDED «Лицензия и сторонние уведомления в сборке app».

## Impact

- **Код:**
  - `packages/dart/codelab_setup` — `lib/src/views/setting_edit_rules.dart` (`SettingEditRefusal`, `settingEditRefusalOf`, `settingKeyEditRefusalOf`), экспорт из основного бареля (`[agent]`);
  - `packages/dart/codelab_embedded` — экспорт `embeddedAgentVersion` из основного бареля (`[agent]`);
  - `apps/codelab_cli` — `settings_rows.dart` переходит на правила моста без изменения текстов (`[client]`);
  - `packages/dart/codelab_client_core` — `ClientWorkspace.startWithoutRestore()` и `WorkspaceRestorer` (`[client]`);
  - `apps/codelab_desktop`:
    - `features/settings/application/` — `AgentDefaultsCubit` и состояние, классификация ключей `agent_defaults_rows.dart`, `StartupSettingsCubit`, `about_diagnostics.dart`;
    - `features/settings/presentation/general_page.dart` — новые блоки; строка «Language» не меняется;
    - `core/platform/` — `startup_preferences.dart`, `build_info.dart`;
    - `features/workbench/application/settings_cubit.dart` — чтение `StartupPreferences` перед восстановлением;
    - `lib/app/` — сборка;
    - `assets/legal/` — копии `LICENSE` и `THIRD_PARTY_NOTICES.md`;
    - ARB `en`/`ru` (`[desktop]`).
- **Зависимости:** новых пакетов нет (`package_info_plus` не добавляется, D11). Allowlist ядра (PKG-2), `setupAllowlist` и `desktopAllowlist` не меняются. Новых пакетов и рёбер нет, граф `README.md` не меняется. Новое правило сторожа одно: `dart:ffi` в `apps/codelab_desktop/lib` — только в `lib/core/platform/build_info.dart` (D1).
- **ACP:** без изменений.
- **Данные пользователя:**
  - умолчания агента пишутся только в `$CODELAB_HOME/config.yaml` тем же писателем `ConfigWriter`, что у CLI и других страниц;
  - новый ключ `shared_preferences` — `codelab.workspace.reopen_last_project`;
  - формат снимка рабочего пространства не меняется.
- **Безопасность:**
  - на «General» нет строк режима разрешений, запретов и границы доверия;
  - секреты и замаскированные значения не редактируются;
  - для удалённого агента локальный конфиг не читается;
  - диагностика не содержит путей, URL, имён профилей, переменных окружения и значений конфигурации;
  - сторонние уведомления показываются из ресурсов сборки без сети.
- **Документы:**
  - `12-4-first-run-and-settings.md` §12.4.9 (строка экрана 26, подмножество строк, порядок блоков);
  - `12-3-desktop-display.md` A11 (строка Enter скрыта до C-03);
  - `apps/codelab_desktop/AGENTS.md` (раздел «Страница «General»»);
  - `packages/dart/codelab_setup/AGENTS.md`;
  - `apps/codelab_desktop/doc/user-guide.md`, `docs/user/configuration.md`;
  - документы change `add-file-preview-and-tree` (задача 3.4, владелец значения `show_ignored`; уточнены этим change).
