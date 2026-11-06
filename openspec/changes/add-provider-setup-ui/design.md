## Context

Второй из двух changes настроек codelab-app. Первый, `add-app-settings-shell` (A), заархивирован 2026-11-05. Он дал навигацию, оболочку, страницу «Connection» и диалог «Add connection profile» с токеном только из переменной окружения. Что A передал сюда — design.md A, D13 (список «В change B переходят»), D18 (ребро `codelab_desktop → codelab_setup` и правило «stage 7»), Risks («allowlist имён переменных — кандидат для change B»).

Источники:
- `dart-agent-and-clients` §12.4.2 (контракт `codelab_setup`), §12.4.3 (первый запуск CLI), §12.4.4 (мастер), §12.4.5 (Providers), §12.4.6 (MCP servers), §12.4.8 (удалённый агент), §12.4.9 (шаги 4–8 «Add profile», `/settings`), §12.4.11 (SETUP-1…SETUP-22), §12.4.13;
- `agent-core-architecture` §15, §17.5.2–§17.5.8 (`ConfigWriter`, `SecretStore`, перечитывание, `SettingsRegistry`); `17-5-agent-setup.md`, OQ4 (поток состояний MCP — «вместе с потребителем, change `add-provider-setup-ui`»);
- холст `docs/design/claude-design/`: `Providers` (05), `Mcp` (05b), `Wizard` (06), `AddProfile` (20a), `Connection` (20), `CliSetup` (C5), `CliSettings` (C13). При расхождении документы и `openspec/specs/` сильнее холста (README холста). Пользователь требует UI/UX строго по холсту; отступления — только перечисленные в D24 и согласованные с ним.

Что уже есть в коде (`develop` после A):
- **`codelab_setup`**:
  - основной барель реэкспортирует только `ConfigIssue`, `ConfigIssueKind`, `ConfigLoadResult`, `before1Note`;
  - `io.dart` — подкоманды `config|provider|mcp|secret`, `SecretAdmin` (`store`, `checkStore`, `delete`, `list`; чтения значения нет), `openSecretStore`, `DescribedSecretStore`;
  - `setupAllowlist = {codelab_agent_core, codelab_agent_io, meta}`.
- **Ядро:**
  - `ConfigEdit` (`SetValue`, `UnsetValue`, `UpsertMcpServer`, `RemoveMcpServer`, `RemoveTable`), `ConfigTarget`, `ConfigSnapshot` (fingerprint), `ConfigConflictException`;
  - `SettingsRegistry` (`secrets.backend` — `fileOnly`: «an open secrets file is chosen only by a deliberate edit»), `SecretNames` (`suggestFor`, `forMcp`, `envOverride`), `SecretResolver`;
  - каталог моделей (`builtin_models.dart`);
  - `McpSessionTools.servers` с `McpServerSummary` (`state`, `toolCount`, `lastError`, `retryIn`) и `reconnect`, но без потока изменений;
  - встроенные команды `/config reload|check`, `/mcp list|reload|enable|disable`;
  - `ProviderPresets` в ядре нет (§17.10.2 — после MVP).
- **`codelab_agent_io`**: `ConfigWriter` (`read(target)`, `apply`, блокировки, сохранение комментариев), `ConfigLoader`, `openSecretStore`: `auto` = `env` (только чтение), `file` — только явным `secrets.backend: file`, не на Windows. Проверки `/models` по HTTP нет нигде.
- **`codelab_embedded`**: `EmbeddedAgent` (`clientTransport`, `secretsInConfig`, `closed`, `dispose`); ядро работает в главном isolate процесса app (решение 7.8).
- **Kit:**
  - `ProfileTokenRef` (`EnvTokenRef`, `UnsupportedTokenRef`), `ProfileSecretSource(environment)`, `ProfileDraft`, `ProfileProbe`;
  - `SessionHandle.send(text) → PromptOutcome`;
  - отдельной «команды» без хода нет.
- **App:**
  - `SettingsPage` — все 11 страниц, видимые задаёт `lib/app/default_settings_pages.dart` (сейчас только `connection`);
  - `AddProfileCubit`, `ConnectionSettingsCubit`, `NavigationCubit`;
  - зависимости app на `codelab_setup` нет (`desktopAllowlist`).
- **CLI:**
  - `ProviderCommands`/`McpServerCommands` из `run.dart`;
  - `PickerSpec` общий для REPL и TUI;
  - `LineEditor` со скрытым вводом — у `StdinSecretInput`.
- **Активный черновик `add-agent-os-secret-backends`** (0/14, «после 1.0»). Он добавляет хранилища ОС за тем же `SecretStore` и меняет только `openSecretStore` и `auto`. Типы, которыми пользуется B (`DescribedSecretStore`, `SecretBackendInfo`, `SecretAdmin`), он не трогает (его proposal, «Не входит»).

Ограничения:
- корневой `AGENTS.md`: §2 (безопасность и целостность данных выше UX), §3.4 и SETUP-14 (ACP не меняется), §5 (клиенты не импортируют `codelab_agent_*`; холст и сторонний код не копируются), §8 (явные автоматы), §9 и §12 (поздние результаты, владельцы подписок), §10 (секреты), §13 (без абстракций «на вырост»), §16, §21;
- вложенные `AGENTS.md`: `codelab_setup` §2 (границы барелей), `apps/codelab_desktop` («Секреты»: только общие бэкенды через `codelab_setup/io.dart`, без `flutter_secure_storage`), `apps/codelab_cli` §2 (`codelab_setup/io.dart` — только `run.dart`), `codelab_client_core` (web-безопасность, секреты только ссылками).

## Goals / Non-Goals

**Goals:**
- страницы «Providers» и «MCP servers» по артбордам `Providers` и `Mcp` для встроенного агента и локального `codelab-agent`; для удалённого и стороннего агента — только чтение (SETUP-2);
- один мастер провайдера (`ProviderSetupFlow`) для app, `codelab provider add` на TTY, клиентских флагов и первого запуска CLI (SETUP-8);
- токен WebSocket-профиля в хранилище секретов агента: «Use stored secret», «Store a new token», порядок «секрет → профиль» с откатом, удаление собственного секрета при «Remove» (SETUP-19, шаги 4–8 §12.4.9);
- `/settings` в CLI по `SettingsRegistry` (`scope: shared`);
- ни значения ключа, ни токена в конфиге, профилях, состоянии Cubit-ов, журналах и выводе (SETUP-1);
- ни одного нового поля или метода ACP (SETUP-14).

**Non-Goals:** — раздел «Не входит» в `proposal.md`. В частности, хранилища ОС остаются за `add-agent-os-secret-backends`, onboarding app — за отдельным change (Q3).

## Decisions

### D1. Охват и связь с `add-agent-os-secret-backends`

B не зависит от черновика хранилищ ОС и не пересекается с ним:
- B пользуется портом `DescribedSecretStore` и `SecretAdmin` такими, какие они есть в 1.0;
- `SecretBackendInfo.id` и `writable` берутся из бэкенда, а не из констант;
- когда черновик подключит `keychain-macos`, строка «Key storage», варианты «Store…» и подсказки станут работать с ним без правки B.

Тексты UI называют настоящий бэкенд (`file`, `env`), а не `keychain-macos` холста (D24).

Поведение B до хранилищ ОС: на новой установке `secrets.backend: auto` = `env`, только чтение. Варианты «Store a new token», «Store in …» мастера и «Secret» MCP недоступны и показывают причину бэкенда (D3). Запись на desktop без хранилища ОС в B не открывается: UI честно показывает «только чтение» и подсказку про `secrets.backend: file` (решение пользователя 2026-11-05, Q1 (а)).

*Альтернативы:*
- (а) сделать B зависимым от черновика хранилищ ОС — переносит работу «после 1.0» в 1.0 вопреки решению 2026-10-31; это был вариант (в) Q1, пользователь его не выбрал;
- (б) временно хранить токены в `shared_preferences` или `flutter_secure_storage` — запрещено (`apps/codelab_desktop/AGENTS.md`: одно хранилище у app, CLI и агента).

### D2. Где живёт логика: `codelab_setup`, исполнитель `[agent]`

Мастер, проверка, порядок записи, доступ к настройкам, снимок конфига и черновик MCP — в основном бареле `codelab_setup` (чистый Dart, web-безопасно), как требует §12.4.2. IO-реализации портов (`FileAgentConfigStore`, `ClientSecretAccess`, `ioProviderCheck`) — только в `io.dart`. App и CLI получают одни и те же автоматы и отличаются только тем, кто посылает события.

Задачи моста помечаются `[agent]`. Так было в прежних changes (`add-agent-configuration`, `add-config-writer-and-reload`): мост держит схему агента и реэкспорт его типов, и его ведёт исполнитель стороны агента. Клиентская часть (kit, CLI) — `[client]`, app и `codelab_ui` — `[desktop]`.

Пресеты MVP — таблица в `codelab_setup/lib/src/provider/provider_presets.dart`:
- OpenAI, Anthropic, OpenRouter (адрес, вид, переменная-подсказка);
- Ollama (локальный, без ключа);
- «Custom OpenAI-compatible», «Custom Anthropic-compatible».

Это ровно список артборда `CliSetup` (решение Q5). Переход таблицы в ядро (§17.10.2) — после MVP, без изменения потребителей: `ProviderPreset` останется типом моста, который реэкспортирует тип ядра. Значения — общеизвестные адреса API, а не чужой код (AGENTS.md §5).

*Альтернативы:*
- автомат в kit — kit одинаков для любого агента, а здесь схема конфига нашего агента; зависимость kit от ядра нарушает §4.1 (§12.4.2, «Почему не другие места»);
- автомат в app и отдельно в CLI — нарушает SETUP-8.

### D3. Хранилище секретов в 1.0 и честный UI

Все места записи секрета (мастер, «Store a new token», «Secret» MCP) спрашивают `ClientSecretAccess.backend` (D4):
- `writable == true` — вариант доступен, подпись называет `backend.id` и имя секрета;
- `writable == false` — варианта нет или он неактивен. Подсказка строится из `SecretReadOnly` (`variable`, `fileBackendOffered`), как у `codelab secret set` (spec agent-secrets «Программная запись секретов»):
  - `Secret store <backend.id> is read-only. Add 'secrets.backend: file' to <home>/config.yaml to store secrets in <home>/secrets.yaml (plaintext, 0600), or set <CODELAB_SECRET_…> in the environment.` — если `fileBackendOffered`; это тот же текст, что `_readOnlyHint` у `codelab secret set` (`codelab_agent_io/lib/src/cli/secret_commands.dart`), чтобы app и CLI говорили одно;
  - `Secret store <backend.id> is read-only. Set <CODELAB_SECRET_…> in the environment.` — на Windows;
  - **если `ClientSecretAccess.configProblem` не пуст** (битый `config.yaml`, недопустимое значение `secrets.backend`; D4) — показывается эта причина, а не совет добавить `secrets.backend: file`: совет «добавьте ключ» при сломанном файле ведёт не туда (решение оркестратора, ревью итерации 1).

  Текст строит одна функция `secretReadOnlyHint(SecretReadOnly, home)` в `codelab_agent_io` (выносится из `SecretCommands._readOnlyHint` без смены вывода CLI), её реэкспортирует `codelab_setup/io.dart`. Пользуются ею `SecretCommands`, мастер CLI и адаптеры app; в Cubit-ы app приходит готовая строка. Функция возвращает текст CLI дословно — `secret store <id> is read-only. …` со строчной буквы (вывод `codelab secret set` не меняется); адаптер app в `lib/app/` делает первую букву заглавной, поэтому в UI подсказка начинается с `Secret store …`, как в сценариях app-settings (решение оркестратора, итерация 1).

**Когда app перечитывает бэкенд** (решение пользователя 2026-11-05, ревью итерации 1): `ClientSecretAccess` открывается заново — с повторным чтением `secrets.backend` — при каждом открытии диалога «Add connection profile», страницы «Connection» и (с итерации 2) страницы «Providers». Поэтому правка `secrets.backend: file` в `config.yaml` применяется без перезапуска app. Транспорт подключения читает секрет через тот же экземпляр, что открыла последняя страница или диалог; до первого открытия — экземпляр composition root.

Ключ `secrets.backend` app не пишет: в реестре он `fileOnly` с причиной «an open secrets file is chosen only by a deliberate edit». Кнопки «хранить ключи в открытом файле» в app нет (Q1 (а), вариант (б) отклонён).

Строка «Key storage» страницы Providers:
- `Key storage: <id>`;
- тег `writable` или `read-only`;
- при `unavailableReason` — InfoBar `storeUnavailable` с причиной (§12.4.5, шаг 2).

Подпись холста «Only key names and presence are read — values never enter the app» остаётся. Для `file` добавляется вторая строка `Keys are stored in an open file <home>/secrets.yaml (mode 0600).`: открытый файл — факт, который пользователь должен видеть (`secrets.backend.plaintext` агента).

### D4. `ClientSecretAccess` — клиентский доступ к секретам

`codelab_agent_io/lib/src/secrets/client_secret_access.dart`, реэкспорт из `codelab_setup/io.dart`:

```dart
final class ClientSecretAccess {
  static Future<ClientSecretAccess> open({required String codelabHome,
      required Map<String, String> environment, required Logger logger});
  SecretBackendInfo get backend;            // id, writable, unavailableReason
  String? get configProblem;                // не null, только если open откатился на env из-за config.yaml
  SecretAdmin get admin;                    // store / checkStore / delete / list
  Future<bool> isSet(String name);          // names() или CODELAB_SECRET_<…>; значение не читается
  Future<String?> read(String name);        // CODELAB_SECRET_<…>, затем бэкенд; без кэша
}
```

