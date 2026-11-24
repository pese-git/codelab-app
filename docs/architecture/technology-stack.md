# Технологический стек CodeLab

Документ описывает утверждённый технологический стек CodeLab — клиентов (desktop, CLI), встроенного Dart-агента, общих пакетов и сайта, — назначение каждой технологии и правила её применения.

Документ задаёт **роль технологий и архитектурные ограничения**. Точные версии зависимостей он не определяет: версии, названные в разделах технологий (§17.1, §20а–§20и), — запись решения на момент утверждения; действующие версии — в источниках ниже.

Источники истины для версий:

* `.fvmrc` — версия Flutter SDK (FVM 3); `.fvm/fvm_config.json` — её копия для старых версий FVM, держится в синхроне (корневой `AGENTS.md` §4);
* `pubspec.yaml` — объявленные зависимости и ограничения версий;
* `pubspec.lock` — разрешённые версии зависимостей;
* секция `melos:` корневого `pubspec.yaml` — оркестрация monorepo (отдельного `melos.yaml` нет);
* `site/.nvmrc`, `site/package.json` и `site/package-lock.json` — версия Node и зависимости сайта `site/` (§28; вне pub workspace и Melos).

Цели:

* зафиксировать одно утверждённое решение для каждой задачи (управление состоянием, внедрение зависимостей, хранение, журналирование, генерация кода, тесты);
* не допускать конкурирующих framework-ов и второй технологии для той же задачи;
* задать для каждой технологии, где она МОЖЕТ и где НЕ ДОЛЖНА использоваться;
* дать порядок проверки и утверждения новой зависимости (§24–§27).

Общие правила — корневой `AGENTS.md` (§4, §5, §6, §8, §11, §13, §14, §15, §20), [`layers-and-dependencies.md`](layers-and-dependencies.md), [`state-management.md`](state-management.md), [`platform-integration.md`](platform-integration.md), [`error-handling.md`](error-handling.md), [`observability.md`](observability.md), [`testing.md`](testing.md). Решения: [ADR-0001](adr/0001-embed-dart-agent-core-behind-acp.md), [ADR-0002](adr/0002-name-packages-codelab-side-layer.md), [ADR-0003](adr/0003-build-project-site-with-astro-in-monorepo.md); реестр — [`adr/README.md`](adr/README.md). Allowlist зависимостей ядра агента (PKG-2) — [`proposals/agent-core/01-layers-and-packages.md`](proposals/agent-core/01-layers-and-packages.md) §1.2.

Термины:

* **Утверждённая технология** — библиотека или инструмент из таблицы §1 или из раздела §12–§28; для её задачи второе решение без архитектурного решения не добавляется (§1, §25).
* **Pub workspace** — общее разрешение зависимостей пакетов monorepo (`resolution: workspace`; §5).
* **Melos** — оркестрация команд по пакетам: скрипты секции `melos:` (§6).
* **FVM** — менеджер версии Flutter SDK проекта (§4).
* **Composition root** — место, где собираются конкретные реализации (§9.1, `layers-and-dependencies.md` §24).
* **Порт и адаптер** — узкий интерфейс приложения и его реализация поверх плагина или `dart:io` (§24).
* **Пин** — точная версия зависимости в `pubspec.yaml` без диапазона `^` (например, §17.1, §20г).
* **Транзитивная зависимость** — пакет, который приходит в `pubspec.lock` через другую зависимость, а не объявлен напрямую.
* **Сгенерированный код** — файлы, которые строит генератор (`build_runner`, `gen-l10n`, `tool/gen_prompts.dart`); вручную не правятся (§13).
* **Allowlist** — допустимые `dependencies` пакета, проверяемые сторожем.
* **Сторож** — тесты `packages/dart/codelab_architecture_tests` (`melos run guard`): правила импорта `test/support/rules.dart` и allowlist-ы `test/pubspec_allowlist_test.dart`.

Где в коде. Корневой `pubspec.yaml` — pub workspace (`workspace:`: три приложения `apps/*`, тринадцать пакетов `packages/dart/*` и `packages/flutter/codelab_ui`; у всех членов `resolution: workspace`), нижняя граница Dart SDK workspace в `environment`, `dev_dependencies` корня (`lints`, `melos`, `path`) и секция `melos:` со скриптами. Версия Flutter SDK — `.fvmrc` и копия `.fvm/fvm_config.json`; в CI её ставит составное действие `.github/actions/prepare/action.yml` (`fvm install`, ключ кэша от `.fvmrc` и `pubspec.lock`), оно же генерирует код (`build_runner`, §13). Разрешённые версии и итоговые ограничения SDK (секция `sdks`) — `pubspec.lock`. Зависимости каждого пакета — его `pubspec.yaml`. Правила анализатора — корневой `analysis_options.yaml` (`package:lints/recommended.yaml` и правила проекта) и `apps/codelab_desktop/analysis_options.yaml` (`package:flutter_lints/flutter.yaml`). Allowlist-ы сторожа — `packages/dart/codelab_architecture_tests/test/pubspec_allowlist_test.dart`: `coreAllowlist`, `ioAllowlist`, `acpAllowlist`, `mcpAllowlist` (агент), `binaryAllowlist` (`apps/codelab_agent`), `kitAllowlist` (`codelab_client_core`), `clientIoAllowlist`, `cliAllowlist`, `setupAllowlist`, `embeddedAllowlist`, `desktopAllowlist` (у `apps/codelab_desktop` — только пакеты `codelab_*`); правила импорта сторонних пакетов (например, `dart_tui`, `xterm2`, `pty2`, `file_selector`, `url_launcher`, `system_theme`, `desktop_drop`) — `test/support/rules.dart`. Сайт — `site/.nvmrc`, `site/package.json`, `site/package-lock.json`.

---

## 1. Общий стек

Проект использует:

| Область                    | Технология              |
| -------------------------- | ----------------------- |
| Язык                       | Dart (минимальный SDK workspace — 3.10: `WebSocketException.httpStatusCode`, change `add-app-settings-shell`, D12; для `codelab_ui` и `codelab_desktop` фактически Dart 3.12 и Flutter 3.44: этого требует зависимость `gpt_markdown`, а `environment` пакетов не поднимается, чтобы не менять версию языка; change `add-desktop-markdown`, D10) |
| UI                         | Flutter Desktop         |
| Дизайн-система             | Fluent UI (`fluent_ui`) |
| Управление состоянием      | `flutter_bloc`          |
| Внедрение зависимостей (DI) | Cherrypick             |
| Функциональные примитивы   | `fpdart`                |
| Неизменяемые и генерируемые модели | Freezed         |
| Генерация кода             | `build_runner`          |
| Системный диалог выбора папки | `file_selector`      |
| Локальное хранение         | `shared_preferences`    |
| Monorepo                   | Pub workspace + Melos   |
| Управление Flutter SDK     | FVM                     |
| Спецификации               | OpenSpec                |
| Тесты Flutter              | `flutter_test`          |
| Интеграционные тесты       | `integration_test`      |
| Правила линтера            | `flutter_lints`         |
| Терминальный UI (`codelab_cli`) | `dart_tui`         |
| Разбор аргументов CLI (`codelab_agent`, `codelab_cli`) | `args` |
| Чтение `config.yaml` и frontmatter агента (`codelab_agent_io`) | `yaml` |
| Правка `config.yaml` с сохранением комментариев (`codelab_agent_io`) | `yaml_edit` |
| Markdown ответа агента в ленте (`codelab_ui`, только `lib/src/rendering/`) | `gpt_markdown` (change [`add-desktop-markdown`](../../openspec/changes/archive/2026-11-11-add-desktop-markdown/design.md), D1; без Material-предка, свои builder-ы) |
| Подсветка кода (`codelab_ui`, только `lib/src/rendering/`) | `val_highlight` (change `add-desktop-markdown`, D4) |
| Открытие внешних ссылок (`codelab_desktop`, только `lib/core/platform/`) | `url_launcher` (change `add-desktop-markdown`, D5) |
| Системный цвет акцента (`codelab_desktop`, только `lib/core/platform/`) | `system_theme` (change [`add-app-appearance-page`](../../openspec/changes/archive/2026-11-20-add-app-appearance-page/design.md), D7; §20з) |
| Приём перетаскивания файлов и папок из ОС (`codelab_desktop`, только `lib/core/platform/os_drop_region.dart`) | `desktop_drop` (change [`add-empty-project-screen`](../../openspec/changes/archive/2026-11-22-add-empty-project-screen/design.md), D3; §20и) |
| Локализация интерфейса (`codelab_desktop`, `codelab_ui`) | `flutter_localizations`, `gen-l10n` (ARB), `intl` для сгенерированного кода (change [`add-desktop-localization`](../../openspec/changes/archive/2026-11-20-add-desktop-localization/design.md), D1; §20ж) |
| Сайт-визитка (`site/`, вне pub workspace и Melos) | Astro на Node, пакетный менеджер npm (ADR-0003, §28) |

Технологии из этой таблицы — **утверждённые решения проекта**.

НЕ СЛЕДУЕТ добавлять альтернативный framework для той же задачи без явной архитектурной причины.

В коде утверждённые разделами этого документа технологии шире таблицы: `path_provider` (§12.3), `structured_log`, `structured_log_flutter`, `structured_log_fluent`, `structured_log_remote_sync` (§17.1, §17.2), `xterm2`, `xterm2_core`, `pty2` (§20г, §20д). В `dependencies` пакетов есть и зависимости, не описанные ни в таблице, ни в разделах: `web_socket_channel` (WebSocket-транспорт `codelab_acp_transports`), `http` (ядро агента, `codelab_agent_mcp`, мосты `codelab_setup` и `codelab_embedded`, бинарь `codelab_agent`), `json_annotation` (`codelab_acp_protocol`; напрямую не импортируется — `@JsonKey` в восьми файлах протокола приходит через реэкспорт `freezed_annotation`), `json_serializable` (`dev_dependencies` того же пакета; не используется — файлов `*.g.dart` в пакете нет), а также служебные пакеты команды Dart `meta`, `path`, `async`, `collection`, `crypto`. Dart-пакеты и Dart-приложения подключают правила линтера `lints`, а не `flutter_lints` (§23). Нижняя граница Dart SDK различается по пакетам — см. `environment` их `pubspec.yaml`; итоговое ограничение workspace — секция `sdks` в `pubspec.lock`.

---

## 2. Dart

Основной язык проекта — Dart.

Допустимый диапазон SDK определяется `pubspec.yaml`.

Dart используется для:

* протокола ACP;
* транспортов;
* клиентской и прикладной логики;
* доменной логики;
* инфраструктуры;
* тестовых утилит;
* логики Flutter-приложения.

Если задача не требует Flutter API, СЛЕДУЕТ предпочитать реализацию на чистом Dart.

Особенно это важно для переиспользуемых пакетов.

В коде на чистом Dart — все пакеты `packages/dart/*` и приложения `apps/codelab_agent` и `apps/codelab_cli`; Flutter нужен только `apps/codelab_desktop` и `packages/flutter/codelab_ui`.

---

## 3. Flutter Desktop

Flutter используется для desktop-приложения и слоя представления.

Основное приложение:

`apps/codelab_desktop`

Код, зависящий от Flutter, СЛЕДУЕТ ограничивать слоями и пакетами, которым Flutter действительно нужен.

Пакеты на чистом Dart НЕ ДОЛЖНЫ получать зависимость от Flutter только ради:

* `BuildContext`;
* событий UI;
* вспомогательных удобств;
* слоя представления управления состоянием;
* диалогов;
* навигации.

Прикладное и доменное поведение СЛЕДУЕТ держать независимым от Flutter там, где это практически возможно.

---

## 4. FVM

Flutter SDK управляется через FVM.

Источник истины для фактически используемой версии:

`.fvmrc` (FVM 3); `.fvm/fvm_config.json` — копия для старых версий FVM, держится в синхроне с `.fvmrc`.

Команды Flutter и Dart ДОЛЖНЫ выполняться через FVM:

```bash
fvm flutter ...
fvm dart ...
```

НЕ СЛЕДУЕТ полагаться на глобально установленный Flutter SDK.

CI ДОЛЖЕН использовать ту же версию Flutter SDK, что задана конфигурацией FVM.

