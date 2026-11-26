# Слои и зависимости CodeLab

Документ задаёт архитектурные слои CodeLab, ответственность пакетов и допустимые направления зависимостей между ними.

Документ обязателен к прочтению при:

* создании нового пакета;
* создании новой фичи;
* переносе кода между пакетами;
* добавлении зависимости между пакетами;
* изменении архитектуры ACP-клиента;
* существенном рефакторинге.

Цели:

* закрепить за каждым пакетом и слоем одну ответственность;
* задать допустимые направления зависимостей и запретить обратные;
* сохранить чистый Dart там, где не нужен Flutter, и web-безопасность там, где она заявлена;
* держать связанность (coupling) под контролем, а не умножать слои ради формы;
* дать критерии, по которым выбирается место для нового кода.

Общие правила — корневой `AGENTS.md` (§4, §5, §6, §7, §11, §13, §14, §15, §17), [`technology-stack.md`](technology-stack.md), [`acp-boundary.md`](acp-boundary.md), [`state-management.md`](state-management.md), [`platform-integration.md`](platform-integration.md), [`permissions.md`](permissions.md), [`error-handling.md`](error-handling.md), [`testing.md`](testing.md). Решения: [ADR-0001](adr/0001-embed-dart-agent-core-behind-acp.md) (встраиваемое ядро агента за ACP), [ADR-0002](adr/0002-name-packages-codelab-side-layer.md) (имена пакетов `codelab_<сторона>_<слой>`). Слои и пакеты агента подробно — [`proposals/agent-core/01-layers-and-packages.md`](proposals/agent-core/01-layers-and-packages.md) (инварианты PKG-1…PKG-6).

Термины:

* **Слой** (layer) — уровень с одной ответственностью: протокол, транспорт, клиентская логика, представление; внутри приложения — `domain`, `application`, `infrastructure`, `presentation` (§2, §15–§18).
* **Сторона** (side) — часть имени пакета по ADR-0002: `acp` (общий протокольный слой), `client` или `agent` (§53).
* **Мост** (bridge) — пакет без префикса стороны, через который клиенты получают агентскую сторону: `codelab_setup`, `codelab_embedded` (§53).
* **Барель** (barrel) — публичная точка входа пакета `lib/<пакет>.dart` или дополнительная `lib/io.dart`, `lib/testing.dart` (§25).
* **Web-безопасный** (web-safe) — код, который собирается в JavaScript и WebAssembly: без `dart:io`, `dart:isolate`, `dart:ffi` и Flutter (§53).
* **Порт** (port) — узкий интерфейс, через который внутренний слой получает внешнюю возможность; реализацию даёт адаптер (§18, §34).
* **Composition root** — место, где собираются конкретные реализации: `apps/codelab_desktop/lib/app/`, `apps/codelab_cli/lib/src/composition_root.dart`, хост `apps/codelab_agent` (§24).
* **Фича** (feature) — каталог `features/<имя>/` приложения, владеющий одной возможностью (§12).
* **Allowlist** — допустимые `dependencies` пакета в `pubspec.yaml`, проверяемые сторожем (§42, §53).
* **Сторож** (guard) — тесты `packages/dart/codelab_architecture_tests`, запуск — `melos run guard` (§42).

Где в коде. Члены pub workspace перечислены в `workspace:` корневого `pubspec.yaml`; имя пакета совпадает с каталогом и следует схеме `codelab_<сторона>_<слой>` (ADR-0002, `package_naming_test.dart`). Общий протокольный слой: `codelab_acp_protocol` (модели и кодеки), `codelab_acp_transports` (основной барель web-безопасен: порт `AcpTransport`, `InProcessAcpLink`, конфигурации; IO-транспорты `StdioAcpTransport`, `WebSocketAcpTransport` и серверные — в `lib/io.dart`), `codelab_acp_testing` (фикстуры и двойники). Клиентская сторона: `codelab_client_acp` (`AcpClientApplication`, автоматы состояний, `ApprovalPolicy`; каталоги `lib/src/domain/`, `application/`, `infrastructure/`), `codelab_client_core` (`ClientWorkspace`, `SessionHandle`, порты `AgentBackend` и `TransportResolver`), `codelab_client_io` (адаптеры `dart:io`, `ioTransportResolver`), `codelab_ui` (`packages/flutter/`, виджеты Fluent; слои `atomics/`, `molecules/`, `organisms/`, `rendering/`, `l10n/`). Агентская сторона: `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `codelab_agent_mcp` (§53). Мосты: `codelab_setup` (основной барель и `lib/io.dart`), `codelab_embedded` (`codelab_embedded.dart`, `io.dart`, `testing.dart`). Приложения: `apps/codelab_desktop` — Flutter, feature-first: `lib/app/` (composition root `createCodeLabRootScope` в `app_scope.dart` на Cherrypick, корень app, навигация `NavigationCubit`), `lib/core/platform/` (адаптеры платформы), `lib/core/text/`, `lib/features/<фича>/{application,presentation}/` для `workbench`, `settings`, `onboarding`, `project_files`, `terminal`, `protocol`, `usage`; слоёв `domain/` и `infrastructure/` в фичах нет. `apps/codelab_cli` — чистый Dart, composition root `lib/src/composition_root.dart`. `apps/codelab_agent` — бинарь агента, хост ядра `lib/src/host/agent_host.dart`. Сторож `packages/dart/codelab_architecture_tests`: правила импортов `PackageRule` в таблице `rules` (`test/support/rules.dart`; web-небезопасные префиксы `webUnsafe`, пакеты языка интерфейса `uiLanguageForbidden`, запечатывание IO- и тестовых барелей `exclude`/`sealExclude`), allowlist-ы `*Allowlist` (`test/pubspec_allowlist_test.dart`; ядро агента — `coreAllowlist`: `http`, `meta`, `collection`, `async`, `crypto`, PKG-2), имена пакетов (`package_naming_test.dart`), сборка ядра только через `buildAgentCore` (`host_assembly_guard_test.dart`, HOST-6), литералы интерфейса (`ui_literals_test.dart`). Сборку ядра агента и основных барелей мостов в JavaScript и WebAssembly проверяет `melos run web-compile`. Что сторож проверяет, а что нет, — §42.

---

## 1. Цель

Главная задача правил зависимостей — не формальное соблюдение Clean Architecture, а контроль связанности.

Архитектура ДОЛЖНА обеспечивать:

* независимость протокола ACP от Flutter;
* независимость переиспользуемой клиентской логики от Flutter;
* изоляцию транспортов;
* изоляцию реализаций, зависящих от платформы;
* переиспользуемый UI для ACP;
* тестируемость логики application;
* явное владение состоянием и побочными эффектами.

Зависимость в `pubspec.yaml` означает только техническую доступность пакета.

Она не означает, что любой слой может использовать этот пакет напрямую.

---

## 2. Уровни архитектуры

Система состоит из следующих архитектурных уровней:

```text id="ll6a2s"
┌─────────────────────────────────────────────┐
│               codelab_desktop               │
│                                             │
│ presentation, оркестрация приложения        │
│ composition root, интеграция с desktop      │
└──────────────────────┬──────────────────────┘
                       │
             ┌─────────┴─────────┐
             ▼                   ▼
┌───────────────────────┐  ┌───────────────────────┐
│      codelab_ui       │  │  codelab_client_acp   │
│                       │  │                       │
│ переиспользуемый UI   │  │ переиспользуемая      │
│ на Flutter            │  │ логика ACP-клиента    │
└───────────────────────┘  └───────────┬───────────┘
                                       │
                         ┌─────────────┴─────────────┐
                         ▼                           ▼
              ┌────────────────────────┐  ┌────────────────────────┐
              │ codelab_acp_transports │  │  codelab_acp_protocol  │
              │                        │  │                        │
              │ транспортный слой      │  │ проводной протокол     │
              └───────────┬────────────┘  └────────────────────────┘
                          │
                          ▼
                    внешний агент
```

Тестовая инфраструктура находится отдельно:

```text id="55dykc"
codelab_acp_testing
    │
    └── используется только тестовым и dev-кодом
```

В коде клиентская сторона шире схемы: между приложениями и `codelab_client_acp` стоит общий клиентский слой `codelab_client_core` (владелец состояния рабочего пространства), его `dart:io`-адаптеры — `codelab_client_io`, а вторым клиентом рядом с `codelab_desktop` работает `apps/codelab_cli`. Фактические рёбра: `codelab_desktop` и `codelab_cli` → `codelab_client_core`, `codelab_client_io`, `codelab_client_acp`, `codelab_acp_protocol`, `codelab_acp_transports`, мосты `codelab_setup` и `codelab_embedded`; `codelab_desktop` → `codelab_ui`; `codelab_client_io` → `codelab_client_core` → `codelab_client_acp` → `codelab_acp_transports` → `codelab_acp_protocol` (`pubspec.yaml` пакетов; схема зависимостей app — `apps/codelab_desktop/doc/01-overview.md`). Направление `codelab_client_core` → `codelab_client_acp` обратно агентскому `codelab_agent_acp` → `codelab_agent_core`: одинаковые имена слоёв у сторон не означают одинакового направления (ADR-0002, Consequences). `codelab_ui` не зависит ни от одного пакета `codelab_*`. Агентская сторона и мосты — §53.

---

## 3. Главное правило зависимостей

Зависимости ДОЛЖНЫ быть направлены от более высокоуровневых компонентов к более низкоуровневым либо к абстракциям, задающим границу.

Запрет зависимости пакетов от приложений и циклов между пакетами — корневой `AGENTS.md` §5. Ниже — какие рёбра между пакетами клиентской стороны этим исключаются.

ЗАПРЕЩЕНО:

```text id="ljd98u"
codelab_acp_protocol
    → codelab_client_acp

codelab_acp_protocol
    → codelab_ui

codelab_acp_protocol
    → codelab_desktop

codelab_acp_transports
    → codelab_ui

codelab_acp_transports
    → codelab_desktop

codelab_client_acp
    → codelab_ui

codelab_client_acp
    → codelab_desktop

codelab_ui
    → codelab_desktop
