# Управление состоянием в CodeLab

Документ задаёт, где живёт состояние клиентов CodeLab (desktop и CLI), кто им владеет и как оно меняется.

Основной фреймворк управления состоянием app — `flutter_bloc`.

Цели:

* разделить состояние приложения и состояние представления;
* определить владельца каждого состояния;
* не допускать дублирования источника истины;
* не переносить семантику протокола ACP напрямую в виджеты;
* сделать жизненный цикл состояния явным;
* обеспечить тестируемость BLoC/Cubit;
* не злоупотреблять глобальным состоянием.

Общие правила — корневой `AGENTS.md` (§6, §8, §9, §12, §13, §14, §16), [`layers-and-dependencies.md`](layers-and-dependencies.md), [`acp-boundary.md`](acp-boundary.md), [`session-lifecycle.md`](session-lifecycle.md), [`streaming.md`](streaming.md), [`concurrency.md`](concurrency.md), [`permissions.md`](permissions.md), [`error-handling.md`](error-handling.md), [`observability.md`](observability.md), [`testing.md`](testing.md), [`technology-stack.md`](technology-stack.md).

Термины:

* **Владелец** (authoritative owner) — единственный объект, который меняет данное состояние; остальные читают его или его проекцию (§2, §19).
* **Источник истины** (source of truth) — состояние владельца, из которого выводятся все представления (§19, STATE-001).
* **Состояние приложения** (application state) — фактическое состояние системы: соединение, сессия, ход, одобрение, вызов инструмента (§3).
* **Состояние представления** (presentation state) — то, что нужно UI; часто выводится из состояния приложения (§4).
* **Производное состояние** (derived state) — значение, однозначно вычисляемое из другого состояния (§5).
* **Эфемерное состояние виджета** (ephemeral widget state) — hover, фокус, анимация; живёт в `State` виджета (§6).
* **Проекция** (projection) — неизменяемое представление состояния владельца для отображения, например `WorkspaceState`, `SessionView`, `ConnectionView` (§2, §52).
* **Разовый эффект** (one-shot effect) — действие UI, которое не должно повторяться после rebuild: уведомление, диалог, навигация (§46, §47).

Где в коде. Протокольное состояние клиента — `codelab_client_acp`: `AcpClientApplication` (`lib/src/application/acp_client_application.dart`) хранит снимки `AcpSession` и публикует их в `sessionChanges`; переходы — функции автоматов `ConnectionStateMachine`, `SessionStateMachine`, `PromptTurnStateMachine` с результатом `StateTransitionResult` (`applied | ignored | rejected`; `lib/src/domain/state_machines.dart`); состояния — freezed-union `ClientConnectionState` и перечисления `SessionLifecycleStatus`, `PromptTurnStatus` (`domain_models.dart`). Владелец клиентского состояния, общий для app и CLI, — `ClientWorkspace` в `codelab_client_core` (`lib/src/workspace/client_workspace.dart`, реализация `DefaultClientWorkspace`): проекции `WorkspaceState` (`current` и синхронный поток `state`), `SessionView` на каждую сессию (`SessionHandle.current` и `view`, поле `revision`), `ConnectionView`, `SessionStatusView`, исходы ходов `promptOutcomes`; модели kit — freezed (`workspace_state.dart`, `connection_view.dart`, `session_views.dart`, `transcript_item.dart`). Desktop использует только `Cubit`; `Bloc` с событиями в коде нет. Состояния Cubit-ов app — рукописные неизменяемые классы с `copyWith` и `sealed`-иерархии; freezed в `lib/` app не используется. Рабочее место — `apps/codelab_desktop/lib/features/workbench/application/`: части `ConnectionCubit`, `SessionsCubit`, `ActiveSessionCubit`, `SettingsCubit`, `LayoutCubit`, `TranscriptViewCubit` (база `ShellPartCubit` и синхронный сигнал `ShellChanges` — `shell_part.dart`), фасад `CodeLabShellCubit` со снимком `CodeLabShellState` (`shell_cubit.dart`, `shell_state.dart`), маппинг в модели `codelab_ui` — `ui_mappers.dart`, а также `SecretMigrationCubit`. Корень app — `lib/app/`: `AppLanguageCubit`, `AppAppearanceCubit`, `NavigationCubit`. Фичи: `features/settings/application/` (`ConnectionSettingsCubit`, `AddProfileCubit`, `ProviderSettingsCubit`, `ProviderWizardCubit`, `AgentsModesCubit`, `AgentDefaultsCubit`, `StartupSettingsCubit`, `McpSettingsCubit`, `SkillsSettingsCubit`, `AppearanceSettingsCubit`, `LegalPageCubit`), `OnboardingCubit` (`features/onboarding/application/`), `ProjectFilesCubit` (`features/project_files/application/`), `TerminalTabsCubit` (`features/terminal/application/`), `ProtocolPaneCubit` (`features/protocol/application/`). DI — Cherrypick, один root scope `createCodeLabRootScope` (`lib/app/app_scope.dart`), подчинённых scope нет: Cubit-ы на весь процесс привязаны `singleton()` или `toInstance`; Cubit-ы страниц настроек (`ConnectionSettingsCubit`, `AddProfileCubit`, `ProviderSettingsCubit`, `AgentsModesCubit`, `AgentDefaultsCubit`, `StartupSettingsCubit`, `McpSettingsCubit`, `SkillsSettingsCubit`, `AppearanceSettingsCubit`) и `OnboardingCubit` — фабрики `toProvide`; хост страницы (`*PageHost`) создаёт Cubit через `codeLabDependenciesOf(context)` в `didChangeDependencies` и закрывает в `dispose`. Не привязаны в scope: `LegalPageCubit` создаёт сам `LegalPageHost` из портов `legalPorts` (`features/settings/presentation/legal_page.dart`), `ProviderWizardCubit` — `ProviderSettingsCubit` (`openWizard`) или открыватель мастера onboarding в `app_scope.dart`. `ProjectFilesCubit` — один на окно: его лениво создаёт при первом показе панели Files и закрывает singleton-держатель `ProjectFilesHolder` (`app_scope.dart`); виджеты получают Cubit-ы через `BlocProvider.value` (`codelab_app_widget.dart`); Cubit-ы процесса закрывает `CodeLabRootLifecycle`. Сохраняемые настройки app — порты на `shared_preferences` в `lib/core/platform/` (`AppLanguagePreferences`, `AppAppearancePreferences`, `OnboardingPreferences`, `StartupPreferences`, `ConnectionPreferences`, `DockLayoutStore`, `SharedPreferencesWorkspaceSnapshotStore`) и `SettingsPageStore` (`lib/app/navigation/`); профили и недавние проекты — JSON-хранилища `codelab_client_io` в `$CODELAB_HOME`; снимок для восстановления — `WorkspaceSnapshot` kit (`codelab_client_core/lib/src/restore/`). CLI: REPL — `ReplSession` и `ReplInputState` (`apps/codelab_cli/lib/src/repl/`), TUI — чистые `reduce` и `render` над `TuiModel` (`lib/src/tui/core/`), ввод-вывод — `TuiEffects`, модель пакета `dart_tui` — `TuiApp`; оба режима работают поверх `ClientWorkspace` и `SessionHandle`. Тесты Cubit-ов — `flutter_test` без `bloc_test`; двойники — `FakeClientWorkspace`, `FakeSessionHandle` (`apps/codelab_desktop/test/support/`) и `FakeAcpTransport` (`codelab_acp_testing`).

---

## 1. Основной принцип

Состояние ДОЛЖНО находиться на том уровне, которому принадлежит его семантика.

Предпочтительная модель:

```text
Протокольное состояние
    → codelab_acp_protocol / codelab_client_acp

Состояние приложения
    → codelab_client_acp / application-слой

Состояние клиентского рабочего пространства (соединение, сессии, транскрипт, очередь, одобрения)
    → codelab_client_core

Состояние представления
    → BLoC / Cubit

Эфемерное состояние виджета
    → Widget
```

НЕ СЛЕДУЕТ помещать всё состояние приложения в BLoC только потому, что проект использует `flutter_bloc`.

В коде роль «BLoC / Cubit» в CLI играют `ReplSession` (REPL) и `TuiModel` с функцией `reduce` (TUI): `flutter_bloc` в CLI нет.

---

## 2. Один владелец

У каждого значимого состояния ДОЛЖЕН быть один владелец.

Например:

```text
жизненный цикл соединения и сессии
    → codelab_client_acp

клиентское рабочее пространство (ConnectionView, SessionView, очередь промптов)
    → codelab_client_core

выбранная вкладка
    → presentation

состояние hover
    → widget
```

Несколько слоёв МОГУТ иметь производное представление одного состояния, но источник истины ДОЛЖЕН быть однозначным.

Владелец клиентского состояния — `codelab_client_core` (`ClientWorkspace`, `WorkspaceState`, `SessionView`; `openspec/changes/archive/2026-10-26-extract-acp-client-kit/design.md`, D4–D7). Cubit-ы `codelab_desktop` и экраны `codelab_cli` его не дублируют: они отображают `WorkspaceState`/`SessionView` в свои модели и держат только состояние своего UI (черновик формы, раскладку, флаги окна).

В коде `SessionsCubit` читает, кроме проекций kit, ещё и снимки `AcpSession` из `AcpClientApplication.sessionChanges` (единственный подписчик среди частей рабочего места), а `ActiveSessionCubit` получает снимок показываемой сессии от него через `show(AcpSession)`: статус «ждёт одобрения» есть только в снимке ядра, а `SessionStatusView` объединяет его с ходом (doc-комментарий `SessionsCubit`, design D7 change `add-session-list-and-reload`). Источник истины при этом остаётся в `codelab_client_acp` и `codelab_client_core`; Cubit-ы строят из обоих только строки UI.

---

## 3. Состояние приложения

Состояние приложения описывает фактическое состояние системы.

Примеры:

* жизненный цикл соединения;
* жизненный цикл сессии;
* активный запрос;
* завершение запроса;
* запрос разрешения;
* состояние переподключения;
* жизненный цикл вызова инструмента.

Состояние приложения НЕ ДОЛЖНО зависеть от того, как именно оно отображается во Flutter.

---

## 4. Состояние представления

Состояние представления описывает то, что нужно UI.

Например (иллюстративные имена):

```text
isPromptInputEnabled
showReconnectBanner
selectedConversationId
activePanel
permissionDialogState
```

Часть состояния представления может выводиться из состояния приложения.

Например:

```text
SessionState.running
      │
      ▼
canSendPrompt = false
canCancel = true
```

---

## 5. Производное состояние

НЕ СЛЕДУЕТ хранить отдельное поле как источник истины, если значение однозначно выводится из другого состояния.

Нежелательно:

```dart
class ChatState {
  final SessionState sessionState;
  final bool canSendPrompt;
  final bool canCancel;
}
```

если:

```text
canSendPrompt
canCancel
```

полностью определяются `sessionState`.

Лучше вычислять их как производные свойства или селекторы.

В коде форма из «Нежелательно» встречается: `ActiveSessionState` хранит `isPromptSubmitting` и `canCancel` рядом с `turnState` (`apps/codelab_desktop/lib/features/workbench/application/active_session_cubit.dart`, «флаги совместимости из `SessionView.status`», design D4 change `extract-acp-client-kit`), а фасад копирует их в `CodeLabShellState`. Источником истины они не являются: Cubit пересчитывает их из `SessionView.status` при каждом показе снимка сессии. Это расхождение с формой правила (и со STATE-006), а не с владением.

---

## 6. Эфемерное состояние виджета

Локальное состояние виджета МОЖНО использовать для забот только представления.

Примеры:

* hover;
* фокус;
* анимация;
* временное раскрытие;
* локальное взаимодействие с прокруткой;
* состояние перетаскивания.

Для такого состояния НЕ СЛЕДУЕТ автоматически создавать Cubit.

В коде так хранятся, например, раскрытые строки на странице «Providers» (`providers_page.dart`) и раскрытие справки на странице «Connection» (`connection_page.dart`). Раскрытие строк ленты — исключение: строки виртуализированы и уничтожаются при уходе с экрана, поэтому выбор пользователя хранит `TranscriptViewCubit`, а не `State` строки (design D3 change `redesign-transcript-rows`).

---

## 7. Что НЕ должно быть состоянием виджета

Виджет НЕ ДОЛЖЕН быть владельцем для:

* соединения ACP;
* сессии;
* запроса;
* вызова инструмента;
* разрешения;
* статуса сохранения;
* переподключения;
* бизнес-данных и данных приложения.

Пересборка (rebuild) или уничтожение виджета НЕ ДОЛЖНЫ уничтожать критичное состояние приложения.

---

## 8. BLoC или Cubit

СЛЕДУЕТ использовать существующие паттерны проекта (корневой `AGENTS.md` §14).

Общий ориентир:

### Cubit

Подходит, когда переходы простые, а API естественно выражается методами:

```text
selectTab()
togglePanel()
loadSettings()
```

### BLoC

Подходит, когда важны:

* явные события;
* порядок событий;
* семантика конкурентности;
* сложный автомат состояний;
* внешний поток событий.

НЕ СЛЕДУЕТ превращать любое простое состояние в BLoC только ради единообразия.

В коде все владельцы состояния app — `Cubit` (полный список — абзац «Где в коде»); `Bloc` с событиями и `bloc_concurrency` не используются. Сложные автоматы живут ниже — в `codelab_client_acp` (автоматы `state_machines.dart`) и `codelab_client_core`, а Cubit-ы вызывают их методами.

---

## 9. Ответственность BLoC

BLoC/Cubit МОЖЕТ:

* принимать намерения пользователя;
* подписываться на события приложения;
* преобразовывать состояние приложения в состояние представления;
* управлять сценарием представления;
* запускать операции приложения;
* управлять жизненным циклом, специфичным для UI.

BLoC/Cubit НЕ ДОЛЖЕН:

* разбирать сырой ACP;
* реализовывать сериализацию;
* владеть конкретным транспортом;
* содержать реализацию работы с файловой системой;
* реализовывать политику безопасности;
* содержать переиспользуемую логику жизненного цикла ACP, если она принадлежит `codelab_client_acp`;
* содержать логику клиента, общую для app и CLI (очередь промптов, проекцию транскрипта, политику переподключения), — она принадлежит `codelab_client_core`.

---

## 10. BLoC — не слой сервисов

НЕ СЛЕДУЕТ делать BLoC местом для всей бизнес-логики.

Нежелательно (иллюстрация):

```text
SessionBloc
├── создаёт процесс
├── разбирает ACP
├── переподключает транспорт
├── пишет файлы
├── оценивает разрешение
├── сохраняет историю
└── обновляет UI
```

Предпочтительно:

```text
SessionBloc
    │
    ▼
API ACP-клиента / приложения
    │
    ├── транспорт
    ├── жизненный цикл сессии
    ├── разрешения
    └── хранение
```

В коде роль «API ACP-клиента / приложения» играют `ClientWorkspace` и `SessionHandle` (`codelab_client_core`) поверх `AcpClientApplication` (`codelab_client_acp`).

---

## 11. Неизменяемость состояния

Состояние BLoC/Cubit ДОЛЖНО быть неизменяемым.

Для сложных типов состояния МОЖНО использовать Freezed.

Например (иллюстрация):