Ограничения SDK в `pubspec.yaml` определяют допустимые версии, но не заменяют FVM как механизм фиксации SDK для разработки.

В коде `.fvmrc` и `.fvm/fvm_config.json` сейчас указывают одну и ту же версию Flutter. CI ставит SDK командой `fvm install` в `.github/actions/prepare/action.yml`; ключ кэша SDK считается от `.fvmrc` и `pubspec.lock`. В git из каталога `.fvm/` отслеживается только `fvm_config.json` (`.gitignore`).

---

## 5. Pub workspace

Пакеты используют разрешение зависимостей pub workspace:

```yaml
resolution: workspace
```

Workspace отвечает за:

* общее разрешение зависимостей;
* работу локальных пакетов;
* согласованный граф зависимостей monorepo.

Pub workspace и Melos выполняют разные функции:

```text
Pub workspace
    └── разрешение зависимостей

Melos
    └── оркестрация команд репозитория
```

НЕ СЛЕДУЕТ использовать Melos как замену разрешению зависимостей workspace.

В коде члены workspace перечислены в `workspace:` корневого `pubspec.yaml`, у каждого из них в `pubspec.yaml` стоит `resolution: workspace`; у workspace один `pubspec.lock` — в корне (вне workspace есть ещё `apps/codelab_desktop/tool/terminal_spike/pubspec.lock` спайка терминала). `site/` в workspace не входит (§28).

---

## 6. Melos

Melos управляет операциями над всем репозиторием.

Основные задачи:

* bootstrap;
* форматирование;
* статический анализ;
* тесты;
* генерация кода;
* выполнение команд по пакетам.

Основные команды задаёт секция `melos:` корневого `pubspec.yaml`.

Типовые операции:

```bash
melos bootstrap
melos format
melos analyze
melos test
```

После изменения структуры пакетов или зависимостей СЛЕДУЕТ выполнить соответствующий bootstrap проекта.

Скрипты уровня репозитория СЛЕДУЕТ по возможности собирать в Melos, а не плодить отдельные shell-скрипты.

В коде скрипты Melos — `format`, `check-format`, `analyze`, `analyze:packages`, `test`, `test:dart`, `guard`, `prompts:check`, `l10n:check`, `web-compile`, `protocol-conformance`, `conformance:client`, `conformance:agent`, `conformance:embedded`, `test:e2e:*`, `build:agent`, `build:cli` и сводный `check` (состав `check` — `testing.md`, абзац «Где в коде»). Отдельного скрипта генерации кода нет: CI запускает `build_runner` через `melos exec --depends-on=build_runner` в `.github/actions/prepare/action.yml` (§13). Вспомогательные Dart-скрипты лежат в `tool/` (например, `tool/l10n_check.dart`, `tool/ci/affected.dart`).

---

## 7. Fluent UI

Основная UI- и дизайн-система проекта:

`fluent_ui`

Новые виджеты приложения СЛЕДУЕТ строить по Fluent UI, если конкретная задача не требует другого.

НЕ СЛЕДУЕТ вводить Material или Cupertino как параллельную дизайн-систему приложения.

Наличие:

```yaml
flutter:
  uses-material-design: true
```

само по себе не делает Material основной UI-системой проекта.

МОЖНО использовать инфраструктуру Flutter/Material, если её требуют сторонние пакеты или экосистема Flutter, но визуальная система приложения ДОЛЖНА оставаться согласованной.

Переиспользуемые Flutter-компоненты, специфичные для ACP, размещаются в:

`packages/flutter/codelab_ui`

В коде `fluent_ui` объявлен в `apps/codelab_desktop` и `codelab_ui`; `uses-material-design: true` стоит в `pubspec.yaml` обоих. Ни `lib/` desktop, ни `lib/` `codelab_ui` не импортирует `package:flutter/material.dart` и `package:flutter/cupertino.dart`; приложение строится на `FluentApp`. Транзитивные UI-пакеты `gpt_markdown` (`material_ui`, `cupertino_ui` и др.) в `codelab_ui` и app запрещает сторож (`_markdownTransitive` в `rules.dart`).

---

## 8. Управление состоянием

Основной framework управления состоянием:

`flutter_bloc`

BLoC/Cubit — утверждённый механизм управления состоянием приложения и представления во Flutter-слое.

НЕ СЛЕДУЕТ добавлять конкурирующие framework-и управления состоянием:

* Riverpod;
* Provider;
* GetX;
* MobX;
* Redux;
* другой аналогичный framework;

если существующая архитектура на BLoC решает задачу.

### 8.1. Ответственность BLoC/Cubit

BLoC/Cubit МОЖЕТ:

* принимать намерения пользователя;
* вызывать API приложения;
* координировать поток представления;
* преобразовывать состояние приложения в состояние представления;
* хранить состояние, значимое для UI;
* реагировать на события приложения.

BLoC/Cubit НЕ ДОЛЖЕН становиться местом для любой логики приложения.

В частности, он НЕ ДОЛЖЕН:

* реализовывать сериализацию и десериализацию ACP;
* реализовывать низкоуровневый транспорт;
* напрямую управлять сокетами и процессами;
* содержать платформенную реализацию работы с файловой системой;
* исполнять политику безопасности;
* самостоятельно реализовывать семантику протокола ACP.

Значимая переиспользуемая логика приложения ДОЛЖНА находиться ниже границы Flutter-представления.

В коде `flutter_bloc` импортирует только `apps/codelab_desktop`, и только в виде Cubit-ов (классов `extends Bloc` нет); `codelab_ui` объявляет `flutter_bloc` в `dependencies`, но не импортирует. Общее для app и CLI клиентское состояние держит `codelab_client_core` без `flutter_bloc` — Cubit-ы app его отображают (корневой `AGENTS.md` §5, `state-management.md`). `provider` есть в `pubspec.lock` только транзитивно — его тянет `flutter_bloc`; `bloc_concurrency` и `bloc_test` в репозитории нет.

---

## 9. Внедрение зависимостей — Cherrypick

Основной framework внедрения зависимостей (DI):

* `cherrypick`;
* `cherrypick_annotations`;
* `cherrypick_generator`.

Cherrypick — утверждённый механизм сборки зависимостей.

НЕ СЛЕДУЕТ добавлять параллельный DI-контейнер, например:

* `get_it`;
* `injectable`;
* другой service locator;
* собственный глобальный реестр зависимостей;

если Cherrypick уже покрывает задачу.

### 9.1. Composition root

Конкретные инфраструктурные зависимости ДОЛЖНЫ создаваться в ограниченном числе composition root.

Например:

```text
Запуск приложения
        │
        ▼
DI / сборка
        │
        ├── транспорты ACP
        ├── ACP-клиент
        ├── хранилища (repositories)
        ├── платформенные адаптеры
        └── зависимости BLoC
```

Виджеты НЕ ДОЛЖНЫ вручную создавать инфраструктурные зависимости.

### 9.2. DI — не архитектура

Наличие DI-контейнера не означает, что разрешена любая зависимость.

Cherrypick ДОЛЖЕН соединять компоненты по правилам зависимостей проекта, а не обходить их.

В коде Cherrypick подключён только в `apps/codelab_desktop` (`cherrypick`, `cherrypick_annotations` — `dependencies`, `cherrypick_generator` — `dev_dependencies`): root scope открывает `createCodeLabRootScope` (`lib/app/app_scope.dart`), модули — классы `Module` там же, сгенерированный `app_scope.module.cherrypick.g.dart` отслеживается в git. CLI (`apps/codelab_cli/lib/src/composition_root.dart`) и бинарь агента (`apps/codelab_agent`) собирают зависимости вручную, без DI-контейнера. `get_it` и `injectable` в репозитории нет. Как виджеты получают зависимости — `layers-and-dependencies.md` §23.

---

## 10. `fpdart`

Проект использует:

`fpdart`

`fpdart` — утверждённый набор примитивов функционального программирования.

Он МОЖЕТ использоваться для:

* `Either`;
* `Option`;
* типизированных результатов;
* композиции операций;
* явного представления ожидаемых сбоев.

СЛЕДУЕТ придерживаться существующего в проекте способа обработки ошибок.

НЕ СЛЕДУЕТ без необходимости смешивать несколько способов представления одной категории ошибок:

```text
Either<Failure, T>
Result<T>
nullable T
Exception
bool success
```

Ожидаемые сбои СЛЕДУЕТ представлять единообразно.

Исключения остаются допустимыми:

* на границах сторонних библиотек;
* для действительно исключительных ситуаций;
* для ошибок программирования;

но при переходе через границу приложения их СЛЕДУЕТ преобразовывать в утверждённую модель ошибок, когда это имеет смысл.

В коде `fpdart` объявлен в `dependencies` `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_acp_testing`, `codelab_client_acp` и `apps/codelab_desktop`, а импортирует его только `codelab_client_acp` (`lib/src/application/use_cases.dart`, `TaskEither<AcpClientApplicationFailure, T>`). Ядро агента `fpdart` не использует (allowlist PKG-2) и возвращает ожидаемые сбои собственным `Result<T, E>` (`packages/dart/codelab_agent_core/lib/src/util/result.dart`). Подробно — `error-handling.md` §7.

---

## 11. Freezed

Проект использует Freezed для генерируемых неизменяемых моделей там, где это оправдано.

Freezed подходит для:

* неизменяемого состояния;
* объединений (union) и представлений вида sealed;
* моделей приложения;
* моделей представления;
* типизированных автоматов состояний.

НЕ СЛЕДУЕТ применять Freezed автоматически к каждому DTO или простому value object.

Генерация кода ДОЛЖНА давать практическую пользу:

* неизменяемость;
* исчерпывающий перебор состояний;
* `copyWith`;
* равенство;
* меньше шаблонного кода.

Сгенерированные файлы НЕ ДОЛЖНЫ редактироваться вручную.

В коде `@freezed` используют `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_client_acp`, `codelab_client_core` и `codelab_ui` (`freezed_annotation` в `dependencies`, `freezed` и `build_runner` в `dev_dependencies`); у `apps/codelab_desktop` `freezed` есть только в `dev_dependencies`, своих `@freezed`-моделей нет. Файлы `*.freezed.dart` исключены из git (`.gitignore`) и генерируются шагом CI (§13); исключение — три файла `codelab_client_acp` (`domain/state_machines.freezed.dart`, `domain/domain_models.freezed.dart`, `application/application_models.freezed.dart`), которые отслеживаются в git, хотя `.gitignore` разрешает только первый из них.

---

## 12. Доступ к файлам платформы и локальное хранение

Технологии:

* `file_selector` — нативный системный диалог выбора папки или файла;
* `shared_preferences` — простое локальное хранилище «ключ — значение».

Обе введены в change `add-open-project-picker` ([`design.md`](../../openspec/changes/archive/2026-09-04-add-open-project-picker/design.md), Decisions 3–4) как единственные технологии для своих задач на момент введения.

### 12.1. `file_selector`

Официальный плагин команды Flutter, даёт нативный системный диалог выбора папки или файла (`NSOpenPanel` на macOS, common file dialog на Windows, GTK/portal на Linux).

МОЖЕТ использоваться:

* для выбора файлов и папок пользователем (например, папки проекта).

НЕ ДОЛЖЕН использоваться:

* для программного чтения и записи файлов (это ответственность `dart:io` и обработки `fs/*` в `codelab_client_acp`) — `file_selector` отвечает только за UI-диалог выбора пути, а не за файловый ввод-вывод.

Изолируется за узким портом приложения (например, `ProjectFolderPicker`) в `apps/codelab_desktop/lib/core/platform/` — виджеты и domain НЕ ДОЛЖНЫ импортировать `file_selector` напрямую (корневой `AGENTS.md` §11).

В коде `package:file_selector/` импортируют только четыре адаптера `lib/core/platform/`: `project_folder_picker.dart`, `theme_file_picker.dart`, `protocol_export_saver.dart`, `usage_csv_saver.dart`; остальной `lib` app его не импортирует — правило сторожа.

### 12.2. `shared_preferences`

Официальный плагин команды Flutter для простого хранилища «ключ — значение», которое переживает перезапуск приложения. Первая технология хранения в проекте.

МОЖЕТ использоваться:

* для небольших настроек самого app, не критичных для целостности данных (например, раскладка дока, язык, оформление, снимок рабочего места), — не для состояния сессий и домена и не для секретов и токенов.