- **Выбор бэкенда.** `open` читает из пользовательского слоя (`$CODELAB_HOME/config.yaml`) только `secrets.backend`: ключ допустим только в слое `user` (`_userOnly`). Значение передаётся в `openSecretStore`, как это делает `openHostSecrets`. Если файл не читается или значение недопустимо, получается `env` с `unavailableReason`: запись не происходит, пока конфиг сломан. Причина — текст `secretsBackendProblem` без значений. Её же отдаёт поле `configProblem`: оно не пусто только при таком откате и отличает сломанный конфиг от обычного `auto → env`, у которого тоже есть `backend.unavailableReason` (разбирать текст причины хрупко; решение оркестратора, повторное ревью итерации 1). При `auto → env` UI по-прежнему советует добавить `secrets.backend: file` (D3).
- **Чтение без кэша.** Резолвер агента кэширует найденное до конца процесса. Клиенту кэш не нужен: токен профиля читается при каждом открытии транспорта, ключ провайдера — при каждом «Check». Замена в другом процессе видна сразу. Порядок «переменная `CODELAB_SECRET_<…>`, затем бэкенд» — тот же, что у `SecretResolver` (agent-secrets «Резолвер секретов»): значение из переменной побеждает, иначе клиент и агент разошлись бы.
- **Время жизни.** Экземпляр не кэширует выбор бэкенда навсегда: хост вызывает `open` заново там, где пользователь ожидает свежего состояния (D3) (решение пользователя 2026-11-05, ревью итерации 1). `open` дешёвый — одно чтение `config.yaml`, без процессов для `env` и `file`.
- **Гонка «проверили — записали».** `SecretAdmin.store` пишет и существующее имя (`SecretUpdated`). Если имя появилось между `checkStore`/`names()` и `store`, клиент считает результат `SecretUpdated` равным `Exists`: секрет не создан этой операцией и при отказе следующего шага не откатывается (решение оркестратора, ревью итерации 1). Атомарного «создать, только если имени нет» в порте нет — задача backlog `[agent]` `SecretAdmin.create` (`delivery-roadmap.md` §10.4).
- **Где значение.** `read` возвращает `String?` только адаптерам `lib/app/` и `run.dart`, которые сразу отдают его транспорту или `ProviderCheck`. В состояние, события и тексты оно не попадает (SETUP-1).

*Альтернативы:*
- экспортировать `openHostSecrets` в мост — D15 change `add-agent-secret-store` оставил его хосту агента; к тому же у него кэш;
- клиент сам вызывает `openSecretStore` и `SecretAdmin` — порядок «переменная, затем бэкенд» и выбор бэкенда разошлись бы у app и CLI.

### D5. `SettingsAccess`: чьи это настройки

`resolveSettingsAccess(...)` (§12.4.2) вызывается для **профиля текущего подключения**, а если окно ни к чему не подключено — для профиля по умолчанию. Страница показывает именно эти настройки. При смене подключения Cubit-ы страниц перечитывают доступ.

| Профиль | Доступ | Пути и `cwd` |
|---|---|---|
| встроенный | `EditableSettings` | `CODELAB_HOME` app, `cwd` — папка проекта сессии |
| stdio, базовое имя команды — `codelab-agent` (`resolveSettingsAccess(command:)`) | `EditableSettings` | `CODELAB_HOME` из `env` профиля, иначе app; `--config <file>` из аргументов — только чтение; `cwd` — папка проекта при `runInProjectDirectory`, иначе слой `projectLocal` недоступен |
| stdio, другая команда | `NotManaged(agentName)`, `agentName` — базовое имя команды | — |
| WebSocket | `RemoteReadOnly(endpoint)` | — |

**Решение по команде, а не по самоназванию** (решение оркестратора, итерация 2; согласовано пользователем 2026-11-06: для чужого агента текст `managed by <команда>`, например `managed by python`; публикация `agentInfo` — follow-up backlog roadmap §10.4). Имени агента из `initialize` (`agentInfo.name`) в `WorkspaceState` kit нет, поэтому «наш stdio-агент или чужой» решается по базовому имени команды профиля. Самоназвание могло бы только опровергнуть это решение (команда `codelab-agent`, а агент назвался иначе → `NotManaged`), но сейчас клиенту оно недоступно. Follow-up `[client]`: публиковать `agentInfo` в `WorkspaceState` и подключить опровержение (`delivery-roadmap.md` §10.4). Остаточный риск: обёртка с другим именем (`./run-agent.sh`) над `codelab-agent` даёт `NotManaged` — безопасно, запись просто недоступна.

`RemoteReadOnly` и `NotManaged`:
- локальный конфиг не читается (SETUP-2);
- InfoBar `warning` с текстом §12.4.8 (`Read-only: this agent runs on <scheme://host:port>.` / `… are managed by <agentName>.`) и командами для хоста агента;
- кнопок записи нет;
- «Default model» показывает текущую модель сессии из `configOptions` (без записи);
- «MCP servers» — только панель «Agent status» (D12).

### D6. `AgentConfigStore` и `FileAgentConfigStore`

Порт и типы — по §12.4.2 без изменений. `FileAgentConfigStore` (`codelab_setup/lib/src/io/`) собирает `ConfigWriter` и `ConfigLoader` с тем же `CODELAB_HOME`, окружением и `cwd`, что у агента из D5.

`snapshot(cwd)`:
- `ConfigWriter.read` для слоёв `user`, `projectLocal`, `project`;
- `ConfigLoader` — для `loaded` и `origins` (лист → источник);
- `ClientSecretAccess.backend` — для поля `secrets`.

`apply` переводит исключения писателя в `ConfigSaveOutcome` по таблице §12.4.2. `ConfigInlineSecretException` проверяется раньше `ConfigException`.

Перечитывание:
- снимок берётся при открытии страницы, после собственной записи и после `ConfigConflict`;
- слежения за файлом у страницы нет, как у «Connection» (design.md A, D4);
- правка в CLI видна при следующем открытии страницы.

Агент следит за файлом сам (§17.5.6) и присылает `config_option_update`; страница подписана на `WorkspaceState` ради строки «Active in this session» (§12.4.5, шаг 7).

Цели записи — только `ConfigTarget.user()` и `ConfigTarget.projectLocal(cwd)` (SETUP-3). Провайдеры и серверы из слоя 3, файла `--config` и переменных окружения показываются с пометкой `defined in <file>` и не редактируются.

### D7. Мастер `ProviderSetupFlow`

Автомат, события, планы правок и шаги — §12.4.4 без изменений, кроме уточнений:
- **Номер проверки.** `Checking` несёт номер попытки. «Retry», «Back», «Cancel» и `dispose()` делают прежний номер устаревшим, и поздний `ProviderCheckResult` отбрасывается с событием `provider_wizard.check_discarded` (AGENTS.md §9, §12). Запрос по таймауту 10 с закрывает соединение (`http.Client.close` у клиента попытки), а не только перестаёт ждать.
- **`SecretValue`** живёт только в черновике. `dispose()`, `Cancel` и `Done` сбрасывают ссылку. В `ProviderSetupState.toString()`, в плане и в `toEdits()` значения нет (SETUP-1). `KeySubmitted(StoreSecret)` с пустым значением — ошибка шага, а не переход.
- **Существующий секрет с тем же именем** (`codelab/<id>` уже в `names()` — остаток удалённого провайдера или ключ, записанный `codelab secret set`). Он не перезаписывается молча (SETUP-5). Шаг ключа показывает `A stored key codelab/<id> already exists in <backend>.` и два варианта:
  - «Use the stored key» (`KeepStoredSecret` для нового провайдера);
  - «Replace it» — явный выбор, план получает `replaceSecret: true`.
- **`SkipCheck`** — только для `unreachable` и `timeout`, после подтверждения, с предупреждением `Not verified: <kind>` в `Reviewing` (SETUP-4). `notFound` разрешает ручной ввод модели без пропуска; для OpenAI-совместимого адреса без `/v1` мастер предлагает вариант с `/v1` (артборд `Wizard`).
- **«This project only»** доступен, только если у `EditableSettings` есть `cwd` проекта (D5).
- **Событие не к месту** игнорируется и пишется в журнал на уровне `debug` (`provider_wizard.event_ignored`, поле `state`).
- **«Back»** (решение оркестратора, ревью итерации 3): `EnteringBaseUrl → ChoosingPreset` (при правке «Back» не к месту); `ChoosingKey → EnteringBaseUrl`; `Checking → ChoosingKey` (попытка устаревает, запрос отменяется); `CheckFailed → ChoosingKey` при `unauthorized`, иначе `EnteringBaseUrl`; `ChoosingModel → ChoosingKey`; `EnteringModelDetails → ChoosingModel`; `Reviewing → ChoosingModel`; `SaveFailed → Reviewing`. Шаг ключа при каждом входе начинается заново: выбранный источник и введённое значение ключа при «Back» с шага ключа и из шагов после него не сохраняются (`SecretValue` сбрасывается, SETUP-1), пользователь вводит ключ снова.
- **Тексты ошибок шагов**, которыми владеет автомат (одни в app и CLI): адрес — `Enter an http or https address.` и `Remove the user name and password from the address.`; ключ — `Enter the API key.` (пустой `StoreSecret`), `Enter the environment variable name.` (пустой `UseEnvVar`), `There is no stored key to keep.` (`KeepStoredSecret` без сохранённого ключа); окно — `Context window must be a positive number.`; запись — `The config file cannot be read.` (`PlanRefusal.layerUnreadable`, D9).
- **Подтверждение `http://`** относится к адресу, который сейчас в поле: подтверждённый адрес запоминается в черновике. Другой `http://`-адрес (правка поля после подтверждения, в том числе после «Back») снова требует подтверждения; тот же подтверждённый адрес — нет. Подтверждение, показанное для одного адреса, не принимается для адреса, изменённого после показа.
- **Переименование на «Review»** (смена id) сбрасывает выбор «Replace it» (`replaceSecret: false`): замена относилась к секрету прежнего имени `codelab/<старый id>`, а под новым именем committer снова проверяет `keys.stored` (D9, шаг 1).

**Порты и входы автомата** (решение оркестратора, подготовка итерации 3). Основной барель не видит `ClientSecretAccess` и `SecretAdmin` (`codelab_agent_io`), поэтому всё, что мастеру нужно от хранилища секретов, приходит одним портом основного бареля — по образцу `SecretDeleter` итерации 2:

```dart
// codelab_setup/lib/src/provider/provider_keys.dart (основной барель)
abstract interface class ProviderKeys {
  SecretBackendInfo get backend;                       // id, writable, unavailableReason
  String? get readOnlyHint;                            // готовая подсказка D3 или null
  Future<bool> stored(String name);                    // имя есть в бэкенде (names()), без CODELAB_SECRET_*
  Future<SecretValue?> read(String name);              // CODELAB_SECRET_*, затем бэкенд; без кэша
  Future<ProviderKeyWrite> write(String name, SecretValue value);
  Future<SecretDeletion> delete(String name);          // тип итерации 2
}
sealed class ProviderKeyWrite {}
final class ProviderKeyCreated extends ProviderKeyWrite {}      // SecretStored
final class ProviderKeyReplaced extends ProviderKeyWrite {}     // SecretUpdated
final class ProviderKeyRefused extends ProviderKeyWrite { final String reason; }  // ReadOnly, Failed, InvalidName, InvalidValue, Collision
```

Реализация — `providerKeysOf(ClientSecretAccess access, {required String home})` в `io.dart` (`lib/src/io/`), рядом с `secretDeleterOf`: `stored` — по `admin.list()` (`SecretListing.names`), `read` — `access.read`, `write` — `admin.store(name, value.reveal())` с переводом исходов, `readOnlyHint` — `secretReadOnlyHint` с учётом `configProblem` (D3). Значение раскрывается только внутри адаптера. Имена веток не совпадают с `SecretStored`/`SecretUpdated` из `io.dart`: composition root импортирует оба бареля. `ProviderRemover` по-прежнему получает `SecretDeleter` — подходит отрывок `keys.delete`.

```dart
ProviderSetupFlow({
  required ProviderCheck check,
  required ProviderSetupCommitter committer,
  required ProviderKeys keys,
  required AgentConfigSnapshot snapshot,
  required EditableSettings access,              // цели записи и cwd (D5)
  required Map<String, String> environment,      // окружение агента: UseEnvVar и api_key_env
  required bool Function(String host) isLocalHost,   // правило kit (D8)
  required Logger logger,
  List<ProviderPreset> presets = ProviderPresets.all,
  ProviderEntryView? editing,
  bool forceDefault = false,                     // true — makeDefault зафиксирован (первый запуск CLI, баннер D26)
  Duration checkTimeout = defaultProviderCheckTimeout,
});
```

- **Существующий секрет** узнаётся `keys.stored('codelab/<id>')` при входе в `ChoosingKey` (после того как id известен); до ответа порта шаг не принимает `KeySubmitted` (событие не к месту). Переменная `CODELAB_SECRET_*` существующим секретом не считается: текст `A stored key … already exists in <backend>.` говорит о бэкенде.
- **Ключ для проверки:** `StoreSecret` — значение черновика; `UseEnvVar(name)` — `environment[name]`; `KeepStoredSecret` при правке — по ссылке редактируемого провайдера: `api_key_secret` → `keys.read`, `api_key_env` → `environment`; `NoKey` — без ключа. Пустое или отсутствующее значение — запрос без ключа, исход проверки показывает отказ, как на странице Providers. Отмена — `CancelTokenSource` попытки: «Retry», «Back», «Cancel» и `dispose()` отменяют её, мост закрывает соединение (D8), итог `CheckCancelled` состояние не меняет.
- **`CheckFailed`** несёт `probeUrl` (без query, userinfo и fragment — `displayBaseUrl` + путь), статус и длительность попытки (`Stopwatch`) — строка артборда `GET <url>/models → 404 · 212 ms`.
- **Окно контекста.** Источники по порядку: поле ответа `/models` (`RemoteModel.contextWindow`), затем встроенный каталог ядра. Каталог ядра сейчас закрыт (`builtinModels` и `_lookupBuiltIn` не экспортируются), поэтому ядро получает публичную функцию `builtinModelInfo(String model) → ModelInfo?` (тот же поиск по точному имени и по префиксу до `-`; `StaticModelCatalog` переходит на неё, второй копии правила нет) и константу `safeDefaultContextWindow = 32000` (тот же литерал в `_resolveFields`) (решение оркестратора, итерация 3; allowlist ядра PKG-2 не меняется). Мост пользуется ими внутри автомата и клиентам их не реэкспортирует: подсказку клиент получает в состоянии. Правило:
  - `ModelChosen` из списка: окно известно из ответа или каталога → `Reviewing`; иначе `EnteringModelDetails(suggestedContextWindow: 32000)`;
  - `ModelEnteredManually` → всегда `EnteringModelDetails` (артборд `Wizard`: «you will also set the context window»), подсказка — каталог, иначе `32000`;
  - план всегда пишет `providers.<id>.models.<m>.context_window` — модель должна быть объявлена в конфиге (§15.4), а явное окно не зависит от смены каталога ядра.