```dart
@freezed
sealed class SessionViewState with _$SessionViewState {
  const factory SessionViewState.disconnected() = _Disconnected;
  const factory SessionViewState.connecting() = _Connecting;
  const factory SessionViewState.ready() = _Ready;
  const factory SessionViewState.running() = _Running;
}
```

Это пример подхода, а не требование использовать именно такие состояния.

В коде состояния Cubit-ов app — классы с `final`-полями и `copyWith` (например, `AppLanguageState`, `OnboardingState`; у `ActiveSessionState` — закрытый `_copyWith`); новое состояние публикуется `emit`. Freezed-модели — в пакетах: `WorkspaceState`, `SessionView`, `ConnectionView`, `TranscriptItem` (`codelab_client_core`), `ClientConnectionState`, `AcpSession`, `StateTransitionResult` (`codelab_client_acp`).

---

## 12. Freezed

Freezed СЛЕДУЕТ использовать, когда он даёт реальную пользу:

* union-состояния;
* неизменяемые модели;
* равенство по значению;
* `copyWith`;
* исчерпывающий `switch`.

НЕ СЛЕДУЕТ применять Freezed автоматически к каждому простому классу.

В коде Freezed подключён в `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_client_acp`, `codelab_client_core` и `codelab_ui` (модели `codelab_config_option.dart`, `codelab_command_action.dart` в `lib/src/molecules/`). В `apps/codelab_desktop` `freezed` есть только в `dev_dependencies`, аннотаций `@freezed` в `lib/` нет: union-состояния app написаны как `sealed`-иерархии вручную (`ConnectionSettingsState`, `OnboardingModelStep`, `AppDestination`).

---

## 13. Невозможные состояния

Модель состояния ДОЛЖНА минимизировать возможность представить невозможное состояние.

Нежелательно:

```dart
class SessionState {
  final bool connected;
  final bool reconnecting;
  final bool running;
  final bool cancelling;
}
```

Предпочтительно:

```text
Disconnected
Connecting
Ready
Running
Cancelling
Reconnecting
```

если эти состояния взаимоисключающие.

В коде так устроены, например, `ConnectionSettingsState` (`ConnectionSettingsLoading | ConnectionSettingsReady | ConnectionSettingsUnreadable`), шаг модели onboarding `OnboardingModelStep` (`ModelPending | ModelSkipped | ModelChoose | ModelSaved`), `AppDestination` (`OnboardingDestination | WorkbenchDestination | SettingsDestination`), `ConnectionView` kit и `ClientConnectionState` ядра. Булевы флаги остаются там, где они независимы или служат защитой от повторного действия: `isRespondingToApproval`, `isRespondingToConfigOption` в `ActiveSessionState`, `finishing` в `OnboardingState`.

---

## 14. Ортогональное состояние

Помещать всё в один union не требуется.

Например:

```text
жизненный цикл сессии
+
выбранная вкладка UI
```

— независимые измерения.

НЕ СЛЕДУЕТ создавать комбинаторный union:

```text
ReadyOnChatTab
ReadyOnSettingsTab
RunningOnChatTab
RunningOnSettingsTab
...
```

---

## 15. Разделение состояния

Большое состояние СЛЕДУЕТ разделять, если его части:

* имеют разный жизненный цикл;
* меняются независимо;
* имеют разных потребителей;
* вызывают лишние rebuild;
* принадлежат разным фичам.

Но дробление НЕ ДОЛЖНО приводить к десяткам Cubit-ов без ясной ответственности.

Пример — рабочее место `codelab_desktop` (`features/workbench/application/`, design D10 change `extract-acp-client-kit`): `ConnectionCubit` (форма подключения, статус), `SessionsCubit` (список и выбор сессий), `ActiveSessionCubit` (лента, очередь, одобрения, опции, план показываемой сессии), `SettingsCubit` (проект, недавние проекты), `LayoutCubit` (панели, палитра) и добавленный позже `TranscriptViewCubit` (раскрытие строк ленты, показанные изображения и выбранная строка панели Agents по сессиям; change `redesign-transcript-rows`, D3). Маппинг представлений kit в модели `codelab_ui` — чистые функции `ui_mappers.dart`. Если одно событие меняет несколько Cubit-ов, а потребитель ждёт одного согласованного снимка, изменения склеиваются синхронно (`ShellChanges.batch`), а не через асинхронный `stream`.

---

## 16. Владение фичи

Предпочтительно, чтобы фича владела своим состоянием представления.

Например (иллюстративные имена):

```text
features/chat/
    → ChatBloc

features/settings/
    → SettingsCubit
```

Глобальное состояние МОЖНО заводить только для забот, действительно общих для всего приложения.

В коде фичи — `features/workbench`, `features/settings`, `features/onboarding`, `features/project_files`, `features/terminal`, `features/protocol`, `features/usage`; у каждой свои Cubit-ы в `application/`, кроме `features/usage` (данные панели Usage строит `ActiveSessionCubit`, `usage_pane_data.dart`). Имя `SettingsCubit` в коде занято частью рабочего места (проект и недавние проекты), а не фичей настроек.

---

## 17. Глобальное состояние

Кандидаты в состояние уровня всего приложения:

* активное рабочее пространство;
* реестр сессий на уровне app;
* тема и настройки;
* аутентификация и конфигурация, если применимо;
* статус соединения верхнего уровня.

НЕ СЛЕДУЕТ делать состояние глобальным только потому, что его используют два виджета.

В коде на весь процесс живут singleton-ы root scope: `ClientWorkspace`, `CodeLabShellCubit` с частями `CodeLabShellParts`, `AppLanguageCubit`, `AppAppearanceCubit`, `NavigationCubit`, `TerminalTabsCubit`, `ProtocolPaneCubit`, `SecretMigrationCubit`, а также держатель `ProjectFilesHolder`, который лениво создаёт один `ProjectFilesCubit` на окно (`app_scope.dart`).

---

## 18. Общее состояние

Если несколько фич используют одно состояние-источник, СЛЕДУЕТ определить его смыслового владельца.

Возможные решения:

* сервис приложения;
* BLoC уровня app;
* общая проекция только для чтения;
* фасад фичи.

НЕ СЛЕДУЕТ дублировать состояние в каждой фиче.

В коде применены три варианта: сервис уровня приложения — `ClientWorkspace`; Cubit уровня app — `AppLanguageCubit`, который другие Cubit-ы видят через узкий порт `AppStrings` (§63а); фасад — `CodeLabShellCubit` над частями рабочего места.

---

## 19. Источник истины

Пример правильного владения (иллюстративные имена):

```text
AcpClientCore
    │
    └── authoritative SessionState
             │
             ▼
        SessionBloc
             │
             └── SessionViewState
```

BLoC МОЖЕТ преобразовывать состояние, но НЕ ДОЛЖЕН независимо воспроизводить весь жизненный цикл.

В коде этой цепочке соответствуют `AcpClientApplication` (снимки `AcpSession`, `SessionLifecycleStatus`) → `ClientWorkspace` (`SessionView`, `SessionStatusView`) → `ActiveSessionCubit` (`ActiveSessionState`) → виджеты рабочего места. Класса `AcpClientCore` в коде нет.

---

## 20. Синхронизация состояния

Если BLoC получает состояние из application-слоя, предпочтительно подписываться на поток событий или состояния.

НЕ СЛЕДУЕТ периодически опрашивать объект только ради синхронизации, если доступен API потока или состояния.

В коде Cubit-ы рабочего места подписаны на потоки `ClientWorkspace.state` (`ConnectionCubit`, `SessionsCubit`), `promptOutcomes` и `SessionHandle.view` (`ActiveSessionCubit`) и `AcpClientApplication.sessionChanges` (только `SessionsCubit`); `ClientWorkspace.state` доставляет изменения синхронно, чтобы хост видел переход соединения сразу после события транспорта.