НЕ ДОЛЖЕН использоваться:

* как замена структурированному хранилищу (SQL/NoSQL) для больших или реляционных данных — при такой потребности требуется отдельный ADR (§26);
* для секретов и токенов (корневой `AGENTS.md` §10 — «Secrets и tokens НЕ ДОЛЖНЫ хардкодиться или попадать в logs»);
* для данных, общих с `codelab` (CLI): они лежат JSON-файлами в `$CODELAB_HOME` через хранилища `codelab_client_io` (§17б) — профили подключения `profiles.json` (change `add-app-settings-shell`, D7) и недавние проекты `recent_projects.json` (change `share-recent-projects-store`, D1). Домен `shared_preferences` привязан к идентификатору бандла app, и CLI его не видит.

Изолируется за портом приложения (например, `StartupPreferences`, `DockLayoutStore`) в `apps/codelab_desktop/lib/core/platform/` — по тому же образцу, что `WorkingDirectoryProvider`.

Вторая технология хранения (SQL, NoSQL, новое файловое хранилище и т. п.) для той же категории задач требует ADR (§26). JSON-файлы `$CODELAB_HOME` второй технологией не считаются: это уже принятый способ хранения общих с CLI данных (§17б), а не замена `shared_preferences` для настроек app.

В коде `package:shared_preferences/` импортируют адаптеры `lib/core/platform/` (`startup_preferences.dart`, `dock_layout_store.dart`, `app_language_preferences.dart`, `app_appearance_preferences.dart`, `connection_preferences.dart`, `onboarding_preferences.dart`, `shared_preferences_workspace_snapshot_store.dart`, `recent_projects_migration.dart`) и, вне `core/platform/`, `lib/app/navigation/settings_page_store.dart`. Правила сторожа для `shared_preferences` нет. Порт `WorkingDirectoryProvider` и его адаптер `IoWorkingDirectoryProvider` теперь живут в `codelab_client_io` (`lib/src/platform/working_directory_provider.dart`).

### 12.3. `path_provider`

Официальный плагин команды Flutter, даёт корректный для ОС путь к каталогу application support (`~/Library/Application Support/...` на macOS, на основе `%APPDATA%` на Windows, на основе XDG на Linux). Введён в change `add-structured-logging` ([`design.md`](../../openspec/changes/archive/2026-10-08-add-structured-logging/design.md)); единственный потребитель на момент введения — файловые sinks журнала (журнал приложения в release, трасса протокола), которые настраивает `CodeLabLoggingModule`; путь нужен до сборки root scope (`createCodeLabRootScope`).

МОЖЕТ использоваться:

* только для получения путей каталогов платформы, а не для файлового ввода-вывода (его выполняют `dart:io` и файловые выводы `structured_log`).

Путь резолвится асинхронно в `main()` до `runApp()` (вызов platform channel, требует `WidgetsFlutterBinding.ensureInitialized()`) и передаётся вниз простой строкой `String`, а не прямой зависимостью виджетов или domain от `path_provider` — по корневому `AGENTS.md` §11.

В коде `package:path_provider/` импортирует только `apps/codelab_desktop/lib/main.dart`: `main()` получает каталог через `getApplicationSupportDirectory()` и передаёт путь `logs/` по цепочке `CodeLabBootstrap(logDirectoryPath:)` → `_CodeLabBootstrapState` (`lib/app/app_scope.dart`) → `createCodeLabRootScope(logDirectoryPath:)` → `CodeLabLoggingModule`.

---

## 13. Генерация кода

Основной набор генерации кода:

* `build_runner`;
* `freezed`;
* `cherrypick_generator`.

Генерацию кода СЛЕДУЕТ запускать стандартной командой репозитория, предпочтительно через Melos.

Сгенерированный результат ДОЛЖЕН воспроизводиться из исходных файлов.

AI-агент НЕ ДОЛЖЕН вручную исправлять сгенерированные Dart-файлы вместо изменения их исходных определений.

При изменении определения генерируемой модели или DI агент ДОЛЖЕН определить, нужен ли повторный запуск генератора.

В коде `build_runner` объявлен в `dev_dependencies` `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_client_acp`, `codelab_client_core`, `codelab_ui` и `apps/codelab_desktop`. Скрипта Melos для генерации нет: CI выполняет `fvm dart run melos exec -c 1 --depends-on=build_runner -- "fvm dart run build_runner build --delete-conflicting-outputs"` (`.github/actions/prepare/action.yml`), потому что `*.freezed.dart` в git нет. Есть и два генератора вне `build_runner`, их результат коммитится и сверяется скриптами Melos: константы промптов ядра агента `prompts.g.dart` — `tool/gen_prompts.dart` пакета `codelab_agent_core` (`prompts:check`), классы локализации — `fvm flutter gen-l10n` (`l10n:check`, §20ж).

---

## 14. Пакеты ACP

Функциональность ACP разделена на специализированные пакеты:

```text
packages/
├── dart/
│   ├── codelab_acp_protocol/
│   ├── codelab_acp_transports/
│   ├── codelab_client_acp/
│   ├── codelab_client_core/
│   ├── codelab_client_io/
│   └── codelab_acp_testing/
│
└── flutter/
    └── codelab_ui/
```

Это разделение — архитектурная граница, а не только организация файлов.

В коде на схеме — клиентская сторона и общий протокольный слой. Кроме них в `packages/dart/` лежат пакеты агентской стороны (`codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `codelab_agent_mcp`), мосты `codelab_setup` и `codelab_embedded` и сторож `codelab_architecture_tests`; полный перечень и назначение — корневой `AGENTS.md` §5, границы — `layers-and-dependencies.md`.

---

## 15. `codelab_acp_protocol`

Пакет:

`packages/dart/codelab_acp_protocol`

Тип: **чистый Dart**.

Отвечает за ACP на уровне wire.

Допустимая ответственность:

* сообщения протокола;
* модели запросов и ответов;
* уведомления;
* идентификаторы;
* сериализация протокола;
* десериализация протокола;
* валидация на уровне протокола;
* ошибки протокола;
* совместимость версий протокола.

НЕ ДОЛЖЕН зависеть от:

* Flutter;
* `flutter_bloc`;
* `fluent_ui`;
* `codelab_ui`;
* виджетов приложения;
* навигации;
* диалогов.

`codelab_acp_protocol` описывает wire-контракт ACP, а не модель представления приложения.

В коде `dependencies` пакета — `fpdart`, `freezed_annotation`, `json_annotation`, `meta`; пакетов `codelab_*` среди них нет.

---

## 16. `codelab_acp_transports`

Пакет:

`packages/dart/codelab_acp_transports`

Тип: **чистый Dart**, пока реализация транспорта не потребует иного архитектурного решения.

Отвечает за взаимодействие на уровне транспорта.

Например:

* транспорт через stdio процесса;
* транспорт поверх потоков;
* сетевой транспорт через сокеты;
* примитивы соединения;
* ошибки транспорта;
* фрейминг, если он — ответственность транспорта.

Транспорт НЕ ДОЛЖЕН:

* зависеть от Flutter-представления;
* показывать диалоги;
* управлять навигацией;
* содержать BLoC;
* принимать UX-решения.

Транспорт ДОЛЖЕН давать API, пригодный для клиентского слоя на чистом Dart.

В коде основной барель пакета web-безопасен, IO-транспорты (`StdioAcpTransport`, `WebSocketAcpTransport`) — в `package:codelab_acp_transports/io.dart` (корневой `AGENTS.md` §5); WebSocket построен на `web_socket_channel`.

---

## 17. `codelab_client_acp`

Пакет:

`packages/dart/codelab_client_acp`

Тип: **чистый Dart**.

Содержит переиспользуемую клиентскую прикладную логику ACP.

Предполагаемая ответственность:

* оркестрация ACP-клиента;
* поведение сессий;
* события ACP уровня приложения;
* жизненный цикл запросов;
* отмена;
* абстракции разрешений;
* координация соединения и сессий;
* преобразование событий протокола в понятия уровня клиента.

`codelab_client_acp` НЕ ДОЛЖЕН зависеть от:

* Flutter;
* виджетов;
* `BuildContext`;
* `fluent_ui`;
* `flutter_bloc`;
* `codelab_ui`.

Если поведение можно реализовать без Flutter и оно общее для ACP-клиента, СЛЕДУЕТ сначала рассмотреть размещение в `codelab_client_acp`, а не в `codelab_desktop`.

При этом `codelab_client_acp` НЕ ДОЛЖЕН превращаться в свалку любой прикладной логики.

Логика клиента, общая для app и CLI, но выше протокольного ядра (рабочее пространство, очередь промптов, проекция транскрипта, одобрения, опции, инспектор), — в `codelab_client_core` (§17а).

### 17.1. Структурированное журналирование — `structured_log`

Технология: [`structured_log`](https://pub.dev/packages/structured_log) — библиотека структурированного журналирования на чистом Dart (вывод JSON, связывание контекста, конвейер процессоров, маршрутизация в несколько sinks, типизированные поля корреляции).

Введена в change `add-structured-logging` ([`design.md`](../../openspec/changes/archive/2026-10-08-add-structured-logging/design.md)) как единственная технология журналирования проекта — заменяет разрозненные `print`/`debugPrint` и служит основой для существующего потока `DiagnosticEntry` `codelab_client_acp`.

Версия на момент введения: `0.2.0-dev.4` (prerelease, `-dev`) — пин точной версии в `pubspec.yaml`, без диапазона `^`. С тех пор пакет дошёл до стабильных выпусков; пин поднят до `0.3.1` — этого требуют актуальные `structured_log_flutter 0.1.3`, `structured_log_fluent 0.1.2+2` (в них исправлены переполнение `LogViewerEmptyState` в узкой пристыкованной панели и горизонтальное переполнение узкой панели инструментов `FluentLogViewer`) и `structured_log_remote_sync 0.2.1` (§17.2). Миграция `0.2 → 0.3` (раздел «Migrating to 0.3.0» в README пакета) для CodeLab свелась к одному: файловые выводы (`AsyncFileOutput`, `AsyncRotatingFileOutput`) переехали в `package:structured_log/io.dart`; временные метки теперь в UTC (`...Z`) — ни наши тесты, ни потребители от формата не зависят.

Зависимость подключена **только** в `codelab_client_acp` (единственный владелец порта `Logger` и адаптера на `structured_log`) и `codelab_desktop` (composition root, конкретная настройка sinks). `codelab_acp_protocol` и `codelab_acp_transports` эту зависимость не получают — о своих событиях они сообщают уже существующими типизированными ошибками и `AcpTransportEvent.diagnostic`, которые `codelab_client_acp` переводит в структурированные события с сохранением контекста корреляции (`design.md`, Decision 1).

Настройка (sinks, процессоры) идёт через глобальные `StructlogConfiguration.configure()`/`getLogger()` пакета — осознанное исключение из общего запрета на глобальный service locator (`layers-and-dependencies.md` §23); обоснование — `design.md`, Decision 7.

В коде, кроме этих двух пакетов, `structured_log` не объявлен нигде; ядро агента и CLI пишут журнал через собственные порты (`observability.md`, абзац «Где в коде»). В `apps/codelab_desktop` `package:structured_log/` импортируют composition root `lib/app/app_scope.dart` (также `package:structured_log/io.dart`) и, ради типа `LogLevel`, файлы панели Protocol: `lib/features/protocol/application/log_record_filter.dart`, `application/protocol_pane_cubit.dart`, `presentation/protocol_pane.dart`. `lib/app/log_buffer_record_source.dart` импортирует `structured_log_flutter`, окно журнала `lib/features/workbench/presentation/widgets/debug_log_viewer_dialog.dart` — `structured_log_flutter` и `structured_log_fluent`.

### 17.2. Локальная пересылка логов на dev-сервер — `structured_log_remote_sync`

Технология: [`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync) — `OutputFunction` с пакетной отправкой и повторами (`RemoteSyncLogOutput`), который пересылает записи по HTTP (`POST /v1/logs`) в `structured_log_server` для просмотра в `structured_log_admin_ui`. Версия: `0.2.1`, точный пин. Пакет — переименованный `structured_log_http` (тот больше не развивается и лишь перенаправляет на `remote_sync`); при переименовании изменились только имена пакета и класса, API (`serverUrl`, `projectSecretKey`, `sender`, `close()`) остался прежним.