- **Правка (`editing`).** Старт с `EnteringBaseUrl`, вид и id зафиксированы, шаг «API type» в строке шагов отмечен пройденным. Цель записи — слой, где лежит провайдер (`user` или `projectLocal`), переключателя «This project only» нет. «Edit» неактивна по тем же отказам, что «Remove»: `notEditable`, `multipleLayers`, `layerUnreadable` (D9), с тем же текстом подсказки. Правило одно — функция моста `providerEditRefusal(snapshot, providerId)` (отказ или `null`); страница берёт подсказку из неё, а автомат проверяет то же правило и отказывает в правке `editing`, для которого оно даёт отказ, без записи — неактивная кнопка не единственный рубеж (решение оркестратора, ревью итерации 3). Литеральный ключ в файле (`KeyLiteralInConfig`, D10): варианта «оставить ключ» нет — app не читает литерал (SETUP-1), а проверка без ключа дала бы ложный `unauthorized`; шаг ключа показывает `The key is written in config.yaml. Choose where to keep it instead.`, и любой выбранный источник вместе с собственными правками ключа даёт `UnsetValue("providers.<id>.api_key")` — как R4-4 у `provider add` (spec agent-configuration «Подкоманды записи и чтения конфига»).
- **Правка: адрес с userinfo в конфиге.** Если `base_url` провайдера в файле содержит userinfo (записан вручную), шаг адреса не показывает его: поле заполняется адресом без userinfo, и шаг сразу несёт ошибку `Remove the user name and password from the address.` (Q11). Значение userinfo не попадает ни в состояние, ни в журнал (SETUP-1).
- **Правка: модель и «Make default».** В `ChoosingModel` текущая модель провайдера выделена; «Make default» на «Review» отражает текущее состояние — включён, если `agent.default_model` указывает на этого провайдера, иначе выключен, пока пользователь не сменит выбор.
- **`forceDefault`.** Первый запуск CLI (D16) и баннер D26 создают мастер с `forceDefault: true`: агент без `agent.default_model` не стартует, поэтому снять «Make default» там нельзя, флажок показан выбранным и неактивным.

**Шаги диалога app и ключи** (решение оркестратора; отображение состояний на строку шагов):

| `ProviderSetupState` | Шаг строки | Ключ тела |
|---|---|---|
| `ChoosingPreset` | API type | `provider-wizard-type` |
| `EnteringBaseUrl` | Base URL | `provider-wizard-base-url` |
| `ChoosingKey` | Key | `provider-wizard-key` |
| `Checking`, `CheckFailed` | Check | `provider-wizard-check` |
| `ChoosingModel`, `EnteringModelDetails` | Model | `provider-wizard-model` |
| `Reviewing`, `Saving`, `SaveFailed` | Review | `provider-wizard-review` |

Шаги левее текущего — пройденные. Над телом каждого шага после первого — сводка пройденных шагов (`Type`, `Base URL`, `Key` …), как в артборде `Wizard`. Кнопки — `provider-wizard-next`, `-back`, `-cancel`, `-retry`, `-skip-check` (с подтверждением `provider-wizard-skip-confirm`), `-save`; варианты `notFound` — `provider-wizard-use-v1`, `provider-wizard-manual-model`; поля — `provider-wizard-base-url-field`, `provider-wizard-key-field` (`PasswordBox`), `provider-wizard-env-field`, `provider-wizard-model-filter`, `provider-wizard-context-window`; на «Review» — `provider-wizard-make-default`, `provider-wizard-project-only`. **Тексты шагов и отказов** (решение пользователя 2026-11-06, Q9 (а)): подписи шагов — из артборда `CliSetup`, одни слова в CLI и app:
- «API type» — `API type`; пресеты `OpenAI`, `Anthropic`, `OpenRouter`, `Ollama (local, no key)`, `Custom OpenAI-compatible endpoint`, `Custom Anthropic-compatible endpoint`;
- «Base URL» — `Base URL`;
- «Key» — `API key source`; варианты `Store in <backend> as "codelab/<id>"` (только при записываемом бэкенде, D3), `Read from environment variable (<VAR>)`, `No key`; поле значения — `API key`;
- «Model» — `Model (type to filter)` и строка `Enter model id manually`; окно — `Context window`;
- «Review» — сводка `Provider`, `key`, `model`, `file` как в `CliSetup`, кнопка `Save`.

Заголовки отказов проверки — по образцу артборда `Wizard` (`Model list not found (404)`): `Key rejected (<код>)` (401/403), `Server unreachable`, `Timed out after 10 s`, `TLS error`, `Unexpected response (<код>)`; под заголовком — строка запроса `GET <url>/models → <код> · <n> ms` (без кода у `unreachable`, `timeout`, `tlsError`). Пояснение в одну строку есть только у `notFound` (текст артборда); у остальных — без пояснения.

**Адрес** (решение пользователя 2026-11-06, Q11 (а)): шаг адреса отклоняет `base_url` с userinfo ошибкой шага `Remove the user name and password from the address.` — валидатор ядра `base_url` на секреты не проверяет (`inline_secrets.dart`), и пароль попал бы в `config.yaml`. Query и fragment допустимы (у Azure OpenAI `api-version` в query штатный); показываются и логируются они только через `displayBaseUrl` и `scheme://host:port`.

Точки входа: `ProviderWizardDialog` (app), вопросы `LineEditor` (CLI). `ProviderWizardCubit` app — тонкая обёртка: `state = ProviderSetupState`. Автомат собирает composition root: `ProviderSettingsSession` получает фабрику `openWizard({ProviderEntryView? editing, bool forceDefault})`, которая строит `ProviderSetupFlow` с `providerKeysOf`, `FileAgentConfigStore`, `ioProviderCheck` и `isLocalHost` kit этой же сессии; Cubit получает готовый автомат и порта `ProviderKeys` не видит — значение ключа в `features/` не попадает (SETUP-1, SETUP-9). `EditableSettings` и папку проекта автомат получает из сессии страницы: «This project only» есть, только если `access.targets` содержит `projectLocal` (D5: для встроенного агента — папка проекта окна, для stdio — только при «Run in the project folder»).

### D8. Проверка `/models`: `HttpProviderCheck`

`HttpProviderCheck(http.Client Function() clientFactory)` — основной барель (только `package:http/http.dart`, web-безопасно). `ioProviderCheck()` в `io.dart` даёт фабрику `IOClient`. App и CLI получают его там же, где остальной `io.dart`. Своей зависимости `http` у app нет.

Запрос и разбор — §12.4.4, шаг 4. Уточнения безопасности:
- **Без редиректов** (`followRedirects = false`). Ответ `3xx` даёт `badResponse` с кодом. Иначе ключ в `Authorization` или `x-api-key` ушёл бы на другой хост, о котором пользователь не знает. Это SETUP-10: запрос идёт только на введённый `base_url`; новое правило — SETUP-23 (итерация 0).
- **Тело ошибки** в результат не попадает: только статус и вид отказа.
- **`http://` к нелокальному хосту** — только после подтверждения на шаге адреса (§12.4.4, шаг 2). Подтверждение привязано к адресу черновика и сбрасывается его правкой, как у `ws://` в A (D11 A).
- **В журнале** — только `scheme://host:port`, без пути и query.
- **Трактовка SETUP-10 на странице Providers** (решение пользователя 2026-11-06): адрес провайдера там уже записан в конфиге, поэтому «Check» строки с `http://` к нелокальному хосту доступна без диалога, а рядом с ней показывается предупреждение `The key is sent unencrypted to <host>.`. Подтверждение на шаге адреса остаётся только в мастере (итерация 3), где адрес вводится впервые.
- **Правило «локальный хост» — одно** (решение оркестратора, итерация 3). Сейчас это публичная `isLocalHost` kit (`codelab_client_core/lib/src/connection/profile_draft.dart`): её используют `ProfileDraft` и предупреждение `http://` страницы Providers, а мастеру она нужна на шаге адреса. Перенести её «в мост с реэкспортом из kit» или в общий пакет нельзя: kit не зависит от стороны агента (§4.1, сторож), мост не импортирует `package:codelab_client_*` и `package:codelab_acp_*` (правило `codelab_setup`), а общего web-безопасного пакета у них нет. Поэтому правило остаётся в kit, а мост получает его параметром: `ProviderSetupFlow({…, required bool Function(String host) isLocalHost})`. App и CLI передают `isLocalHost` kit из composition root; тесты моста — свою функцию. Второй копии правила нет. Новый пакет ради одной функции отклонён как несоразмерный (AGENTS.md §13).
- **Неподдерживаемый вид.** Проверку умеют только `openai-compatible` и `anthropic`. Какие виды проверяются и какой адрес по умолчанию у вида — решает мост (`supportsProviderCheck(kind)`, адрес по виду), а не app (решение оркестратора, ревью итерации 2).

`codelab_setup` += `http` в allowlist. Пакет уже в allowlist ядра и у `codelab_embedded`, новой сторонней зависимости в monorepo нет.

### D9. Запись провайдера: `ProviderSetupCommitter`

Порядок — §12.4.4, шаг 8 (SETUP-5):
1. `StoreSecret` → `ProviderKeys.write` (поверх `ClientSecretAccess.admin.store`, D7). При `replaceSecret: false` committer сначала заново спрашивает `keys.stored(name)`: имя могло появиться после шага ключа (другой процесс, `codelab secret set`). Есть — запись не выполняется, исход `ProviderKeyAppeared`, мастер возвращается в `ChoosingKey` с вариантами «Use the stored key» / «Replace it» (как «Имя секрета появилось между проверкой и записью» у `ProfileCommitter`, итерация 1).
2. `AgentConfigStore.apply(base, plan.toEdits())`.
3. Не `ConfigSaved` и секрет создан на шаге 1 впервые (`ProviderKeyCreated` = `SecretStored`) → `keys.delete`. Заменённый секрет (`ProviderKeyReplaced` = `SecretUpdated`) после неудачи конфига прежним значением не восстанавливается: старого значения клиент не знает. Пользователь сделал явный выбор «Replace it», и сообщение `SaveFailed` говорит, что ключ уже заменён.
4. `ProviderKeyRefused` → конфиг не пишется, возврат в `ChoosingKey` с причиной и предложением `UseEnvVar`.

**Создан или существовал — как узнать** (подготовка итерации 3). Отдельный `SecretAdmin.create` для этого не нужен: `SecretAdmin.store` уже различает `SecretStored` и `SecretUpdated` по списку имён до записи, этого достаточно для правила отката. Остаточное окно гонки — между перепроверкой шага 1 и `store`: если имя появилось в нём, исход `ProviderKeyReplaced` при `replaceSecret: false` считается заменой (`keyReplaced: true`, без отката), как `SecretUpdated` → `Exists` у профилей (D4). Атомарный `SecretAdmin.create` закрыл бы и это окно, но меняет порт `codelab_agent_io` и `ProfileCommitter`; он остаётся задачей backlog `[agent]` (`delivery-roadmap.md` §10.4) и в итерацию 3 не входит (решение оркестратора).

**Контракт committer** (уточнение §12.4.2, где он принимал `DescribedSecretStore` и возвращал `ConfigSaveOutcome`):

```dart
final class ProviderSetupCommitter {
  ProviderSetupCommitter({required AgentConfigStore config, required ProviderKeys keys});
  Future<ProviderCommitOutcome> commit(ProviderSetupPlan plan, ConfigSnapshot base);   // base — слой plan.target
  Future<AgentConfigSnapshot> reload({required String cwd});   // свежий снимок после ConfigConflict
}
enum KeyRollback { none, deleted, failed }   // что стало с созданным на шаге 1 секретом
enum PlanRefusal { providerExists, providerMissing, layerUnreadable }   // отказ «Save» до записи
sealed class ProviderCommitOutcome {}
final class ProviderCommitted extends ProviderCommitOutcome { final ConfigSaved saved; final bool keyReplaced; }
final class ProviderKeyAppeared extends ProviderCommitOutcome {}                         // шаг 1, конфиг не писался
final class ProviderKeyNotStored extends ProviderCommitOutcome { final String reason; }  // шаг 4
final class ProviderConfigNotSaved extends ProviderCommitOutcome {
  final ConfigSaveOutcome? outcome;     // ConfigConflict | ConfigRejected | ConfigInlineSecret; null — исключение
  final String? errorType;              // имя типа исключения apply, без текста
  final bool keyReplaced;
  final KeyRollback rollback;           // none | deleted | failed
}
```

- **Исключение `apply`.** `FileAgentConfigStore` чужие исключения не перехватывает (D6). Committer ловит любое исключение `apply` после записи секрета, откатывает созданный секрет и возвращает `ProviderConfigNotSaved(outcome: null, errorType: <тип>)`: иначе созданный секрет остался бы сиротой. Текст исключения никуда не идёт (SETUP-1, сценарий «Маркер не утекает из мастера»).
- **Откат не удался** (`keys.delete` → `failed` или исключение `keys.delete`): `rollback: KeyRollback.failed`, исходный исход записи конфига (`outcome`, `errorType`) сохраняется — исключение отката его не заменяет. `SaveFailed` называет имя секрета, который остался в хранилище, событие `provider_wizard.save_failed` — `rollback: failed` (D18).
- **Отказ до записи (`PlanRefusal`).** «Save» в `Reviewing` сначала сверяет план со снимком: `providerExists` — при добавлении id уже занят; `providerMissing` — при правке провайдера больше нет в конфиге; `layerUnreadable` — слоя `plan.target` нет в снимке (файл не читается). Отказ остаётся в `Reviewing` с текстом (`A provider with this id already exists.`, `The provider is no longer in the config.`, `The config file cannot be read.`), committer не вызывается.
- **Конфликт (`ConfigConflict`) и `reload`** (решение оркестратора, ревью итерации 3). Файл изменился после чтения снимка (SETUP-6). Автомат вызывает `committer.reload(cwd: …)` и заменяет снимок свежим: иначе повторный «Save» шёл бы от старого отпечатка и конфликтовал бы вечно (D21). Автоповтора записи нет. Черновик сохраняется целиком, включая введённый ключ (`SecretValue`), а план пересобирается по свежему снимку: `makeDefault` без явного выбора пользователя — снова по наличию `agent.default_model`, `unsetKeys` и слой записи при правке — по свежему снимку. Секрет, созданный до первого конфликта, откатывается (шаг 3), а при повторном «Save» пишется заново по тому же порядку. Сбой `reload` — событие `provider_wizard.reload_failed` (`error_type`), снимок остаётся прежним, мастер всё равно в `Reviewing`.
- **Автомат:** `ProviderCommitted` → `Done`; `ProviderConfigNotSaved` → `SaveFailed` (из него «Back» → `Reviewing`; `ConfigConflict` в app — сразу `Reviewing` с баннером, §12.4.4, шаг 10); `ProviderKeyAppeared` и `ProviderKeyNotStored` → `ChoosingKey`.