---

## 21. Начальное состояние

Начальное состояние ДОЛЖНО быть задано явно.

Например:

```text
unknown
initializing
disconnected
```

СЛЕДУЕТ выбирать исходя из реальной семантики.

НЕ СЛЕДУЕТ показывать `disconnected`, если приложение ещё не завершило инициализацию и фактический статус неизвестен.

В коде начальное состояние, которое нельзя узнать синхронно, выражено отдельным вариантом: `ConnectionSettingsLoading`, `FactsLoading` и `ModelPending` в onboarding. Язык, оформление и флаг onboarding читаются в `main` до `runApp` и приходят в root scope швами, поэтому первый кадр уже знает их значения (§63а–§63в).

---

## 22. Состояние загрузки

`loading` НЕ ДОЛЖЕН быть универсальным состоянием для всех операций.

СЛЕДУЕТ различать:

```text
connecting
loading history
creating session
sending prompt
```

если различается UX или семантика жизненного цикла.

---

## 23. Состояние ошибки

Ошибке не обязательно заменять всё состояние.

Например:

```text
session = ready
lastSendError = ...
```

может быть лучше, чем:

```text
SessionState.error
```

если сессия остаётся работоспособной.

В коде так устроены, например, `saveFailed` в `AppLanguageState` и `AppAppearanceState` (язык и оформление остаются применёнными), `linkNote` в `CodeLabShellState` и `canRetry` в `SessionView`.

---

## 24. Окончательная и восстановимая ошибка

СЛЕДУЕТ различать:

* ошибку операции;
* восстановимую ошибку сессии;
* окончательный сбой сессии;
* ошибку представления.

НЕ СЛЕДУЕТ использовать один общий

```text
ErrorState(message)
```

для всех видов сбоя.

---

## 25. Типизированные сбои

Слой представления ДОЛЖЕН получать типизированный сбой приложения или нормализованную модель ошибки представления.

НЕ СЛЕДУЕТ передавать сырое исключение прямо в виджет.

Нежелательно:

```dart
Text(exception.toString())
```

Подробнее о типизированных сбоях — [`error-handling.md`](error-handling.md).

---

## 26. Переходы состояния

Значимые переходы ДОЛЖНЫ идти через один понятный механизм.

Например:

```text
событие
  ↓
обработчик BLoC
  ↓
emit(newState)
```

или через поток состояния приложения.

НЕ СЛЕДУЕТ менять одно и то же состояние из нескольких независимых объектов без координации.

В коде переходы протокольного состояния идут только через автоматы `state_machines.dart` (`StateTransitionResult`), а состояние каждого Cubit-а меняют только его методы через `emit`.

---

## 27. События

Событие BLoC ДОЛЖНО описывать намерение или значимое внешнее событие.

Хорошие примеры:

```text
ConnectRequested
PromptSubmitted
CancelRequested
SessionStateChanged
PermissionDecisionSubmitted
```

Плохие:

```text
ButtonClicked
BooleanChanged
DoThing
```

если событие теряет смысл.

Имена в §27–§35 иллюстративные: `Bloc` с событиями в коде нет (§8). У Cubit-ов намерения выражены методами, например `ConnectionCubit.restart`, `ActiveSessionCubit.respondToApproval`, `NavigationCubit.finishOnboarding`.

---

## 28. Намерение пользователя и событие приложения

СЛЕДУЕТ различать:

```text
PromptSubmitted
    → намерение пользователя

PromptCompleted
    → событие приложения
```

У них разное происхождение и разная семантика.

---

## 29. Имена событий BLoC

Имена ДОЛЖНЫ отражать уже произошедшее событие или намерение.

Пример:

```text
ConnectRequested
ConnectionLost
ReconnectSucceeded
```

Это упрощает журналы событий и отладку.

---

## 30. Конкурентность событий

Для каждого обработчика события ДОЛЖНА быть понятна его семантика конкурентности.

Возможные варианты:

* sequential;
* concurrent;
* restartable;
* droppable.

Выбор ДОЛЖЕН соответствовать смыслу операции.

Подробнее:

`docs/architecture/concurrency.md` (§60–§62)

---

## 31. Отправка промпта

`PromptSubmitted` НЕ СЛЕДУЕТ делать `restartable`, если обработчик отмены не отменяет реальный запрос ACP.

Новое событие НЕ ДОЛЖНО локально «отменять» предыдущий запрос, оставляя его работающим у агента.

В коде новый промпт не отменяет текущий ход: `SessionHandle.send` занятой сессии (`running` или `cancelling`) ставит промпт в очередь kit, а отмена — отдельный `SessionHandle.cancel`, который отправляет `session/cancel`.

---

## 32. Подключение

Повторный `ConnectRequested` МОЖЕТ использовать семантику single-flight/droppable, если повторное подключение не имеет смысла.

Однако основная защита ДОЛЖНА находиться и в жизненном цикле приложения.

В коде эта защита — в `ClientWorkspace`: номер попытки подключения, вытесненная попытка состояние не меняет, а `ConnectionCubit` не пишет для неё ни `failed`, ни «started» (`apps/codelab_desktop/AGENTS.md`; D6 change `add-embedded-agent-mode`).

---

## 33. Поиск и фильтр

Поиск и фильтр, которые касаются только представления, МОГУТ использовать семантику debounce/restartable.

Это пример операции, где новое намерение действительно заменяет предыдущее.

---

## 34. Подписка в BLoC

Если BLoC подписывается на поток приложения, подписка ДОЛЖНА:

* иметь владельца — этот BLoC;
* создаваться один раз;
* отменяться в `close()`;
* обрабатывать ошибки.

В коде подписки Cubit-ов создаются в конструкторе и отменяются в переопределённом `close()`, например у `ActiveSessionCubit` — на `AppStrings.changes`, `ClientWorkspace.promptOutcomes` и `SessionHandle.view` показываемой сессии; подписка на `view` переключается при смене сессии (§60).

---

## 35. Перевод подписки в события

Предпочтительно переводить внешний callback в событие BLoC:

```text
поток клиента
    │
    ▼
событие SessionStateChanged
    │
    ▼
обработчик BLoC
```

Это помогает сохранить один путь обработки событий.

---

## 36. Прямой emit из callback

Прямой `emit` из произвольного callback может усложнить конкурентность.

Если он используется, жизненный цикл и упорядочивание ДОЛЖНЫ быть безопасными.

Для сложного BLoC предпочтительнее отправлять типизированное событие.

В коде Cubit-ы вызывают `emit` прямо из обработчиков потоков и из продолжений `async`-методов; после `await` они, как правило, проверяют `isClosed`, прежде чем публиковать результат (например, `ActiveSessionCubit`).

---

## 37. Закрытие BLoC

После `close()`:

* подписки закрыты;
* таймеры остановлены;
* callbacks НЕ ДОЛЖНЫ отправлять события;
* поздняя асинхронная операция НЕ ДОЛЖНА публиковать состояние.

Подробнее — [`concurrency.md`](concurrency.md) §9.

---

## 38. DI и BLoC

BLoC ДОЛЖЕН получать зависимости через конструктор или утверждённую сборку Cherrypick.

Например (иллюстрация):

```dart
class SessionBloc extends Bloc<SessionEvent, SessionState> {
  SessionBloc({
    required AcpClient client,
  }) : _client = client;
}
```

НЕ СЛЕДУЕТ получать конкретную infrastructure через глобальный локатор внутри обработчика.

В коде Cubit-ы получают зависимости конструктором; собирает их `app_scope.dart` (`currentScope.resolve<…>()` вызывается только там и в сгенерированном модуле `app_scope.module.cherrypick.g.dart`, внутри привязок модулей).

---

## 39. Создание BLoC