**Только для локальной разработки самого CodeLab, не функция для пользователя.** `CodeLabLoggingModule` (`apps/codelab_desktop/lib/app/app_scope.dart`) создаёт `RemoteSyncLogOutput`, только если ОБЕ константы времени компиляции `CODELAB_LOG_SERVER_URL` и `CODELAB_LOG_SERVER_KEY` (`String.fromEnvironment`, передаются через `--dart-define` при `flutter run`) непустые; по умолчанию (без `--dart-define`) sink не создаётся вовсе — нулевая стоимость и нулевой риск. `projectSecretKey` — секрет; он НЕ ДОЛЖЕН попадать в репозиторий (`.env` или shell-профиль разработчика, а не файл в git) — корневой `AGENTS.md` §10.

Sink получает те же события `category=application`, что идут в консоль и файл, — отдельной категории нет. Он передаётся необязательным параметром `httpOutput` функции `configureCodeLabLogging()` (`packages/dart/codelab_client_acp/lib/src/infrastructure/structured_log_logger.dart`) — `codelab_client_acp` не получает зависимость от `structured_log_remote_sync` (только от типа `OutputFunction` из `structured_log`), пакет подключён исключительно в `codelab_desktop` — по тому же образцу, что `structured_log_flutter` и `structured_log_fluent` (Decision 1 [`replace-debug-log-panel-with-fluent/design.md`](../../openspec/changes/archive/2026-10-08-replace-debug-log-panel-with-fluent/design.md)). `CodeLabLoggingLifecycle.dispose()` закрывает `RemoteSyncLogOutput` (сбрасывает буфер) наравне с остальными sinks.

---

## 17а. `codelab_client_core`

Пакет: `packages/dart/codelab_client_core`. Тип: **чистый Dart**, web-безопасный (без `dart:io`).

Общий клиентский слой без UI для `codelab_desktop` и `codelab_cli` (change `extract-acp-client-kit`): `ClientWorkspace` и `SessionHandle`, явный автомат `ConnectionView`, профили подключения и `TransportResolver`, `SecretSource`, инкрементальная проекция транскрипта, `PromptQueue`, представления опций, команд и одобрений, `InspectorProjection`, `WorkspaceDiagnostic` и `describeFailure`, порты хранилищ (`ProfileStore`, `RecentProjectsStore`). Источник данных — порт `AgentBackend`, реализация `AcpClientBackend` поверх `AcpClientApplication` из `codelab_client_acp`.

Зависит только от `codelab_client_acp`, `codelab_acp_protocol`, `codelab_acp_transports` (без `io.dart`), `freezed_annotation` и `meta`; Flutter и `dart:io` запрещены сторожем (`melos run guard`). Правила — во вложенном `AGENTS.md` пакета.

В коде `kitAllowlist` сторожа шире фактических зависимостей: кроме перечисленных он допускает `collection` и `async`.

## 17б. `codelab_client_io`

Пакет: `packages/dart/codelab_client_io`. Тип: **чистый Dart** с `dart:io`, без Flutter.

`dart:io`-адаптеры портов клиента для хостов на Dart VM и desktop: `IoTextFileIo`, `IoTerminalProcessRunner`, `IoWorkingDirectoryProvider`, `ioTransportResolver` с настоящими stdio- и WebSocket-транспортами, `JsonFileProfileStore` и `JsonFileRecentProjectsStore` — общие файлы `$CODELAB_HOME/profiles.json` и `$CODELAB_HOME/recent_projects.json`, которые пишут и app, и CLI (changes `add-app-settings-shell`, D7; `share-recent-projects-store`, D1). Flutter-плагины (`file_selector`, `shared_preferences`) остаются в `codelab_desktop`. Правила — во вложенном `AGENTS.md` пакета.

---

## 18. `codelab_ui`

Пакет:

`packages/flutter/codelab_ui`

Тип: **Flutter-пакет**.

Отвечает за переиспользуемые компоненты представления, специфичные для ACP.

Утверждённый стек:

* Flutter;
* `fluent_ui`;
* `flutter_bloc`.

МОЖЕТ содержать:

* переиспользуемые ACP-виджеты;
* компоненты представления ACP;
* модели представления;
* переиспользуемый UI, знающий о BLoC;
* общие визуальные состояния ACP.

НЕ ДОЛЖЕН:

* реализовывать транспорт ACP;
* владеть низкоуровневым соединением;
* зависеть от `codelab_desktop`;
* содержать сборку, специфичную для desktop-приложения;
* реализовывать платформенную инфраструктуру без явной необходимости.

`codelab_ui` ДОЛЖЕН оставаться переиспользуемой Flutter-границей.

В коде `dependencies` пакета — `fluent_ui`, `flutter_bloc`, `flutter_localizations`, `intl`, `freezed_annotation`, `gpt_markdown`, `val_highlight`; пакетов `codelab_*` нет. `flutter_bloc` объявлен, но не импортируется (§8). Своего `analysis_options.yaml` у пакета нет, поэтому к нему применяется корневой (`lints`), хотя `flutter_lints` есть в его `dev_dependencies` (§23).

---

## 19. `codelab_acp_testing`

Пакет:

`packages/dart/codelab_acp_testing`

Предназначен для переиспользуемой тестовой инфраструктуры ACP.

МОЖЕТ содержать:

* fakes;
* фикстуры;
* построители тестовых данных;
* поддельные транспорты;
* помощники протокольных тестов;
* переиспользуемые тестовые сценарии.

Рабочие пакеты НЕ ДОЛЖНЫ зависеть от `codelab_acp_testing`.

`codelab_acp_testing` СЛЕДУЕТ сохранять на чистом Dart, если зависимость от Flutter не необходима.

Тестовые помощники для Flutter при значительном объёме СЛЕДУЕТ отделять от тестовых утилит на чистом Dart.

В коде пакет на чистом Dart без Flutter, но не web-безопасен (загрузчик фикстур использует `dart:io`); его подключают в `dev_dependencies`, кроме `apps/codelab_cli`, где он — обычная зависимость для `test-scenario` с импортом только из `lib/src/scenario/` (корневой `AGENTS.md` §5; `testing.md` §6, §7).

---

## 20. `codelab_desktop`

Приложение:

`apps/codelab_desktop`

— desktop composition root и конечное приложение.

Оно объединяет:

* пакеты ACP;
* Flutter UI;
* управление состоянием;
* DI;
* интеграцию с desktop;
* функции, специфичные для приложения.

`codelab_desktop` МОЖЕТ зависеть от:

* `codelab_client_core`;
* `codelab_client_io`;
* `codelab_client_acp`;
* `codelab_acp_protocol`;
* `codelab_acp_transports`;
* `codelab_ui`;
* утверждённых зависимостей Flutter и приложения.

Однако наличие прямой зависимости не означает, что любой слой приложения может использовать пакет напрямую.

Например, виджет НЕ ДОЛЖЕН обращаться к `codelab_acp_transports` только потому, что пакет объявлен в `codelab_desktop/pubspec.yaml`.

Архитектурные правила зависимостей важнее технической доступности зависимости.

В коде у `apps/codelab_desktop` в `dependencies` есть и мосты `codelab_embedded` и `codelab_setup`: через них app получает встроенного агента и настройки агента (корневой `AGENTS.md` §5); пакеты `codelab_*` app проверяет `desktopAllowlist` сторожа, и он содержит оба моста.

---

## 20а. `codelab_cli`: терминальный UI — `dart_tui`

