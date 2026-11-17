## Context

### Откуда функция

«Test connection» введена change `add-app-settings-shell` (D12 — `ProfileProbe`, D14 — метка «Not tested», D17 — события, D20 — отступления от артборда) и расширена change `add-provider-setup-ui` (D13 — проверка нового токена из памяти через `SecretRebindableResolver.withSecrets`). Change `require-project-folder` добавил D7 — проверку stdio-профиля без проекта (`probeProfileFor`) и прямо назвал её временной: «Пользователь решил убрать «Test connection» совсем — отдельным change после этого».

После итерации B того же change агент стартует сам (D13): выбор проекта, «New session», фокус на `notLoaded`/`detached`-сессии. «Use» выбирает профиль для следующего старта, «Restart agent» перезапускает агента. Результат старта виден в строке профиля (бейдж `Connecting…` / `Connected` / `Failed`) и в рабочем месте — экран сбоя или баннер с причиной и «Retry» (agent-workbench-ui «Connection banner above a non-empty transcript», «Агент стартует сам»). Отказ по токену описывает `describeConnectFailureByToken` (acp-client-kit «Отказ рукопожатия из-за токена»).

### Где функция живёт сейчас (сверено с `develop`, коммит `337979c0`)

**Desktop, `apps/codelab_desktop/lib/`:**

| Место | Что относится к проверке |
|---|---|
| `features/settings/application/probe_profile.dart` (весь файл) | `probeProfileFor` — D7 `require-project-folder` |
| `features/settings/application/probe_outcome_view.dart` (весь файл) | `probeOutcomeText`, `probeOutcomeIsOk`, `probeOutcomeName` — тексты исхода (D12) |
| `features/settings/application/add_profile_state.dart:9, 48–53, 108–135, 174–200, 223–247` | поля `probe`, `probeText`, `canTest`, `saveLabel` («Save» / «Save without test»), состояния `Probing`, `ConfirmingPlaintextProbe`, `SavedProfile.probe`, `Saved.probe` / `tested` |
| `features/settings/application/add_profile_cubit.dart:12, 19–20, 42–43, 53, 101, 104, 131–138, 193–198, 419–576, 744–750, 764, 796–799, 842–862, 984, 1080–1155, 1197` | зависимость `ProfileProbe`, `projectDirectory`, `testConnection`, `confirmPlaintextProbe`, `_startProbe`, `_cancelProbe`, `_probeToken`, `_probeOf`, поле `tested` события `connection_profile.saved`, расчёт `canTest` / `probeText`, `_probeTokenView` |
| `features/settings/application/connection_settings_cubit.dart:11, 14–15, 33–34, 82–88, 127–154, 245–262, 451–524, 554, 635, 651–652, 676, 763` | `ProfileProbe`, `projectDirectory`, `_probes`, `_probedProfiles`, `_pendingTested`, `_probing`, `testProfile`, `profileAdded(id, tested)`, `lastProbes`, `_sameConnection` (используется только для исходов проверки) |
| `features/settings/application/connection_settings_state.dart:10, 16, 59–212, 250, 279, 342, 369` | `ProfileRowView.probe`, `isProbing`, `probeText`, `isTested`, `showNotTested`, `ConnectionSettingsLoaded.lastProbes` |
| `features/settings/presentation/add_profile_dialog.dart:52, 148–160, 178, 224, 297–305, 634–690, 721–723` | панель «Test anyway» (`add-profile-test-anyway`), строка «Check» и `_CheckRow` (`add-profile-test`, `add-profile-probe-result`), `form.saveLabel`, `· marked "Not tested"` экрана «Profile saved» |
| `features/settings/presentation/connection_page.dart:8, 74, 210, 311–312, 421, 434, 546–560, 588–592` | `probeOutcomeIsOk`, `onTest`, исход строки (`connection-profile-probe-<id>`), бейдж «Not tested», кнопка `connection-profile-test-<id>`, передача исходов диалога странице |
| `lib/app/app_scope.dart:11, 21, 757–766, 776, 781–782, 799–801` | импорт `classifyProbeFailure`, `ProfileProbe`, `bind<ProfileProbe>()`, аргументы `probe:` и `projectDirectory:` двух Cubit-ов |
| `apps/codelab_desktop/AGENTS.md:26` | правило про `ProfileProbe`, `classifyProbeFailure`, `probeOutcomeText`, `testProfile` |