BLoC ДОЛЖЕН создаваться в правильной области жизни.

Например:

```text
время жизни приложения
время жизни фичи
время жизни страницы
время жизни диалога
```

Область ДОЛЖНА соответствовать жизненному циклу состояния.

В коде три уровня: на время жизни приложения — singleton-ы root scope (§17); на время жизни окна — `ProjectFilesCubit` в держателе `ProjectFilesHolder`: Cubit создаётся при первом показе панели Files и переживает переключение вкладок дока; на время жизни страницы или экрана — фабрики `toProvide`, которые создаёт и закрывает хост страницы (`ConnectionPageHost` и другие `*PageHost`), а также `LegalPageCubit`, который `LegalPageHost` создаёт сам. На время диалога создаётся, например, `ProviderWizardCubit` мастера провайдера (его создают `ProviderSettingsCubit` или открыватель мастера onboarding).

---

## 40. Несовпадение области

НЕ СЛЕДУЕТ создавать BLoC с областью страницы для состояния, которое должно переживать навигацию между страницами.

И наоборот, НЕ СЛЕДУЕТ создавать глобальный singleton BLoC для временного состояния диалога.

---

## 41. Область Cherrypick

Область DI и жизненный цикл BLoC ДОЛЖНЫ быть согласованы.

Зависимость с областью сессии НЕ ДОЛЖНА случайно пережить сессию и использовать старые ресурсы.

В коде подчинённых scope Cherrypick нет, в том числе на сессию: ресурсы сессии живут в `SessionHandle` kit, а не в DI.

---

## 42. Маппинг в представление

Модель приложения МОЖНО преобразовывать в модель представления:

* в BLoC;
* в отдельном маппере;
* в фабрике view model.

Отдельный маппер СЛЕДУЕТ заводить, только если маппинг достаточно сложен или переиспользуется.

В коде отдельные мапперы — чистые функции `ui_mappers.dart` (представления kit → модели `codelab_ui`), `agents_pane_data.dart`, `usage_pane_data.dart`.

---

## 43. Не хранить виджеты в состоянии

Состояние BLoC НЕ ДОЛЖНО содержать:

* `Widget`;
* `BuildContext`;
* `NavigatorState`;
* callbacks диалогов, тесно связанные с деревом виджетов.

Состояние ДОЛЖНО быть ориентировано на данные.

---

## 44. Callbacks в состоянии

Callback-функции в состоянии СЛЕДУЕТ использовать осторожно.

Для состояния приложения они обычно неуместны.

Модель представления МОЖЕТ содержать callback только как деталь композиции UI, но предпочтительно связывать действия на уровне виджета.

В коде модели `codelab_ui`, которые строит `ui_mappers.dart`, несут callbacks как деталь композиции, например выбор варианта одобрения в строке ленты (`_onApprovalSelected` в `ActiveSessionCubit`).

---

## 45. Навигация

Навигация — забота представления.

BLoC НЕ ДОЛЖЕН зависеть от `BuildContext`.

Возможные паттерны:

* UI реагирует на состояние;
* разовый эффект представления;
* абстракция маршрутизатора на границе представления.

В коде навигация верхнего уровня — состояние `NavigationCubit` (`AppDestination`: onboarding, рабочее место, настройки), а не маршруты `Navigator`; UI перестраивается по этому состоянию.

---

## 46. Разовые эффекты

Некоторые действия UI не являются долговременным состоянием:

* показать уведомление;
* открыть диалог;
* перейти на другой экран;
* подтвердить копирование.

НЕ СЛЕДУЕТ моделировать их булевым полем:

```text
showDialog = true
```

которое остаётся в состоянии и может сработать повторно после rebuild.

---

## 47. Эффекты

Если проект использует отдельный механизм эффектов, его СЛЕДУЕТ применять последовательно.

Концептуально:

```text
State
    → долговременное представление UI

Effect
    → разовое действие UI
```

НЕ СЛЕДУЕТ вводить новый фреймворк эффектов без необходимости.

В коде отдельного механизма эффектов нет. Разовые действия передаются полями состояния с номером запроса или ревизией, по которым виджет отличает новый запрос от повтора, например `CodeLabTranscriptShowRequest.serial` и `composerDraftRevision`, а также типизированными заметками (`ShellLinkNote`); исходы ходов идут потоком `ClientWorkspace.promptOutcomes`. Для реакции на смену состояния без перестройки виджеты используют `BlocListener` (например, `codelab_app_widget.dart`, `workbench_usage_pane.dart`).

---

## 48. Состояние диалога

Диалог разрешения отличается от обычного разового эффекта: у запроса разрешения есть жизненный цикл приложения.

Сам запрос ДОЛЖЕН оставаться в состоянии:

```text
PermissionRequest.pending
```

а способ отображения может быть диалогом или панелью.

В коде ожидающий запрос — `ApprovalStateView.pending` (`PendingApprovalView`) в `SessionView.pendingApprovals` и в элементе вызова инструмента транскрипта (`codelab_client_core`). App показывает его блоком одобрения в ленте, REPL CLI — блоком под выводом, по одному в порядке `pendingApprovals`.

---

## 49. Сохранение состояния

Не всякое состояние BLoC сохраняется между запусками.

Сохранять СЛЕДУЕТ только состояние, которое имеет смысл после перезапуска.

Например:

```text
настройки пользователя
настройки рабочего пространства
история разговоров
```

Состояния времени выполнения вроде:

```text
connecting
cancelling
hovered
```

сохранять напрямую НЕ СЛЕДУЕТ.

В коде сохраняются настройки app (порты на `shared_preferences`, абзац «Где в коде»), профили и недавние проекты (`$CODELAB_HOME`), раскладка дока и снимок рабочего пространства. Историю разговоров клиент не хранит: транскрипт после перезапуска приходит реплеем `session/load` от агента.

---

## 50. Модель хранения ≠ состояние BLoC

НЕ СЛЕДУЕТ сериализовать состояние BLoC целиком как модель хранения без осознанного решения.

Модель хранения ДОЛЖНА иметь собственную стабильную семантику.

В коде модель хранения отделена от состояния Cubit-ов, например `WorkspaceSnapshot` с версией формата (`static const version = 1`) и форматом `{"version": 1, "windows": {"main": {…}}}` (без курсоров `session/list`, транскриптов, очередей, профилей и секретов), `DockLayout` у `DockLayoutStore`.

---

## 51. Восстановление

После перезапуска сохранённое состояние ДОЛЖНО пройти восстановление и сверку на уровне приложения.

Например, сохранённая

```text
последняя известная сессия
```

не означает:

```text
сессия сейчас подключена
```

В коде `ClientWorkspace.restoreProject` возвращает только проект снимка; сессии восстанавливаются при первом успешном `connect` в запуске: они попадают в список, активная загружается через `session/load`, а при отсутствии `loadSession` у агента или ошибке загрузки создаётся новая сессия с уведомлением (design D6 change `add-session-list-and-reload`).

---

## 52. Состояние потока

Агрегация потока ДОЛЖНА находиться в application/client-слое, если она описывает семантику ACP.

BLoC МОЖЕТ хранить проекцию для представления.

Например (иллюстративные имена):

```text
application:
MessageStreamingState

presentation:
ChatMessageViewState
```

В коде агрегация обновлений `session/update` — в `AcpClientApplication` и `TranscriptProjector` kit (транскрипт `SessionView.transcript`), проекция представления — строки ленты `ActiveSessionState.transcriptRows`. Подробнее — [`streaming.md`](streaming.md).

---

## 53. Частые обновления

При частых обновлениях потока СЛЕДУЕТ сокращать лишние rebuild.

СЛЕДУЕТ использовать:

* `BlocSelector`;
* `buildWhen`;
* небольшие виджеты;
* производные проекции.