Технология: [`dart_tui`](https://pub.dev/packages/dart_tui) ([репозиторий](https://github.com/codenameakshay/dart_tui)) — каркас терминального UI на чистом Dart в духе Elm и Bubble Tea: `Model` с `init()`, `update(Msg)` и `view()` (возвращает `View`), асинхронные команды `Cmd` (функция, которая доставляет одно сообщение; помощники `tick`, `every`, `batch`, `sequence`, `execProcess`), `Program(options: [...]).run(model)` — владелец цикла событий, raw-режима, альтернативного экрана, рендера (построчный diff, synchronized output `?2026` при поддержке терминала, не чаще `withFps`, по умолчанию 60 кадров в секунду) и сигналов. В пакете 27+ компонентов (spinner, viewport, список с фильтром, select list, help, text area и др.) и стили в духе Lipgloss.

Решение принято владельцем продукта для полноэкранного режима нового приложения `apps/codelab_cli` (терминальный ACP-клиент `codelab`, план — [`proposals/dart-agent-and-clients.md`](proposals/dart-agent-and-clients.md), этап 6). Архитектура TUI поверх пакета — [§12.2.7](proposals/dart-agent-and-clients/12-2-cli-display-and-input.md), обоснование и риски — §12.2.12 того же раздела.

1. **Назначение.** Терминальный слой и цикл Model–Update–View полноэкранного режима `codelab --ui tui`: ввод клавиш (kitty keyboard protocol, xterm modifyOtherKeys, bracketed paste), мышь, размер окна, вывод кадров, восстановление терминала при выходе.
2. **Где используется.** Только полноэкранный режим `--ui tui`, только код `apps/codelab_cli/lib/src/tui/`, а внутри него — только адаптер (`TuiApp`, `TuiInput`, `TuiEffects`, `RegistryKeyMap`, `TuiCommandContext`, `TuiRunner`); чистое ядро экрана `lib/src/tui/core/` (`TuiModel`, `reduce`, `render`) не импортирует ни пакет, ни `dart:io` — второе правило сторожа. Компоненты пакета в адаптере: `SpinnerModel`, `ListModel`, `HelpModel` (design.md change `add-cli-tui`, D12).
3. **Где не используется.** Построчный REPL и headless (`-p`, `stream-json`; proposals §12.2.1) пишут в stdout сами и пакет не используют. `codelab_client_core`, `codelab_client_acp`, `codelab_client_io`, пакеты агента и `codelab_desktop` от него не зависят. Компоненты-редакторы пакета (`TextAreaModel`, `TextInputModel`) и стили `Style` для markdown не используются: у CLI свой композер с реестром клавиш и свой ANSI-рендер markdown, общий с REPL.
4. **Какую проблему решает.** Не писать и не сопровождать свой терминальный слой (raw-режим через termios и консоль Windows, построчный diff кадра, декодер kitty и modifyOtherKeys, bracketed paste, мышь, сигналы и восстановление терминала) и получить поддерживаемые компоненты (список с фильтром, viewport, spinner, help) в той же архитектуре Model–Update–View, что задумана для TUI.
5. **Влияние на архитектурные границы.** `package:dart_tui/` импортируется только из `apps/codelab_cli/lib/src/tui/**`; остальной CLI и kit о нём не знают — правило сторожа импортов (proposals §9.5, `PackageRule` над `apps/codelab_cli/lib/src` с `exclude: ['tui/']`). Модель отображения kit (`SessionView`) остаётся источником состояния; пакет её не заменяет и не дублирует.
6. **Заменяет ли существующую технологию.** Нет. Заменяет только запланированный в proposals собственный рендер TUI (прежний вариант §12.2.7); кода TUI тогда ещё не было.
7. **Требуется ли миграция.** Нет: заменять нечего.
8. **Требуется ли ADR.** Нет. Технология затрагивает только представление нового приложения и не меняет архитектуру ACP-клиента, управление состоянием `codelab_desktop` и границы пакетов (§26). Решение фиксируется в proposals §12.2.12 и в `design.md` OpenSpec change `add-cli-tui` вместе с итогом разведки (задача 6.11, D14: пакет подтверждён).

Проверка по §25:

* **Существующие зависимости и SDK.** Ни одна утверждённая технология не решает задачу терминального UI; `flutter_bloc` и `fluent_ui` — Flutter и к CLI неприменимы. Средствами `dart:io` задача решается только своим терминальным слоем — от него и отказались.
* **Конкурирующий framework.** Нет: управление состоянием `codelab_desktop` (`flutter_bloc`) не затрагивается; MVU пакета живёт только внутри CLI и только в представлении.
* **Desktop-платформы.** Заявлены Linux, macOS и Windows (на pub.dev также Android и iOS — для CLI не важны). На Windows по исходникам 3.0.0 включается ввод VT (`SetConsoleMode`); вывод VT, размер окна и conhost не подтверждены — пункт чек-листа разведки; до подтверждения на Windows остаётся построчный REPL.
* **Ограничения SDK.** Пакет требует Dart `>=3.5.0 <4.0.0`; диапазон `apps/codelab_cli` (`>=3.8.0 <4.0.0`) в него входит.
* **Нативная настройка.** Отдельной нет, но пакет использует `dart:ffi` (termios libc на macOS и Linux, kernel32 на Windows) и зависит от `ffi`; прочие зависимости — `characters`, `path`. AOT-сборка `dart compile exe` это поддерживает; веб-сборка CLI не нужна.
* **Тестирование.** Специального тестового стенда у пакета нет. Чистые `reduce`/`render` тестируются без пакета; адаптер — через опции `withInput` (поток байт вместо stdin), `withOutput` (свой `IOSink`), `withWindowSize`, `withoutSignalHandler`; PTY-e2e CLI не меняются.
* **Безопасность.** Raw-режим и управляющие последовательности: пакет пишет содержимое `View` в терминал без фильтрации, поэтому текст из LLM и инструментов (недоверенный) проходит санитизацию нашим рендером до попадания в `View` — вырезаются C0 (кроме `\t` и `\n`), DEL и C1, в том числе `ESC`; OSC 8 — только для `http`, `https`, `file` (proposals §12.2.11, TUI-10, TUI-11). Восстановление терминала при исключении и сигнале — `Program` пакета и наш `TuiRunner` (TUI-4). Сеть, файлы и секреты пакет не трогает.
* **Лицензия и сопровождение.** MIT (совместима, proposals §7а); verified publisher `hashstudios.dev`. На 2026-10-22: 3.0.0 от 2026-10-17, мажорные версии 2.0 и 3.0 вышли с заметками о миграции, 4 лайка, 160 pub points, около 8,4 тыс. загрузок. Пакет молодой — риск и меры в proposals §10 и §12.2.12.

Версия: диапазон — в `apps/codelab_cli/pubspec.yaml`, точная — в `pubspec.lock`. Переход на новую мажорную версию — отдельный PR с прогоном PTY-тестов и чек-листа разведки (proposals §12.2.7).

---

## 20б. Разбор аргументов командной строки — `args`

Технология: [`args`](https://pub.dev/packages/args) — пакет команды Dart (publisher `dart.dev`) для разбора аргументов командной строки: `ArgParser` с флагами, опциями, повторяемыми опциями, подкомандами, скрытыми опциями и генерацией справки.

Решение принято владельцем продукта для бинаря агента `apps/codelab_agent` (`codelab-agent serve`, OpenSpec change `add-codelab-agent-binary`, design.md D1); тот же пакет использует CLI `codelab` с этапа 6.

1. **Назначение.** Синтаксис аргументов: команда `serve`, флаги `--stdio`/`--ws`, повторяемый `--model`, скрытый `--llm-script`, справка, ошибка неизвестного флага. Правила конфигурации поверх разбора (переменная окружения как значение по умолчанию, флаг сильнее переменной, взаимоисключения, код выхода `64`) — код приложения (документ ядра §15.6).
2. **Где используется.** Только точки входа приложений: `apps/codelab_agent/lib/src/cli/`, с этапа 6 — `apps/codelab_cli`.
3. **Где не используется.** Пакеты `packages/*` (ядро, ACP, транспорты, клиентский слой): они не разбирают аргументы процесса. `codelab_desktop` — Flutter-приложение без аргументов командной строки.
4. **Какую проблему решает.** Не писать и не сопровождать свой разборщик аргументов со справкой и ошибками и не расходиться с будущим CLI `codelab` с подкомандами.
5. **Влияние на архитектурные границы.** Нет: пакет — чистый Dart без IO; allowlist зависимостей `apps/codelab_agent` в `pubspec_allowlist_test.dart` содержит `args`.
6. **Заменяет ли существующую технологию.** Нет; до этого аргументы процесса в репозитории не разбирали.
7. **Требуется ли миграция.** Нет.
8. **Требуется ли ADR.** Нет: технология не меняет архитектуру и не затрагивает границы пакетов (§26).

Проверка по §25: средствами SDK задача решается только своим разборщиком; конкурирующего framework нет; пакет на чистом Dart (Linux, macOS, Windows, AOT `dart compile exe`), SDK `>=3.3`; нативной настройки нет; тестируется вызовом разбора без процесса (`serve_flags_test.dart`); безопасность — пакет не читает окружение и файлы, значения флагов в справку не попадают; лицензия BSD-3-Clause, сопровождает команда Dart. До решения пакет уже был транзитивной зависимостью workspace.

Версия: диапазон — в `pubspec.yaml` `apps/codelab_agent` и `apps/codelab_cli`, точная — в `pubspec.lock`.

В коде `package:args/` импортируют `apps/codelab_agent/lib/src/cli/` (подкоманды `serve`, `config`, `provider`, `mcp`, `secret`), `apps/codelab_agent/lib/src/run.dart` и `apps/codelab_cli/lib/src/cli_args.dart`; `args` есть в `binaryAllowlist` и `cliAllowlist` сторожа.

---

## 20в. Конфигурация агента — `yaml` и `yaml_edit`; TOML не используется

Единственный формат конфигурации Dart-агента — YAML 1.2 в строгом профиле (`config.yaml`; `docs/architecture/proposals/agent-core/15-configuration.md` §15.1, §15.5). Две технологии, обе в `codelab_agent_io`:

| Технология | Назначение | Где используется |
|---|---|---|
| [`yaml`](https://pub.dev/packages/yaml) (publisher `dart.dev`) | чтение YAML с позициями узлов: файл, строка и столбец в сообщениях об ошибках; тот же разборщик читает frontmatter определений агентов и skills | `codelab_agent_io`: `ConfigLoader`, `yaml_reader`, загрузчик файлов проекта |
| [`yaml_edit`](https://pub.dev/packages/yaml_edit) (publisher `dart.dev`) | запись конфига с сохранением комментариев, порядка и стиля ключей | `codelab_agent_io`: `ConfigWriter` (`codelab config set/unset`, `provider add`, страницы настроек) |

1. **Назначение.** `yaml` даёт ошибкам конфигурации точное место в файле; `yaml_edit` позволяет командам и страницам настроек менять одну запись, не переписывая файл пользователя целиком.
2. **Где не используются.** `codelab_agent_core` YAML не читает и разборщиков не импортирует (CFG-5): схема и валидатор — чистая функция ядра `CoreConfig.fromLayers` над уже разобранным деревом, поэтому ядро остаётся web-безопасным с зависимостями `http`, `meta`, `collection`, `async`, `crypto`. Клиенты получают чтение и запись конфига через мост `codelab_setup`, а не через прямую зависимость.
3. **`toml` не используется.** `codelab.toml` Python-агента Dart-агент не читает и не переводит (решение пользователя 2026-10-29): агент только предупреждает, что нашёл старый файл, а перенос делается вручную по таблице §15.7. Пакет `toml` в зависимости не добавляется.
4. **Влияние на архитектурные границы.** Нет: оба пакета — чистый Dart; allowlist зависимостей `codelab_agent_io` в `pubspec_allowlist_test.dart` содержит `yaml` и `yaml_edit`.
5. **Заменяет ли существующую технологию.** Нет. `args` (раздел 20б) разбирает аргументы процесса, а не файлы конфигурации.

Версии: диапазоны — в `packages/dart/codelab_agent_io/pubspec.yaml`, точные — в `pubspec.lock`.

В коде разборщик — `lib/src/config/yaml_reader.dart`, загрузчик — `config_loader.dart`, запись — `config_writer.dart` пакета `codelab_agent_io`, а `package:yaml_edit/` импортирует `lib/src/config/yaml_document_edit.dart`; что `toml` в `dependencies` `codelab_agent_io` не проходит, проверяет тест сторожа в `pubspec_allowlist_test.dart`.

---

## 20г. `codelab_desktop`: рендер терминала пользователя — `xterm2`

**Статус: утверждено.** Решение пользователя 2026-11-11 (Q2, Q3). Пакет и версия выбраны спайком 1.1 — [`design.md` change `add-integrated-terminal`](../../openspec/changes/archive/2026-11-22-add-integrated-terminal/design.md), D15; запасной `xterm` не понадобился. В `pubspec.yaml` app пакеты добавлены задачей 1.4 change.

Технология: [`xterm2`](https://pub.dev/packages/xterm2) **5.4.0** — форк `xterm.dart`, виджет `TerminalView`. Модель экрана — отдельный пакет [`xterm2_core`](https://pub.dev/packages/xterm2_core) **1.0.0** на чистом Dart: автомат, буферы, парсер escape-последовательностей, кодирование ввода. Пин точных версий — в `apps/codelab_desktop/pubspec.yaml`.

1. **Назначение.** Эмуляция VT/xterm и отрисовка вкладок панели Terminal десктопа (D-28, `proposals/dart-agent-and-clients/12-3-desktop-display.md`, A16).
2. **Где используется.** Только `apps/codelab_desktop/lib/features/terminal/`:
   * `xterm2_core` — `application/` (модель экрана вкладки) и `presentation/`;
   * `xterm2` (виджеты) — только `presentation/`.

   Правила сторожа — D11 change.
3. **Где не используется.**
   * `codelab_ui` — организм `CodeLabTerminalPane` получает виджет терминала слотом;
   * `codelab_client_*`, пакеты агента, `apps/codelab_cli`;
   * лента: строки инструментов ACP `terminal/*` остаются текстом;
   * обработчик ZMODEM (`zmodem`, транзитивно от `xterm2`, реэкспортируется `xterm2`) не подключается: `ZModemMux` — файловый обмен в обход политики (D3 change), импорт `package:zmodem/` запрещён сторожем.
4. **Какую проблему решает.** Не писать свой парсер ANSI и рендер: escape-последовательности, широкие символы, альтернативный экран, scrollback, выделение, bracketed paste.
5. **Влияние на архитектурные границы.**
   * Application импортирует из пакетов терминала только чистый `xterm2_core` (корневой `AGENTS.md` §6); `fvm dart run` без Flutter подтверждён спайком. Прямые импорты `package:xterm2/` и `package:flutter/` в application запрещены сторожем; транзитивно, через порты `lib/core/platform/`, application зависит от Flutter-пакета app — как принятый образец `dock_layout_store.dart` (D3 change).
   * `TerminalView` работает внутри `FluentApp` без `MaterialApp` и без Material-виджетов; импорт `package:flutter/material.dart` есть только внутри самого `xterm2`, как библиотека SDK. Тема строится из `FluentTheme` (§7).
   * **Буфер обмена (решение пользователя Q13).** Чтение и запись через OSC 52, 1337 и 5522 запрещены. Обработчики ЗАПРЕЩЕНО оставлять `null`: иначе `TerminalView.initState` подставит системный буфер через `??=`. Политика модели вкладки:
     * `clipboardDecoder: (_, _) => null`;
     * `allowITerm2ClipboardCapture: false`, `allowKittyClipboard: false`;
     * пустой `onClipboardStore`;
     * `onClipboardQuery` → `null`.

     Подробнее — D3 change. Выделение и Cmd+C/Cmd+V пользователя работают.
   * Ссылки OSC 8 открываются после подтверждения только для `http`/`https` (решение Q14) через `url_launcher` за портом `lib/core/platform/` (решение Q16, D11 change). Пакет описан в §20е; `add-desktop-markdown`, если сольётся позже, ссылается на него.
   * Запись в модель — порциями до 4 КБ не чаще кадра с бюджетом на кадр: один `write` на ~400 КБ держит UI isolate ~120 мс (D15). Без кадров (окно скрыто или свёрнуто) сброс идёт по таймеру с тем же бюджетом; неразобранный буфер вкладки ограничен ~8 МБ, переполнение отбрасывает самый старый вывод с пометкой `[output truncated]` (решение Q20, D3 change).
   * Ответ эмулятора на CSI 21 t (отчёт заголовка окна) в `xterm2_core` 1.0.0 не выключается: текст OSC 2 из вывода может попасть во ввод shell (без Enter). Риск принят до появления флага в пакете (Risks change). Заголовок OSC 0/2 в подписи вкладки не используется (решение Q22).
6. **Заменяет ли существующую технологию.** Нет.
7. **Требуется ли миграция.** Нет.
8. **Требуется ли ADR.** Нет (Q3): технология затрагивает одну фичу одного app и не меняет границы пакетов, управление состоянием и ACP — прецедент §20а.

Рассмотренные кандидаты (pub.dev, 2026-11-11; сравнение — раздел Context design.md):

| Пакет | Версия | Лицензия | Итог |
|---|---|---|---|
| `xterm2` + `xterm2_core` | 5.4.0 + 1.0.0 | MIT | **выбран** |
| `xterm` | 4.0.0 | MIT | запасной, не понадобился: не обновлялся с 2024-02 |
| `xterm3` | 6.4.0 | AGPL-3.0 | исключён: несовместим с MIT |
| `kterm` | 1.6.0 | MIT | не выбран: kitty-графика, разбор изображений из вывода |
| `terminal_view` | 0.5.0 | MIT | не выбран: нет отдельного чистого ядра |

Проверка по §25:
* **Desktop-платформы.** Заявлены macOS, Linux, Windows; проверено на macOS (сборки app есть только для неё).
* **Ограничения SDK.** `xterm2` — Flutter `>=3.27`, Dart `>=3.6`; собирается на версии Flutter из `.fvmrc` (на момент проверки — Flutter 3.47 / Dart 3.13).
* **Нативная настройка.** Нет.
* **Тестирование.** Widget-тесты с настоящим `TerminalView` идут под `fvm flutter test` (спайк: `terminal_view_fluent_test.dart`).
* **Безопасность.** Вывод процесса — недоверенный поток: буфер обмена закрыт, вывод и ввод не журналируются (`observability.md` §35).

В коде `package:xterm2_core/` импортируют `lib/features/terminal/application/terminal_model.dart` и `terminal_tabs_cubit.dart`, `package:xterm2/` — `presentation/terminal_pane.dart` и `terminal_theme.dart`.

---

## 20д. `codelab_desktop`: PTY для терминала пользователя — `pty2`

**Статус: утверждено.** Решение пользователя 2026-11-11 (Q1, Q3). Пакет и версия выбраны спайком 1.1 — [`design.md` change `add-integrated-terminal`](../../openspec/changes/archive/2026-11-22-add-integrated-terminal/design.md), D15; запасной `flutter_pty` не понадобился.

Вариант `Process.start` без PTY отклонён: без TTY не работают:
* редактирование строки, история и Tab-дополнение;
* сигнал Ctrl+C;
* `sudo`, `ssh` и запрос пароля `git`;
* полноэкранные программы;
* построчный вывод программ на C.

Технология: [`pty2`](https://pub.dev/packages/pty2) **0.8.1** — PTY на чистом Dart. C-код (`forkpty`, `setsid`) собирается хуком native assets; на Windows — ConPTY. Пин точной версии — в `apps/codelab_desktop/pubspec.yaml`.

1. **Назначение.** Запуск интерактивного shell пользователя (`$SHELL -l`) в псевдотерминале: ввод, вывод, размер окна, сигналы.
2. **Где используется.** Только адаптер `apps/codelab_desktop/lib/core/platform/user_shell_launcher.dart` за портом `UserShellLauncher` (§24, `platform-integration.md` §8, §73). Правило сторожа — D11 change. **Сейчас** адаптер вызывает `pty2` на UI isolate, запись в PTY синхронная. **План после 1.0** (решение Q24 принято 2026-11-12, реализация отложена; терминал выпускается в 1.0 с известными ограничениями): адаптер держит `pty2` целиком в фоновом isolate — по одному на shell вкладки: старт, чтение, запись, `resize`, сигналы и ожидание выхода идут там, UI isolate обменивается с ним сообщениями (D2 change, «Фоновый isolate вкладки»; задача 2.13, перенесена в change `add-terminal-keys-and-isolate`).
3. **Где не используется.**
   * ACP `terminal/*`: `IoTerminalProcessRunner` в `codelab_client_io` остаётся на `Process.start`;
   * процесс агента (`StdioAcpTransport`);
   * `apps/codelab_cli`;
   * пакеты `packages/dart/*`.
4. **Какую проблему решает.** `dart:io` не умеет PTY. Свой FFI-слой к `forkpty` и ConPTY — нативный код без сопровождения.
5. **Влияние на архитектурные границы.** Нативный API не выходит за адаптер. Фича работает с портом и тестируется с fake. Пакет не попадает в `codelab_client_io`: у порта один потребитель, а native assets собирались бы и для CLI (D2 change).

   Особенности API, которые скрывает адаптер (D2, D15):
   * нет `pid`; по плану после 1.0 адаптер получает его обёрткой старта `/bin/sh -c '…; exec "$0" "$@"'` и шлёт `hangUp`/`kill` по нему из UI isolate (`Process.killPid`) в обход isolate вкладки (Q24, Q25);
   * `write` синхронный: при полном буфере PTY (на macOS ~1 КБ ввода) он крутит `poll` на вызывающем isolate, пока программа не прочитает ввод. Сейчас это UI isolate — открытый риск, принятый для 1.0 как известная проблема (Risks change, «Синхронная запись в PTY»); по плану Q24 `pty2` уходит в isolate вкладки;
   * ввод — `write(String)`, вывод — `Stream<String>`;
   * код выхода ждёт isolate на каждый shell блокирующим FFI `waitpid`; Dart VM при остановке движка ждёт этот isolate, поэтому, пока shell жив, процесс app не завершается, а `Isolate.kill` ожидание не прерывает — штатный выход ДОЛЖЕН сам завершить shell (D4, D15 п. 9 change);
   * `kill(SIGHUP)` и `kill(SIGKILL)` шлются группе процесса, любой сигнал закрывает PTY-мастер;
   * без `environment` дочерний процесс получает узкий набор переменных — адаптер передаёт `Platform.environment` целиком (Q9);
   * ошибок старта нет (процесс выходит с `1`/`-1`) — адаптер проверяет файл и папку до `start`;
   * код выхода иногда `-1` — адаптер отдаёт `null`, вкладка показывает «exited» без кода.
6. **Заменяет ли существующую технологию.** Нет.
7. **Требуется ли миграция.** Нет.
8. **Требуется ли ADR.** Нет (Q3); обоснование — как в §20г.

Проверка по §24–§25:
* **Desktop-платформы.** `pty2` — macOS, Linux (`forkpty`), Windows (ConPTY; необязательная загрузка ConPTY из NuGet в app не включена). Проверено на macOS arm64: `fvm flutter build macos` debug и release, в бандле `pty2_unix.framework`.
* **Ограничения SDK.** `pty2` требует Dart `>=3.11.0`. У `apps/codelab_desktop` нижняя граница поднята с `>=3.8.0` до `>=3.11.0`; корень workspace и другие пакеты не меняются (D11 change, задача 1.4).
* **Нативные зависимости.** C-компилятор при сборке: Xcode CLT на macOS, `cc` или `gcc` на Linux. Отдельной настройки Xcode или CocoaPods нет.
* **Жизненный цикл.**
  * Процесс принадлежит вкладке: закрытие — `SIGHUP`, через 2 с `SIGKILL`.
  * Выход из app закрывает все вкладки: обработчик `AppLifecycleListener.onExitRequested` → `closeAll()`. Обработчик ДОЛЖЕН быть установлен — без него штатный выход зависает на `waitpid` `pty2` (решение пользователя 2026-11-12; D14, D15 п. 9 change).
  * Крах или убийство app — `SIGHUP` от закрытия PTY-мастера, подтверждено спайком; при штатном выходе эта страховка не срабатывает (`concurrency.md` §45, `platform-integration.md` §23).
  * Задание интерактивного shell, игнорирующее `SIGHUP`, после `SIGKILL` shell остаётся сиротой — поведение пользователя, как `nohup`.
* **Потоки и isolate.** Сейчас: чтение — в фоновых isolate `pty2` (без модели поток 585 КБ читается за 0,29 с), запись, `resize` и сигналы — на UI isolate; запись при полном буфере PTY блокирует UI isolate (открытый риск, принят для 1.0 как известная проблема). Разбор эмулятором — на UI isolate, порциями (§20г). План после 1.0 (Q24): весь `pty2` — в isolate вкладки, `UserShell.write` ставит строку в очередь и сразу возвращается; вывод проходит лишний переход между isolate, его стоимость под «Flood» меряет задача 2.13 (перенесена в change `add-terminal-keys-and-isolate`).
* **Безопасность.** Shell пользователя вне политики разрешений и containment (`permissions.md` §2), окружение app передаётся целиком (`platform-integration.md` §53, исключение).
* **Тестирование.** Native assets собираются под `fvm flutter test` и `fvm dart test`; контрактный тест адаптера идёт на Dart VM в `feature/*`. На код выхода тесты не опираются.
* **Сопровождение.** 0.8.1 от 2026-11-10; активное сопровождение, но ломающие версии 0.6–0.8 вышли за две недели. Мера — пин точной версии, обновление — отдельным PR с контрактным тестом.

### Транзитивные зависимости и лицензии терминала (§20г–§20д)

Список ведётся здесь, а не в `THIRD_PARTY_NOTICES.md` (решение пользователя Q12): тот реестр — для воспроизведённых фрагментов. Это замыкание `dependencies` пакетов `xterm2`, `xterm2_core`, `pty2` по `pubspec.lock` спайка; лицензии взяты из тегов pub.dev и файлов `LICENSE`. Несовместимых с MIT нет. Источник — D15 change. Версии в таблице — по lock спайка; действующие — в `pubspec.lock` и могут отличаться.

| Пакет | Версия | Лицензия | Тянет | В lock workspace до change |
|---|---|---|---|---|
| `pty2` | 0.8.1 | MIT | прямая | нет |
| `xterm2` | 5.4.0 | MIT | прямая | нет |
| `xterm2_core` | 1.0.0 | MIT | прямая, `xterm2` | нет |
| `zmodem` | 0.0.6 | MIT | `xterm2` | нет |
| `quiver` | 3.2.2 | Apache-2.0 | `xterm2` | нет |
| `equatable` | 2.1.0 | MIT | `xterm2` | нет |
| `native_toolchain_c` | 0.19.6 | BSD-3-Clause | `pty2` (хук сборки) | нет |
| `win32` | 6.4.0 | BSD-3-Clause | `pty2` (Windows) | нет |
| `ffi_leak_tracker` | 0.1.2 | BSD-3-Clause | `win32` | нет |
| `code_assets` | 2.2.0 | BSD-3-Clause | `pty2`, `native_toolchain_c` | 1.2.1 — поднимается (мажор) |
| `hooks` | 2.2.0 | BSD-3-Clause | `pty2`, `code_assets` | 2.0.2 — поднимается |
| `record_use` | 1.1.1 | BSD-3-Clause | `hooks` | 0.6.0 — поднимается |
| `yaml` | 3.1.4 | MIT | `hooks` | 3.1.3 |
| `characters`, `collection`, `convert`, `crypto`, `ffi`, `file`, `glob`, `logging`, `matcher`, `meta`, `path`, `platform`, `process`, `pub_semver`, `typed_data`, `async`, `boolean_selector`, `source_span`, `stack_trace`, `stream_channel`, `string_scanner`, `term_glyph`, `test_api` | см. D15 | BSD-3-Clause | разные | уже есть |

Кроме замыкания, в lock workspace поднимается `objective_c` 9.5.0 → 9.6.4 (BSD-3-Clause, publisher `dart.dev`; сухой прогон спайка давал 9.6.3, при `melos bootstrap` разрешилась опубликованная 2026-11-11 версия 9.6.4): он тянется через существующие пакеты. Сборку app и тесты затронутых пакетов с новым lock проверяла задача 1.4 change.

## 20е. `codelab_desktop`: открытие ссылок во внешнем приложении — `url_launcher`

**Статус: утверждено.** Пакет введён change `add-desktop-markdown` (архив 2026-11-11, D5/D10; строка таблицы §1); терминал переиспользует его порт, правило сторожа и зависимость — решение пользователя 2026-11-11 (Q16), [`design.md` change `add-integrated-terminal`](../../openspec/changes/archive/2026-11-22-add-integrated-terminal/design.md), D11; задача 2.10.

Технология: [`url_launcher`](https://pub.dev/packages/url_launcher) **6.3.3** (BSD-3-Clause, publisher `flutter.dev`). При слиянии терминала запись приведена к точному пину `6.3.3` (было `^6.3.3`; D11), а граница `flutter:` у app поднята до `>=3.41.0` — требование пакета.

1. **Где.** Только порт `ExternalLinkOpener` и адаптер `UrlLauncherExternalLinkOpener` в `apps/codelab_desktop/lib/core/platform/external_link_opener.dart` (политика схем — `link_policy.dart`); импорт `package:url_launcher/` в остальном `lib` app запрещён сторожем (одно правило на оба потребителя).
2. **Потребители.** Ссылки в ответе агента (markdown, политика `isOpenableLink`) и ссылки OSC 8 в терминале (Q14).
3. **Безопасность терминала.** Первая линия — application (`terminalLinkDecision`: только `http`/`https`; адрес с bidi, нулевой шириной или управляющими C0/C1 — «нельзя» при любой схеме, Q21); диалог показывает нормализованный адрес — ровно тот, что уходит в порт; вторая линия — политика адаптера (`isOpenableLink`); адрес в журнал не пишется — только схема (`observability.md` §35). OSC 1337 `OpenURL` (`Terminal.onOpenUrl`) не подключается.
4. **Заменяет ли существующую технологию.** Нет. **Миграция** — нет. **ADR** — нет (Q3, прецедент §20а).

В коде `package:url_launcher/` импортирует и второй порт `lib/core/platform/` — `LocalFolderOpener` (`local_folder_opener.dart`, открытие каталогов со страниц «Skills & extensions» и «Agents & modes»); правило сторожа исключает из запрета весь каталог `core/platform/` (`exclude: ['core/platform/']` в `rules.dart`), а не один файл.

---

## 20ж. `codelab_desktop` и `codelab_ui`: локализация интерфейса — `flutter_localizations`, `gen-l10n`, `intl`

**Статус: утверждено.** Решение — change [`add-desktop-localization`](../../openspec/changes/archive/2026-11-20-add-desktop-localization/design.md), D1, D3, D4, D10; требование — D-19 матрицы паритета (`proposals/agent-parity-goals.md`). До этого change утверждённого решения для i18n в стеке не было.

Технология: стандартная локализация Flutter. `flutter_localizations` — часть SDK; классы сообщений генерирует `fvm flutter gen-l10n` из каталогов ARB; сообщения — ICU (`plural`, `select`, типизированные плейсхолдеры); `intl` нужен сгенерированному коду для `plural` и `Intl.message`.

1. **Где.** Только два пакета:
   * `apps/codelab_desktop` — `l10n.yaml`, каталоги `lib/l10n/app_en.arb` и `app_ru.arb`, класс `AppLocalizations` (`nullable-getter: false`), доступ из виджетов — `context.l10n`;
   * `packages/flutter/codelab_ui` — свой каталог `codelab_ui_en.arb`/`codelab_ui_ru.arb`, класс `CodeLabLocalizations` (`nullable-getter: true`); без делегата в дереве кит показывает английский (D4).
2. **Версии.** В `pubspec.yaml` — `flutter_localizations: sdk: flutter` и `intl: any`: версию `intl` закрепляет `flutter_localizations` SDK, своя граница привела бы к конфликту решателя (D3). Новых пакетов в `pubspec.lock` не появилось: `intl` и `flutter_localizations` уже приходили транзитивно через `fluent_ui`.
3. **Сгенерированный код коммитится** — в отличие от `*.freezed.dart`, которые генерируются при сборке (§11, §13): `dart analyze` работает без шага генерации. Совпадение кода с ARB проверяет скрипт Melos `l10n:check` (перегенерация во временный каталог и сравнение) — в составе `check` и в затронутых проверках при правке ARB или `l10n.yaml`. Править сгенерированные `app_localizations*.dart` вручную ЗАПРЕЩЕНО.
4. **Где НЕ используется.** `codelab_client_core` и `codelab_client_acp` НЕ ДОЛЖНЫ импортировать `package:intl/` и `package:flutter_localizations/` — правило сторожа (D10; spec `workspace-architecture` «Ядро клиента не зависит от языка интерфейса»). Пакеты `codelab_agent_*` и тексты, которые видит модель, остаются английскими (`agent-core-architecture` §12.2). Форматы usage (`usage_format.dart`) остаются без `intl` и локали (D8).
5. **Fluent.** `FluentApp` сам добавляет `FluentLocalizations.delegate`; делегаты app и кита складываются с ним в один список `localizationsDelegates` у `FluentApp`; `supportedLocales` — только `en` и `ru` (spec `app-settings` «Локализация интерфейса app»).
6. **Заменяет ли существующую технологию.** Нет. **Альтернативы** — `easy_localization`, `slang`, рукописные таблицы — отклонены (D1). **ADR** — нет: технология не меняет архитектуру приложения и входит в Flutter SDK.

Правила слоёв для текста (где собирается текст и как он пересобирается при смене языка) — `layers-and-dependencies.md` §54 «Текст интерфейса и локализация»; термины перевода — `l10n-glossary.md`.

В коде сгенерированные классы лежат рядом с ARB: `apps/codelab_desktop/lib/l10n/app_localizations*.dart` (расширение `context.l10n` — `lib/l10n/l10n.dart`) и `packages/flutter/codelab_ui/lib/src/l10n/codelab_localizations*.dart`; запрет `intl` и `flutter_localizations` в ядре клиента — список `uiLanguageForbidden` в `rules.dart`. `usage_format.dart` лежит в `codelab_client_core` (`lib/src/usage/`).

---

## 20з. `codelab_desktop`: системный цвет акцента — `system_theme`

**Статус: утверждено** решением пользователя 2026-11-20 (Q5 (б) change [`add-app-appearance-page`](../../openspec/changes/archive/2026-11-20-add-app-appearance-page/design.md), D7). Добавлен в `pubspec.yaml` app задачей 4.10 change.

Технология: [`system_theme`](https://pub.dev/packages/system_theme) **3.3.0** (опубликован 2026-05-26; BSD-3-Clause; publisher `bdlukaa.dev` — тот же автор, что у `fluent_ui`). Требует Dart `^3.12.0` и Flutter `>=3.44.0`; версия Flutter проекта (`.fvmrc`, на момент утверждения — 3.47.0) совместима. Транзитивно добавляется `system_theme_web` 0.0.5 (BSD-3-Clause, тот же publisher; зависит от `web` — уже в lock — и SDK `flutter_web_plugins`). Пин — точная версия `3.3.0`, как у `url_launcher` (§20е).

Проверка по §24–§25:

1. **Почему не своими силами.** Flutter не отдаёт системный акцент на десктопе (`dart:ui` `SystemColor` — только web). Альтернатива — свой нативный канал на каждой платформе (D7 change, отклонена пользователем).
2. **Платформы.** Пакет объявляет Android, iOS, web, Windows, macOS, Linux. Получение цвета:
   * macOS — `NSColor.controlAccentColor` в sRGB, смены — уведомление `NSSystemColorsDidChangeNotification` (с 3.2.0);
   * Windows — цвета акцента системы, смены — событие системы;
   * Linux — цвет GTK-темы `theme_selected_bg_color`; **смен нет**: поток `onChange` на Linux выдаёт одно текущее значение.

   Уведомления о смене — только macOS и Windows (`supportsListeningToAccentColorChanges`).
3. **Нативная настройка.** Плагин регистрируется генератором плагинов Flutter (macOS — Swift Package Manager / CocoaPods, Linux — GTK, Windows — C++). Ручной настройки раннера и entitlements не требуется. Плагин только читает цвет, сети и файлов не трогает.
4. **Особенности API, которые закрывает адаптер.**
   * при недоступном плагине `load()` молча оставляет запасной цвет (`MissingPluginException` → `debugPrint`). Адаптер создаёт свой `SystemAccentColor` с запасным цветом-маркером `Color(0x00000000)` (прозрачный цвет не бывает акцентом) и считает акцент недоступным, если после `load()` остался маркер;
   * статический `SystemTheme.accentColor` загружается при первом обращении без `await`, и его исключение было бы потеряно (корневой `AGENTS.md` §12). Адаптер его не использует;
   * `SystemAccentColor.load()` подписывается на `onChange` и не отписывается. Адаптер создаёт объект один раз за процесс, поэтому такая подписка одна; подписку для приложения держит `AppAppearanceCubit` и отменяет в `close()` (`concurrency.md` §47б).
5. **Где.** Только адаптер `SystemThemeAccentSource` порта `SystemAccentSource` в `apps/codelab_desktop/lib/core/platform/system_accent_source.dart`; импорт `package:system_theme/` в остальном `lib` app запрещён сторожем (по образцу `url_launcher`). Код фич видит только порт.
6. **Тестирование.** Cubit и страница тестируются на `FakeSystemAccentSource`; адаптер — на подменённом обработчике канала `system_theme` в `TestDefaultBinaryMessenger`.
7. **Безопасность.** Плагин не принимает данных от пользователя и агента; цвет из системы используется только как роль `accent`.
8. **Лицензии.** BSD-3-Clause совместима с MIT; зависимости pub.dev в `THIRD_PARTY_NOTICES.md` не вносятся (его вводная часть), шрифтов и ресурсов пакет в сборку не кладёт.
9. **Заменяет ли существующую технологию.** Нет. **ADR** — нет: узкая платформенная зависимость за портом, архитектуру не меняет (прецедент §20е).

---

## 20и. `codelab_desktop`: приём перетаскивания из ОС — `desktop_drop`

**Статус: утверждено** решением пользователя 2026-11-22 по итогам проверки — задачи 1.1 change [`add-empty-project-screen`](../../openspec/changes/archive/2026-11-22-add-empty-project-screen/design.md) (D3). Первый потребитель — экран без проекта (кадр 11a); вложения композера D-12 переиспользуют тот же адаптер (`proposals/dart-agent-and-clients/12-3-desktop-display.md` §12.3.6). Пакет добавлен в `pubspec.yaml` app задачей 5.4 change.

Технология: [`desktop_drop`](https://pub.dev/packages/desktop_drop) **0.8.4** (опубликован 2026-09-01; Apache-2.0; publisher `mixin.dev`). Требует Dart `^3.5.0` и Flutter `>=3.0.0`; версия SDK проекта (`.fvmrc`, на момент утверждения — Flutter 3.47.0 / Dart 3.13.0) совместима. Пин — точная версия `0.8.4`, как у `url_launcher` и `system_theme` (§20е, §20з).

Проверка по §24–§25:

1. **Почему не SDK.** В Flutter 3.47.0 API приёма внешнего перетаскивания на десктопе нет: `DragTarget` и `Draggable` работают только внутри дерева виджетов (проверено поиском по исходникам framework). `file_selector` (§12.1) покрывает только диалоги. Своего решения в проекте нет. Альтернативы — `super_drag_and_drop` (нативное расширение на Rust) и свой канал на трёх ОС — отклонены (D3).
2. **Версия.** 0.9.0–0.9.2 требуют Flutter `>=3.47.7`, поэтому пин — 0.8.4 до обновления Flutter. При переходе на 0.9.x: `dbus` уходит из замыкания, добавляются `cross_file ^0.4.0`, `cross_file_platform_interface`, `cross_file_web`, `mime` — их лицензии проверяются при обновлении (сейчас не проверены).
3. **Платформы и нативная часть.** `pluginClass DesktopDropPlugin` для macOS, Windows и Linux; регистрацию делает генератор плагинов Flutter (registrant-файлы), ручной настройки раннера нет. macOS — Swift Package Manager / podspec без сторонних зависимостей; новых entitlements не нужно, потому что песочница выключена. Windows — OLE drop target окна. Linux — GTK (`text/uri-list`). Сборка `fvm flutter build macos --debug` с пакетом проходит локально; Linux и Windows проверяет CI-сборка ветки после задачи 5.4. Настоящий бросок проверяется вручную (задача 5.5).
4. **Транзитивные пакеты.** Новые в `pubspec.lock`:

   | Пакет | Версия | Лицензия | Тянет | Примечание |
   |---|---|---|---|---|
   | `desktop_drop` | 0.8.4 | Apache-2.0 | прямая | |
   | `dbus` | 0.7.15 | MPL-2.0 | `desktop_drop` | нужен только на Linux; допущен явным решением пользователя 2026-11-22 (п. 5) |
   | `universal_platform` | 1.1.0 | MIT | `desktop_drop` | |

   `cross_file`, `web` и `flutter_web_plugins` уже были в lock (через `file_selector` и SDK).
5. **Лицензии.** Apache-2.0 и MIT совместимы с MIT. `dbus` — MPL-2.0, слабый copyleft на уровне файла: изменённые файлы самого пакета пришлось бы раскрывать под MPL-2.0, а код CodeLab, который его использует, лицензию не меняет. Проект `dbus` не правит и не копирует, пакет приходит из pub.dev как есть. Пользователь допустил его явным решением 2026-11-22 как исключение для этой зависимости. Любой другой пакет под MPL или более строгой лицензией требует нового решения. Зависимости pub.dev в `THIRD_PARTY_NOTICES.md` не вносятся (вводная часть файла, §20з п. 8).
6. **Где.** Только адаптер `OsDropRegion` в `apps/codelab_desktop/lib/core/platform/os_drop_region.dart`; импорт `package:desktop_drop/` в остальном `lib` app запрещён сторожем (по образцу `system_theme`). Типы плагина за адаптер не выходят; вид пути проверяет порт `LocalPathKindOf`, решение принимает `SettingsCubit` (`platform-integration.md` §37а). `codelab_ui` от плагина не зависит.
7. **Жизненный цикл и потоки.** Плагин только доставляет события входа, выхода и броска в UI isolate; файлов не читает и в фоне не работает. Подписка живёт, пока виджет-адаптер в дереве.
8. **Безопасность.** Пакет отдаёт только пути, которые пользователь сам бросил в окно. Путь — недоверенный вход: вид проверяет application, containment — агент и клиентская проверка `fs/*`/`terminal/*` (`permissions.md`).
9. **Тестирование.** Экран и Cubit тестируются без плагина (колбэки `OsDropRegion`, поддельный `LocalPathKindOf`); адаптер — событиями канала плагина в `TestDefaultBinaryMessenger`.
10. **Сопровождение.** Последний выпуск — 2026-09-01, пакет активно выпускается (линия 0.9.x). Открытые issues по трём ОС не просмотрены: GitHub API был недоступен при проверке. Это остаточный пункт проверки, его закрывают ручная проверка 5.5 и CI-сборка трёх ОС.
11. **Риски.** UIPI на Windows: в app, запущенный с повышенными правами, перетаскивание из Проводника не доходит — документируется, не обходится. Песочница macOS (P-13): с ней брошенный URL доступен только процессу app, решение пересматривается вместе с `file_selector` (задача 9.11 дорожной карты). Обновление на 0.9.x при переходе Flutter меняет транзитивное замыкание (п. 2).
12. **Заменяет ли существующую технологию.** Нет. **ADR** — нет: узкая платформенная зависимость за адаптером, архитектуру не меняет (прецедент §20е, §20з).

---

## 21. Направление зависимостей пакетов

Целевая модель подсистемы ACP:

```text
                  ┌──────────────────┐
                  │ codelab_desktop  │
                  │ composition root │
                  └────────┬─────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
          codelab_ui    codelab_client_core ◄── codelab_client_io
                           │          (адаптеры dart:io)
                           ▼
                    codelab_client_acp
                           │
                 ┌─────────┴───────┐
                 │                 │
                 ▼                 ▼
          codelab_acp_transports     codelab_acp_protocol
                 │
                 ▼
          внешний агент
```

Точная матрица зависимостей задана в:

`docs/architecture/layers-and-dependencies.md`

Основные инварианты:

* `codelab_acp_protocol` не зависит от Flutter-пакетов;
* `codelab_acp_transports` не зависит от Flutter UI;
* `codelab_client_acp` остаётся на чистом Dart;
* `codelab_client_core` остаётся на чистом Dart без `dart:io` и зависит только от `codelab_client_acp`, `codelab_acp_protocol`, `codelab_acp_transports`; `codelab_client_io` — без Flutter;
* `codelab_ui` не зависит от `codelab_desktop`;
* `codelab_desktop` выполняет сборку (composition);
* пакеты нижних уровней не зависят от пакета приложения.

В коде схема показывает только клиентскую сторону desktop. Вторым клиентом рядом с `codelab_desktop` работает `apps/codelab_cli` с теми же клиентскими зависимостями (без `codelab_ui`); оба клиента получают агентскую сторону через мосты `codelab_setup` и `codelab_embedded`; агентская сторона (`codelab_agent_*`, бинарь `apps/codelab_agent`) — `layers-and-dependencies.md` §53. Полный граф пакетов — `README.md` корня, раздел «Граф зависимостей».

---

## 22. Стек тестирования

Используются:

* `flutter_test`;
* `integration_test`;
* `codelab_acp_testing`;
* стандартные средства тестирования Dart там, где применимо.

Предпочтительный уровень тестирования определяется типом кода:

```text
Логика на чистом Dart
    → модульные тесты Dart

Протокол ACP
    → тесты протокола и сериализации

Ядро ACP-клиента
    → модульные тесты + тесты жизненного цикла

Flutter-представление
    → тесты BLoC + виджет-тесты

Интеграция desktop
    → интеграционные тесты
```

Логику на чистом Dart НЕ СЛЕДУЕТ тестировать через Flutter binding, если достаточно обычного модульного теста.

Переиспользуемую тестовую инфраструктуру ACP СЛЕДУЕТ размещать в `codelab_acp_testing`.

Подробная стратегия:

`docs/architecture/testing.md`

В коде Dart-пакеты и приложения `codelab_agent`, `codelab_cli` тестируются на `package:test`; `flutter_test` — в `dev_dependencies` `apps/codelab_desktop` и `codelab_ui`; `integration_test` и `flutter_driver` — только в `dev_dependencies` `apps/codelab_desktop`. Библиотек моков (`mockito`, `mocktail`) и `bloc_test` в репозитории нет: двойники пишутся вручную (`testing.md`, абзац «Где в коде»).

---

## 23. Статический анализ

Проект использует:

`flutter_lints`

Конкретные правила линтера задаёт `analysis_options.yaml` репозитория.

Источник истины — фактическая конфигурация анализатора, а не этот документ.

Изменённый код ДОЛЖЕН проходить статический анализ по правилам корневого `AGENTS.md`.

В коде `flutter_lints` подключает только `apps/codelab_desktop/analysis_options.yaml` (`package:flutter_lints/flutter.yaml`). Корневой `analysis_options.yaml` подключает `package:lints/recommended.yaml`, включает `avoid_print`, `prefer_final_locals`, `require_trailing_commas`, `sort_pub_dependencies` и исключает сгенерированные `*.g.dart`, `*.freezed.dart`, каталоги сборки и `site/`; он действует для всех пакетов без своего `analysis_options.yaml`, в том числе для `codelab_ui`. Dart-пакеты и приложения объявляют `lints` в `dev_dependencies`.

---

## 24. Desktop-зависимости

Любая новая desktop-зависимость ДОЛЖНА быть проверена как минимум по критериям:

* поддержка Windows;
* поддержка macOS;
* поддержка Linux;
* нативные зависимости;
* жизненный цикл;
* поведение потоков и isolate;
* последствия для безопасности;
* состояние сопровождения.

Платформенный плагин СЛЕДУЕТ изолировать за адаптером, если его API начинает проникать в логику приложения.

Например:

```text
Фича
   │
   ▼
Порт приложения
   ▲
   │
Desktop-адаптер
   │
   ▼
Платформенный плагин
```

Это позволяет менять реализацию, не распространяя API плагина по приложению.

В коде адаптеры плагинов собраны в `apps/codelab_desktop/lib/core/platform/` (`platform-integration.md` §8).

---

## 25. Новые зависимости

Перед добавлением новой зависимости агент ОБЯЗАН проверить:

1. Решает ли уже существующая зависимость ту же задачу.
2. Можно ли решить задачу средствами Dart/Flutter SDK.
3. Соответствует ли зависимость архитектуре проекта.
4. Поддерживает ли она нужные desktop-платформы.
5. Совместима ли она с текущими ограничениями SDK.
6. Не вводит ли она конкурирующий framework.
7. Требует ли нативной настройки.
8. Как она влияет на тестирование.
9. Как она влияет на безопасность.
10. Требуется ли ADR.

Особенно НЕ СЛЕДУЕТ без архитектурного решения добавлять альтернативы:

* `flutter_bloc`;
* Cherrypick;
* `fluent_ui`;
* `fpdart`;
* Freezed.

---

## 26. Когда требуется ADR

Architecture Decision Record требуется при значимом изменении технологического направления.

В частности, при:

* замене `flutter_bloc`;
* добавлении второго framework управления состоянием;
* замене Cherrypick;
* добавлении второго DI-контейнера;
* смене основной UI- и дизайн-системы;
* изменении архитектуры транспорта ACP;
* выборе технологии хранения;
* выборе сетевого стека;
* изменении стратегии обработки ошибок;
* значимом изменении стратегии генерации кода;
* выборе значимой технологии интеграции с платформой.

Обычное обновление существующей зависимости в пределах совместимого выпуска само по себе обычно ADR не требует.

Если обновление приводит к архитектурным или поведенческим изменениям, необходимость ADR или OpenSpec change оценивается по характеру этих изменений.

В коде принятые ADR — `docs/architecture/adr/` (реестр — `adr/README.md`); из технологий этого документа отдельный ADR есть только у сайта (ADR-0003, §28); `flutter_bloc` и Cherrypick выбраны до первого ADR, а технологии §20а–§20и утверждены в `design.md` OpenSpec changes без ADR.

---

## 27. Добавление технологии в стек

При утверждении новой технологии этот документ ДОЛЖЕН быть обновлён.

Для технологии нужно указать:

1. Назначение.
2. Где она может использоваться.
3. Где она не должна использоваться.
4. Какую существующую проблему она решает.
5. Как она влияет на архитектурные границы.
6. Заменяет ли она существующую технологию.
7. Требуется ли миграция.
8. Требуется ли ADR.

`technology-stack.md` ДОЛЖЕН описывать **актуальный утверждённый стек**, а не историю всех когда-либо использовавшихся библиотек.

История значимых решений хранится в ADR.

---

## 28. Сайт `site/`: Astro, Node и npm

**Статус: утверждено.** ADR-0003 принят 2026-11-18 после одобрения и реализации change [`add-astro-site`](../../openspec/changes/archive/2026-11-18-add-astro-site/design.md) (PR #363).

1. **Назначение.** Статический сайт-визитка CodeLab: главная, возможности трёх продуктов, установка, документация, новости выпусков. Документация читается из репозитория на месте (content collections Astro), а не копируется.
2. **Где.** Только каталог `site/` и джоб `site` в `.github/workflows/ci.yml`. Версия Node — `site/.nvmrc`, зависимости — `site/package.json` с точными версиями и закоммиченный `site/package-lock.json`; установка — `npm ci`.
3. **Где НЕ использовать.** Node, npm и JavaScript-зависимости НЕ ДОЛЖНЫ появляться вне `site/`: в пакетах, приложениях, скриптах Melos и `tool/`. `site/` НЕ ДОЛЖЕН входить в `workspace:` корневого `pubspec.yaml` и в Melos; сторож `codelab_architecture_tests` его не проверяет.
4. **Какую проблему решает.** Публичная точка входа и навигация по продуктовой документации без второй копии текста; проверка ссылок документации при каждой её правке.
5. **Влияние на границы.** Граф пакетов не меняется: сайт не пакет и не зависит от Dart-кода. Связь с остальным репозиторием — только чтение Markdown и изображений из опубликованных источников (allowlist в design.md change `add-astro-site`, D3).
6. **Заменяет ли существующую технологию.** Нет. Второй генератор сайта или документации НЕ СЛЕДУЕТ добавлять.
7. **Миграция.** Не требуется.
8. **ADR.** ADR-0003.

Зависимости сайта добавляются по §25 с поправкой на npm: лицензия — MIT, BSD, ISC или Apache-2.0 (copyleft не допускается), версия — точная, lock-файл — в том же коммите. Правила разработки сайта — skill `.claude/skills/codelab-site/`.

В коде корневой `analysis_options.yaml` исключает `site/**` из анализа Dart (ADR-0003, D1), а скрипт `tool/ci/ci_scope.dart` выбирает джоб `site` при изменении `site/**` и опубликованных документов.