**Desktop, тесты:** `test/features/settings/application/probe_outcome_view_test.dart` (весь файл); `add_profile_cubit_test.dart` — группы `probe text (3.8b, D12)` (231), `test connection` (634), `plaintext confirmation before Test connection` (807), отдельные тесты в `form` (505); `connection_settings_cubit_test.dart` — 213–224, 733, 763, 1152–1163, 1182, группа `Test connection of a row (iteration 3, D14)` (1501–1730); `test/features/settings/presentation/add_profile_dialog_test.dart` — группы `check` (517–640), `plaintext confirmation before Test connection` (760–800), тест 1063; `connection_page_test.dart` — 611, группа `rename and test connection` (912, тест 981), группа `row probe texts come from typed data` (1029); `integration_test/connection_profiles_flow_test.dart:94–95, 169–170, 227–252`.

**Kit:**
- `packages/dart/codelab_client_core/lib/src/connection/profile_probe.dart` — весь файл; экспорт `lib/codelab_client_core.dart:23`; `transport_resolver.dart:35–47, 71, 78–84` (`SecretRebindableResolver`, `withSecrets`); комментарии `profile_secrets.dart:68`, `token_rejection.dart:18`; тест `test/connection/profile_probe_test.dart`; `AGENTS.md:7, 16, 17`.
- `packages/dart/codelab_client_io/lib/src/transport/classify_probe_failure.dart` — весь файл; экспорт `lib/codelab_client_io.dart:19`; тест `test/probe_failure_test.dart`; `AGENTS.md:13`.

**Прочее:**
- `apps/codelab_cli/lib/src/headless/headless_runner.dart:4–6` — `hide TimedOut` из-за одноимённого исхода проверки.
- `packages/dart/codelab_setup/lib/src/io/classify_provider_check_error.dart:13`, `test/io/provider_check_classifier_test.dart:10` — комментарии «как в `classifyProbeFailure`».

**Чего нет:**
- В `profiles.json` (`JsonFileProfileStore`, `ConnectionProfile`) и `shared_preferences` статуса проверки нет. «Not tested» — состояние страницы `lastProbes` за жизнь её открытия (D14 `add-app-settings-shell`).
- `apps/codelab_cli` пробу не вызывает: `codelab profiles add` проверку не делает.
- Не путать с проверкой провайдера на странице «Providers» («Check», `not checked`, `ProviderCheck`) и с `providerSetupProbe` composition root (D26 `add-provider-setup-ui`) — это другие функции, они остаются.

## Goals / Non-Goals

**Goals:**
- Убрать «Test connection» из desktop целиком: кнопки, исходы, метку «Not tested», подтверждение перед проверкой, события и состояние, которое существовало только ради проверки.
- Убрать из kit API, у которого не остаётся потребителей (Q1 (а)).
- Сохранить всё, что относится к записи профиля: валидацию черновика, подтверждение `ws://` при сохранении, токены, `ProfileCommitter`.
- Снять D7 `require-project-folder` и его сценарий.

**Non-Goals:**
- Проверка провайдера LLM («Providers» → «Check») и `providerSetupProbe`.
- Новые проверки при сохранении (Q3) и причина сбоя в строке профиля (Q4).
- Формат `profiles.json`, поведение CLI, ACP.
- Правка референсных артбордов `docs/design/claude-design/*`.

## Decisions

### D1. Удаление из desktop целиком, без флага