НЕ СЛЕДУЕТ решать проблему производительности переносом состояния-источника обратно в виджет.

В коде `buildWhen` используется, например, в `codelab_app_widget.dart` (`FluentApp` перестраивается только при смене `locale` и оформления), `appearance_page.dart`, `workbench_usage_pane.dart`.

---

## 54. Равенство

Равенство состояний ДОЛЖНО быть корректным.

Freezed помогает обеспечить равенство по значению.

Некорректное равенство может приводить к:

* пропущенным rebuild;
* лишним rebuild;
* странным падениям тестов.

В коде у проекций kit равенство по значению (freezed). У верхних состояний Cubit-ов app (`ActiveSessionState`, `SessionsState`, `LayoutState`, `SettingsState`, `WindowConnectionState`, `TranscriptViewState`, `CodeLabShellState`, `AppLanguageState`, `AppAppearanceState`, `OnboardingState`) `operator ==` не переопределён: `emit` нового объекта всегда доходит до слушателей, даже если значение не изменилось. Равенство по значению написано вручную у вложенных вариантов (например, `OnboardingModelStep`, `DocumentLoad`) и у состояний `LegalPageState`, `TerminalTabsState`, `ProtocolPaneState`.

---

## 55. Большие коллекции

Большие неизменяемые коллекции могут быть дорогими при частом копировании.

Если производительность потока становится проблемой, представление СЛЕДУЕТ оптимизировать осознанно.

Корректность важнее преждевременной оптимизации.

---

## 56. Нормализованное состояние

Для сложной модели UI полезно хранить нормализованное состояние:

```text
messagesById
messageOrder
toolCallsById
```

вместо вложенных изменяемых структур.

Это особенно полезно при инкрементальных обновлениях.

---

## 57. Идентичность сущностей

Элементы списков, сообщения и вызовы инструментов ДОЛЖНЫ иметь стабильную идентичность.

UI НЕ ДОЛЖЕН сопоставлять состояние только по индексу в списке.

В коде элементы транскрипта и строки ленты имеют id (`toolCallId`, id строки); выбор пользователя в `TranscriptViewState` хранится по id сессии и id строки.

---

## 58. Ревизия состояния

Для сложного производного или кэшированного состояния может пригодиться ревизия.

Например:

```text
conversationRevision
```

Но ревизию НЕ СЛЕДУЕТ вводить без реальной необходимости.

В коде ревизия есть у `SessionView` (`revision`: UI сравнивает представления по ней, а не обходом полей) и у черновика композера (`composerDraftRevision`, §47).

---

## 59. Устаревшие обновления приложения

BLoC ДОЛЖЕН игнорировать обновление, если application-слой уже пометил его устаревшим или оно относится к другой сессии своей области.

Слой представления НЕ ДОЛЖЕН заново реализовывать всю фильтрацию устаревших событий.

В коде фильтрация — в `codelab_client_acp` (поколение соединения, [`session-lifecycle.md`](session-lifecycle.md) §15–§16) и `ClientWorkspace` (номер попытки подключения, §32). Cubit-ы фильтруют только по id показываемой сессии.

---

## 60. Переключение сессий

При переключении между сессиями ДОЛЖНО быть определено:

* какой BLoC владеет выбором;
* какие подписки переключаются;
* очищается ли прежнее состояние представления;
* как исключаются поздние события прежней сессии.

В коде выбором владеет `SessionsCubit` (выбор сессии — `ClientWorkspace.activate`, неоткрытую сессию сначала загружает `loadSession`); `ActiveSessionCubit` при показе новой сессии переподписывается на её `SessionHandle.view` и строит состояние заново; выбор пользователя в ленте (`TranscriptViewState`) хранится по сессиям и при переключении не смешивается. Изменение списка и показываемой сессии — один пакет `ShellChanges`.

---

## 61. Состояние на сессию

Если одновременно могут быть активны несколько сессий, НЕ СЛЕДУЕТ использовать одно плоское `currentSessionState`, когда UI должен сохранять состояние каждой сессии.

Возможна модель:

```text
sessionsById
activeSessionId
```

если это соответствует архитектуре продукта.

В коде продукт поддерживает несколько сессий одновременно (change `add-multi-session-concurrency`): `WorkspaceState.sessions` и `activeSessionId`, по `SessionHandle` и `SessionView` на сессию; очередь фоновой сессии живёт в kit, пока её не выберут.

---

## 62. Приложение с одной сессией

Если продукт сознательно поддерживает только одну активную сессию, это ДОЛЖНО быть инвариантом приложения, а не случайным ограничением BLoC.

---

## 63. Состояние настроек

Настройки чаще всего принадлежат отдельной фиче.

СЛЕДУЕТ различать:

* сохранённые настройки;
* состояние формы редактирования;
* действующую конфигурацию времени выполнения.

Они не обязаны быть одним типом.

### 63а. Язык интерфейса app

Источник — change [`add-desktop-localization`](../../openspec/changes/archive/2026-11-20-add-desktop-localization/design.md), D2 и D5; spec `app-settings` «Язык интерфейса app». Это частный случай §2 и §19: у языка один владелец.

* **Владелец — `AppLanguageCubit`** (`apps/codelab_desktop/lib/app/language/app_language_cubit.dart`, root scope, singleton). Состояние — `AppLanguageState(preference, locale, strings, saveFailed)`: `preference` — `system | en | ru`, `locale` — применённый язык, `strings` — `AppLocalizations` этого языка, `saveFailed` — признак неудачной записи. Отдельного `LanguageSettingsCubit` нет: страница «Settings › General» читает и вызывает `AppLanguageCubit` напрямую.
* **Сохранённое и действующее.** Сохранённое значение (`shared_preferences`, ключ `codelab.app.language`, порт `AppLanguagePreferences`) и применённый язык различаются (§63): `locale` выводится чистой функцией `resolveAppLocale(preference, systemLocales)`. Незнакомое или нестроковое сохранённое значение читается как `system`, ключ не перезаписывается. `load()` не бросает и возвращает `AppLanguageLoad(preference, storedValueInvalid, readFailure)`: сбой открытия хранилища тоже даёт `system`.
* **Начальное состояние** (§21) приходит синхронно через шов `createCodeLabRootScope(language:)` типа `AppLanguageStart` (`apps/codelab_desktop/lib/app/language/app_language_start.dart`, `AppLanguageStart.fromLoad`): `preference`, `locale` и диагностика чтения, каталог строит сам Cubit; без шва — `AppLanguageStart.fallback` (`system`, `en`). `main` читает предпочтение и языки системы до `runApp`, поэтому первый кадр уже на нужном языке и асинхронной загрузки нет.
* **Переход `select(preference)`** — сначала `emit` нового состояния, потом запись ключа. Это не оптимистичное обновление с откатом (§67, §68): при сбое записи язык остаётся применённым, ставится `saveFailed`, страница показывает ошибку с кнопкой `Retry` (повтор записи текущего выбора). Записи идут по очереди, побеждает последний выбор; обогнанная запись своё состояние не публикует (`concurrency.md` §47а).
* **Потребители — ровно два вида.**
  1. `CodeLabApp` — `BlocBuilder<AppLanguageCubit>` над `FluentApp` (`locale: state.locale`); виджеты получают язык через `Localizations` и своих подписок не держат.
  2. Cubit-ы, у которых в состоянии есть производный текст (`layers-and-dependencies.md` §54). Они видят язык через узкий порт `AppStrings` (`current`, `changes`), который реализует `AppLanguageCubit`. Язык для них — явный вход проекции наравне с остальными; при его смене Cubit пересобирает всё производное состояние из последних входов (§5 — производное состояние не хранится отдельно от входов). Разовые сообщения хранятся типизированными, а не строкой.