После `ConfigSaved`:
- **ключ заменён под тем же именем** (`SecretUpdated`). Работающий встроенный агент держит старое значение в кэше резолвера, а конфиг не изменился, поэтому перечитывания нет. Баннер `saved` получает строку `The new key is used after Restart agent (Settings › Connection).`;
- **агент не подключён** (встроенный агент не открылся из-за отсутствия провайдера) — баннер `Saved. Connect to start the agent with the new provider.` с кнопкой «Connect» (`ConnectionCommands.connect` профиля по умолчанию). «Не подключён» — `WorkspaceState.connection` не `Connected` и не `Reconnecting` в момент `ConfigSaved`; страница уже подписана на `WorkspaceState` (D10, «Active in this session»).

**Удаление провайдера — `ProviderRemover`** (мост, итерация 2). Уточнение SETUP-24 (решение оркестратора, ревью итерации 2): «ключ используется другим провайдером» учитывает не только `api_key_secret`, но и ссылки `${secret:<имя>}` в любой строке конфига (заголовки провайдеров, `env` и `headers` MCP); после `ConfigSaved` ссылки перепроверяются по свежему снимку, и секрет удаляется, только если ссылок не осталось. (решение оркестратора, итерация 2). План удаления отказывает до записи типизированно (`ProviderRemovalRefusal`): `unknownProvider`, `notEditable` (провайдер не только в слоях `user`/`projectLocal`), `lastProvider`, `newDefaultRequired`, `newDefaultInvalid`, а также сверх §12.4.5:
- `multipleLayers` — листья провайдера лежат в нескольких слоях: один `apply` пишет один слой, половина записи оставила бы неполного провайдера;
- `layerUnreadable` — файл слоя провайдера не читается, основы для записи нет;
- `defaultOverridden` — `agent.default_model` задан в слое выше слоя провайдера, и правка нижнего слоя не сменила бы итоговую модель.

Каждый отказ — неактивная «Remove» или текст в подтверждении, без записи. Типы моста итерации 2: `AgentConfigSnapshot.origins` — `Map<String, ConfigSourceView>` (вид источника и подпись), пятый статус ключа — `KeyLiteralInConfig` (D10).

### D10. Страница «Providers»

`ProviderSettingsCubit` (`features/settings/application/`) — состояния `ProviderSettingsLoading | ProviderSettingsReadOnly | ProviderSettingsReady | ProviderSettingsUnreadable` (§12.4.2, плюс `Unreadable` для битого `config.yaml`: страница показывает ошибку загрузчика и не пишет файл, как «Connection» в A, D4).

Разметка — артборд `Providers`:
1. шапка «Providers» и «Add provider» (CommandBar);
2. строка «Default model» (ComboBox) с подписью `Used by new sessions. Active in this session: <model>`; вторая часть — только при открытой сессии с опцией `model`;
3. строка «Key storage» (D3);
4. «Configured providers» — Expander на провайдера:
   - заголовок `<id>`, тег «Default», если `agent.default_model` указывает на него;
   - подпись `<id> · <kind label> · [<base_url> ·] Key: … · <n> model(s)[ · defined in <file>]`;
   - тег результата последней проверки: `ok, <n> models`, `not checked`, `unauthorized`, `unreachable`, `timeout`, `not found`, `TLS error`, `bad response`, `Key: missing`;
   - в свёрнутом виде — кнопки «Check», «Edit», «Remove»;
   - в раскрытом — таблица «Key / Last check / Source» и те же кнопки;
5. подвал `Config file: <path>` и строка про «Remove».

Действия:
- **Check** — адаптер `lib/app/` читает ключ (`ClientSecretAccess.read` или переменную `api_key_env` окружения агента) и сразу передаёт его в `ProviderCheck`. В состоянии остаётся `ProviderCheckView` (`ok(n, durationMs, at)` или вид отказа). Результат — UI-состояние страницы, в файл не пишется. Номер проверки на строку: повторный Check и закрытие страницы отменяют прежний; отмена передаётся в `ProviderCheck.listModels(…, cancel:)`, и мост закрывает соединение запроса, а не только перестаёт ждать.
- **Edit** — мастер с `editing` (§12.4.5, шаг 4).
- **Неподдерживаемый вид провайдера** (`gemini` и неизвестные) — «Check» неактивна с подсказкой `Check is not available for <kind> providers yet.`; признак и адрес по умолчанию даёт мост (D8) (решение оркестратора, ревью итерации 2).
- **`http://` к нелокальному хосту** — предупреждение `The key is sent unencrypted to <host>.` рядом с «Check», без диалога (D8, трактовка SETUP-10) (решение пользователя 2026-11-06).
- **Подпись строки** показывает `base_url` через `displayBaseUrl` моста — без userinfo, query и fragment, как origin в CLI (D25) (решение оркестратора, ревью итерации 2).
- **Недоверенный проект.** Слой 3 недоверенного проекта не попадает ни в запасное слияние листьев, ни в источник листа: строка не показывает провайдера и источника из файла, который агент не читает (решение оркестратора, ревью итерации 2).
- **Временное состояние итерации 2** (решение оркестратора, итерация 2): мастера ещё нет (итерация 3), поэтому «Add provider» и «Edit» видны по разметке и с ключами артборда, но неактивны с подсказкой `Use codelab provider add in a terminal; the wizard comes in a later version.` Итерация 3 включает их, не меняя разметку.
- **Литеральный ключ** (согласовано пользователем 2026-11-06; `providers.<id>.api_key` в файле, статус `KeyLiteralInConfig`, подпись `Key: in config file (plain text)`) — «Check» неактивна с подсказкой `The key is written in config.yaml. Move it to the secret store: codelab secret migrate.` (решение оркестратора, итерация 2). App не читает литеральное значение из конфига (SETUP-1), а Check без ключа дал бы ложный `unauthorized`. Текста именно для этого случая в существующих сообщениях нет; формулировка совпадает по команде с причиной `fileOnly` реестра (`a secret is never written by clients; run: codelab secret migrate`) и по смыслу — с баннером переноса секретов app (`Secrets are stored in the agent config file.`, change `add-config-literal-secrets-and-migrate`, D8).
- **Remove** — подтверждение `Remove provider <id>?` (`CodeLabDialogTitle`):
  - флажок «Also delete the stored key»;
  - выбор «New default model», если удаляется провайдер модели по умолчанию;
  - последнего провайдера удалить нельзя: подсказка §12.4.5, шаг 6.

  Правки — одним `apply`. Секрет удаляется только после `ConfigSaved` (SETUP-24, итерация 0).
- **Default model** — `SetValue("agent.default_model", …)` в слой, где ключ определён сейчас, если он редактируемый, иначе в `user` (§12.4.5, шаг 3).
- **Пустой конфиг** (провайдеров нет) — строка `No providers yet. The embedded agent needs one to run a turn.` и «Add provider» (в холсте пустого состояния нет, D24). В итерации 2 это та же кнопка `providers-add`, что в шапке: неактивна с той же подсказкой `Use codelab provider add in a terminal; the wizard comes in a later version.`; отдельной кнопки и другого текста у пустого состояния нет. С итерации 3 обе кнопки открывают мастер.

Ключи тестов:
- тело — `settings-providers`;
- строка — `providers-<part>-<id>`, где `<part>`: `row`, `check`, `edit`, `remove`, `status`, `key`;
- `providers-default-model`, `providers-key-storage`, `providers-add`, `providers-read-only`, `providers-unreadable`, `providers-empty`;
- подтверждение — `providers-remove-confirm`, `providers-remove-delete-key`, `providers-remove-new-default`.

Мастер — `provider-wizard` и `provider-wizard-<step>` (шаги — по `ProviderSetupState`).

### D11. Страница «MCP servers»

`McpSettingsCubit` — `McpSettingsLoading | McpSettingsReadOnly | McpSettingsReady | McpSettingsUnreadable` (§12.4.2). Разметка — артборд `Mcp`:
1. шапка и «Add server»;
2. InfoBar результата записи (ниже);
3. подпись `<n> servers · Composition from the config · agent status below`;
4. Expander на сервер:
   - заголовок `<name> <type> <source>` и цель (команда или URL без значений секретов; `env`, `headers` и `args` маскируются, как `codelab mcp list`, R0-2);
   - ToggleSwitch `enabled`;
   - в раскрытом виде — редактор `McpServerDraft`:
     - имя, тип (RadioButton `stdio`/`http`), поля типа;
     - `headers`/`env` со строками «Secret»;
     - «Save to User config» / «This project only»;
     - «Save», «Reconnect», «Remove»;
5. панель «Agent status» (D12).

Правила (§12.4.6):
- **Секретное значение** уходит в `SecretStore` под `SecretNames.forMcp(name, key)`. В конфиг пишется `${secret:<имя>}`. Порядок «секрет → конфиг → откат» — тот же, что D9.
  - При read-only бэкенде флажок «Secret» неактивен с подсказкой D3, а литеральное значение, похожее на ключ, писатель отклоняет (`ConfigInlineSecret`).
  - Существующий секрет с тем же именем не перезаписывается без выбора «Replace it» (как D7).
  - Поле значения секрета при правке показывает «stored», а не значение. Пустое поле означает «не менять» (`McpValueDraft.secret(keep)`).
- **Toggle** пишет `UpsertMcpServer({name, enabled})` в слой сервера. Для сервера слоя 3 toggle неактивен, а «Disable here» пишет `enabled: false` в `projectLocal`.
- **Remove** — `RemoveMcpServer(name)`. После `ConfigSaved` удаляются секреты с префиксом `codelab/mcp/<name>/` из `names()` (SETUP-24). Сервер слоя 3 удалить нельзя.
- **Проверка после записи** — локально, а не через `/config check` (отступление от §12.4.6, шаг 6). После `ConfigSaved` Cubit берёт свежий `snapshot`, и `FileAgentConfigStore` загружает конфиг с окружением агента из D5: процесс app для встроенного агента, процесс app плюс `env` профиля для stdio `codelab-agent`. Если в `loaded.issues` есть ошибки, показывается InfoBar `error` холста:
  - `Saved, but the agent rejected the new config`;
  - `Config: invalid`;
  - проблемы с путём ключа;
  - `The agent keeps running on the previous config until this is fixed.`;
  - кнопка `Edit <server>`.

  `ConfigSaved.warnings` показываются баннером `saved` до этого.

  Почему не `/config check`: команда агента — это ход в сессии пользователя (видна в ленте, встаёт в очередь при идущем ходе), а для встроенного агента тот же загрузчик в том же процессе даёт тот же ответ без протокола. Для stdio-агента окружение восстанавливается из профиля. Остаточное расхождение (агент запущен с другим окружением снаружи CodeLab) — риск ниже.

Ключи:
- тело — `settings-mcp`;
- строка — `mcp-<part>-<name>`, где `<part>`: `row`, `toggle`, `save`, `reconnect`, `remove`, `disable-here`;
- `mcp-add`, `mcp-rejected`, `mcp-read-only`, `mcp-status`, `mcp-status-reload-all`.

### D12. «Agent status»: живая таблица встроенного агента и `/mcp list` для остальных

**Встроенный агент** — структурный статус без ACP (SETUP-11):
- **ядро** (`[agent]`): `McpSessionTools` получает `Stream<List<McpServerSummary>> get changes`. Событие — при каждой смене состояния, числа инструментов или ошибки сервера. Поток закрывается вместе с `close()`. `AgentRuntime` даёт хосту `McpStatusPort? mcpStatus(SessionId)` — снимок `servers`, `changes` и `reconnect(name)`; без MCP — `null`. Это OQ4 `17-5-agent-setup.md` с потребителем, без отдельного `McpSupervisor` (там же, «Отступление 8.10»);
- **`codelab_embedded`** (`[agent]`): `EmbeddedAgent.mcpStatus(String sessionId)` поверх порта рантайма. Реэкспорт `McpServerSummary`, `McpServerState` в основном бареле — без `dart:io`;
- **app** (`[desktop]`): `McpSettingsCubit` подписывается на `changes` активной сессии. Подписка одна; её владелец — Cubit (AGENTS.md §9). Смена активной сессии, переподключение и `close()` отменяют подписку. Таблица — `SERVER · STATE · TOOLS · LAST ERROR · Actions` холста, «Reconnect» строки вызывает `reconnect(name)`. Подпись — `Live from the embedded agent · <hh:mm>`.

Как app узнаёт `EmbeddedAgent` текущего подключения: `EmbeddedTransportResolver` (`lib/app/`) уже держит текущего агента. Он получает метод `currentAgent`, а Cubit — узкий порт `EmbeddedMcpStatusSource` из composition root. Виджеты агента не видят.

**Агент вне процесса** (stdio, WebSocket) — решение пользователя 2026-11-05, Q2 (а):
- по явной кнопке «Refresh» (или «Reconnect» / «Reload all») страница отправляет `/mcp list` (`/mcp reload <name>`, `/mcp reload`) обычным `SessionHandle.send` активной сессии (SETUP-14);
- текст ответа этого хода показывается в моноширинном блоке как есть, без разбора (SETUP-11);
- кнопки неактивны, пока у активной сессии идёт ход или соединение не `Connected`; иначе промпт встал бы в очередь, а ответ пришёл бы позже;
- автоматических запросов нет: каждое обращение — действие пользователя и видно в ленте.

Ответ, пришедший после смены сессии или закрытия страницы, отбрасывается по номеру запроса. Без открытой сессии или если агент не объявил `/mcp` — `Open a session to see live status`.

### D13. Токен профиля в хранилище секретов: kit

- **Форма ссылки.** `ProfileTokenRef.parse`:
  - `env:<NAME>` → `EnvTokenRef` (как в A);
  - `secret:<имя>`, где имя проходит правило `SecretNames` (`^[a-z0-9][a-z0-9._/-]{0,127}$`, без `..`) → `SecretTokenRef(name)`;
  - иначе → `UnsupportedTokenRef` с маскированным `toString()`.

  Явный префикс `secret:`, а не голое имя: голое значение в `tokenRef` по-прежнему считается возможным вписанным токеном и не выводится (D13 A). Старая сборка (A) видит `secret:…` как неподдерживаемую ссылку и подключается без токена, файл не портит.