Удаляются:
- `AddProfileCubit`: `testConnection`, `confirmPlaintextProbe`, состояния `Probing` и `ConfirmingPlaintextProbe`, поля формы `probe`, `probeText`, `canTest`; зависимости `ProfileProbe` и `projectDirectory` из конструктора;
- `saveLabel` — кнопка всегда «Save»;
- `SavedProfile` сводится к id сохранённого профиля, `Saved.tested` и `Saved.probe` уходят;
- `ConnectionSettingsCubit`: `testProfile`, `_probes`, `_probedProfiles`, `_pendingTested`, `_probing`, `_probeSeq`, `_sameConnection`; `profileAdded(id, tested)` заменён на `profilesChanged()` без параметров; зависимости `ProfileProbe` и `projectDirectory`;
- `ProfileRowView`: `probe`, `isProbing`, `probeText`, `isTested`, `showNotTested`; `ConnectionSettingsLoaded.lastProbes`;
- файлы `probe_profile.dart` и `probe_outcome_view.dart`;
- в `app_scope.dart` — `bind<ProfileProbe>()` и аргументы `probe:` и `projectDirectory:`.

`profilesChanged()` (прежний `profileAdded`) остаётся единственным сигналом: страница после закрытия диалога один раз перечитывает `profiles.json`, если в диалоге что-то сохранено, и показывает все профили, сохранённые за жизнь диалога (сценарий «Add another, затем Cancel»).

Альтернативы:
- (б) спрятать кнопки за флагом — отклонено: мёртвый код с собственными гонками отмены (AGENTS.md §13);
- (в) оставить проверку только в строке сохранённого профиля — отклонено решением пользователя «Убрать совсем»; «Use» и старт агента уже дают ту же информацию.

### D2. Kit: удалить пробу и классификатор, у которых не остаётся потребителей

Принято Q1 (а). Из `codelab_client_core` удаляются `profile_probe.dart` целиком (`ProfileProbe`, `ProbeCancellation`, `ProfileProbeOutcome` и варианты, `UnreachableReason`, `ProbeFailureClassifier`, `_IdleTransport`, `_OneOffSecretSource`) и его экспорт; `SecretRebindableResolver` и `ConfigTransportResolver.withSecrets` — их единственный вызывающий `ProfileProbe.probe(token:)`. Из `codelab_client_io` — `classifyProbeFailure` и его экспорт.

Остаются: `tokenRejectionStatus`, `describeTokenRejection`, `profileTokenSent`, `describeConnectFailureByToken` (ими пользуется подключение), `describeFailure`, `AcpWebSocketHandshakeRejected` и сохранение типа и `errorCode` у ошибки запуска `StdioAcpTransport` (agent-transports, design.md change `redact-cli-stdio-profile-args`, D8: аргументы не должны попадать в текст ошибки — это требование безопасности, а не только опора классификатора).

Альтернативы:
- (б) оставить пробу в kit «на будущее» (`codelab profiles test` в CLI) — отклонено: потребителя нет, спецификацию пришлось бы поддерживать без кода, который её проверяет в продукте; вернуть можно из истории git отдельным change;
- (в) оставить только `classifyProbeFailure`, чтобы позже показывать на экране сбоя старта `Command not found: <command>` вместо общего текста — отклонено в этом change: это новое поведение экрана сбоя с другим типом исхода; если понадобится, его проектирует отдельный change (Q4).

### D3. `profiles.json` и CLI: миграции нет

Статус проверки нигде не сохраняется: `ConnectionProfile` и `JsonFileProfileStore` полей проверки не имеют, `shared_preferences` хранит только `codelab.connection.default_profile`. Формат и версия `profiles.json` не меняются. Старые файлы читаются как раньше; app после change пишет те же записи. CLI (`codelab profiles …`, `--agent`) не затронут.

### D4. Тексты UI после удаления

**Диалог «Add connection profile»:**
- строк формы четыре группы: Type, Name (и id), поля типа, After saving («Use by default»); строки «Check» нет;
- кнопки: «Save» (`add-profile-save`, доступность — прежняя `canSave`) и «Cancel»;
- `ws://` к нелокальному хосту: панель «Unencrypted connection» с «Save anyway» только перед записью, тексты прежние;
- подсказки токена прежние. В требовании о незаданной переменной уходит оговорка «в блоке проверки до и после «Test connection»»: блока больше нет, правило «одна заметка под полем» остаётся;
- значение выбранного «Use stored secret» диалог не читает вообще (раньше — «кроме проверки»); значение нового токена держится в памяти до записи через `ProfileCommitter`.