* Смена языка НЕ ДОЛЖНА менять состояние сессий, очереди, одобрений и соединения и НЕ ДОЛЖНА пересоздавать `FluentApp`: меняется только `locale`, поэтому `State` виджетов (ввод композера, черновики, фокус, прокрутка) сохраняется.


### 63б. Оформление app

Источник — change [`add-app-appearance-page`](../../openspec/changes/archive/2026-11-20-add-app-appearance-page/design.md), D4, D5, D13; spec `app-settings` «Режим оформления и темы режимов», «Хранение оформления». Это ещё один частный случай §2 и §19: у оформления один владелец.

* **Владелец — `AppAppearanceCubit`** (`apps/codelab_desktop/lib/app/appearance/`, root scope, singleton). Состояние — `AppAppearanceState`: выбор пользователя (`mode`, `lightTheme`, `darkTheme`, `systemAccent`), применённое оформление (готовые `FluentThemeData` двух режимов, акцент, признак запасной темы `fallback`) и `saveFailed`.
* **Сохранённое и действующее (§63).** Сохранённый выбор (`shared_preferences`, документ `codelab.app.appearance`, порт `AppAppearancePreferences`) и применённое оформление различаются. Тема режима, которая не загрузилась (файла нет, ошибка чтения или разбора, база темы относится к другому режиму), применяется как встроенная тема режима, а выбор не перезаписывается. Незнакомое значение документа читается как значение по умолчанию и тоже не перезаписывается до явного выбора.
* **Начальное состояние** приходит синхронно швом `createCodeLabRootScope(appearance:)` типа `AppAppearanceStart`; `main` читает документ и файлы тем до `runApp` (`concurrency.md` §47б).
* **Переходы** — `setMode`, `useTheme` (не загрузившуюся пользовательскую тему не назначает), `resetTheme(Brightness)`, `setSystemAccent`, `reloadTheme`, `refreshSystemAccent`, `retrySave`: сначала `emit`, потом запись; при сбое записи выбор остаётся применённым, страница показывает ошибку с `Retry` (как §63а).
* **Потребители.** `CodeLabApp` — `BlocBuilder<AppAppearanceCubit>` над `FluentApp`, меняет только `theme`, `darkTheme`, `themeMode`; `FluentApp` не пересоздаётся, `State` виджетов сохраняется. Страница «Appearance» вызывает Cubit через свой `AppearanceSettingsCubit`: состояние страницы (каталог тем, выбранная для превью тема, разбор, контраст, импорт) — состояние редактирования страницы, а не сохранённые настройки, и закрывается вместе со страницей.
* Смена оформления НЕ ДОЛЖНА менять состояние сессий, очереди, одобрений и соединения.

### 63в. Onboarding app

Источник — change [`add-app-onboarding`](../../openspec/changes/archive/2026-11-21-add-app-onboarding/design.md), D1–D6, D8, D10 (просмотр правовых документов, поле `document`), и change [`add-onboarding-project-step`](../../openspec/changes/archive/2026-11-22-add-onboarding-project-step/design.md) (шаг «Open a project»); spec `app-onboarding`. Onboarding — не настройка, но устроен так же: сохранённое значение и экранное состояние различаются (§63), у каждого свой владелец.

* **Сохранённое — флаг `codelab.app.onboarding_done`** (`shared_preferences`, порт `OnboardingPreferences` в `lib/core/platform/`). Хранит только `true`. `load()` не бросает и возвращает `OnboardingLoad(done, storedValueInvalid, readFailure)`: незнакомое значение и сбой хранилища читаются как «пройден», ключ не перезаписывается (целостность данных, AGENTS.md §2). Флаг читается в `main` до `runApp` и приходит швом `createCodeLabRootScope(onboarding:)` (D3).
* **Навигация — `NavigationCubit`**: начальное назначение `OnboardingDestination` задаёт шов, `finishOnboarding()` переводит его в `WorkbenchDestination`. Шага в назначении нет (D1).
* **Экранное состояние — `OnboardingCubit`** (`features/onboarding/application/`, живёт, пока показан экран). `OnboardingState`: `step` (`welcome | permissions | model | privacy | project`), факты `FactsLoading | FactsLoaded | FactsUnavailable` (`FactsLoaded` несёт и `EditableSettings`, по которому открывается мастер), шаг модели `ModelPending | ModelSkipped(reason) | ModelChoose(notice, wizard) | ModelSaved(summary, wizard)` с фазой мастера `wizard: idle | active`, фаза шага проекта `project: idle | choosing` (`ProjectStepPhase`), открытый правовой документ шага «Privacy» `document` и `finishing`. Пока факты не прочитаны или недоступны, шаг 2 не называет режим новой сессии (D7). Невозможных сочетаний булевых флагов нет (§STATE-004). Переходы — таблица D4.
* **Мастер провайдера** — свой `ProviderWizardCubit` на время диалога (как у страницы «Providers»). `OnboardingCubit` получает только итог `Done(plan, committed)` и строит из него `OnboardingSavedSummary` без значения ключа (SETUP-1).
* **Тексты по фактам** (пути, бэкенд секретов, режим) — функции presentation «(факты, язык)», а не строки в состоянии (`layers-and-dependencies.md` §54).
* Onboarding НЕ ДОЛЖЕН менять состояние сессий, соединения и очереди: пока он показан, рабочее место не строится, а агент не стартует (D5; `concurrency.md` §47в).

---

## 64. Состояние формы

Временный ввод формы МОЖЕТ находиться:

* локально в виджете;
* в Cubit, если форма сложная;
* в отдельной модели формы.

НЕ СЛЕДУЕТ отправлять каждое изменение текстового поля в глобальный BLoC приложения без причины.

В коде черновик профиля подключения — модель `ProfileDraft` kit (`codelab_client_core/lib/src/connection/profile_draft.dart`), его держит `AddProfileCubit` страницы, а не `ConnectionCubit` рабочего места.

---

## 65. Проверка ввода

Проверка в UI и проверка в приложении различаются.

Проверка представления:

```text
поле пустое
неверный локальный формат
```

Проверка приложения:

```text
операция запрещена в текущей сессии
capability не поддерживается
```

Ограничения безопасности и приложения НЕ ДОЛЖНЫ существовать только в проверке формы.

В коде `ProfileDraft.validate` отдаёт типизированные проблемы по полям (`ProfileDraftIssue`), а правила безопасности (секретоподобный `env`, зарезервированный id) проверяются ещё и в `ProfileDraft.toProfile` — единственном пути из черновика в `ConnectionProfile`.

---

## 66. Загрузка коллекций

Для состояния коллекции полезно различать:

```text
initial loading
refreshing
loaded empty
loaded data
failed
```

если различается UX.

Одного `isLoading` может не хватить.

---

## 67. Оптимистичные обновления

Оптимистичное состояние МОЖНО использовать, если есть сверка.

Например:

```text
промпт появляется сразу
    ↓
запрос принят или отклонён
    ↓
подтверждение или откат
```

Оптимистичное состояние ДОЛЖНО отличаться от подтверждённого, если это влияет на корректность.

---

## 68. Откат

Если оптимистичная операция не удалась, откат ДОЛЖЕН быть детерминированным.

НЕ СЛЕДУЕТ просто оставлять UI в состоянии, которого сервер или агент не подтвердил.

---

## 69. Отображение ошибок

Сообщение для пользователя НЕ ДОЛЖНО быть единственной формой состояния ошибки.

СЛЕДУЕТ сохранять типизированную причину для:

* повтора;
* диагностики;
* решений UI.

---

## 70. Журналирование состояния

Значимые переходы состояния СЛЕДУЕТ журналировать на границе приложения.

НЕ СЛЕДУЕТ журналировать каждый hover и каждое локальное изменение UI.