- **Порт `ProfileSecrets`** (kit, чистый Dart):

  ```dart
  abstract interface class ProfileSecrets {
    ProfileSecretBackend get backend;                 // id, writable, unavailableReason
    Future<List<String>> names();                     // для «Use stored secret»
    Future<bool> isSet(String name);
    Future<ProfileSecretWrite> store(String name, SecretText value);   // Stored | Exists | ReadOnly | Failed
    Future<ProfileSecretDelete> delete(String name);
    Future<String?> read(String name);                // только для SecretSource транспорта
  }
  ```

  Реализация — в composition root app (`lib/app/`) и в `run.dart` CLI поверх `ClientSecretAccess` (D4). Kit не знает `codelab_setup`.
- **`SecretText`** (kit) — обёртка значения нового токена в черновике: `toString()` и JSON — `***`, `reveal()` только для `ProfileSecrets.store` и проверки. Отдельный от `SecretValue` моста тип нужен потому, что kit не зависит от стороны агента. Дублирование — десять строк, и это цена границы §4.1.
- **`ProfileSecretSource(environment, {ProfileSecrets? stored})`** — `secret:` читает `stored.read(name)`; без `stored`, при пустом или отсутствующем значении — `null`, подключение без токена.
- **Предупреждение о незаданном секрете** выдаёт хост — app и CLI — перед подключением профиля с `secret:`, если `ProfileSecretSource.isSecretMissing(profile)` истинно. Это метод источника (не расширение): он проверяет `ProfileSecrets.isSet(name)` порта и значение не читает; для `env:`, профиля без токена, неподдерживаемой ссылки и не-WebSocket — `false`, ошибка порта считается «не задан». Текст — функция kit `secretMissingWarning(profileId)`: диагностика `Profile <id> has no stored secret value; connecting without a token.` и событие с единственным полем `profile_id` (имя секрета — не секрет, но диагностика держится правила A) (решение оркестратора, ревью итерации 1). Kit-источник сам ничего не пишет: у него нет логгера и `profile_id`. Формулировка без «token <слово>» намеренно: `SecretRedactor` диагностики (`\bToken\s+…`) затёр бы слово как значение токена (решение оркестратора, ревью итерации 1).
- **`ProfileCommitter`** (kit; тест `profile_commit_test.dart`, названный в §12.4.13):
  1. перечитать id (как «Save anyway» в A);
  2. если выбран «Store a new token»: `store('codelab/profiles/<id>/token', value)`; `Exists` (в том числе `SecretUpdated` из гонки, D4) → проблема черновика `tokenSecretExists` без записи профиля и без отката;
  3. ещё раз проверить id — уже после записи секрета: `codelab profiles add` в другом процессе мог занять его за время шага 2. Занятый id → проблема `idTaken` и откат секрета, созданного на шаге 2 (решение оркестратора, ревью итерации 1);
  4. `ProfileStore.save(profile с tokenRef: secret:codelab/profiles/<id>/token)`;
  5. если шаг 4 не удался, а секрет создан на шаге 2, — `delete`. Ошибка отката — событие `connection_profile.token_rollback_failed` и текст `The profile was not saved; the token stays in <backend> as <name>. Remove it with codelab secret delete <name>.`.

  Результаты `ProfileSaveFailed` и `RemoveFailed` несут `errorType` — имя типа исключения для события журнала, без `toString()` (решение оркестратора, ревью итерации 1).

  Имя всегда `codelab/profiles/<id>/token`, где id нового профиля по правилу A (`^[a-z0-9][a-z0-9._-]{0,63}$`) — оно проходит `SecretNames`.
- **Проверка нового токена.** `ProfileProbe.probe(profile, token: SecretText?)` (профиль из `ProfileDraft.toProfile`; токен подставляется через `SecretRebindableResolver.withSecrets`, резолвер без этой возможности даёт `Unsupported`, а не проверку без токена; пустой `NewSecretToken` — явный отказ проверки без открытия транспорта, а не проверка без токена (решение оркестратора, ревью итерации 1)) передаёт транспорту значение из памяти через одноразовый `SecretSource`, до записи в хранилище (§12.4.9, шаг 5). Для «Use stored secret» проверка читает секрет тем же `ProfileSecretSource`, что подключение.
- **Удаление.** `ProfileCommitter.remove(id, {deleteOwnSecret})`:
  1. `ProfileStore.remove`;
  2. после успеха — `ProfileSecrets.delete` собственного `codelab/profiles/<id>/token`, если флажок выбран. Секрет удаляется, только если профиль ссылается именно на него и ни один другой профиль файла на него не ссылается. Чужие секреты («Use stored secret») не удаляются никогда. Ошибка удаления секрета профиль не возвращает: событие `connection_profile.token_delete_failed` и подсказка `codelab secret delete <name>`.

### D14. Токен профиля: UI app

«Add connection profile», поле «Token» WebSocket — четыре варианта в порядке:
1. «No token»;
2. «Use stored secret» — ComboBox имён `ProfileSecrets.names()`, отфильтрованных функцией kit `selectableProfileTokenSecrets(names)`: только `codelab/profiles/*`, которые принимает `ProfileTokenRef` (`secret:<имя>` разбирается в `SecretTokenRef`). Ключи провайдеров (`codelab/<id>`) и секреты MCP (`codelab/mcp/…`) в список не попадают: ключ LLM не должен уйти агенту заголовком Bearer (решение пользователя 2026-11-05, ревью итерации 1). Ручная ссылка `secret:<любое допустимое имя>` в `profiles.json` по-прежнему работает: фильтр ограничивает только выбор в UI. Пустой отфильтрованный список или бэкенд с ошибкой — вариант неактивен с подсказкой `No stored secrets in <backend>.`;
3. «Store a new token» — `PasswordBox` и подпись холста `Saved as codelab/profiles/<id>/token in <backend>. The value is never shown again or written to profiles.json.`. При read-only бэкенде вариант неактивен с подсказкой D3;
4. «From environment variable» — как в A (D13 A).

Четвёртый вариант — отступление от холста (D24). В 1.0 бэкенд по умолчанию `env`, и без этого варианта токен в app нельзя было бы задать совсем.

Остальные правила A действуют для любого варианта с токеном («Use stored secret», «Store a new token», «From environment variable»):
- подтверждение `ws://` к нелокальному хосту перед «Test connection» и «Save»;
- текст «Unauthorized: the agent rejected the token» — если токен действительно отправлен;
- предупреждение под URL `ws:// to another machine: the token is sent unencrypted.`;
- сброс подтверждения при правке URL или выбора токена.

Новое значение `PasswordBox` и выбор имени тоже сбрасывают подтверждение.

Строка WebSocket-профиля на «Connection» (ключ `connection-profile-token-<id>`):
- `Token secret <имя>` и тег `<backend> · set` или `<backend> · missing` (артборд `Connection`; наличие — `isSet`, значение не читается);
- `From $<NAME>` как в A;
- `No token`.

Поле имени — текст, а не редактируемый `TextBox` холста: правки профиля в 1.0 нет (D24).

«Remove» WebSocket-профиля с собственным секретом показывает флажок «Also delete the stored token codelab/profiles/<id>/token» (по умолчанию включён, §12.4.9, шаг 8; ключ `connection-remove-delete-token`).

Ключи диалога:
- `add-profile-token-stored`, `add-profile-token-stored-name`, `add-profile-token-new`, `add-profile-token-new-value`, `add-profile-token-backend`;
- прежние `add-profile-token-none`, `add-profile-token-env`, `add-profile-token-env-name` не меняются.

### D15. CLI: `codelab provider add` и клиентские флаги

- **Флаговая форма ядра** без клиентских флагов не меняется: вывод, коды и байты совпадают с `codelab-agent provider add` (spec codelab-cli «Подкоманды codelab provider и codelab mcp»).
- **Клиентские флаги** `--preset <id>`, `--skip-check`, `--yes` переводят команду в автомат `ProviderSetupFlow`. Флаги ядра (`--kind`, `--base-url`, `--model`, `--context-window`, `--api-key-secret|--api-key-env|--api-key-stdin`, `--default`) становятся событиями подряд. Проверка `/models` выполняется до записи; пропустить её можно только `--skip-check` (SETUP-4).
  - Неполный набор с `--yes` (нет модели, окно неизвестно) — код `64` с именем недостающего флага.
  - Отказ проверки без `--skip-check` — код `1` и `codelab: provider check failed: <kind> (<scheme://host:port>)`, файл не изменён.
  - Набор правок совпадает с ядром.
- **Без обязательных флагов на TTY** (stdin и stdout — терминал) — интерактивный мастер. Без TTY — прежний код `64` с прежним текстом.
- **Шаги мастера** — вопросы `LineEditor`, выбор — список со стрелками (как `CliSetup`). Ключ вводится без эха тем же скрытым вводом, что у `StdinSecretInput` (Ctrl+R показывает и прячет, Ctrl+U очищает; U-17). Ctrl+C — выход `130`, конфиг не изменён.
- **Тексты** — артборд `CliSetup` с реальным бэкендом: `Store in file as "codelab/anthropic"`. При read-only бэкенде этой строки нет, а под вопросом печатается причина D3.

### D16. CLI: мастер первого запуска (U-17)

`composition_root.dart` до запуска встроенного агента (без `--agent`, `-a embedded`, `-a default`) вызывает `checkProviderReadiness(snapshot, secrets, env)` — **только если stdin и stdout — TTY и режим не `-p`** (SETUP-7):
- `ProviderReady` → обычный старт;
- `ConfigBroken` (проблемы, кроме отсутствия провайдера с моделью) → мастер не запускается, старт идёт прежним путём: `EmbeddedAgentConfigException`, код `64`;
- `NoProviderConfigured` (нет ни одного провайдера с моделью; признак — общий `providerSetupNeeded` моста, D26) → текст `CliSetup` (`No model provider is configured for the embedded agent.` …) и мастер с `ConfigTarget.user()`, `makeDefault: true`. `Done` → старт агента (он читает уже записанный файл). `Cancelled`/Ctrl+C → `130`;
- `ProviderKeyMissing`:
  - бэкенд пишет → `Store a key for "<id>" in <backend>? [Y/n]` и шаг ключа в режиме правки;
  - «нет» → подсказка и обычный старт;
  - read-only → строка §12.4.3, шаг 4, и обычный старт: первый ход даст прежнюю ошибку ключа.

  Отступление от §12.4.3 (там выход `1`): блокировать REPL, где пользователь может выбрать модель другого провайдера, хуже, чем показать подсказку (D24).

Без TTY и в `-p` поведение прежнее (решение Q4): `codelab -p` без конфига — код `64` с подсказкой `config check`. Мастер не запускается для внешних агентов (§12.4.3, шаг 7).

### D17. CLI: `/provider` и `/settings` в REPL и TUI

Решения пользователя 2026-11-05: Q6 — «если `--ui tui`, то экран `CliSettings` в TUI; если REPL — по реестру настроек»; Q7 — мастер `/provider add` прямо в TUI.

**`/provider add|list|remove`** вызывают те же обработчики, что подкоманды. Порт `SetupCommands` собирает `run.dart`, а REPL и TUI получают его через `ReplContext`: правило «`codelab_setup/io.dart` только из `run.dart`» не меняется. Для `RemoteReadOnly`/`NotManaged` — строка §12.4.8, шаг 3. После записи — `Saved provider "<id>". Models are available in /model.` (агент сам пришлёт `config_option_update`).

**Мастер в REPL** — построчный, как у `codelab provider add` (D15).

**Мастер в `--ui tui`** — модальный экран TUI. Он ведёт тот же автомат `ProviderSetupFlow`, что подкоманда и REPL; шаги, вопросы и тексты — по артборду `CliSetup`:
- `? API type` — список со стрелками;
- `? Base URL ›` — поле ввода;
- `? API key source` — список;
- `? API key ›` — поле со скрытым вводом: на экране `*` по числу рун, Ctrl+R показывает и снова прячет, Ctrl+U очищает поле (U-17);
- строка проверки `Checking <scheme://host:port>/… … ok, <n> models` / вид отказа;
- `? Model (type to filter) ›` — фильтр по подстроке и пункт `Enter model id manually`;
- сводка и `? Save? [Y/n]`.

Модель экрана — чистое ядро `lib/src/tui/core/` (TUI-5):
- `TuiModel.overlay` из `PickerSpec?` становится закрытой иерархией `TuiOverlay`: `PickerOverlay`, `ProviderWizardOverlay(ProviderSetupState, поле ввода)`, `SettingsOverlay` (ниже);
- адаптер `lib/src/tui/` пересылает события автомату и `states` обратно сообщениями `TuiMsg`. Значение ключа живёт только в `SecretValue` черновика автомата и в буфере поля ввода оверлея. В строки кадра попадает только маска. Буфер очищается при переходе в `Checking`, при `Cancel` и при закрытии оверлея.

Фокус и одобрения:
- пока открыт оверлей мастера или настроек, клавиши получает только он: Enter не отправляет промпт, Esc закрывает оверлей (`Cancel` автомата), а не отменяет ход;
- клавиши зоны одобрения при открытом оверлее не обрабатываются. Новый запрос разрешения показывается в строке статуса (`approval pending · esc to answer`) и отвечается только после закрытия оверлея, в зоне одобрения с контекстом вызова (как D2 change A для app);
- `Saving` блокирует Esc, как в app (D21).

Первый запуск (D16) в `--ui tui` остаётся построчным, до старта экрана TUI: агент ещё не запущен, а артборд `CliSetup` — построчный вывод терминала.

**`/settings` в REPL** — список и пикер по `SettingsRegistry` (`scope: shared`):
- `/settings` — `PickerSpec` со строками `key value source` по секциям реестра;
- `/settings <key>` — пикер значений `enumeration`/`bool` или подсказка формата;
- `/settings <key> <value>` — запись в `user`, с `--local` — в `projectLocal(cwd)`;
- `/settings <key> --reset` — `UnsetValue`;
- разбор — `SettingsRegistry.parseCliValue`;
- `secret`/`secretName` не редактируются (`Use codelab secret set <name>`);
- `restartRequired` — пометка `(applies after restart)`.

**`/settings` в `--ui tui`** — полноэкранный оверлей `SettingsOverlay` по артборду `CliSettings`:
- шапка `Settings · /settings · user <path> · project <path>`;
- слева столбец `sections` с текущим разделом `›`, справа таблица `key · value · source`, внизу строка-подсказка о слое и полоса клавиш;
- клавиши `↑↓ move · enter edit · ←→ choose · tab section · r reset · esc close`; Enter на `enumeration`/`bool` открывает выбор ←→, на числе и строке — поле ввода с проверкой `parseCliValue`;
- данные — те же `SettingFieldView`, что в REPL, и та же запись через `AgentConfigStore`.