**Экран «Profile saved»** (принято Q2 (а)): InfoBar `Added to profiles.json as <id>` и, если отмечено, ` · used by default`; ниже прежний текст `The running agent is unchanged. Select it with Use in the profile row; Restart agent applies it.`; кнопки «Done» и «Add another».

**Строка профиля:** заголовок, вторая строка, источник токена, метки «Default», «Current», «Selected», бейдж попытки `connection-profile-status-<id>`; действия «Use», «Rename», «Remove». У встроенного агента — только «Use» (если он не выбран).

**Как пользователь проверяет профиль теперь:** «Use» в строке и любой триггер старта (выбор проекта, «New session») либо «Restart agent». Результат — бейдж строки и экран или баннер сбоя рабочего места с причиной и «Retry».

### D5. Подтверждение `ws://` — только при сохранении

Состояние `ConfirmingPlaintextProbe` и «Test anyway» уходят. Правило «одно подтверждение на пару «URL, выбор токена»» остаётся для повторного «Save» после «Save anyway» (ошибка записи, `idTaken` с правкой id): правка URL, варианта токена, имени переменной, выбранного секрета или нового токена по-прежнему сбрасывает подтверждение. Сценарий «Строка сохранённого профиля не спрашивает подтверждения» сохраняет смысл для «Use» и старта агента.

Расхождение с артбордами `AddProfile`, `Connection`, `PhoneConnection` (там есть строка «Check», кнопка «Test connection» и метка «Not tested») фиксируется здесь как отступление, артборды не правятся: они референс, как в D20 `add-app-settings-shell` и D24 `add-provider-setup-ui`.

### D6. Наблюдаемость

Перестают писаться `connection_profile.probe_started`, `connection_profile.probe_finished`, `connection_profile.probe_discarded` и поле `tested` события `connection_profile.saved`. `operation_id` уходит из событий страницы «Connection» и диалога: им нумеровались только проверки. Из того же требования снимается устаревшее `connection.connect_on_start` (D19 `require-project-folder`, код его не пишет). События «Providers» и «MCP servers» (`operation_id` проверки провайдера) не меняются. Жизненный цикл старта агента по-прежнему журналируется событиями подключения (`connection.*`) и `ConnectionCommands.attemptProfile`.

Внешних потребителей у событий `probe_*` нет (поиск по репозиторию: только сами Cubit-ы и их тесты).

### D7. Снятие D7 `require-project-folder`

`probeProfileFor` и источник `projectDirectory` у `AddProfileCubit` и `ConnectionSettingsCubit` удаляются: папка проекта нужна им была только для проверки. Сценарий agent-workbench-ui «Test connection without a selected project» снимается (MODIFIED требования «Project selection is independent of the connection type»). Правило «без проекта нет папки» (D1 того change) действует без исключений.

### D8. Пакеты, зависимости, сторож

Пакеты по ADR-0002 не меняются:
- `codelab_client_core` (сторона `client`, слой `core`) — удаление публичного API, web-безопасность сохраняется;
- `codelab_client_io` (`client`, `io`) — удаление функции;
- `apps/codelab_desktop`, `apps/codelab_cli` — потребители.

Новых рёбер и пакетов нет, `apps/codelab_desktop` по-прежнему зависит от `codelab_client_io` (`JsonFileProfileStore`, `IoProjectFiles` и другие). Правило сторожа в `codelab_architecture_tests/test/support/rules.dart` не нужно; граф в `README.md` не меняется. Allowlist зависимостей ядра (PKG-2) не затронут: ядро агента не меняется.

### D9. Документы и вложенные `AGENTS.md`

До кода (задачи группы 0) архитектор правит:
- `docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md` §12.4.9: шаги 4–8 и «Уточнения change `add-app-settings-shell`» без «Test connection», «Test anyway», «Not tested», ключей `add-profile-test`, `add-profile-probe-result`, `add-profile-test-anyway`, `connection-profile-…-probe`/`-test`; SETUP-20 (около строки 1378) помечается снятым этим change; обоснование «Проверка не обязательна… пометка «Not tested»» (около 1444–1448) — заменяется ссылкой на старт по «Use»; перечень тестов kit (`profile_probe_test.dart`, `probe_failure_test.dart`, около 1575–1582) и интеграционный тест app (около 1584–1592) — по D2 и задаче 1.6;
- `delivery-roadmap.md:549` — «Test connection» в перечне закрытого M3 с пометкой «удалена change `remove-test-connection`»;
- `agent-parity-goals.md` U-06 — без «Test connection» и `probe_outcome_view_test.dart`.