Полезно журналировать, например:

```text
SessionState.ready → SessionState.running
RequestState.streaming → completed
```

В коде переходы соединения журналирует одна точка `AcpClientApplication._transitionConnection` (`connection_state_changed`); переходы сессии и хода общей записью не журналируются — подробности и расхождение в [`observability.md`](observability.md) §6. Cubit-ы пишут события своих сценариев, например `connection.start_failed`, `connection.restart` (`ConnectionCubit`), `workbench.approval_answer` (`ActiveSessionCubit`).

---

## 71. Отладочное журналирование BLoC

Если используется наблюдатель BLoC, он ДОЛЖЕН:

* маскировать чувствительные данные;
* не выгружать большие payload ACP;
* не быть единственным источником диагностики жизненного цикла.

В коде `BlocObserver` не подключён.

---

## 72. Тестирование BLoC

Тесты BLoC ДОЛЖНЫ проверять:

* входное намерение;
* взаимодействие с приложением;
* итоговые состояния представления;
* преобразование ошибок;
* очистку при завершении жизненного цикла.

НЕ СЛЕДУЕТ через тесты BLoC заново тестировать парсер протокола или транспорт.

В коде тесты Cubit-ов пишутся на `flutter_test` без `bloc_test`: вызывается метод, проверяется `cubit.state` или поток `cubit.stream` (например, `apps/codelab_desktop/test/features/settings/application/agent_defaults_cubit_test.dart`). Подробнее — [`testing.md`](testing.md) §25–§27.

---

## 73. Тесты Cubit

Тесты Cubit ДОЛЖНЫ быть небольшими и сфокусированными.

Если для теста Cubit нужно поднимать весь стек ACP, граница зависимостей, вероятно, слишком тесная.

В коде Cubit-ы настроек, терминала и onboarding тестируются в основном на двойниках портов, а Cubit-ы рабочего места (`connection_cubit_test.dart` и другие в `test/features/workbench/application/`) — поверх настоящих `ClientWorkspace` и `AcpClientApplication` с транспортом `FakeAcpTransport`: проверяется связка с ядром клиента без процесса агента.

---

## 74. Поддельные зависимости приложения

В тестах BLoC СЛЕДУЕТ использовать поддельные зависимости, обращённые к приложению.

Например (иллюстративные имена):

```text
FakeAcpClient
FakeSessionController
```

а не настоящий транспорт процесса.

В коде это, например, `FakeClientWorkspace` и `FakeSessionHandle` (`apps/codelab_desktop/test/support/fake_client_workspace.dart`), `FakeAcpTransport` (`codelab_acp_testing`), `FakeProjectFiles`, `FakeProfileSecrets`, `InMemoryProfileStore` (`test/support/`).

---

## 75. Тесты виджетов

Тесты виджетов ДОЛЖНЫ проверять:

* отрисовку состояния;
* доступность и недоступность элементов управления;
* отправку намерений;
* правильность производного UI;
* поведение UI разрешений.

Жизненный цикл приложения тестируется уровнем ниже.

---

## 76. Интеграционные тесты

Интеграционные тесты покрывают связку:

```text
UI
  ↓
BLoC
  ↓
приложение
  ↓
поддельный или тестовый агент ACP
```

для критичных сквозных сценариев.

В коде интеграционные тесты app — `apps/codelab_desktop/integration_test/` (например, `fs_flow_test.dart` с настоящим stdio-агентом); на устройстве они запускаются только в `release/*` (корневой `AGENTS.md` §21).

---

## 77. Нежелательные паттерны

### Сырой ACP в состоянии

```dart
class ChatState {
  final Map<String, dynamic> lastAcpMessage;
}
```

если это состояние UI приложения.

---

### Суп из булевых флагов

```dart
isLoading
isConnected
isRunning
hasError
isCancelling
```

без ясной модели состояния.

---

### Глобальный мега-BLoC

```text
AppBloc
├── sessions
├── settings
├── routing
├── permissions
├── files
├── ACP transport
└── entire UI
```

считается архитектурным запахом.

---

### BLoC как локатор сервисов

```dart
final transport = container.resolve<StdioTransport>();
```

в обработчике события.

---

### Побочный эффект в getter

Getter состояния НЕ ДОЛЖЕН выполнять ввод-вывод или менять состояние.

---

### Состояние с `BuildContext`

ЗАПРЕЩЕНО.

---

## 78. Когда создавать новый BLoC/Cubit

Перед созданием ДОЛЖНЫ быть ответы на вопросы:

1. Каким состоянием он владеет?
2. Какой у него жизненный цикл?
3. Кто потребители?
4. Почему не хватает локального состояния виджета?
5. Почему владельцем не является существующий BLoC?
6. Это состояние представления или состояние приложения?
7. Какие зависимости ему нужны?
8. Какие тесты будут написаны?

Если чёткой ответственности нет, новый BLoC/Cubit создавать НЕ СЛЕДУЕТ.

---

## 79. Когда НЕ создавать BLoC

НЕ СЛЕДУЕТ создавать отдельный BLoC для:

* hover;
* простого переключателя внутри одного виджета;
* контроллера анимации;
* локального выбранного индекса, который больше нигде не нужен;
* неизменяемого статичного представления.

СЛЕДУЕТ использовать минимально необходимый механизм.

---

## 80. Когда переносить логику из BLoC в `codelab_client_acp`

Перенос СЛЕДУЕТ рассмотреть, если логика:

* не зависит от Flutter;
* описывает жизненный цикл ACP;
* нужна нескольким BLoC или фичам;
* содержит автомат состояний сессии или запроса;
* содержит семантику переподключения или отмены;
* должна тестироваться независимо от представления.

Логику клиента, общую для app и CLI, см. §9.

---

## 81. Когда оставить логику в BLoC

Логику МОЖНО оставить в BLoC, если она:

* касается только представления;
* связывает намерения пользователя с API приложения;
* преобразует состояние приложения в состояние UI;
* управляет взаимодействием, которое касается только представления.

---

## 82. Главные инварианты

### STATE-001 — Один источник истины

Состояние-источник не дублируется между слоями.

### STATE-002 — BLoC не владеет семантикой протокола

Сырой ACP и логика транспорта находятся ниже представления.

### STATE-003 — Состояние неизменяемо

Значимые переходы состояния создают новые неизменяемые значения.

### STATE-004 — Невозможные состояния минимизированы

Используются явные типы состояний вместо неограниченного набора флагов.

### STATE-005 — Состояние виджета только эфемерное

Жизненный цикл приложения не хранится в виджете.

### STATE-006 — Производное состояние не дублируется без необходимости

`canSend`, `canCancel` и подобные значения выводятся из состояния-источника, когда это возможно.

### STATE-007 — Жизненный цикл состояния соответствует области DI и UI

Глобальное состояние не создаётся для локальной заботы, локальное состояние не используется для жизненного цикла всего приложения.

---

## 83. Основная модель

Предпочтительная архитектура:

```text
            ACP / Infrastructure
                    │
                    ▼
             codelab_client_acp
                    │
          состояние-источник
                    │
                    ▼
               BLoC/Cubit
                    │
         состояние представления
                    │
                    ▼
                Widgets
```

Намерение пользователя идёт в обратном направлении:

```text
Widget
   │
   ▼
BLoC/Cubit
   │
   ▼
API приложения
   │
   ▼
ACP-клиент / infrastructure
```

Если виджет начинает владеть жизненным циклом ACP, BLoC реализует транспорт, а `codelab_client_acp` зависит от типов состояния Flutter, границы СЛЕДУЕТ пересмотреть.

В коде между `codelab_client_acp` и Cubit-ами стоит `codelab_client_core` (`ClientWorkspace`, §2); CLI использует ту же цепочку без `flutter_bloc` (§1).