Разбор артборда `CliSettings` против реестра. Ключи артборда — это ключи клиентского файла CLI `~/.codelab/cli.yaml` (`12-2-cli-display-and-input.md`, таблица настроек CLI). Этого файла в коде нет: «файла `cli.yaml` до конца MVP нет» (`cli_args.dart`), а по §12.2 CLI его только читает. Ключей агента в артборде немного, и они названы иначе, чем в схеме:

| Строка артборда | Чей ключ | Поведение за ним сегодня | В TUI-экране B |
|---|---|---|---|
| `display.language` | `cli.yaml` | слоя локализации нет (строки только английские) | нет |
| `display.theme` | `cli.yaml`, U-18 | `/theme` не реализован | нет |
| `display.view` | — (нет ни в реестре, ни в таблице §12.2) | нет | нет |
| `display.thoughts` | `cli.yaml` | есть: `/thoughts dim\|collapsed\|hidden` и флаг; без сохранения, только на сеанс | нет (Q8 (i)) |
| `display.mouse` | `cli.yaml` `tui.mouse`, U-22 | нет | нет |
| `display.hyperlinks` | — | нет (OSC 8 не используется) | нет |
| `input.enter_while_running` | `cli.yaml` | только `queue` (steer — C-03 после MVP) | нет |
| `input.history_size`, `input.secret_warning` | — | история есть, размер фиксирован; предупреждения нет | нет |
| `agent.profile` | — | профиль выбирает `--agent`, без него — встроенный агент (D21 change A) | нет |
| `agent.mode` | реестр: `permissions.mode` | есть | да, под именем реестра |
| `agent.max_steps` | реестр: `budget.max_steps` | есть | да, под именем реестра |
| `power` | `cli.yaml` `power.mode`, U-25 | нет | нет |
| `update.channel`, `update.check` | `cli.yaml`, U-20 | нет | нет |

Решение B — вариант (i) (решение пользователя 2026-11-05, Q8):
- TUI-экран рисуется по разметке и клавишам артборда, но строки берутся только из реестра (`scope: shared`): разделы — секции реестра (Models, Agent, Providers, Permissions, Budget, MCP …);
- в разделах Providers и MCP — те ключи реестра, у которых есть редактор (`providers.*` — по одному блоку на провайдера; `mcp.servers` — `mapList`, строка-ссылка «edit with codelab mcp add»);
- разделов Display, Input и Updates нет, строк `power` и `agent.profile` тоже — отступление D24.

Вариант (ii) — добавить эти ключи вместе с поведением:
- нужно ввести файл `cli.yaml`: чтение, валидацию профиля YAML и запись (сейчас §12.2 говорит «только читает»);
- поведение каждого ключа — это отдельные цели после MVP: локализация D-19/§12.2, `/theme` U-18, мышь U-22, steer C-03, запрет сна U-25, обновления U-20;
- затронутые спеки: `codelab-cli` (новое требование файла настроек CLI и требования этих целей), `codelab-tui`, `cli-headless` (если ключи влияют на `-p`);
- это объём нескольких changes, а не итерации B.

Минимальный вариант (ii′) — `cli.yaml` только с `display.thoughts` и `ui.mode`, у которых поведение уже есть. Он вводит новый формат пользовательских данных и запись в него. Пользователь выбрал (i) (Q8, 2026-11-05); (ii′) и (ii) — будущие changes целей §12.2.

Запись TUI-экрана:
- клавиша **`ctrl+u`** сохраняет значение в `user` вместо слоя по умолчанию;
- **слой по умолчанию** — тот, где ключ сейчас определён, если он редактируемый, иначе `user`;
- **ключ из проектного слоя.** Артборд пишет «set by the project file; your choice is saved there». Запись в проектный `<cwd>/.codelab/config.yaml` (слой 3) запрещена SETUP-3, поэтому для такого ключа экран пишет в `.codelab/config.local.yaml` (`projectLocal`), а подсказка говорит `<key> is set by the project file; your choice is saved to .codelab/config.local.yaml. ctrl+u saves to user instead.` (D24);
- **`r reset`** — `UnsetValue` в слое, где ключ определён, если он редактируемый.

Для `RemoteReadOnly`/`NotManaged` экран открывается только для чтения: строка §12.4.8, шаг 3, вместо полосы клавиш записи.

### D18. Наблюдаемость

Логгеры:
- app — `codelab_desktop.settings`, компонент `settings` (как D17 A);
- мост — `Logger` ядра, который передаёт хост;
- CLI — логгер CLI.

| Событие | Уровень | Поля |
|---|---|---|
| `provider_settings.loaded` | debug | `providers`, `access: editable \| remote \| not_managed` |
| `provider_settings.unreadable` | warning | `error_type` |
| `provider_settings.check_started` / `check_finished` / `check_discarded` | info / info / debug | `operation_id`, `provider_id`, `outcome`, `duration_ms` |
| `provider_settings.default_model_changed` | info | `provider_id` (часть до `/`) |
| `provider_settings.removed` | info | `provider_id`, `key_deleted` |
| `provider_wizard.started` | info | `mode: add \| edit`, `entry: app \| banner \| cli \| first_run \| flags` (`banner` — «Add provider» баннера соединения, D26). `entry` — перечисление моста, параметр автомата обязательный: точка входа не угадывается по умолчанию |
| `provider_wizard.address_rejected` | info | `reason: invalid \| userinfo` — адрес шага отклонён; сам адрес не пишется |
| `provider_wizard.insecure_address` | info | `origin` (`scheme://host:port`) — запрошено подтверждение `http://` |
| `provider_wizard.keys_unavailable` | warning | `error_type` — порт `ProviderKeys.stored` бросил; шаг ключа считает, что секрета нет |
| `provider_wizard.reload_failed` | warning | `error_type` — перечитывание снимка после `ConfigConflict` не удалось (D9) |
| `provider_wizard.check_finished` / `check_discarded` | info / debug | `operation_id`, `preset`, `endpoint` (`scheme://host:port`), `outcome`, `status?`. `check_discarded` пишет только мост (автомат и `HttpProviderCheck`), один раз на попытку: app и CLI его не дублируют |
| `provider_wizard.saved` | info | `provider_id`, `key: none \| env \| secret`, `target: user \| local`, `make_default`, `skipped_check` |
| `provider_wizard.save_failed` | warning | `provider_id`, `outcome: conflict \| rejected \| inline_secret \| secret_failed \| secret_appeared \| error`, `rollback: none \| deleted \| failed` (`KeyRollback`, D9; вместо булева `secret_rolled_back`, который не отличал «нечего откатывать» от «откат не удался»), `error_type?` (только при `error`, имя типа; D9) |
| `provider_wizard.reconnect` / `reconnect_skipped` | info / debug | — (переподключение встроенного агента после записи из баннера и его пропуск из-за новой попытки подключения, D26) |
| `provider_wizard.cancelled` / `event_ignored` | debug | `state` |
| `mcp_settings.saved` / `removed` / `toggled` | info | `server`, `type`, `target`, `secret_refs` (число) |
| `mcp_settings.save_failed` | warning | `server`, `outcome` |
| `mcp_settings.rejected_after_save` | warning | `server`, `issues` (число) |
| `mcp_settings.status_subscribed` / `status_unsubscribed` | debug | — |
| `mcp_settings.command_sent` | info | `command: list \| reload`, `server?` |
| `connection_profile.token_stored` | info | `profile_id`, `backend` |
| `connection_profile.token_rollback` / `token_rollback_failed` | warning | `profile_id`, `backend`, `error_type?` |
| `connection_profile.token_deleted` / `token_delete_failed` | info / warning | `profile_id`, `backend`, `error_type?` |
| `connection_profile.token_secret_missing` | warning | `profile_id` — секрет `secret:` не задан перед подключением (D13) |
| `secrets.client.backend` | info | `backend`, `writable`, `reason?` — `unavailableReason` бэкенда, текст без значений (D3) |

`connection_profile.saved` получает `token: none | env | secret` (было `none | env`). Все пять событий `connection_profile.token_*` несут `profile_id` и `backend`, как требует spec app-settings «События журнала настроек без секретов» (решение оркестратора, ревью итерации 1).

В события не попадают (§43–§46):
- значения ключей и токенов;
- имена переменных `api_key_env` и токена профиля — как в A;
- имена секретов провайдеров (`codelab/<id>`) — выводятся из `provider_id`;
- путь и query `base_url` и URL MCP;
- значения `headers` и `env`;
- тексты ответов `/models` и `/mcp list`;
- тексты исключений — только имя типа.

Уровень `error` не используется: всё это ожидаемые ситуации, которые пользователь видит и исправляет сам.

### D19. Виджеты `codelab_ui`

Переиспользуются виджеты A: `CodeLabSettingsRow`, `CodeLabSettingsSection`, `CodeLabExpanderCard`, `CodeLabBadge`, `CodeLabStatusIndicator`, `CodeLabForm*`, `CodeLabSegmentedControl`, `CodeLabDialogTitle`. Новые — только те, которых нет и которые встречаются больше одного раза:
- **`CodeLabButtonEmphasis.subtle` и `.danger`** у существующего `CodeLabButton` (итерация 2) — кнопки строк провайдера `f-btn subtle` и `f-btn subtle danger` артборда `Providers` («Check», «Edit», «Remove»); новый виджет не нужен;
- **`CodeLabKeyValueList`** (molecule) — таблица «подпись — значение» раскрытого Expander (`.kv` артбордов `Providers`, `Connection`);
- **`CodeLabStepBreadcrumb`** (molecule) — строка шагов мастера `API type › Base URL › Key › Check › Model › Review` с текущим шагом. Вход — список подписей и индекс текущего шага (`steps: List<String>`, `current: int`); шаги левее — пройденные, текущий — `.st.cur` артборда (полужирный, основной цвет), остальные — `text2`; разделитель `›`. Знания `ProviderSetupState` у виджета нет: отображение состояний на шаги — в presentation app (D7, таблица шагов);
- **`CodeLabStatusTable`** (organism) — таблица «Agent status» (`ListView (table)` артборда `Mcp`) с колонками и действием строки;
- **`CodeLabMonospaceBlock`** (atom) — моноширинный блок ответа `/mcp list` (без разбора, с переносом и выделением).

Превью обязательны для каждой новой молекулы и организма (D16 A). Бизнес-логики и знания `ProviderEntryView` у виджетов нет: модели — простые значения и колбэки.

### D20. Пакеты, зависимости, сторож и граф

| Пакет | Что меняется | Слой |
|---|---|---|
| `codelab_agent_core` | `McpSessionTools.changes`, `AgentRuntime.mcpStatus` (D12); публичные `builtinModelInfo` и `safeDefaultContextWindow` для подсказки окна мастера (D7, итерация 3) | core |
| `codelab_agent_io` | `ClientSecretAccess` (D4) | io |
| `codelab_embedded` | `EmbeddedAgent.mcpStatus`, реэкспорт `McpServerSummary`, `McpServerState` | мост |
| `codelab_setup` | основной барель §12.4.2 (D2, D5–D9), `io.dart`: `FileAgentConfigStore`, `ClientSecretAccess`, `ioProviderCheck`; `http` | мост |
| `codelab_client_core` | `SecretTokenRef`, `ProfileSecrets`, `SecretText`, `ProfileCommitter`, `ProfileProbe(token:)`, `ProfileSecretSource(stored:)` (D13) | core, web-безопасно |
| `codelab_ui` | виджеты D19 | ui |
| `apps/codelab_desktop` | `codelab_setup`; страницы, Cubit-ы, мастер, правки «Connection» и «Add profile»; сборка `lib/app/` | app |
| `apps/codelab_cli` | мастер, первый запуск, `/provider`, `/settings`, `ProfileSecrets` | app |

Направление зависимостей:

```text
codelab_desktop ──► codelab_setup ──► codelab_agent_core, http, meta
      │                  └─(io.dart)─► codelab_agent_io
      ├──► codelab_embedded ──► codelab_agent_*
      └──► codelab_client_core (ProfileSecrets — порт, без зависимости от setup)
codelab_cli ──► codelab_setup (уже есть), codelab_embedded, codelab_client_core
```

Новое ребро — только `codelab_desktop → codelab_setup`. Цикла нет: мост не зависит от клиентских пакетов (правило сторожа). Граф в `README.md` получает строку `desktop --> setup` и пояснение.

Правила сторожа (`codelab_architecture_tests/test/support/rules.dart` и `pubspec_allowlist_test.dart`):
1. `setupAllowlist` += `http`. Негативный тест «reports http in the dependencies of the setup bridge» меняется на «reports `dio`»: http теперь разрешён.
2. `desktopAllowlist` += `codelab_setup`.
3. `PackageRule('apps/codelab_desktop/lib', forbidden: ['package:codelab_setup/io.dart'], exclude: ['app/'])` — IO-барель моста только в composition root, как `codelab_embedded/io.dart`.
4. `PackageRule('apps/codelab_desktop/lib/features/settings/presentation', forbidden: ['dart:io', 'package:codelab_setup/io.dart'])` — SETUP-9; комментарий «stage 7» в `rules.dart` заменяется правилом.

Allowlist ядра (PKG-2) не меняется: поток состояний MCP — `dart:async` без новых пакетов. Основной барель `codelab_setup` остаётся web-безопасным (`package:http/http.dart` без `io_client`); `melos run web-compile` проверяет его вместе с kit.

### D21. Конкурентность и поздние результаты