Вложенные `AGENTS.md` пакетов (`apps/codelab_desktop`, `codelab_client_core`, `codelab_client_io`) правят исполнители вместе с кодом — это правила кода своих каталогов.

### D10. Порядок архивирования с `add-file-preview-and-tree`

Активный change `add-file-preview-and-tree` тоже MODIFY-ит требование acp-client-kit «IO-адаптеры клиента» (добавляет `IoProjectFiles`). Дельта этого change снята с текущей `openspec/specs`. Тот, кто архивируется вторым, обязан перенести в свою дельту правку первого: иначе архивирование затрёт `IoProjectFiles` или вернёт `classifyProbeFailure`. Задача 6.2.

## Risks / Trade-offs

- [Профиль нельзя проверить, не делая его профилем окна] → «Use» не трогает работающего агента (spec app-settings): выбор и «Restart agent» — осознанный шаг; при идущем ходе «Restart agent» спрашивает подтверждение (D22 `require-project-folder`). Это принятое решение пользователя.
- [Неверный новый токен сохраняется в хранилище, ошибка видна только при старте] → текст `the agent rejected the token (HTTP 401)` на экране сбоя (`describeConnectFailureByToken`); удалить профиль с собственным секретом можно «Remove» с флажком удаления токена.
- [Менее точная причина сбоя для stdio (нет `Command not found: <command>`)] → экран сбоя показывает причину старта; уточнение текста — отдельный change (Q4, D2 (в)).
- [Поздний исход проверки после закрытия страницы] → исчезает вместе с проверкой: в desktop больше нет второго, параллельного старту, пути открытия транспорта, его отмены и привязки исхода к полям профиля (AGENTS.md §9, §12). Риск гонок уменьшается.
- [Безопасность] → убывает поверхность: диалог больше не читает значение выбранного секрета и не подменяет источник секретов резолвера (`withSecrets`); токен не уходит на сервер до явного старта агента. Containment и permission flow не затронуты: проба не выполняла `fs/*` и `terminal/*`.
- [Конфликт дельт с `add-file-preview-and-tree`] → D10, задача 6.2.

## Migration Plan

Миграции данных нет (D3). Выпуск — одним PR: сначала desktop перестаёт использовать пробу (группа 3), затем kit удаляет API (группа 4), чтобы на каждом коммите репозиторий собирался. Откат — revert PR; данные пользователя не затрагиваются.

## Принятые решения по вопросам

- **Q1 (а)** — API пробы удаляется из kit целиком: `ProfileProbe` и всё связанное из `codelab_client_core`, `classifyProbeFailure` из `codelab_client_io`, `SecretRebindableResolver` и `withSecrets` (D2). Решил координатор (техническое решение по AGENTS.md §13). Отклонены: (б) оставить в kit без потребителей; (в) оставить только классификатор.
- **Q2 (а)** — экран «Profile saved» без пометки: `Added to profiles.json as <id>` [` · used by default`] и прежний текст про «Use» и «Restart agent» (D4). Решил пользователь. Отклонены: (б) подсказка «To check it, select it with Use…»; (в) кнопка «Use now».
- **Q3 (а)** — при «Save» только существующая локальная валидация черновика, сетевой и `PATH`-проверки нет. Решил пользователь. Отклонены: (б) проверка команды в `PATH` (отдельный change); (в) сетевая проверка при сохранении — та же проба.
- **Q4 (а)** — строка профиля показывает только бейдж `Failed`; причина — на экране или баннере сбоя рабочего места. Решил пользователь. Отклонено: (б) подсказка с причиной у бейджа (отдельный change).
- Попутно: событие `connection.connect_on_start` снято из требования app-settings «События журнала настроек без секретов» — код его не пишет с D19 change `require-project-folder` (решение координатора).

## Открытые вопросы

Нет.