```

В коде ни одного из этих рёбер нет: в `pubspec.yaml` пакетов нет зависимостей от `apps/*`, а у `codelab_acp_protocol` и `codelab_ui` нет зависимостей от других пакетов `codelab_*`.

---

## 4. Матрица зависимостей

Базовая политика зависимостей:

| Откуда ↓ / Куда → | `codelab_acp_protocol` | `codelab_acp_transports` | `codelab_client_acp` | `codelab_ui` | `codelab_desktop` | `codelab_acp_testing` |
| ----------------- | -------------: | ---------------: | ----------------: | -------: | ------------: | ------------: |
| `codelab_acp_protocol`    |              — |                ❌ |                 ❌ |        ❌ |             ❌ |             ❌ |
| `codelab_acp_transports`  |              ✅ |                — |                 ❌ |        ❌ |             ❌ |             ❌ |
| `codelab_client_acp` |              ✅ |               ✅* |                 — |        ❌ |             ❌ |             ❌ |
| `codelab_ui`          |             ⚠️ |                ❌ |                ⚠️ |        — |             ❌ |             ❌ |
| `codelab_desktop`     |              ✅ |                ✅ |                 ✅ |        ✅ |             — |             ❌ |
| `codelab_acp_testing`     |              ✅ |                ✅ |                 ✅ |       ❌* |             ❌ |             — |

Обозначения:

* ✅ — зависимость разрешена;
* ❌ — зависимость запрещена;
* ⚠️ — зависимость МОЖНО добавить только при архитектурной необходимости;
* `*` — см. отдельные правила ниже.

Матрица описывает архитектурную политику.

Фактический `pubspec.yaml` ДОЛЖЕН быть не шире необходимого графа зависимостей.

Матрица относится к клиентской стороне. Пакеты агентской стороны (`codelab_agent_*`) и мосты `codelab_setup`, `codelab_embedded` описаны в разделе 53.

В коде матрица не покрывает `codelab_client_core`, `codelab_client_io` и `apps/codelab_cli`: их границы заданы allowlist-ами сторожа (`kitAllowlist`, `clientIoAllowlist`, `cliAllowlist` в `pubspec_allowlist_test.dart`) и правилами импорта (`rules.dart`). Ячейки ⚠️ не использованы: `codelab_ui` не зависит ни от `codelab_acp_protocol`, ни от `codelab_client_acp`. `codelab_acp_testing` у `codelab_desktop` — только в `dev_dependencies`; ячейка ❌ касается рабочих зависимостей (§9, §41). Правило «не шире необходимого» в коде нарушено: `fpdart` объявлен в `dependencies` `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_acp_testing` и `apps/codelab_desktop`, но ни один их файл `package:fpdart` не импортирует (импортирует только `codelab_client_acp`, `lib/src/application/use_cases.dart`); `flutter_bloc` объявлен в `codelab_ui`, но не импортируется. Сторож это не проверяет: у этих пакетов нет allowlist-а, а у `apps/codelab_desktop` проверяются только пакеты `codelab_*`.

---

## 5. `codelab_acp_protocol`

Пакет:

`packages/dart/codelab_acp_protocol`

### Ответственность

`codelab_acp_protocol` представляет проводной контракт ACP.

Может содержать:

* модели запросов и ответов;
* уведомления;
* протокольные DTO;
* идентификаторы;
* сериализацию;
* десериализацию;
* протокольную валидацию;
* протокольные ошибки;
* совместимость версий.

### Разрешённые зависимости

Только библиотеки на чистом Dart, необходимые для реализации протокола.

### Запрещённые зависимости

`codelab_acp_protocol` НЕ ДОЛЖЕН зависеть от:

* `codelab_acp_transports`;
* `codelab_client_acp`;
* `codelab_ui`;
* `codelab_desktop`;
* Flutter;
* `flutter_bloc`;
* `fluent_ui`;
* UI платформы.

### Инвариант

```text id="k1fmlo"
проводной контракт ACP
      │
      ▼
codelab_acp_protocol
```

Для определения сообщения ACP НЕ ДОЛЖНО требоваться ничего из слоёв application или presentation.

В коде зависимости пакета — `fpdart`, `freezed_annotation`, `json_annotation`, `meta`; `fpdart` не используется (§4). Правила импорта для пакета в `rules.dart` нет: отсутствие Flutter держит состав `pubspec.yaml` (`acp-boundary.md` §3).

---

## 6. `codelab_acp_transports`

Пакет:

`packages/dart/codelab_acp_transports`

### Ответственность

Транспортный пакет отвечает за доставку сообщений ACP между клиентом и агентом.

Может содержать:

* транспорт stdio;
* транспорт процесса;
* потоковый транспорт;
* транспорт сокета;
* разбиение на кадры (framing);
* жизненный цикл транспорта;
* ошибки транспорта.

### Разрешённые зависимости

`codelab_acp_transports` МОЖЕТ зависеть от:

* `codelab_acp_protocol`;
* Dart SDK;
* библиотек на чистом Dart, нужных конкретному транспорту.

### Запрещённые зависимости

НЕ ДОЛЖЕН зависеть от:

* `codelab_client_acp`;
* `codelab_ui`;
* `codelab_desktop`;
* presentation на Flutter;
* `flutter_bloc`;
* `fluent_ui`.

### Граница транспорта

Транспорт отвечает за:

```text id="fngjcp"
байты / потоки
      ↕
сообщения ACP
```

Транспорт НЕ отвечает за:

```text id="sz1o87"
UI сессии
диалоги разрешений
навигацию
бизнес-состояние
состояние представления
```

В коде основной барель `package:codelab_acp_transports/codelab_acp_transports.dart` web-безопасен (порт `AcpTransport`, `InProcessAcpLink`, конфигурации транспортов); IO-транспорты (`StdioAcpTransport`, `WebSocketAcpTransport`, серверные `StdioServerAcpTransport` и `WebSocketServerAcpTransport`) экспортирует только `package:codelab_acp_transports/io.dart`. Сторож запрещает пакету `webUnsafe` (в том числе `package:flutter/`) везде, кроме `lib/io.dart` и `lib/src/io/`, и запрещает остальному коду пакета, включая основной барель, ссылаться на них (`sealExclude`). Зависимости — `codelab_acp_protocol`, `fpdart` (не используется, §4), `freezed_annotation`, `meta`, `web_socket_channel`.

---

## 7. `codelab_client_acp`

Пакет:

`packages/dart/codelab_client_acp`

### Ответственность

`codelab_client_acp` содержит переиспользуемое клиентское поведение ACP уровня application.

Может содержать:

* оркестрацию ACP-клиента;
* координацию соединения;
* жизненный цикл сессии;
* жизненный цикл запроса;
* отмену;
* события ACP уровня application;
* абстракции разрешений;
* автоматы состояний клиента;
* преобразование протокольных понятий в понятия application.

### Разрешённые зависимости

`codelab_client_acp` МОЖЕТ зависеть от:

* `codelab_acp_protocol`;
* абстракций транспорта;
* `codelab_acp_transports`, если конкретный транспорт — осознанная часть архитектуры клиентского ядра;
* библиотек на чистом Dart.

### Предпочтительная граница

Если это практично, `codelab_client_acp` СЛЕДУЕТ зависеть от абстракции транспорта, а конкретный транспорт создавать выше — в composition root.

Предпочтительно:

```text id="gocztb"
codelab_client_acp
       │
       ▼
интерфейс транспорта
       ▲
       │
codelab_acp_transports
```

вместо жёсткой связи:

```text id="3c0fr4"
codelab_client_acp
       │
       ▼
ConcreteStdioTransport
```

Это особенно важно, если транспортов несколько или они планируются.

### Запрещённые зависимости

`codelab_client_acp` НЕ ДОЛЖЕН зависеть от:

* Flutter;
* `flutter_bloc`;
* `fluent_ui`;
* `codelab_ui`;
* `codelab_desktop`;
* виджетов;
* `BuildContext`;
* навигации;
* диалогов.

### Инвариант

Если поведение ACP-клиента можно полностью проверить обычным Dart-тестом без Flutter binding, это сильный кандидат для `codelab_client_acp`.

В коде пакет зависит от основного бареля `codelab_acp_transports` ради порта `AcpTransport`: `AcpClientApplication({required AcpTransport transport, ...})` получает транспорт снаружи, а конкретный создаёт composition root (`_createStdioTransport` в `apps/codelab_desktop/lib/app/app_scope.dart`, `ioTransportResolver` в `codelab_client_io`). Остальные зависимости — `codelab_acp_protocol`, `fpdart`, `freezed_annotation`, `meta`, `path`, `structured_log`. Сторож запрещает пакету `webUnsafe` (в том числе `package:flutter/` и `package:codelab_acp_transports/io.dart`) и пакеты языка интерфейса `uiLanguageForbidden`; `flutter_bloc` и `fluent_ui` отдельно не перечислены, но без Flutter SDK в `pubspec.yaml` их импорт не разрешится. Allowlist-а у пакета нет.

---

## 8. `codelab_ui`

Пакет:

`packages/flutter/codelab_ui`

### Ответственность

`codelab_ui` содержит переиспользуемое presentation на Flutter для ACP.

Может содержать:

* виджеты ACP;
* переиспользуемый UI разговора;
* UI вызовов инструментов;
* UI статусов;
* показ запросов разрешения;
* переиспользуемые модели представления;
* компоненты, знающие о BLoC.

### Разрешённые зависимости

`codelab_ui` МОЖЕТ зависеть от:

* Flutter;
* `fluent_ui`;
* `flutter_bloc`;
* `flutter_localizations` и `intl` — только для собственного каталога сообщений кита (`CodeLabLocalizations`, раздел 54; change `add-desktop-localization`, D4).

Зависимость от `codelab_client_acp` или `codelab_acp_protocol` МОЖНО добавить, только если переиспользуемый UI действительно должен понимать соответствующую публичную модель.

### Предпочтение

СЛЕДУЕТ предпочитать:

```text id="37e1mo"
модель ACP / application
        │
        ▼
преобразование для presentation
        │
        ▼
модель / виджет codelab_ui
```

вместо распространения сырых протокольных DTO по дереву виджетов.

### Запрещённые зависимости

`codelab_ui` НЕ ДОЛЖЕН зависеть от:

* `codelab_desktop`;
* конкретного транспорта ACP;
* composition root приложения;
* сервисов, специфичных для desktop-приложения.

### Инвариант

`codelab_ui` ДОЛЖЕН оставаться переиспользуемым.

Если компонент имеет смысл только внутри одной фичи `codelab_desktop`, его НЕ СЛЕДУЕТ автоматически переносить в `codelab_ui`.

В коде `codelab_ui` не зависит ни от одного пакета `codelab_*` (`pubspec.yaml`): модели ACP и состояние клиента переводит в типы кита маппер app `apps/codelab_desktop/lib/features/workbench/application/ui_mappers.dart` (`README.md` пакета). Правила кита — `packages/flutter/codelab_ui/AGENTS.md` (§2 «Нет логики»: виджет не решает, опасно ли действие, и не разбирает протокольный текст). Сторож проверяет у кита только импорты: парсер `gpt_markdown` и подсветка `val_highlight` — лишь в `lib/src/rendering/`, их транзитивные пакеты (`material_ui`, `cupertino_ui`, `flutter_svg` и др.) и плагин перетаскивания из ОС `desktop_drop` запрещены везде (нативный плагин — инфраструктура app, `AGENTS.md` §11); отсутствие бизнес-логики и зависимости от `codelab_desktop` сторож не проверяет. Текст интерфейса кита — `ui_literals_test.dart` (§54).

Общие UI-примитивы — кнопки, текст, значки, бейджи, индикаторы, палитра и тоны (`CodeLabButton`, `CodeLabText`, `CodeLabBadge`, `CodeLabPalette` и др.) — живут в одном месте, `packages/flutter/codelab_ui/lib/src/atomics/`; составные виджеты — `molecules/` и `organisms/`. Новый примитив, нужный нескольким фичам app, СЛЕДУЕТ добавлять в `atomics/`, а не повторять в фичах (§46; раньше это была норма удалённого требования `workspace-architecture` «Ограничения SOLID, KISS и DRY», change `align-cross-cutting-specs`, D5).

---

## 9. `codelab_acp_testing`

Пакет:

`packages/dart/codelab_acp_testing`

### Ответственность

Переиспользуемая тестовая инфраструктура.

Может содержать:

* фейкового ACP-агента;
* фейковый транспорт;
* фикстуры;
* построители протокольных сообщений;
* тестовые фабрики;
* утилиты для тестов жизненного цикла;
* помощники проверок.

### Зависимости

`codelab_acp_testing` МОЖЕТ зависеть от ACP-пакетов на чистом Dart:

* `codelab_acp_protocol`;
* `codelab_acp_transports`;
* `codelab_client_acp`.

Рабочий код НЕ ДОЛЖЕН зависеть от `codelab_acp_testing`.

Если появятся переиспользуемые тестовые помощники для Flutter, СЛЕДУЕТ рассмотреть отдельный тестовый пакет для Flutter вместо добавления Flutter в чистый Dart-пакет `codelab_acp_testing`.

В коде пакет зависит от `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_client_acp` и `fpdart` (не используется, §4). У всех пакетов и у `apps/codelab_desktop` он в `dev_dependencies`. Единственное исключение из запрета для рабочего кода — `apps/codelab_cli`: команда `test-scenario` проигрывает фикстуры в рабочем бинаре, поэтому пакет — обычная зависимость, а импорт разрешён только из `lib/src/scenario/` (корневой `AGENTS.md` §5; правило `apps/codelab_cli/lib/src` в `rules.dart`; change `add-codelab-cli`, D3).

---

## 10. `codelab_desktop`

Приложение:

`apps/codelab_desktop`

### Ответственность

`codelab_desktop` — конечное desktop-приложение и composition root.

Отвечает за:

* запуск приложения;
* сборку зависимостей;
* возможности, специфичные для desktop;
* навигацию;
* состояние верхнего уровня;
* presentation приложения;
* связывание ядра ACP с UI на Flutter;
* адаптеры платформы.

### Разрешённые зависимости

Приложение МОЖЕТ зависеть от:

* `codelab_acp_protocol`;
* `codelab_acp_transports`;
* `codelab_client_acp`;
* `codelab_ui`;
* Flutter;
* `flutter_bloc`;
* Cherrypick;
* `fpdart`;
* утверждённых пакетов платформы.

Однако каждую зависимость ДОЛЖЕН использовать только соответствующий слой.

В коде к этому списку добавлены `codelab_client_core`, `codelab_client_io` и мосты `codelab_setup`, `codelab_embedded`; это весь допустимый набор пакетов `codelab_*` (`desktopAllowlist`). Пакеты `codelab_agent_*` в зависимостях и импортах app запрещены сторожем (корневой `AGENTS.md` §5). Сторонние зависимости app и правила их изоляции в `lib/core/platform/` — [обзор app, «Правила зависимостей и как их проверяет сторож»](../../apps/codelab_desktop/doc/01-overview.md#правила-зависимостей-и-как-их-проверяет-сторож) и `platform-integration.md` §8.

---

## 11. Внутренняя структура `codelab_desktop`

Предпочтительная структура:

```text id="zxg2s2"
lib/
├── app/
│   ├── bootstrap/
│   ├── di/
│   ├── routing/
│   └── ...
│
├── core/
│   └── общий код, специфичный для приложения
│
└── features/
    ├── chat/
    ├── sessions/
    ├── settings/
    └── ...
```

Фича МОЖЕТ быть простой (пример иллюстративный):

```text id="87uazp"
features/settings/
├── settings_page.dart
├── settings_cubit.dart
└── settings_state.dart
```

или более сложной:

```text id="gxy9ns"
features/chat/
├── application/
├── infrastructure/
└── presentation/
```

НЕ СЛЕДУЕТ создавать `domain/application/infrastructure/presentation` автоматически.

В коде `lib/app/` не разбит на `bootstrap/`, `di/` и `routing/`: сборка и запуск — `app_scope.dart` (`createCodeLabRootScope`, `CodeLabBootstrap`), корневой виджет — `codelab_app_widget.dart`, рядом подкаталоги `appearance/`, `language/`, `navigation/` (`NavigationCubit`, `AppDestination`; пакета маршрутизации нет), `onboarding/`. `lib/core/` — `platform/` (адаптеры платформы и хранилища настроек) и `text/`. Фичи — `workbench`, `settings`, `onboarding`, `project_files`, `terminal`, `protocol`, `usage`; у каждой только `application/` и `presentation/`: доменная логика живёт в `codelab_client_core` и `codelab_client_acp`, адаптеры — в `lib/core/platform/` и `lib/app/` (`apps/codelab_desktop/doc/01-overview.md`). Каталогов `chat/` и `sessions/` нет: их роль играет `workbench`.

---

## 12. Границы фич

Фича ДОЛЖНА владеть поведением, специфичным для своей возможности.

Например:

```text id="1wjjhp"
features/
├── chat/
├── sessions/
├── settings/
└── workbench/
```

Одна фича НЕ ДОЛЖНА импортировать закрытую реализацию другой фичи.

Запрещённый шаблон:

```text id="pd29v2"
features/chat/internal/foo.dart
              ▲
              │
features/settings/bar.dart
```

Если функциональность действительно общая:

1. определить её смыслового владельца;
2. выделить публичный API фичи;
3. либо перенести её в `core` уровня приложения;
4. либо вынести в переиспользуемый пакет, если она нужна нескольким приложениям или пакетам.

В коде у фич нет разделения на публичный API и закрытую реализацию (каталогов `internal/` или `src/` нет): фичи импортируют файлы `application/` и `presentation/` друг друга напрямую. Так `workbench` импортирует `settings/application/`, `usage/application/`, `protocol/application/`, `terminal/application/`, а `onboarding` — `settings/application/` и `workbench/application/`. Связь через узкий интерфейс application — например, `ConnectionCommands` (`features/settings/application/connection_commands.dart`), его реализует `ConnectionCubit` фичи `workbench` (§27). Сторож границы фич не проверяет.

---

## 13. `app/`

`app/` содержит сборку уровня приложения.

Типичные обязанности:

* запуск;
* сборка DI;
* навигация;
* жизненный цикл окна и приложения верхнего уровня;
* связывание глобальных BLoC;
* конфигурация приложения.

`app/` НЕ ДОЛЖЕН превращаться в место хранения бизнес-логики фич.

---

## 14. `core/` уровня приложения

`apps/codelab_desktop/lib/core/` предназначен только для действительно общего кода, специфичного для приложения.

Примеры:

* абстракции уровня приложения;
* общие примитивы presentation;
* адаптеры, нужные нескольким фичам;
* общие ошибки приложения, если они действительно нужны нескольким фичам.

`core/` НЕ ДОЛЖЕН становиться свалкой.

Перед переносом кода в `core` ДОЛЖНЫ быть определены минимум два независимых потребителя либо другая ясная сквозная ответственность.

В коде этому правилу следуют порты `lib/core/platform/`: например, `ConnectionPreferences` нужен странице «Connection», рабочему месту и composition root, поэтому лежит в `core/platform/`, а `SettingsPageStore` с одним потребителем (`NavigationCubit`) — рядом с ним в `lib/app/navigation/` (doc-комментарии этих портов).

---

## 15. Слой presentation

Presentation включает:

* виджеты Flutter;
* страницы;
* диалоги;
* BLoC/Cubit;
* состояние представления;
* преобразование для presentation;
* интеграцию с навигацией.

Presentation МОЖЕТ зависеть от API уровня application.

Presentation НЕ ДОЛЖЕН напрямую:

* управлять низкоуровневым транспортом;
* выполнять сериализацию ACP;
* создавать процессы;
* обращаться к реализации файловой системы;
* принимать решения политики безопасности.

Правильный поток:

```text id="uvokq4"
пользователь
 │
 ▼
виджет
 │
 ▼
BLoC / Cubit
 │
 ▼
API application
```

В коде Cubit-ы desktop лежат в `features/*/application/`, а не в `presentation/`; в `presentation/` — только виджеты (`apps/codelab_desktop/doc/03-state-flow.md`, `state-management.md`). В `presentation/` нет импортов `dart:io`, `codelab_acp_transports` и `codelab_client_io`. Сторож запрещает `dart:io` в `features/settings/presentation/`, во всей фиче `onboarding` и во всей фиче `project_files`, IO-барели мостов `codelab_embedded/io.dart` и `codelab_setup/io.dart` — во всём `lib/` app, кроме `lib/app/`, а пять плагинов платформы (`file_selector`, `url_launcher`, `pty2`, `desktop_drop`, `system_theme`) — вне своих адаптеров в `lib/core/platform/`. Общего запрета `dart:io` и транспортов для `presentation/` остальных фич в стороже нет.

---

## 16. Слой application

Слой application определяет действия системы.

Например:

* подключиться;
* создать сессию;
* отправить промпт;
* отменить запрос;
* переподключиться;
* ответить на запрос разрешения;
* обработать событие ACP.

Слой application:

* координирует зависимости;
* определяет переходы состояния application;
* применяет политики application.

Он НЕ ДОЛЖЕН зависеть от:

* виджетов Flutter;
* `BuildContext`;
* диалогов;
* конкретных визуальных компонентов.

Для переиспользуемого поведения ACP предпочтительный владелец — `codelab_client_acp`.

В коде `BuildContext` в `features/*/application/` не используется. Часть файлов application импортирует типы Flutter, не являющиеся виджетами: `ImageProvider` из `package:flutter/painting.dart` (`workbench/application/shell_cubit.dart`), `listEquals`, `mapEquals` из `package:flutter/foundation.dart` (`settings/application/legal_page_state.dart`), `FluentIcons`, `FluentThemeData`, `AccentColor` из `fluent_ui` (`ui_mappers.dart`, `contrast_checks.dart`, `appearance_settings_cubit.dart`), модели кита `codelab_ui` и сгенерированный `AppLocalizations`; сами Cubit-ы — из `flutter_bloc`. Сторож запрещает `package:flutter/` только в `features/terminal/application/`, `features/usage/application/` и `features/protocol/application/`. Переиспользуемое поведение лежит ниже: `AcpClientApplication` (`codelab_client_acp`) и `ClientWorkspace` (`codelab_client_core`).

---

## 17. Слой domain

Отдельный слой domain создаётся только там, где есть реальная доменная модель или инварианты.

Domain может содержать:

* сущности;
* объекты-значения;
* автоматы состояний;
* политики;
* доменные ошибки.

НЕ СЛЕДУЕТ создавать слой domain только потому, что архитектурный шаблон содержит слово `domain`.

Domain НЕ ДОЛЖЕН зависеть от Flutter или infrastructure.

В коде слой domain есть только в `codelab_client_acp` (`lib/src/domain/`: автоматы `state_machines.dart`, модели `domain_models.dart`, `ApprovalPolicy`, порты `fs_access.dart` и `terminal_access.dart`); Flutter ему запрещает правило пакета в `rules.dart`. В фичах desktop каталогов `domain/` нет (§11).

---

## 18. Слой infrastructure

Infrastructure реализует взаимодействие с внешним миром.

Примеры:

* транспорт ACP;
* файловая система;
* защищённое хранилище;
* хранение данных;
* нативные API;
* внешний процесс;
* сеть.

Предпочтительный шаблон:

```text id="7gk75k"
application
    │
    ▼
порт / абстракция
    ▲
    │
адаптер infrastructure
    │
    ▼
внешняя система
```

Конкретные зависимости infrastructure ДОЛЖНЫ создаваться в composition root.

В коде так устроены, например, порт `TextFileReader` (`codelab_client_acp/lib/src/domain/fs_access.dart`) и его адаптер `IoTextFileIo` (`codelab_client_io`), порт `ExecutionEnv` ядра агента и `LocalExecutionEnv` (`codelab_agent_io`), порты `lib/core/platform/` desktop (`ProjectFolderPicker`, `ExternalLinkOpener`, `UserShellLauncher` и др.). Подробно — `platform-integration.md`.

---

## 19. Границы моделей ACP

СЛЕДУЕТ различать минимум три вида моделей:

```text id="vvtl2s"
протокольная модель
     ↓ преобразование
прикладная модель
     ↓ преобразование
модель представления
```

Не каждый переход требует отдельного класса.

Преобразование нужно тогда, когда у моделей разные смысл или жизненный цикл.

### Протокольная модель

Описывает проводное представление.

Владелец:

`codelab_acp_protocol`

### Прикладная модель

Описывает понятия ACP-клиента.

Владелец:

`codelab_client_acp` или соответствующая фича application.

### Модель представления

Описывает данные в форме, удобной UI.

Владелец:

`codelab_ui` или presentation конкретной фичи.

В коде вызов инструмента проходит уровни `ToolCall` (`codelab_acp_protocol`) → `ToolCallRecord` (`codelab_client_acp`) → `ToolCallItem` транскрипта (`codelab_client_core`) → `CodeLabToolCallRow` (`codelab_ui`); последний шаг делает `ui_mappers.dart` в `features/workbench/application/` (`acp-boundary.md`).

---

## 20. Когда преобразование НЕ нужно

НЕ СЛЕДУЕТ создавать отдельные модели только ради слоёв.

Если неизменяемый объект-значение:

* имеет одинаковый смысл;
* не содержит протокольных деталей;
* не создаёт нежелательной зависимости;
* не требует отдельного жизненного цикла;

его МОЖНО переиспользовать.

Цель — контролировать связанность, а не увеличивать число DTO.

---

## 21. Владение состоянием

У каждого состояния ДОЛЖЕН быть один понятный владелец.

Например:

```text id="zunq6e"
состояние транспорта
    → транспорт

состояние клиента и сессии ACP
    → codelab_client_acp

состояние представления
    → BLoC/Cubit

эфемерное состояние виджета
    → виджет
```

НЕ СЛЕДУЕТ хранить одно авторитетное состояние одновременно в нескольких слоях.

Производное состояние представления МОЖНО хранить, но источник истины ДОЛЖЕН быть понятен.

В коде между клиентом ACP и Cubit-ами есть ещё один владелец — `ClientWorkspace` (`codelab_client_core`): ему принадлежат соединение, сессии, транскрипт, очередь промптов и одобрения, общие для app и CLI. Подробно — `state-management.md` (абзац «Где в коде», §1).

---

## 22. Владение побочными эффектами

У каждого побочного эффекта ДОЛЖЕН быть определённый архитектурный владелец.

| Побочный эффект | Владелец |
| --------------------- | ---------------------- |
| сериализация ACP | `codelab_acp_protocol` |
| ввод-вывод транспорта ACP | `codelab_acp_transports` |
| оркестрация сессий | `codelab_client_acp` |
| политика разрешений | application / ядро |
| диалог | presentation |
| навигация | presentation / app |
| файловая система | адаптер infrastructure |
| защищённое хранилище | адаптер infrastructure |
| запуск процессов | адаптер infrastructure |
| отрисовка | presentation на Flutter |

Фича НЕ ДОЛЖНА выполнять побочный эффект только потому, что соответствующий пакет технически доступен.

В коде адаптеры файловой системы, процессов и хранилищ — `codelab_client_io`, `lib/core/platform/` desktop и `codelab_agent_io`; классификация риска одобрения — `ApprovalPolicy` (`codelab_client_acp`), политика разрешений агента — `PermissionPolicy` (`codelab_agent_core/lib/src/permissions/policy.dart`); навигация desktop — `NavigationCubit` (`lib/app/navigation/`).

---

## 23. Граница внедрения зависимостей

Cherrypick используется для сборки, но НЕ отменяет правила зависимостей.

Неправильно:

```text
виджет
  │
  └── resolve ConcreteTransport
```

Правильно:

```text
composition root
      │
      ├── ConcreteTransport
      │
      ├── ACP-клиент
      │
      └── API application
                 │
                 ▼
              BLoC/Cubit
                 │
                 ▼
               виджет
```

DI-контейнер ДОЛЖЕН использоваться для сборки графа объектов, а не как способ получить произвольную зависимость из любой точки приложения.

СЛЕДУЕТ предпочитать внедрение через конструктор или установленный шаблон Cherrypick.

НЕ СЛЕДУЕТ:

* передавать DI-контейнер глубоко в код application;
* использовать контейнер как глобальный service locator;
* разрешать зависимость прямо внутри domain;
* разрешать зависимость infrastructure прямо внутри виджета.

В коде desktop открывает один root scope `CherryPick.openRootScope()` в `createCodeLabRootScope` (`lib/app/app_scope.dart`); `resolve` вызывается только в `app_scope.dart` и сгенерированном `app_scope.module.cherrypick.g.dart`. Виджеты получают зависимости через типизированный `CodeLabDependencies` (`codeLabDependenciesOf(context)`, `InheritedWidget` `CodeLabDependenciesScope`): Cubit-ы процесса, фабрики Cubit-ов страниц и порты, а не сам scope (время жизни — `state-management.md`, абзац «Где в коде»). Глобальный `getLogger()`/`StructlogConfiguration` пакета `structured_log` — сознательное исключение из запрета на глобальный service locator (design.md change [`add-structured-logging`](../../openspec/changes/archive/2026-10-08-add-structured-logging/design.md), Decision 7; `technology-stack.md` §17.1).

---

## 24. Composition root

`codelab_desktop` — главный composition root desktop-приложения.

Composition root отвечает за связывание:

* конкретных транспортов ACP;
* ACP-клиента;
* адаптеров платформы;
* реализаций хранилищ;
* сервисов application;
* BLoC/Cubit;
* навигации;
* конфигурации.

Composition root МОЖЕТ знать о конкретных реализациях.

Нижележащие слои НЕ ДОЛЖНЫ получать эту ответственность.

Пример (имена иллюстративные):

```text
main / bootstrap
      │
      ▼
сборка Cherrypick
      │
      ├── StdioTransport
      ├── AcpClient
      ├── PermissionPolicy
      ├── SecureStorageAdapter
      ├── PlatformAdapter
      └── SessionBloc
```

Создавать новую конкретную зависимость СЛЕДУЕТ в composition root либо в модуле сборки своей области, если проект использует такую структуру.

В коде composition root desktop — `createCodeLabRootScope` (`apps/codelab_desktop/lib/app/app_scope.dart`): модули Cherrypick `CodeLabLoggingModule`, `CodeLabProtocolModule`, `CodeLabTransportRuntimeModule`, `CodeLabEmbeddedAgentModule`, `CodeLabLanguageModule`, `CodeLabOnboardingModule`, `CodeLabAppearanceModule`, `CodeLabPlatformModule`, `CodeLabConnectionModule`, `CodeLabPresentationModule` и сгенерированные `CodeLabTransportsModuleContract`, `CodeLabProtocolApplicationModuleContract`, `CodeLabRootLifecycleModuleContract`; закрытие — `CodeLabRootLifecycle`. IO-барели мостов (`codelab_embedded/io.dart`, `codelab_setup/io.dart`) в app разрешены только `lib/app/` (сторож). Composition root CLI — `buildCliRuntime` (`apps/codelab_cli/lib/src/composition_root.dart`), единственное место CLI, где разрешён `codelab_embedded/io.dart`; агент как процесс собирается в `apps/codelab_agent` (`lib/src/host/agent_host.dart`, `buildAgentCore`).

---

## 25. Публичный API пакетов

Зависимость между пакетами ДОЛЖНА проходить через публичный API пакета.

Предпочтительно:

```dart
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
```

вместо импорта внутренних файлов реализации другого пакета.

Публичный API ДОЛЖЕН экспортировать только те сущности, которые действительно составляют контракт пакета.

НЕ СЛЕДУЕТ экспортировать всё содержимое `lib/src/` ради удобства.

Публичный API пакета ДОЛЖЕН оставаться минимальным и осмысленным.

В коде у части пакетов несколько барелей с разной областью: `codelab_acp_transports` (`codelab_acp_transports.dart`, `io.dart`), `codelab_setup` (`codelab_setup.dart`, `io.dart`), `codelab_embedded` (`codelab_embedded.dart`, `io.dart`, `testing.dart`), `codelab_agent_core`, `codelab_agent_io` и `codelab_agent_mcp` (основной барель и `testing.dart`). Кто какой барель может импортировать — корневой `AGENTS.md` §5 и `rules.dart`.

---

## 26. Внутренний API

Детали реализации пакета ДОЛЖНЫ находиться вне его публичного контракта.

Предпочтительная структура:

```text
lib/
├── codelab_acp_protocol.dart
└── src/
    ├── models/
    ├── serialization/
    └── ...
```

Код другого пакета НЕ ДОЛЖЕН импортировать:

```dart
package:some_package/src/...
```

если это не осознанное и явно документированное исключение.

Если внешнему потребителю приходится использовать `src`, СЛЕДУЕТ проверить, не отсутствует ли нужная сущность в публичном API.

В коде в `lib/` и `bin/` пакетов и приложений импортов `package:<другой пакет>/src/` нет. В тестах их два: `codelab_agent_acp/test/projection/event_projection_test.dart` → `package:codelab_agent_core/src/tools/pairing.dart` (без пояснения) и `codelab_embedded/test/fake_mcp_http_host_test.dart` → `package:codelab_agent_mcp/src/mcp_client.dart` (с комментарием и `// ignore_for_file: implementation_imports`). Сторож такие импорты не проверяет; `fvm dart analyze` на первом из них замечаний не выдаёт.

---

## 27. Связь между фичами

Фичи НЕ ДОЛЖНЫ связываться через закрытую реализацию друг друга.

Предпочтительные варианты взаимодействия:

### Через API уровня application

```text
фича A
   │
   ▼
API application
   ▲
   │
фича B
```

### Через общую абстракцию состояния или событий

Если несколько фич реагируют на одно событие уровня application:

```text
        событие application
             /       \
            ▼         ▼
        фича A     фича B
```

### Через публичный фасад фичи

Если одна фича явно предоставляет возможность другой:

```text
фича B
   │
   ▼
публичный API фичи A
```

НЕ СЛЕДУЕТ создавать глобальную шину событий только ради устранения прямых импортов.

В коде страница «Connection» получает узкий интерфейс `ConnectionCommands` (`features/settings/application/connection_commands.dart`), который реализует `ConnectionCubit` фичи `workbench`, а не обращается к его внутренностям (design.md change `add-app-settings-shell`, D4). Общее состояние фичи читают из проекций `ClientWorkspace`; глобальной шины событий нет. Публичных фасадов в отдельном файле у фич нет (§12).

---

## 28. События

События ДОЛЖНЫ принадлежать тому уровню, смысл которого они описывают.

Примеры (имена иллюстративные):

```text
AcpResponseReceived
    → уровень протокола / клиента

SessionConnected
    → уровень application / клиента

ChatScrolledToBottom
    → уровень presentation
```

НЕ СЛЕДУЕТ использовать один тип события одновременно как:

* протокольное сообщение;
* событие domain/application;
* событие BLoC;
* событие UI;

если у этих уровней разный смысл.

В коде событий с такими именами нет: транспорт публикует `AcpTransportEvent`, протокольный клиент — снимки `AcpSession` и `ClientConnectionState`, `ClientWorkspace` — проекции `WorkspaceState` и `SessionView`; desktop использует только `Cubit`, событий BLoC нет (`state-management.md`).

---

## 29. Границы ошибок

Ошибки тоже ДОЛЖНЫ следовать архитектурным границам.

Предпочтительный поток:

```text
внешнее исключение
      │
      ▼
ошибка infrastructure / транспорта
      │
      ▼
сбой application
      │
      ▼
состояние ошибки в presentation
      │
      ▼
сообщение пользователю
```

Не каждой ошибке нужен отдельный класс на каждом уровне.

Преобразование нужно, если:

* меняется смысл;
* нужно скрыть детали реализации;
* нужно привести к одному виду несколько внешних ошибок;
* UI не должен знать техническую ошибку;
* нужно добавить контекст application.

Типы ошибок по слоям — `error-handling.md` (абзац «Где в коде»).

---

## 30. Ошибки протокола

Ошибки уровня протокола принадлежат `codelab_acp_protocol`.

Например:

* некорректное сообщение;
* неподдерживаемые протокольные данные;
* сбой сериализации;
* некорректная форма протокольных данных.

Они НЕ ДОЛЖНЫ содержать поведение, специфичное для Flutter.

В коде — `AcpProtocolError` с видом `AcpProtocolErrorKind` и `JsonRpcProtocolException` (`codelab_acp_protocol/lib/src/json_rpc/protocol_error.dart`).

---

## 31. Ошибки транспорта

Ошибки транспорта принадлежат `codelab_acp_transports`.

Например:

* поток закрыт;
* процесс завершился;
* сокет отключился;
* ошибка разбиения на кадры;
* транспорт недоступен.

Ошибка транспорта НЕ ДОЛЖНА автоматически определять UX.

Например:

```text
SocketClosed
```

не означает автоматически:

```text
ShowReconnectDialog
```

Решение о переподключении и показе принадлежит более высокому слою.

В коде — `AcpTransportException` с кодом `AcpTransportErrorCode` и событие `AcpTransportEvent.failure` (`codelab_acp_transports/lib/src/acp_transport.dart`).

---

## 32. Сбои application

Слой application МОЖЕТ преобразовывать ошибки нижних уровней в более осмысленные сбои.

Например (имена иллюстративные):

```text
TransportClosedUnexpectedly
        │
        ▼
SessionConnectionLost
        │
        ▼
SessionState.reconnecting
```

Так presentation реагирует на смысл уровня application, а не на детали реализации транспорта.

В коде потеря транспорта становится `ClientConnectionState.failed` с `ConnectionFailureReason` (`codelab_client_acp`) и `ConnectionView.lost` (`codelab_client_core`); автоматического переподключения нет, его запускает пользователь через `ClientWorkspace.reconnect` (`error-handling.md` §79).

---

## 33. Граница разрешений

Политика разрешений ДОЛЖНА находиться выше транспорта и протокола, но ниже сбора решения в presentation.

Правильная зависимость:

```text
запрос ACP
    │
    ▼
политика разрешений application
    │
    ├── разрешено
    │
    ├── запрещено
    │
    └── нужно решение пользователя
                │
                ▼
            presentation
```

Неправильно:

```text
транспорт
   │
   └── showDialog()
```

или:

```text
виджет
   │
   └── if (tool.name == 'shell') ...
```

Presentation НЕ ДОЛЖНА содержать авторитетную политику безопасности.

В коде запрос агента `session/request_permission` становится `ApprovalRequest` в `codelab_client_acp`; его риск вычисляет `ApprovalPolicy` (`lib/src/domain/approval_policy.dart`), а app только переводит `ApprovalRiskLevel` в `CodeLabApprovalRisk` кита (`ui_mappers.dart`); ответ пользователя уходит через `respondToPermission`. Решение «спрашивать ли» принимает агент (`PermissionPolicy` в `codelab_agent_core`); для `fs/*` и `terminal/*` клиент вместо одобрения ограничивает пути рабочей папкой (`resolveWithinWorkingDirectory`, корневой `AGENTS.md` §10). Подробно — `permissions.md`.

---

## 34. Граница платформы

Функциональность, зависящая от платформы, ДОЛЖНА находиться за границей абстракции, если она влияет на поведение application.

Например (пример иллюстративный):

```dart
abstract interface class AppWindow {
  Future<void> minimize();

  Future<void> maximize();
}
```

Конкретная реализация МОЖЕТ использовать плагин платформы:

```text
application
    │
    ▼
AppWindow
    ▲
    │
FlutterDesktopWindowAdapter
    │
    ▼
плагин платформы
```

Это особенно важно для:

* управления окнами;
* файловой системы;
* защищённого хранилища;
* буфера обмена;
* уведомлений;
* запуска внешних процессов;
* путей платформы.

В коде порта `AppWindow` нет; реальные порты платформы desktop — `lib/core/platform/` (`ProjectFolderPicker`, `ThemeFilePicker`, `ExternalLinkOpener`, `LocalFolderOpener`, `UserShellLauncher`, `SystemAccentSource` и др.), а плагины изолированы правилами сторожа (`platform-integration.md` §4, §8).

---

## 35. `dart:io`

Использование `dart:io` само по себе не запрещено.

Однако оно ДОЛЖНО соответствовать границе.

МОЖНО:

```text
codelab_acp_transports
адаптеры infrastructure desktop
адаптеры файловой системы
адаптеры процессов
```

НЕ СЛЕДУЕТ использовать `dart:io` напрямую из:

* виджетов;
* BLoC слоя presentation, если это операция infrastructure;
* domain;
* переиспользуемых компонентов UI.

В коде `dart:io` импортируют: `codelab_acp_transports` (`lib/src/io/`), `codelab_client_io`, `codelab_agent_io`, IO-слои мостов (`codelab_setup/lib/src/io/`, `codelab_embedded/lib/src/io/` и `lib/src/testing/`), `codelab_acp_testing`, приложения CLI и агента; в desktop — только `lib/main.dart`, `lib/app/app_scope.dart` и адаптеры `lib/core/platform/`. В `features/` и в `codelab_ui` импортов `dart:io` нет. Часть Cubit-ов (`shell_cubit.dart`, `settings_cubit.dart`, `terminal_tabs_cubit.dart`) импортирует `codelab_client_io` ради одного typedef `DirectoryExists`; правила, запрещающего `package:codelab_client_io/` в `application/`, нет, а `dart:io` приходит через него транзитивно, и сканер импортов этого не видит.

---

## 36. Граница BLoC

`flutter_bloc` принадлежит стороне архитектуры Flutter/presentation.

BLoC/Cubit МОЖЕТ зависеть от API, обращённого к application.

Предпочтительно:

```text
виджет
   │
   ▼
BLoC
   │
   ▼
API ACP-клиента / application
```

НЕ СЛЕДУЕТ:

```text
виджет
   │
   ▼
BLoC
   │
   ▼
конкретный транспорт
```

BLoC НЕ ДОЛЖЕН подменять слой application.

Если BLoC начинает содержать:

* жизненный цикл транспорта;
* разбор протокола ACP;
* сложную политику разрешений;
* переиспользуемый автомат состояний сессии;
* значимые алгоритмы повтора и переподключения;

СЛЕДУЕТ проверить, не принадлежит ли эта логика `codelab_client_acp`.

В коде Cubit-ы работают через `ClientWorkspace` и `SessionHandle` (`codelab_client_core`) поверх `AcpClientApplication`. Из `codelab_acp_transports` они берут только типы основного бареля: фабрики `CodeLabStdioTransportFactory` и `CodeLabWebSocketTransportFactory` (`connection_cubit.dart`) возвращают порт `AcpTransport`, а конкретный транспорт создаёт `app_scope.dart`.

---

## 37. `codelab_ui` и BLoC

`codelab_ui` МОЖЕТ содержать виджеты, знающие о BLoC, поскольку пакет явно является пакетом presentation на Flutter.

Однако переиспользуемый визуальный компонент СЛЕДУЕТ по возможности отделять от конкретного контекста управления состоянием.

Предпочтительно (пример иллюстративный):

```dart
ToolCallView(
  status: state.status,
  name: state.name,
  onApprove: onApprove,
)
```

когда компонент чисто визуальный.

Обёртку, знающую о BLoC, МОЖНО добавить, если она действительно улучшает переиспользование:

```text
ToolCallBlocView
      │
      ▼
ToolCallView
```

Это уменьшает связанность переиспользуемых визуальных компонентов с конкретным BLoC.

В коде виджетов, знающих о BLoC, в `codelab_ui` нет: виджеты кита (например, `CodeLabToolCallTile`, `CodeLabApprovalPrompt`) получают значения и колбэки, а `flutter_bloc` в `lib/` кита не импортируется (§4).

---

## 38. Зависимость от Cherrypick

Cherrypick относится прежде всего к сборке и запуску приложения.

Наличие аннотаций НЕ ДОЛЖНО без необходимости заставлять низкоуровневые пакеты зависеть от DI-фреймворка.

Чистый переиспользуемый пакет СЛЕДУЕТ сохранять независимым от Cherrypick, если внедрение зависимостей может выполнить его потребитель.

Предпочтительно (пример иллюстративный):

```dart
class AcpClient {
  AcpClient({
    required AcpTransport transport,
  });
}
```

а привязку:

```text
AcpTransport → StdioAcpTransport
```

определять в слое сборки.

Это позволяет:

* тестировать компонент без контейнера;
* переиспользовать пакет вне приложения на Flutter;
* заменять конкретную реализацию;
* уменьшать связанность с фреймворком.

В коде так устроен `AcpClientApplication({required AcpTransport transport, ...})`; Cherrypick (`cherrypick`, `cherrypick_annotations`) есть только в зависимостях `apps/codelab_desktop`, пакеты от него не зависят.

---

## 39. Граница `fpdart`

`fpdart` МОЖЕТ использоваться в пакетах application на чистом Dart.

Однако публичный API пакета НЕ СЛЕДУЕТ делать зависимым от `fpdart` только ради удобства внутренней реализации, если это без необходимости заставляет всех потребителей работать с `Either`, `Option` и другими типами библиотеки.

Решение использовать типы `fpdart` в публичном контракте ДОЛЖНО быть осознанным.

Если `Either<Failure, T>` — утверждённая часть API application, его МОЖНО использовать.

Главное правило — единообразие.

В коде `fpdart` импортирует только `codelab_client_acp`: публичные результаты use case-ов — `TaskEither<AcpClientApplicationFailure, T>` (`lib/src/application/use_cases.dart`, экспортируется основным барелем). Объявления `fpdart` в других пакетах не используются (§4).

---

## 40. Граница Freezed

Freezed — инструмент реализации и генерации кода, и его МОЖНО использовать в разных слоях.

Однако сгенерированный API НЕ ДОЛЖЕН случайно связывать слои.

Например, Freezed-состояние BLoC НЕ ДОЛЖНО импортироваться в `codelab_client_acp` только потому, что оно удобно для UI.

Тип ДОЛЖЕН жить на том уровне, смысл которого он представляет.

В коде Freezed подключён в `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_client_acp`, `codelab_client_core` и `codelab_ui`; в `apps/codelab_desktop` — только в `dev_dependencies`, состояния Cubit-ов написаны вручную (`state-management.md`).

---

## 41. Тестовые зависимости

У тестового кода граф зависимостей МОЖЕТ быть шире, чем у рабочего.

Например:

```text
тесты codelab_client_acp
       │
       └── codelab_acp_testing
```

Это МОЖНО.

Однако тестовая зависимость НЕ ДОЛЖНА создавать рабочую зависимость.

Рабочий код из `lib/` НЕ ДОЛЖЕН импортировать тестовые помощники.

Пакеты только для тестов ДОЛЖНЫ находиться в `dev_dependencies`, если нет отдельной причины.

В коде отдельная причина одна — `apps/codelab_cli` (§9). Тестовые барели пакетов агента клиентам недоступны вовсе (запрет `package:codelab_agent_`); `codelab_embedded/testing.dart` в `lib/` CLI разрешён только драйверу фикстур `lib/src/scenario/`, а в `lib/` `apps/codelab_desktop` запрещён целиком (сторож). Через `dev_dependencies` есть ожидаемые обратные рёбра: `codelab_acp_transports` и `codelab_client_acp` используют в тестах `codelab_acp_testing`, который сам зависит от них.

---

## 42. Архитектурные тесты

Критические инварианты зависимостей СЛЕДУЕТ по возможности проверять автоматически.

Полезно проверять:

* `codelab_acp_protocol` не зависит от Flutter;
* `codelab_client_acp` не зависит от Flutter;
* `codelab_acp_transports` не зависит от presentation на Flutter;
* `codelab_ui` не зависит от `codelab_desktop`;
* рабочие пакеты не зависят от `codelab_acp_testing`;
* между пакетами нет запрещённых импортов `package:*/src/*`.

Архитектурное правило, которое можно надёжно проверить автоматически, СЛЕДУЕТ постепенно переносить из документации в статическую проверку или CI.

Документация при этом остаётся источником смысла правила.

В коде проверки — сторож `packages/dart/codelab_architecture_tests` (`melos run guard`; описание — `README.md` пакета). Полный перечень его правил — таблица `rules` (`test/support/rules.dart`), константы `*Allowlist` и HOST-6; проверяемая норма — требование spec [`workspace-architecture`](../../openspec/specs/workspace-architecture/spec.md) «Автоматический сторож границ пакетов», здесь его правила второй раз не перечисляются. Таблица ниже сверяет правила этого документа и корневого `AGENTS.md` §5–§6 с охватом сторожа и называет то, чего он не проверяет:

| Правило | Проверка |
|---|---|
| `codelab_acp_protocol` без Flutter (§5) | нет; Flutter отсутствует в `pubspec.yaml`, правила в `rules.dart` нет |
| `codelab_client_acp`, `codelab_client_core` без Flutter, `dart:io`, `intl` (§7) | `rules.dart`: `webUnsafe`, `uiLanguageForbidden`; allowlist — только у `codelab_client_core` (`kitAllowlist`) |
| `codelab_acp_transports` без Flutter (§6) | `rules.dart`: `webUnsafe` для всего пакета, кроме `lib/io.dart` и `lib/src/io/` |
| Пакеты `packages/dart/` на чистом Dart (корневой `AGENTS.md` §5) | общего правила нет; `package:flutter/` запрещён правилами `codelab_agent_*`, `codelab_client_*`, `codelab_setup`, `codelab_embedded` и основного бареля `codelab_acp_transports`; у `codelab_acp_protocol` и `codelab_acp_testing` правила нет |
| `codelab_ui` не зависит от `codelab_desktop` (§8) | нет; у кита нет зависимостей `codelab_*` |
| `codelab_ui` без бизнес-логики (§8) | нет; ревью по `codelab_ui/AGENTS.md` §2; литералы интерфейса — `ui_literals_test.dart` |
| Пакеты не зависят от приложений, нет циклов (корневой `AGENTS.md` §5) | нет; в `dependencies` таких рёбер нет |
| `codelab_acp_testing` только в `dev_dependencies` (§9, §41) | allowlist-ы пакетов агента, мостов, `codelab_client_core`, `codelab_client_io`, `apps/codelab_agent` и `desktopAllowlist` (пакеты `codelab_*` app); у `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_client_acp`, `codelab_ui` allowlist-а нет |
| Исключение CLI для `test-scenario` (§9) | `rules.dart`: `apps/codelab_cli/lib/src`, `exclude: ['scenario/']`; `cliAllowlist` |
| Нет межпакетных импортов `package:*/src/*` (§26) | нет (§26) |
| `domain` без Flutter (§17) | правило `codelab_client_acp`; в фичах desktop `domain/` нет |
| `application` без Flutter-виджетов и `BuildContext` (§16) | частично: `package:flutter/` запрещён в `application/` фич `terminal`, `usage`, `protocol` |
| `presentation` без транспорта, файлов, процессов (§15) | частично: `dart:io` запрещён в `settings/presentation/`, фичах `onboarding` и `project_files`; плагины платформы — только в адаптерах `lib/core/platform/`; IO-барели мостов — только в `lib/app/` |
| Виджеты не создают репозитории и адаптеры (корневой `AGENTS.md` §6) | нет; ревью |
| Web-безопасные барели (`codelab_acp_transports`, `codelab_embedded`, `codelab_setup`, ядро агента) | `rules.dart` (`webUnsafe`, `sealExclude`); компиляция ядра и основных барелей мостов — `melos run web-compile` |
| `io.dart` и `testing.dart` мостов — только composition root и тесты (корневой `AGENTS.md` §5) | `rules.dart`: `codelab_embedded/io.dart` — только `lib/app/` desktop и `lib/src/composition_root.dart` CLI; `codelab_setup/io.dart` — только `lib/app/` desktop; в CLI — только `lib/src/run.dart` (правило на весь `lib/`, включая барель `lib/codelab_cli.dart`); `codelab_embedded/testing.dart` — только `lib/src/scenario/` CLI; `bin/` CLI — ни `codelab_embedded/io.dart`, ни `codelab_embedded/testing.dart`, ни `codelab_setup/io.dart` (change `align-cross-cutting-specs`, D6) |
| Нативные плагины — только в адаптерах платформы (корневой `AGENTS.md` §11) | `rules.dart`: в desktop — только `lib/core/platform/`; в `codelab_ui` `package:desktop_drop/` запрещён во всём `lib/` (требование [`workspace-architecture`](../../openspec/specs/workspace-architecture/spec.md) «Плагин перетаскивания из ОС только в адаптере платформы»; change `align-cross-cutting-specs`, D6) |
| Запрет `package:codelab_agent_*` в приложениях-клиентах | `rules.dart` (`apps/codelab_desktop`, `apps/codelab_cli`), `desktopAllowlist`, `cliAllowlist` |
| Имена пакетов по ADR-0002 | `package_naming_test.dart` |

---

## 43. Добавление нового пакета

Перед созданием нового пакета ДОЛЖНО быть определено:

1. Какой конкретной ответственностью он владеет.
2. Почему существующий пакет — неправильный владелец.
3. Переиспользуем ли код.
4. Должен ли пакет быть на чистом Dart или на Flutter.
5. Кто будет его потребителем.
6. От каких пакетов ему разрешено зависеть.
7. Как выглядит его публичный API.
8. Как пакет будет тестироваться.
9. Не создаёт ли он новый цикл зависимостей.
10. Не является ли пакет слишком мелкой абстракцией без самостоятельного смысла.

Новый пакет не создаётся только ради уменьшения числа файлов в существующем пакете.

В коде новый пакет получает имя по ADR-0002 и правило сторожа вместе с собой: `PackageRule` в `rules.dart`, при ограничении зависимостей — `*Allowlist` в `pubspec_allowlist_test.dart` и негативный тест (корневой `AGENTS.md` §5; порядок — `README.md` сторожа, «Как добавить правило для нового пакета»).

Расширение allowlist (`*Allowlist`) существующего пакета ДОЛЖНО проходить через OpenSpec change: новая зависимость меняет архитектуру пакета (корневой `AGENTS.md` §4, §17), а сторож проверяет только, что `dependencies` — подмножество allowlist, и не видит, кто и зачем его расширил. Для ядра агента это ещё и PKG-2 (`coreAllowlist`).

---

## 44. Когда выносить код из `codelab_desktop`

Код — кандидат на переиспользуемый пакет, если выполняется одно или несколько условий:

* он нужен нескольким приложениям;
* он представляет самостоятельную возможность ACP;
* он должен работать без приложения на Flutter;
* у него есть устойчивый публичный контракт;
* изоляция заметно улучшает тестирование;
* это явно отдельная техническая граница.

НЕ СЛЕДУЕТ выносить код в пакет только потому, что фича стала большой.

Большая фича МОЖЕТ оставаться фичей приложения, если её смысл специфичен для приложения.

В коде по условиям «нужен нескольким приложениям» и «должен работать без приложения на Flutter» вынесен `codelab_client_core`: клиентский слой нужен и desktop, и CLI (change [`extract-acp-client-kit`](../../openspec/changes/archive/2026-10-26-extract-acp-client-kit/design.md)).

---

## 45. Когда код принадлежит `codelab_client_acp`

Код СЛЕДУЕТ рассматривать для `codelab_client_acp`, если он:

* относится к поведению ACP-клиента;
* не требует Flutter;
* должен быть переиспользуемым;
* управляет жизненным циклом сессии или запроса;
* реализует смысл ACP уровня application;
* нужен разным ACP-клиентам или слоям UI.

Например:

```text
автомат состояний сессии
семантика отмены запроса
свёртка событий ACP-клиента
абстракция политики переподключения
модель запроса разрешения
```

могут быть хорошими кандидатами.

Конкретное размещение ДОЛЖНО учитывать существующую структуру пакета.

В коде поведение рабочего пространства, общее для app и CLI (транскрипт, очередь промптов, одобрения, восстановление), живёт уровнем выше — в `codelab_client_core`, а `codelab_client_acp` держит протокольного клиента, автоматы и доменные модели.

---

## 46. Когда код принадлежит `codelab_ui`

Код СЛЕДУЕТ рассматривать для `codelab_ui`, если он:

* является переиспользуемым presentation на Flutter для ACP;
* не зависит от `codelab_desktop`;
* потенциально полезен в другом ACP-приложении на Flutter;
* имеет стабильный контракт presentation.

Например:

```text
карточка вызова инструмента
индикатор статуса ACP
содержимое запроса разрешения
отрисовка сообщения разговора
```

могут быть кандидатами.

Страницу или сценарий, специфичные для приложения, СЛЕДУЕТ оставить в `codelab_desktop`.

---

## 47. Когда код принадлежит фиче приложения

Код ДОЛЖЕН оставаться внутри `codelab_desktop/features/<feature>`, если он:

* специфичен только для приложения CodeLab;
* определяет конкретный сценарий приложения;
* тесно связан с навигацией приложения;
* не имеет самостоятельного переиспользуемого контракта;
* использует несколько переиспользуемых ACP-пакетов для реализации возможности, специфичной для приложения.

НЕ СЛЕДУЕТ преждевременно превращать каждую фичу в пакет.

---

## 48. Запрещённые короткие пути

Следующие короткие пути считаются архитектурно опасными.

### Виджет → транспорт

```text
виджет
  ↓
codelab_acp_transports
```

ЗАПРЕЩЕНО для поведения application.

---

### Виджет → файловая система

```text
виджет
  ↓
File(...)
```

НЕ СЛЕДУЕТ для операций infrastructure.

---

### Протокол → UI

```text
codelab_acp_protocol
    ↓
виджет Flutter
```

ЗАПРЕЩЕНО.

---

### Ядро → presentation

```text
codelab_client_acp
      ↓
flutter_bloc / fluent_ui
```

ЗАПРЕЩЕНО.

---

### Переиспользуемый пакет → приложение

```text
codelab_ui
   ↓
codelab_desktop
```

ЗАПРЕЩЕНО.

---

### Рабочий код → тестовый

```text
codelab_client_acp/lib
       ↓
codelab_acp_testing
```

ЗАПРЕЩЕНО.

---

### Фича → закрытые внутренности другой фичи

```text
features/a
    ↓
features/b/src/private
```

ЗАПРЕЩЕНО.

---

## 49. Допустимые прагматичные упрощения

Не каждая прямая зависимость нарушает архитектуру.

Например, простая фича только для presentation может выглядеть так:

```text
виджет
   │
   ▼
Cubit
```

без отдельного use case.

Это МОЖНО, если Cubit не содержит сложности infrastructure или application.

Простой неизменяемый объект-значение МОЖЕТ использоваться сразу в нескольких слоях, если его смысл не меняется.

НЕ СЛЕДУЕТ создавать маппер только ради того, чтобы маппер существовал.

---

## 50. Правило изменения графа зависимостей

При добавлении новой зависимости между пакетами агент ОБЯЗАН:

1. Определить направление зависимости.
2. Проверить матрицу зависимостей.
3. Проверить отсутствие цикла.
4. Проверить, не переносит ли зависимость Flutter в пакет на чистом Dart.
5. Проверить публичный API целевого пакета.
6. Обосновать, зачем зависимость нужна.
7. Обновить этот документ, если граф зависимостей действительно меняется архитектурно.

Если новая зависимость противоречит матрице, изменение требует архитектурного решения, а не просто правки `pubspec.yaml`.

В коде расширение allowlist-а сторожа требует OpenSpec change (`README.md` сторожа; для ядра агента — PKG-2).

---

## 51. Целевая модель зависимостей

Итоговый принцип:

```text
                    ПРИЛОЖЕНИЕ
                         │
                         ▼
                  codelab_desktop
                    /          \
                   ▼            ▼
              codelab_ui      API приложения ACP
                                  │
                                  ▼
                          codelab_client_acp
                            /           \
                           ▼             ▼
              codelab_acp_transports   codelab_acp_protocol
                       │
                       ▼
                 внешний агент
```

При инверсии через абстракцию транспорта конкретный граф может выглядеть так:

```text
                   composition root
                    /           \
                   ▼             ▼
          codelab_client_acp   codelab_acp_transports
                   │             │
                   ▼             │
           порт транспорта ◄─────┘
                   │
                   ▼
              codelab_acp_protocol
```

Конкретное направление зависимостей ДОЛЖНО минимизировать связанность и сохранять границы чистого Dart.

В коде роль «API приложения ACP» играют `ClientWorkspace` и `SessionHandle` (`codelab_client_core`), а порт транспорта `AcpTransport` лежит в основном бареле `codelab_acp_transports`, поэтому `codelab_client_acp` зависит от пакета транспортов, но не от его `io.dart` (§2, §7).

---

## 52. Главный критерий размещения кода

Выбирая место для нового кода, разработчик ДОЛЖЕН отвечать не на вопрос:

> Где удобнее его положить?

а на вопросы:

> Кто владеет этой ответственностью?

> На каком уровне существует её смысл?

> Какие зависимости ей действительно необходимы?

> Должна ли она быть переиспользуемой?

> Требует ли она Flutter?

Если ответы найдены правильно, место кода обычно становится очевидным.

Архитектурные границы важнее структуры каталогов.

Структура каталогов ДОЛЖНА отражать архитектуру, а не заменять её.

---

## 53. Агентская сторона: пакеты агента и мосты

Встроенный Dart-агент — второй хост ядра рядом с бинарём `codelab-agent`. Он живёт в пакетах `codelab_agent_*`; клиенты (`codelab_desktop`, `codelab_cli`) получают его через мосты. Имена пакетов подчиняются ADR-0002: `codelab_<сторона>_<слой>`, мосты между сторонами префикса `codelab_agent_` не получают.

### Пакеты агента

| Пакет | Ответственность | Зависимости (кроме Dart SDK) |
|---|---|---|
| `codelab_agent_core` | ядро на чистом Dart: LLM, цикл, инструменты, разрешения, сессии, схема и валидатор конфигурации; web-безопасно (PKG-1) | только `http`, `meta`, `collection`, `async`, `crypto` (PKG-2) |
| `codelab_agent_io` | реализации портов ядра на `dart:io`: файлы и процессы, журналы сессий, `ConfigLoader`, хранилища секретов, файлы проекта | `codelab_agent_core`, `yaml`, `yaml_edit`, `async`, `meta` |
| `codelab_agent_mcp` | MCP-клиент без `dart:io`; stdio-процесс сервера приходит портом ядра из `codelab_agent_io` | `codelab_agent_core`, `http`, `async`, `meta` |
| `codelab_agent_acp` | проекция `AgentRuntime` в ACP-сервер `AcpAgentServer` над любым `AcpTransport` | `codelab_agent_core`, `codelab_acp_protocol`, `codelab_acp_transports`, `async`, `meta` |
| `apps/codelab_agent` | бинарь `codelab-agent serve --stdio \| --ws`; composition root агента как процесса | пакеты агента, `codelab_acp_*`, `args`, `http`, `async`, `meta` |

Правила направления (ядро без пакетов проекта и `dart:io`, PKG-1 и PKG-6; `codelab_agent_acp` и `codelab_agent_mcp` без `dart:io` и друг без друга, PKG-3; сборка ядра только через `buildAgentCore`, HOST-6; агентские пакеты без клиентских пакетов, `codelab_ui` и приложений) — требование spec [`workspace-architecture`](../../openspec/specs/workspace-architecture/spec.md) «Автоматический сторож границ пакетов» и инварианты [`proposals/agent-core/01-layers-and-packages.md`](proposals/agent-core/01-layers-and-packages.md) §1.5. Почему: ядро — одно для трёх хостов (бинарь, встроенный агент, web-smoke), поэтому всё внешнее приходит портами; ACP-проекция и MCP-клиент без `dart:io` собираются вместе с ядром во встроенном агенте; единая точка сборки `buildAgentCore` не даёт хостам разойтись в порядке шагов ([`proposals/agent-core/10-core-assembly-and-profiles.md`](proposals/agent-core/10-core-assembly-and-profiles.md) §10.7).

В коде запрет `dart:io` для `codelab_agent_acp` и `codelab_agent_mcp` проверяют правила `rules.dart` (PKG-3), а отсутствие зависимости друг от друга и от клиентских пакетов — их allowlist-ы (`acpAllowlist`, `mcpAllowlist`). В `dev_dependencies` `codelab_agent_acp` есть `codelab_client_acp` (контрактный тест `test/contract/client_application_contract_test.dart`), рабочие `dependencies` чисты.

### Мосты к клиентам

Запрет импорта `package:codelab_agent_*` в клиентах и правила импорта барелей мостов — корневой `AGENTS.md` §5 и требование spec `workspace-architecture` «Автоматический сторож границ пакетов» (PKG-4). Агентская сторона приходит через два моста:

* `codelab_setup` — настройка агента: чистые типы конфигурации ядра (основной барель, web-безопасный) и общие подкоманды `config`, `secret`, `provider`, `mcp` из `codelab_agent_io` (`lib/io.dart`). Через него клиенты читают и редактируют `config.yaml`, не зная о `ConfigLoader`.
* `codelab_embedded` — встроенный агент: хост ядра, который собирает агента через `buildAgentCore` и `AcpAgentServer` и соединяет его с клиентом парой `InProcessAcpLink` в процессе клиента. Точки входа: `codelab_embedded.dart` (web-безопасная), `io.dart` (настольный открыватель: конфигурация, секреты, журнал сессий, MCP), `testing.dart` (сценарный открыватель для тестов). Правила импорта `io.dart` и `testing.dart` — `AGENTS.md` §5 и то же требование spec.

```text
apps/codelab_desktop ─┐                      ┌─ codelab_setup ──── codelab_agent_core (типы)
apps/codelab_cli ─────┤  только через мосты ─┤                  └─ codelab_agent_io (io.dart)
                      │                      └─ codelab_embedded ─ codelab_agent_acp ─ codelab_agent_core
                      │                                          ├─ codelab_agent_mcp
                      │                                          └─ codelab_agent_io (io.dart)
apps/codelab_agent ──────── пакеты агента напрямую (composition root процесса)
```

Клиент по-прежнему говорит с агентом только по ACP: встроенный агент отличается от внешнего лишь транспортом (`InProcessAcpLink` вместо stdio или WebSocket), а не контрактом. Поэтому клиентский код не ветвится по виду агента (`docs/architecture/acp-boundary.md`).

### Где проверяется

* границы импортов и allowlist зависимостей — `melos run guard` (`packages/dart/codelab_architecture_tests`, правила в `test/support/rules.dart`);
* web-безопасность ядра и основных барелей мостов `codelab_embedded` и `codelab_setup` (web-smoke точки входа) — `melos run web-compile`;
* новый пакет агентской стороны получает правило сторожа вместе с пакетом (раздел 43).

---

## 54. Текст интерфейса и локализация

Источник решений — change [`add-desktop-localization`](../../openspec/changes/archive/2026-11-20-add-desktop-localization/design.md) (D2, D4–D7, D10); требование — spec `app-settings` «Язык интерфейса app» и «Локализация интерфейса app». Технология — `technology-stack.md` §20ж, термины перевода — `l10n-glossary.md`.

### Кто строит текст

| Слой | Строит переведённый текст | Как |
|---|---|---|
| `codelab_client_core`, `codelab_client_acp` | нет | отдаёт типизированные данные: коды, виды, причины (`NoticeReason`, `ProfileDraftIssueCode`, `ToolKind`, `PromptFailure`); английские `text`/`message` остаются для CLI и диагностики; `intl` и `flutter_localizations` запрещены сторожем |
| `codelab_ui` | только свои фиксированные словари (статусы, риски, тоны, вкладки `ToolPane`, подписи кнопок по умолчанию) | `codeLabStringsOf(context)` по каталогу `CodeLabLocalizations`; без делегата — английский; app выбирает значение enum, а не текст (`codelab_ui/AGENTS.md` §5) |
| `codelab_desktop` presentation | всё остальное | `context.l10n` (`AppLocalizations`) |
| `codelab_desktop` application (Cubit-ы, мапперы) | производный текст моделей кита | по явному входу `AppStrings` (см. ниже) |
| `features/usage/application`, `features/terminal/application` | нет | эти каталоги без Flutter (правило сторожа); отдают типизированные значения (`UsageBudgetRowKind`, `UsageBudgetTitle`, статус вкладки), текст собирает presentation |

App НЕ ДОЛЖЕН переводить или разбирать английскую строку ядра клиента: если для перевода не хватает данных, ядро получает аддитивное типизированное поле (как `NoticeReason`, spec `acp-client-kit` «Типизированная причина заметки транскрипта»). Это частный случай `error-handling.md` §43 и §98.

### Три вида текста

| Вид | Примеры | Где живёт | Пересборка при смене языка |
|---|---|---|---|
| **Текст виджета** | подписи, кнопки, пустые состояния, InfoBar с постоянным текстом, словари кита | `build` виджета | `context.l10n` / `codeLabStringsOf(context)`; Flutter пересобирает через `Localizations`, своих подписок нет |
| **Производный текст в состоянии** | строки ленты и заметки, сайдбар, шапка, строка статуса, палитра, строки страниц настроек | модели кита в состоянии Cubit-а | язык — **явный вход** Cubit-а, как `usage` или статус сессии; по событию `AppStrings.changes` Cubit пересобирает всю проекцию из последних входов и сбрасывает кэши, ключ которых не учитывает язык |
| **Разовое сообщение** | исход действия («provider removed»), ошибка записи конфига, отказ подключения | состояние Cubit-а | хранится **типизированным сообщением** (sealed-класс с аргументами); текст собирает presentation по `context.l10n`, поэтому он пересобирается как текст виджета. Хранить готовую строку ЗАПРЕЩЕНО: входа, из которого её можно пересобрать, уже нет |

### Правила

1. Состояние, построенное из входов, — функция `(входы, язык)`. Cubit НЕ ДОЛЖЕН хранить переведённую строку, которую нельзя пересобрать из его входов.
2. `AppStrings.current` читается только внутри проекции; при смене языка пересобирается вся проекция, а не отдельные поля.
3. Единственный источник языка — `AppLanguageCubit` (`state-management.md` §63а). Cubit с текстом получает узкий порт `AppStrings` (`current`, `changes`), а не сам `AppLanguageCubit`: порт нужен для независимого тестирования (`AGENTS.md` §13). Подписка — одна на Cubit, в конструкторе, отмена в `close()` (`concurrency.md` §47а).
4. Склейка фразы из частей ЗАПРЕЩЕНА: текст от агента, путь, id, команда подставляются плейсхолдером одного сообщения. Количество — только ICU `plural`.
5. Enum НЕ ДОЛЖЕН хранить английский заголовок для показа (`SettingsPage.title`, `SettingsGroup.title`, `ToolPane.label` теряют поле); текст по значению даёт функция presentation, `slug` и `navKey` остаются.
6. Ключи тестов (`ValueKey`), события журнала и их поля от языка не зависят; текст интерфейса в журнал не попадает.
7. Что не переводится (содержимое агента, протокольные значения, пути, команды, продукты, клавиши, «Debug log» и «Inspector», числа usage) — spec `app-settings` «Локализация интерфейса app» и `l10n-glossary.md`.

### Зависимости

`flutter_localizations` и `intl` — прямые зависимости только `codelab_desktop` и `codelab_ui`. Направление зависимостей и граф пакетов не меняются; новых пакетов нет. Каталоги ARB и сгенерированный код живут только в `apps/codelab_desktop/lib/l10n/` и `packages/flutter/codelab_ui/lib/src/l10n/` (spec `workspace-architecture` «Ядро клиента не зависит от языка интерфейса»).

### Где проверяется

* `intl` и `flutter_localizations` в `codelab_client_core` и `codelab_client_acp` — `melos run guard` (правило в `test/support/rules.dart`);
* совпадение сгенерированного кода с ARB — `melos run l10n:check`;
* согласованность каталогов `en`/`ru` — `l10n_catalogs_test.dart` каждого пакета;
* смесь языков после переключения — помощник `expectNoStaleLanguage` (`testing.md`, раздел о локали);
* литералы мимо каталога в presentation — `ui_literals_test.dart` сторожа (эвристика по узкому списку позиций; литералы в `application/` проверяет ревью).