| Операция | Владелец | Защита |
|---|---|---|
| снимок конфига страницы | `ProviderSettingsCubit`, `McpSettingsCubit` | номер загрузки: поздний снимок после новой загрузки или `close()` отбрасывается |
| Check строки | `ProviderSettingsCubit` | номер на строку, отмена при повторе, `close()` и смене подключения окна (новый `SettingsAccess`), `check_discarded` |
| проверка мастера | `ProviderSetupFlow` | номер попытки и `CancelTokenSource` попытки: «Retry», «Back», «Cancel», `dispose()` и закрытие диалога отменяют запрос, мост закрывает соединение (D7, D8) |
| существующий секрет мастера | `ProviderSetupCommitter` | перепроверка `keys.stored` перед записью при `replaceSecret: false` → `ProviderKeyAppeared` без записи (D9) |
| переподключение после мастера из баннера | `ConnectionCubit` | метка сбоя `ProviderSetupNotice` попытки; любая новая попытка её сбрасывает, переподключение — только при той же метке (D26) |
| запись провайдера и MCP | Cubit мастера и страницы | состояние `Saving` до чтения базы; повторное «Save» игнорируется; Cancel и Esc заблокированы в `Saving` (как D14 A); конфликт — `ConfigConflict`, без автоповтора (SETUP-6) |
| запись профиля с токеном | `AddProfileCubit` + `ProfileCommitter` | перечитывание id до записи секрета; откат секрета при отказе профиля |
| подписка на `changes` MCP | `McpSettingsCubit` | одна подписка; отмена при смене сессии, переподключении, `close()` |
| `/mcp list` вне процесса | `McpSettingsCubit` | номер запроса; ответ после смены сессии отбрасывается; кнопки неактивны во время хода |
| одновременная запись app и CLI | `ConfigWriter` | блокировка записи и fingerprint базы (§17.5.2); проигравший получает `ConfigConflict` |

Ошибки fire-and-forget (Check, подписка) не теряются: они переводятся в состояние строки и событие журнала (AGENTS.md §12).

### D22. Тесты по веткам

В `feature/*`:
- `fvm dart test` — `codelab_setup` (с `MockClient` и `HttpServer` loopback для `/models`), `codelab_agent_io` (`ClientSecretAccess` во временном `CODELAB_HOME`), `codelab_agent_core`, `codelab_embedded`, kit, `codelab_cli` (в том числе PTY-e2e мастера, первого запуска и оверлеев `--ui tui` на тестовом хранилище `CODELAB_TEST_SECRET_STORE`, §12.4.13);
- `fvm flutter test` — `codelab_ui`, `codelab_desktop`;
- `melos run guard`, `melos run web-compile` (kit и основной барель `codelab_setup`).

Интеграционные тесты app (`embedded_provider_settings_flow_test.dart`, `mcp_settings_flow_test.dart`, дополнение `connection_profiles_flow_test.dart`) в `feature/*` только компилируются (`fvm flutter analyze`). На устройстве их запускает `release/<version>` (AGENTS.md §21).

Маркер утечки `sk-test-leak-…` подставляется в ключ мастера, токен профиля, значение заголовка MCP, `base_url` (query) и текст исключения. Тесты проверяют журнал, состояние Cubit-ов, вывод CLI и файлы `config.yaml`/`profiles.json`.

### D23. Итерации

Каждая итерация — отдельный PR в `develop`:
- **0 — документы.** §12.4.2–§12.4.6, §12.4.9, §12.4.11 (SETUP-23, SETUP-24; уточнения SETUP-7, SETUP-11), §12.4.13; `17-5` OQ4; roadmap §10; `agent-parity-goals.md`; вложенные `AGENTS.md`.
- **1 — токены профилей в хранилище секретов.** `ClientSecretAccess` `[agent]`; `secret:`, `ProfileSecrets`, `ProfileCommitter`, проверка из памяти `[client]`; зависимость app от `codelab_setup`, правила сторожа, «Use stored secret», «Store a new token», «Remove» с секретом `[desktop]`; CLI читает `secret:` `[client]`. Самый короткий сквозной срез, который вводит ребро и правила сторожа.
- **2 — Providers: просмотр и простые правки.** `SettingsAccess`, `AgentConfigStore`, `FileAgentConfigStore`, модели представления, `HttpProviderCheck` и `http` `[agent]`; страница, «Default model», Check, Remove, состояния только для чтения `[desktop]`.
- **3 — мастер провайдера в app.** `ProviderSetupFlow`, пресеты, `ProviderSetupCommitter`, `ProviderReadiness` `[agent]`; `ProviderWizardDialog`, «Add provider», «Edit» `[desktop]`.
- **4 — CLI** `[client]`: `provider add` с мастером и клиентскими флагами, первый запуск, `/provider` и `/settings` в REPL; оверлеи TUI — мастер `/provider add` и экран `CliSettings` (D17); PTY-e2e для REPL и `--ui tui`. Самая крупная итерация клиента; оверлеи TUI МОГУТ идти вторым PR внутри итерации (4a — REPL и подкоманды, 4b — TUI).
- **5 — MCP servers.** `McpServerDraft` `[agent]`; поток состояний и `EmbeddedAgent.mcpStatus` `[agent]`; страница, редактор, «Agent status» `[desktop]`.
- **6 — правки UX после ручного прогона, документы и DoD** (как итерация 4 A).

Зависимости:
- 2 ← 1 (ребро и сторож);
- 3 ← 2;
- 4 ← 3 (автомат);
- 5 ← 2;
- 6 ← все.

4 и 5 независимы и могут идти параллельно.

### D24. Расхождения холста и решения

| Где | Холст | Решение | Почему |
|---|---|---|---|
| Навигация (`Providers`, `Mcp`) | все 11 пунктов | видимы Connection, Providers, MCP servers | SETUP-17 |
| «Key storage» (`Providers`) | `keychain-macos`, тег `writable` | настоящий бэкенд (`env`/`file`), тег `writable`/`read-only`, причина при `unavailableReason`; для `file` — строка об открытом файле | хранилища ОС — после 1.0 (D1, D3) |
| Статус ключа строки | `Key: in keychain-macos`, `Key: missing in keychain-macos` | `Key: in <backend>`, `Key: missing in <backend>`, `Key: env <VAR> (set\|not set)`, `No key` | то же |
| `http://` к нелокальному хосту на странице Providers | нет | предупреждение `The key is sent unencrypted to <host>.` рядом с Check, без диалога (D8; решение пользователя 2026-11-06) | адрес уже в конфиге |
| Неподдерживаемый вид провайдера | Check у каждой строки | Check неактивна: `Check is not available for <kind> providers yet.` (D10) | проверка есть только для `openai-compatible` и `anthropic` |
| «Add provider», «Edit» в итерации 2 | активны | видны, неактивны с подсказкой `codelab provider add` до итерации 3 (D10) | мастер — итерация 3 |
| Литеральный ключ в `config.yaml` | нет | `Key: in config file (plain text)`, Check неактивна с подсказкой `codelab secret migrate` (D10; согласовано 2026-11-06) | app не читает литерал; Check без ключа дал бы ложный `unauthorized` |
| Встроенный агент без провайдера (баннер соединения) | нет: ни `Boot`, ни `States` такого состояния не показывают; ближайшее — шаг «Choose a model» артборда `Onboarding` (вне охвата, Q3) | баннер `No model provider is configured for the embedded agent.` с «Add provider» → мастер (D26) | решение пользователя 2026-11-06 |
| Пустой список провайдеров | нет | строка `No providers yet…` и «Add provider» (D10) | состояние новой установки |
| Битый `config.yaml` | нет | InfoBar ошибки загрузчика, запись недоступна (D10, D11) | целостность данных (§2) |
| Ключ мастера (`Wizard`, `CliSetup`) | `Store in keychain-macos as codelab/<id>` | `Store in <backend> as codelab/<id>`; при read-only — варианта нет, причина D3 | D1, D3 |
| Существующий секрет | нет | «Use the stored key» / «Replace it» (D7) | SETUP-5 |
| Шаги мастера app, кроме проверки (`Wizard`) | артборд показывает только шаг «Check» с отказом `notFound` | тот же каркас для каждого шага: заголовок `Add provider` (`Edit provider <id>` при правке), строка шагов, сводка пройденных шагов, тело шага, кнопки внизу (D7, таблица шагов); тексты шагов — из `CliSetup`, заголовки отказов — по образцу артборда (D7; решение пользователя 2026-11-06, Q9 (а)) | в холсте других шагов нет |
| Кнопки карточки подключения и баннера в состоянии «нет провайдера» (D26) | нет: артборда состояния нет | одна основная (accent) кнопка — «Add provider»; «Connect» и «Reconnect» — обычные; на экране подключения «Reconnect» скрыт, повтор попытки — «Connect»; кнопки в одну строку. В `codelab_ui` — параметр `extraAction` у `CodeLabConnectionScreen` и `CodeLabConnectionBanner`: при нём «Connect»/«Reconnect» не accent (решение координатора, исправления итерации 3) | основное действие состояния — добавить провайдера; две accent-кнопки спорили бы за внимание |
| Высота диалога мастера (`Wizard`) | диалог центрирован и меняет высоту по шагу | минимальная высота содержимого 300 px (решение координатора, исправления итерации 3) | окно не прыгает между короткими шагами |
| Отступ страниц настроек сверху (`Providers`, `Connection`, `Mcp`) | содержимое прижато к верху: `padding: 28px 40px 40px`, `max-width: 1000px` | не отступление: блок содержимого, центрированный по вертикали, — дефект вёрстки, задача 3.15 | ручной прогон итерации 2 |
| Вход «Sign in» | нет в 1.0 | нет | L-17 после MVP |
| Пресеты (`CliSetup`) | 6 пресетов | те же 6 (Q5) | — |
| MCP «Secret» (`Mcp`) | `Secret — stored in keychain as …` | `Secret — stored in <backend> as …`; неактивен при read-only | D3 |
| Проверка после записи MCP | ответ `/config check` агента | локальная загрузка конфига с окружением агента, тот же InfoBar и текст (D11) | без хода в сессии пользователя |
| «Agent status» вне процесса | текст `/mcp list` | по явной кнопке, только без идущего хода (D12, Q2) | ход виден в ленте и встаёт в очередь |
| Токен (`AddProfile`) | «No token», «Use stored secret», «Store a new token» | + «From environment variable» четвёртым вариантом (D14) | в 1.0 бэкенд по умолчанию только для чтения; решение A, D13 |
| `Token secret` (`Connection`) | редактируемое поле, `keychain-macos · set` | текст имени и `<backend> · set\|missing` | правки профиля в 1.0 нет (§12.4.9, шаг 8) |
| «Remove» профиля | нет подтверждения | подтверждение с флажком «Also delete the stored token …» | §12.4.9, шаг 8 |
| Первый запуск CLI при отсутствии ключа (`CliSetup`) | — | при read-only — подсказка и обычный старт, без выхода `1` (D16) | REPL нужен для выбора другой модели |
| `/settings` в TUI (`CliSettings`) | разделы Display, Input, Agent, Providers, MCP, Updates | разметка и клавиши артборда; строки — только ключи реестра `scope: shared` по его секциям; Display, Input, Updates, `power`, `agent.profile` нет; `agent.mode` и `agent.max_steps` показаны как `permissions.mode` и `budget.max_steps` (D17) | это ключи `cli.yaml`, файла нет, поведения у большинства нет (Q6, Q8) |
| `/settings` в TUI: ключ из проектного файла | «your choice is saved there» | запись в `.codelab/config.local.yaml`, `ctrl+u` — в `user` (D17) | SETUP-3: слой 3 клиенты не пишут |
| `/settings` в REPL | — (артборда нет) | список и пикер по реестру (D17) | решение Q6 |
| Onboarding (`Onboarding`) | 4 экрана | не входит (Q3) | нужен `OnboardingDestination` |
| `CliMcp` (`/mcp disable`, `/tools`) | — | не входит | команды агента |
| Phone / Tablet | `PhoneProviders`, `PhoneSettings`, `TabletSettings` | не входит | мобильной сборки нет (§12.8) |

### D25. Отказ подключения из-за токена

Smoke CLI показал: при 401/403 рукопожатия WebSocket и CLI, и app печатали общий `Failed to connect ACP transport.`, и пользователь не понимал, что дело в токене. Решение (решение оркестратора по итогам smoke, 2026-11-06):
- **Где живёт определение.** В kit, `codelab_client_core/lib/src/connection/token_rejection.dart`, чистый Dart: `tokenRejectionStatus(error)` ищет `AcpWebSocketHandshakeRejected` с 401/403 по цепочке `cause` (`AcpClientApplicationException` → `AcpTransportException` → отказ рукопожатия), а не разбирает текст; `describeTokenRejection(error, {tokenSent})` даёт текст; `profileTokenSent(profile, SecretSource?)` говорит, был ли токен отправлен, **не читая значения**: для `ProfileSecretSource` с `secret:` — через `isSet` порта, для `env:` — по наличию непустой переменной. Хосты зовут `describeConnectFailureByToken(error, profile, SecretSource?)`: она сначала ищет статус и только при 401/403 обращается к источнику — при прочих ошибках токен вообще не трогается (решение оркестратора, ревью `feature/ws-unauthorized-message`). `classifyProbeFailure` (`codelab_client_io`) переходит на `tokenRejectionStatus`, поэтому таблица статусов одна у «Test connection» и у подключения.
- **Тексты** — те же смыслы, что исходы проверки D12 change `add-app-settings-shell` («rejected» только если токен действительно отправлен), с кодом: `the agent rejected the token (HTTP <код>)` / `the agent requires a token (HTTP <код>)`. Код статуса — не секрет и помогает различить 401 и 403.
- **Хосты:**
  - CLI — причина после прежнего префикса места: `codelab: cannot start the agent <адрес>: …` (старт REPL, `--ui tui`, `-p`), `codelab: cannot connect to <адрес>: …` (после `/profile`), `codelab: cannot reconnect: …` (`/reconnect` и переподключение); код `-p` прежний `1`;
  - app — диагностика `ConnectionCubit` и баннер сбоя подключения в main pane (spec agent-workbench-ui «Отказ подключения из-за токена в workbench»). Kit отдаёт строчный текст без точки, app делает первую букву заглавной и ставит точку (`The agent rejected the token (HTTP 401).`), как с подсказкой бэкенда в D3.
- **Адрес в выводе CLI** (решение оркестратора по MAJOR ревью, безопасность): `describeProfile` для WebSocket-профиля печатает только origin `scheme://host:port`, как `profileOrigin` у app — без пути, query, fragment и userinfo, где мог оказаться токен. Это видимое изменение вывода: путь (`/acp`) больше не печатается (spec codelab-cli «Адрес WebSocket-профиля в выводе CLI").
- **Без значений:** значение токена, ссылка и имя переменной в текст не входят (SETUP-1, D18).
- ACP не меняется: статус рукопожатия даёт транспорт (D12 change A).

*Альтернатива:* распознавать текст исключения `WebSocketException` в хостах — хрупко и дублирует таблицу статусов в трёх местах.

### D26. Встроенный агент без провайдера: баннер с «Add provider»

Решение пользователя 2026-11-06, итерация 3. На новой установке встроенный агент не открывается: `EmbeddedAgentConfigException` (`agent.default_model: required` …), и баннер соединения показывает сырой текст проблем с подсказкой `codelab config check`, без пути к настройке.

- **Признак** — чистая функция моста `providerSetupNeeded(AgentConfigSnapshot snapshot)` в основном бареле `codelab_setup`. Истинна, если у загрузки есть проблемы, все они — `ConfigIssueKind.value` ключа `agent.default_model`, и выполнено одно из двух:
  - среди проблем есть проблема с событием `config.model.none` — ни у одного провайдера нет модели: новая установка, пустой файл, провайдеры без моделей (design.md change `optional-default-model`, D4);
  - в конфиге нет ни одного листа `providers.*` (явная модель по умолчанию указывает в пустоту).

  *Уточнение change `optional-default-model` (2026-11-06).* `agent.default_model` стал необязательным: без ключа агент берёт последнюю выбранную модель или первую модель первого провайдера (D3), поэтому «провайдеры есть, ключа модели нет» — не проблема загрузки и мастера не требует. Признак опирается на событие `config.model.none` проблемы `value` ключа `agent.default_model`, а не на отсутствие листа; прежняя ветка «ключа нет ни в одном слое» удалена. `checkProviderReadiness` берёт модель так же, как ядро (`CoreConfig.defaultModel`: явный ключ или первая модель первого провайдера), а не из листа конфига.

  Любая другая проблема — `false`; в частности `agent.default_model: gw/typo` при заданном провайдере `gw` — обычная ошибка конфига.

  *Почему снимок, а не только `ConfigIssue`* (подготовка итерации 3, решение оркестратора; уточняет первоначальную формулировку «по `key` и `kind`»): валидатор ядра даёт одну и ту же проблему `value` ключа `agent.default_model` и для отсутствия моделей, и для модели вне каталога (`… is not in the model catalog`). По `key` и `kind` их не различить, а текст `message` разбирать нельзя. До change `optional-default-model` их отличало наличие ключа в слоях (`AgentConfigSnapshot.startProblems`); теперь — структурное поле `ConfigIssue.event` (`config.model.none`). Альтернатива — новый `ConfigIssueKind` или поле в `ConfigIssue` ядра — меняет публичный тип ядра и все его `switch` ради одного признака клиента; отклонена (§13).

  Эту же функцию использует `checkProviderReadiness`, чтобы отличить `NoProviderConfigured` от `ConfigBroken`, — app (этот баннер) и CLI (первый запуск, D16) не расходятся. Какие `kind` и ключи даёт валидатор, фиксирует тест моста на настоящем загрузчике (пустой `CODELAB_HOME`, провайдеры без модели, модель без провайдеров, модель вне каталога): при смене валидатора тест падает, а не признак тихо ломается.

  *Почему мост, а не kit:* `ConfigIssue` и снимок — типы схемы агента, kit о них не знает (§4.1); мост уже держит `AgentConfigSnapshot` и `ProviderReadiness`.
- **Как app узнаёт.** `EmbeddedTransportResolver` (`lib/app/`) при `EmbeddedAgentConfigException` вызывает функцию composition root `Future<bool> Function(String cwd)`: она берёт `FileAgentConfigStore.snapshot(cwd)` с тем же `CODELAB_HOME` и окружением, что у открывателя, и возвращает `providerSetupNeeded`. Результат резолвер записывает в порт `ProviderSetupOffer` (`lib/app/`, по образцу `SecretMigrationOffer`, D8 change `add-config-literal-secrets-and-migrate`) — значение `ProviderSetupNeeded(cwd)` или `null` — **до** того, как бросить `ClientWorkspaceException(message)`. Наружу уходит прежнее исключение: публичный API kit не меняется. Начало каждого открытия встроенного агента и успешное открытие сбрасывают значение в `null`. Сбой самого снимка (ошибка чтения) даёт `false`: баннер показывает прежний текст.
- **Привязка к попытке.** Резолвер видит только попытки встроенного агента, а подключение к stdio- или WebSocket-профилю идёт мимо него, поэтому номер попытки держит `ConnectionCubit` (единственный владелец `_attempt`, AGENTS.md app). При сбое попытки встроенного агента он синхронно читает `ProviderSetupOffer` и публикует в `WindowConnectionState` метку `ProviderSetupNotice` этой попытки (непрозрачный объект, номер наружу не выходит) — так же, как текст отказа по токену `_tokenRejection` (D25). Любая новая попытка (`connect`, `reconnect` любого профиля) метку сбрасывает.
- **Баннер** (spec agent-workbench-ui «Встроенный агент без провайдера»): при метке — `No model provider is configured for the embedded agent.` (тот же текст, что первая строка CLI, D16) и действие «Add provider» (`connection-banner-add-provider`). Прочие ошибки конфига показываются как сейчас.
- **Действие** открывает мастер провайдера (D7) в `ProviderWizardDialog` поверх рабочего места: `forceDefault: true`, цель по умолчанию `user`; «This project only» — по общему правилу (папка проекта сбоя, `ProviderSetupNeeded.cwd`). Сессию настроек для встроенного профиля открывает та же фабрика composition root, что у страницы Providers (`openProviderSettingsSession`). После `ConfigSaved` диалог закрывается, и workbench вызывает `ConnectionCubit.connectAfterProviderSetup(notice)`: Cubit подключает встроенный профиль, **только если** текущая метка — тот же объект (новой попытки не было); иначе — ничего, событие `provider_wizard.reconnect_skipped` (AGENTS.md §9, D21). Диалог модальный, поэтому сменить профиль через страницу «Connection», пока он открыт, нельзя; правило защищает от попыток, начатых без пользователя (Connect on start, переподключение kit), и проверяется тестом, который начинает другую попытку программно. `Cancel` мастера оставляет баннер как есть.
- Полный onboarding остаётся отдельным change (Q3).

*Альтернативы:*
- разбирать текст `message` на `agent.default_model: required` — хрупко и расходится с CLI;
- открывать страницу Providers вместо мастера — лишний шаг, а пустая страница в итерации 2 и так ведёт в мастер;
- типизированное исключение в `ClientWorkspace` — меняет публичный API kit ради одного случая встроенного агента.

## Risks / Trade-offs

- **[Секрет в журнале, состоянии или ошибке]** → значения живут только в `SecretValue`/`SecretText`, ключ для Check и токен для транспорта читаются в адаптере `lib/app/`/`run.dart` и сразу отдаются потребителю (D4); события — только id и виды (D18); тесты с маркером на всех путях (D22).
- **[Перезапись пользовательского `config.yaml`]** → только `ConfigWriter` (комментарии и порядок сохраняются, валидатор до замены, атомарная замена, блокировка); конфликт — `ConfigConflict` без автоповтора с сохранённым черновиком (SETUP-6); битый файл не пишется (D10). Остаточный риск: правка в редакторе пользователя между снимком и записью — именно её ловит fingerprint.
- **[Гонка записи секрета]** → между проверкой имени и `SecretAdmin.store` другой процесс может записать то же имя; клиент считает `SecretUpdated` равным `Exists` и не откатывает такой секрет (D4); мастер провайдера сужает окно перепроверкой имени перед записью (D9). Остаточный риск: значение, записанное другим процессом в этом окне, перезаписано значением пользователя app. Исправление — атомарный `SecretAdmin.create` (backlog `[agent]`, `delivery-roadmap.md` §10.4).
- **[Ключ LLM как Bearer]** → «Use stored secret» показывает только `codelab/profiles/*` (D14); ручная ссылка `secret:` на другой секрет в `profiles.json` остаётся на ответственности пользователя, как `env:` у A.
- **[Перезапись чужого секрета]** → существующее имя не перезаписывается без «Replace it» (D7, D11, D13); при откате удаляется только созданный этой операцией секрет (SETUP-5).
- **[Открытый файл секретов]** → `file` выбирает только пользователь правкой или `codelab config set` (D3); UI называет файл открытым. Кнопки, которая сама включает `file`, нет — решение Q1 (а).
- **[Ключ уходит на чужой хост]** → проверка только на введённый `base_url`, без редиректов (SETUP-23), `http://` к нелокальному хосту — с подтверждением (SETUP-10); ключ провайдера используется только с адресом своего провайдера.
- **[Устаревший ключ после замены]** → резолвер работающего агента кэширует значение; баннер «applies after Restart agent» (D9). Исправление кэша — не здесь: оно в ядре (`invalidate` по событию хранилища) и потребовало бы IPC для внешнего агента.
- **[Расхождение локальной проверки MCP и агента]** → для stdio-агента окружение восстанавливается из профиля; агент, запущенный снаружи CodeLab с другим окружением, может отклонить конфиг, который локально валиден. Агент при этом работает на старом конфиге и пишет `config.reload.failed` в свой журнал; строка «Agent status» покажет `failed` после «Refresh».
- **[Ключ в TUI]** Значение вводится в экран TUI, который перерисовывается диффом строк. → В модели кадра только маска; значение — в `SecretValue` автомата и в буфере поля, буфер очищается после отправки шага, при `Cancel` и закрытии (D17). Поле ключа не пишется в историю композера и `cli_history`. Вставка (bracketed paste) идёт в поле, а не в композер. Тест кадров: ни один кадр, ни снимок экрана PTY, ни лог CLI не содержат маркера; Ctrl+R показывает значение только в кадре поля и только до повторного Ctrl+R. Остаточный риск — то же, что у любого терминала: показанное по Ctrl+R значение остаётся в буфере прокрутки эмулятора, пока экран не перерисован; альтернативный экран TUI это смягчает.
- **[Клавиши мастера и одобрения]** → при открытом оверлее зона одобрения клавиш не получает, запрос виден в строке статуса (D17); Enter и Esc оверлея не отправляют промпт и не отменяют ход.
- **[Поздние результаты и гонки]** → D21. Тесты: закрытие страницы во время Check, Cancel мастера во время проверки, смена сессии при подписке на `changes`.
- **[Скрытые ходы в сессии]** → нет автоматических `/mcp`; только по кнопке, видимо в ленте (D12, Q2).
- **[Чужая переменная как Bearer]** (принятый риск A) — B не расширяет его: `secret:` указывает только на имена хранилища CodeLab, а не на произвольные переменные. Allowlist имён переменных для `env:` остаётся кандидатом, но в B не вводится: он сломал бы существующие профили CLI (D15 A).
- **[Права и Windows]** → бэкенд `file` на Windows не предлагается (`fileBackendOffered: false`), подсказки D3 это учитывают.
- **[Forward compatibility ACP]** → протокол не меняется; статус MCP вне процесса — текст обычного хода (SETUP-11, SETUP-14). Старые сборки читают `tokenRef: secret:…` как неподдерживаемую ссылку без утечки значения.
- **[Web-безопасность]** → основной барель `codelab_setup` и kit без `dart:io`; `IOClient` только в `io.dart`; `web-compile` в задачах.
- **[Allowlist ядра PKG-2]** → не меняется; `http` уже в нём, мост получает его через свой allowlist (D20).
- **[Containment и разрешения]** → B не добавляет действий агента. MCP-серверы stdio запускает агент по конфигу, как при `codelab mcp add`; одобрение вызовов инструментов не меняется (`permissions.tools`). Команда профиля stdio по-прежнему запускает произвольную команду пользователя (риск A).
- **[Объём change]** → семь итераций, каждая — отдельный PR со своим DoD; 4 и 5 параллельны (D23).

## Migration Plan

1. Итерация 0 — документы, без кода.
2. Итерации 1–5 по D23. После итерации 1 app уже зависит от `codelab_setup`, а `default_settings_pages.dart` ещё показывает только «Connection». «Providers» появляется в навигации в итерации 2, «MCP servers» — в итерации 5 (SETUP-17: пустых страниц нет).
3. Итерация 6 — ручной прогон и DoD.

Откат — revert PR итерации:
- `profiles.json` между итерациями не меняет версию; профиль с `secret:` в откаченной сборке подключается без токена (как неподдерживаемая ссылка A);
- `config.yaml` B пишет только ключами схемы ядра, их понимает любая сборка агента 8.10+;
- секреты в `secrets.yaml` остаются, их показывает `codelab secret list`.

## Open Questions

Решения пользователя 2026-11-05:
- **Q1** — (а): честный read-only с подсказкой добавить `secrets.backend: file` (D1, D3).
- **Q2** — (а): `/mcp list` и `/mcp reload` по кнопке, только когда нет хода (D12).
- **Q3** — (а): onboarding app — отдельный change.
- **Q4** — (а): без TTY и в `-p` поведение прежнее, код `64` (D16).
- **Q5** — (а): 6 пресетов холста (D2).
- **Q6** — в `--ui tui` экран `CliSettings`, в REPL — список и пикер по реестру (D17).
- **Q7** — мастер `/provider add` прямо в TUI на `ProviderSetupFlow` (D17).
- **D5** — принадлежность stdio-агента по базовому имени команды, текст `managed by <команда>`; `agentInfo` — follow-up (решение пользователя 2026-11-06).
- **Литеральный ключ и SETUP-10 на странице Providers** — D10, D8 (решения пользователя 2026-11-06).
- **Q8** — (i): экран `/settings` в TUI только с ключами реестра; Display, Input, Updates, `power`, `agent.profile` — отступление D24 (D17).
- **D24** — все отступления согласованы, в том числе строки TUI-экрана `/settings` только с ключами реестра, записи ключа проектного слоя в `config.local.yaml` и `/settings` в REPL по реестру.

Решения пользователя 2026-11-06 (подготовка итерации 3):
- **Q9** — (а): подписи шагов мастера app — из `CliSetup`, заголовки отказов — `Key rejected (<код>)`, `Server unreachable`, `Timed out after 10 s`, `TLS error`, `Unexpected response (<код>)` (D7, D24).
- **Q10** — (а): `codelab-agent provider add` при отсутствии `agent.default_model` во всех слоях ставит его сам — отдельный change `[agent]` вне этого change (MODIFIED agent-configuration), пункт backlog `delivery-roadmap.md` §10.4. В этом change флаговая форма `codelab provider add` остаётся байт в байт равной `codelab-agent` (D15).
- **Q11** — (а): userinfo в `base_url` мастера отклоняется с подсказкой, query и fragment разрешены (D7).
- **D26** — признак `providerSetupNeeded(AgentConfigSnapshot)` по снимку без изменения ядра; **D7** — неснимаемый «Make default» (`forceDefault`) в мастере из баннера и при первом запуске CLI — подтверждены.

Открытых вопросов нет.
