## Context

Куда app отправляет данные пользователя (`PRIVACY.md` §2, источник истины о передаче):

| Получатель | Кто отправляет | Что уходит | Кто знает настоящий адрес |
|---|---|---|---|
| Провайдер модели встроенного агента | ядро агента в процессе app (`codelab_embedded`), функция модели `createConfiguredStreamFunction` → `createRoutedStreamFunction` | промпт, история сессии, прочитанные файлы и вывод команд, ключ API | только ядро: провайдер выбирается по `ModelRef.provider` каждого запроса, а модель меняют опция `model`, определения агентов (субагенты), fallback, проектный конфиг доверенного проекта и переменные `CODELAB_*` |
| Внешний ACP-агент | транспорт клиента (`ConfigTransportResolver`: `StdioAcpTransport`, `WebSocketAcpTransport`) | всё, чем обмениваются по ACP: `cwd`, промпты, файлы `fs/*`, вывод `terminal/*` | app: профиль `stdio` (команда) или `webSocket` (`uri`) |
| MCP-серверы | ядро агента (`codelab_agent_mcp`) | сведения о клиенте, заголовки конфигурации, аргументы вызовов | ядро |
| Провайдер при проверке ключа | мост `codelab_setup` (`HttpProviderCheck`) | `GET /models` с ключом | мост |
| Хост изображения | app по «Show image» | `GET` без ключей | app |

Сейчас разрешения не спрашивает никто. Шаг onboarding «Privacy» раскрывает перечень (D9 change `add-app-onboarding`) и прямо запрещает записывать согласие (spec app-onboarding «Шаг «Privacy»», сценарий «Нечего принимать»). Спецификация `licensing-and-attribution` запрещает хранить «запись о согласии» вообще (§12.7.7а), хотя смысл запрета — что условия не нужно принимать.

Существующие механизмы, на которые опирается change:
- Провайдер без ключа уже даёт ошибку `auth` без HTTP-запроса (`createRoutedStreamFunction`, `unavailable`). Это образец «отказа до сети» в ядре.
- Итог хода `failed` уже проецируется в ACP как `-32603` с `data.codelab.errorClass` (§13.8). Клиент показывает ошибку хода и «Retry».
- `EmbeddedHostServices` — точка расширения моста (`codelab_embedded/AGENTS.md` §4(г)). `McpStatusPort` уже реэкспортируется основным барелем.
- Настройки окна app хранятся в `shared_preferences` за портами `lib/core/platform/` (образец — `onboarding_preferences.dart`).
- `TransportResolver` — порт `codelab_client_core`, резолверы регистрирует composition root app.
- Обрыв транспорта в `Connected` даёт `ConnectionView.lost` с баннером «Reconnect» (change `add-connection-and-error-states`, D1).

## Goals / Non-Goals

**Goals:**
- Ни один запрос модели встроенного агента не уходит удалённому провайдеру без разрешения на этого провайдера. Это касается и субагентов, и сжатия, и fallback, и смены модели.
- Ни один транспорт к внешнему агенту не открывается без разрешения на этого агента.
- Пользователь видит, кому и что уходит, и разрешает это явным действием. Он может отказать и всё равно пользоваться программой, а позже посмотреть и отозвать разрешение.
- ACP не меняется, CLI и `codelab-agent` ведут себя как раньше.

**Non-Goals:**
- Принятие условий использования и политики (они остаются справочными).
- Гейт для MCP-серверов, проверки ключа и «Show image» (D6).
- Разрешения в CLI (D7).

## Decisions

### D1. Разрешение на передачу данных — отдельное понятие, не принятие условий

Разрешение — это запись «пользователь разрешил отправлять данные получателю X». Оно не ссылается на редакцию `TERMS.md` или `PRIVACY.md` и не открывает доступ к программе: onboarding, настройки, история сессий и локальная модель работают без него. Отказ лишь не даёт отправить конкретный запрос.

Поведение описывает новая capability `app-data-sharing`. Спецификация `licensing-and-attribution` уточняет запрет: нельзя хранить запись о *принятии условий или политики*. Само требование «условия справочные» не ослабляется.

**Альтернативы.**
- *Сделать принятие условий обязательным* (чекбокс «I agree»). Пользователь уже решил оставить условия справочными. Кроме того, 5.1.2(i) требует разрешения на передачу, а не на условия.
- *Расширить существующее требование шага «Privacy», без новой capability.* Гейт живёт не в onboarding: он действует при каждом запросе и в настройках. Отдельная capability держит поведение в одном месте.

### D2. Гранулярность: разрешение на получателя

| Получатель | Идентичность | Показ |
|---|---|---|
| Провайдер модели | вид API (`ProviderApi`: `openaiChat`, `anthropicMessages`, `gemini`) + хост `baseUrl` в нижнем регистре + порт, если он явно задан и отличается от порта по умолчанию для схемы; IPv6 — в квадратных скобках | id провайдера конфига и хост: `anthropic · api.anthropic.com` |
| Внешний агент по WebSocket | хост и порт `uri` по тому же правилу; схема (`ws`/`wss`), путь, query и userinfo не входят | метка профиля и `host[:port]` |
| Внешний агент по stdio | строка `command` профиля как есть; `args` и `env` не входят | метка профиля и команда с `~` вместо домашнего каталога |

Id провайдера в идентичность не входит: если пользователь переименует `gw` в `gateway` с тем же адресом, получатель тот же. Путь `baseUrl` тоже не входит: `https://llm.internal/v1` и `https://llm.internal/openai` — один хост и один получатель. Смена хоста, порта, вида API или команды — новый получатель и новый вопрос. Нормализацию для всех путей (onboarding, гейт ядра, обёртка транспорта) делает одна чистая функция домена app `DataRecipient.provider(api, baseUrl)` / `DataRecipient.agent(profile)`.

**Альтернативы.**
- *Одно общее разрешение на всех провайдеров.* Проще, но 5.1.2(i) говорит о том, *кому* уходят данные. Если пользователь добавит второго провайдера или сменит адрес шлюза, общее «да» отправит данные получателю, о котором его не спрашивали.
- *По id провайдера.* Id — имя в конфиге, его можно оставить прежним при новом адресе. Тогда разрешение «переехало» бы к другому получателю.
- *По полному `baseUrl`.* Путь не меняет получателя, а лишние вопросы приучают нажимать «Allow» не читая.

### D3. Локальная модель не спрашивается, внешний агент — всегда

Провайдер считается локальным, если хост его `baseUrl` — `localhost`, адрес IPv4 из `127.0.0.0/8` или `::1`. Такой запрос не уходит с компьютера, поэтому гейт пропускает его без вопроса и без записи. Адреса локальной сети (`192.168.*`, `10.*`), `0.0.0.0` и имена вида `*.localhost` локальными не считаются, для них вопрос задаётся. Правило — функция `DataRecipient.isLocal`, а не решение ядра: ядро спрашивает хоста про каждый запрос (D4).

Внешний агент спрашивается всегда, даже `stdio` и `ws://127.0.0.1`. Процесс агента локальный, но куда он отправит данные дальше, CodeLab не знает (`PRIVACY.md` §2: «Внешний ACP-агент»).

**Альтернативы.**
- *Спрашивать и для loopback-провайдера.* Это честно, но бессмысленно: третьего лица нет. Вопрос о локальной модели обесценил бы остальные вопросы.
- *Не спрашивать для loopback-агента.* Агент — посредник с неизвестным получателем. Отсутствие вопроса противоречило бы 5.1.2(i).

### D4. Принуждение для встроенного агента — декоратор ядра перед каждым запросом модели

В `codelab_agent_core` появляются `ProviderEndpoint` (id провайдера, `ProviderApi`, `baseUrl`; `ProviderEndpoint.of(ProviderConfig)`), тип гейта `SharingGate = Future<bool> Function(ProviderEndpoint, Future<void> cancelled)` и декоратор `withSharingGate(inner, endpointOf:, gate:, logger:)` (`agent-core/02-llm-contract.md` §2.10.6, LLM-17). Хост, который передал гейт, получает функцию модели, где каждый запрос сначала ждёт ответа гейта:
- `true` — запрос идёт во внутреннюю функцию как раньше;
- `false` — `ErrorEvent` `badRequest` `<id>: the user did not allow sending data to this provider`, внутренняя функция не вызывается, HTTP-запроса нет;
- исключение гейта — тот же отказ с текстом `<id>: the data sharing check failed` (fail closed);
- отмена `CancelToken` во время ожидания — `aborted` (LLM-7); `cancelled` гейта завершается.

`endpointOf` строит хост по `CoreConfig`: для провайдера из `providerProblems` или неизвестного он даёт `null`, и запрос уходит во внутреннюю функцию без вопроса. Та сама завершает его без HTTP (`auth` или `badRequest`), поэтому пользователю не задают вопрос, за которым сразу последует ошибка ключа.

`codelab_embedded` получает необязательное поле `EmbeddedHostServices.sharingGate` и параметр `sharingGate` у `localEmbeddedAgentOpener` и `scriptedEmbeddedAgentOpener`. Если гейт есть, `createEmbeddedAgent` оборачивает функцию модели в `modelsFor` при каждом снимке конфигурации, а сценарный открыватель оборачивает сценарную функцию. Основной барель реэкспортирует `SharingGate`, `ProviderEndpoint` и `ProviderApi`. Без гейта функция не оборачивается: CLI и тесты без гейта не меняются.

Класс `badRequest` не повторяется и не переключает модель (LLM-9, §2.10.3). Ход заканчивается итогом `failed`, и клиент получает существующий `-32603` с `data.codelab.errorClass: "badRequest"` и текстом отказа (§13.8). Новых значений и полей ACP нет. «Retry» в транскрипте повторяет ход и снова вызывает гейт: это путь к разрешению после отказа.

**Альтернативы.**
- *Гейт на клиенте перед `session/prompt`* (`SessionHandle.send` в `codelab_client_core`). Клиент не знает, какому провайдеру уйдёт запрос: модель меняют опция `model`, определение агента субагента, fallback, проектный конфиг и `CODELAB_*`. Проверка «по модели по умолчанию» пропустила бы субагента с другим провайдером и fallback. Проверка «по всем провайдерам конфига» спрашивала бы о тех, кому ничего не уходит.
- *`session/request_permission` от агента.* Этот метод относится к вызову инструмента (`toolCallId`). Запрос к модели — не инструмент, и такое использование было бы новой семантикой ACP (запрещено §3.4).
- *Обёртка только в `codelab_embedded`, без ядра.* Строить поток событий (`runProvider`, контракт LLM-1…LLM-7) мосту пришлось бы самому, а сценарный путь и путь конфигурации получили бы две копии. Декоратор ядра — точка расширения документа ядра (§2.10, AGENTS.md ядра §3(г)).
- *Новый класс ошибки `LlmErrorClass.denied`.* Он расширил бы перечисление, которое проецируется в `data.codelab.errorClass`, то есть изменил бы контракт расширения `_codelab`. `badRequest` уже значит «запрос не будет выполнен, повтор не поможет», и app знает об отказе сама (D8).

### D5. Внешний ACP-агент — гейт в обёртке TransportResolver app, отзыв закрывает транспорт

App оборачивает свой `ConfigTransportResolver` (профили `stdio` и `webSocket`) классом `SharingGatedTransportResolver` (`features/data_sharing/application/`). `open(profile, …)` сначала спрашивает `DataSharingCubit.requestAgent(profile)`:
- разрешено — открывает внутренний транспорт и возвращает обёртку `AcpTransport`, которая подписана на отзыв этого получателя;
- отказ — бросает `DataSharingDeniedException` до запуска процесса и до сокета. `ClientWorkspace` превращает её в `ConnectionView.failed(startFailed, 'Data sharing with this agent is not allowed.')` по существующему пути сбоя резолвера.

Отзыв разрешения закрывает обёрнутый транспорт. `ClientWorkspace` видит обрыв в `Connected` и переходит в `ConnectionLost`. Идущий ход завершается так же, как при любом обрыве, а «Reconnect» снова спросит гейт. `connect`, `ensureAgent` и `reconnect` идут через резолвер, поэтому обойти гейт ни один триггер старта не может. `EmbeddedProfile` обёртка не трогает: его открывает `EmbeddedTransportResolver`, а гейт провайдеров живёт в ядре (D4).

`initialize` тоже не уходит без разрешения. Он не несёт данных разговора, зато `session/new` несёт `cwd`, а транспорт stdio запускает чужой процесс. Граница «до транспорта» проще и строже.

**Альтернативы.**
- *Вне области.* По умолчанию профиль встроенный, но внешний агент — штатная функция app (`ws://`, `wss://` на чужой адрес). Без вопроса 5.1.2(i) нарушалось бы для пользователя, который его выбрал.
- *Порт гейта в `ClientWorkspace.connect` (`codelab_client_core`).* Пришлось бы менять общий для CLI пакет, добавлять причину в `ConnectionFailureReason` (`codelab_client_acp`) и метод `disconnect` для отзыва. Резолвер — уже существующая точка расширения composition root.
- *Гейт перед `session/prompt` для внешнего агента.* До первого промпта агент уже получил бы `cwd` и список сессий. Отзыв посреди сессии всё равно потребовал бы закрыть соединение.

### D6. MCP, проверка ключа и «Show image» — вне области

- **MCP-серверы.** Каждый `tools/call` проходит `PermissionPolicy` агента с уровнем `exec` (spec agent-permissions «MCP-вызов только после решения политики»). В режимах `ask`, `standard` и `accept-edits` вызов спрашивается, «разрешить всегда» действует только для тех же аргументов. `initialize` и `tools/list` несут сведения о клиенте и заголовки из конфигурации пользователя, но не данные разговора. Сервер пользователь добавляет сам, а шаг «Privacy» и политика его раскрывают. Открытый вопрос — Q3.
- **Проверка ключа** (`GET /models`). Её запускает пользователь в мастере. Уходит только ключ, без данных разговора, редиректы не выполняются.
- **«Show image».** Запрос по нажатию пользователя, без ключей и cookie.

**Альтернатива** — гейт на MCP-сервер по хосту `url`. Для stdio-сервера (локальный процесс) он повторил бы проблему внешнего агента, но при этом дублировал бы политику вызовов, которая уже спрашивает о каждом вызове.

### D7. Владелец состояния — application-слой app; CLI и `codelab-agent` вне области

Политика (кого спрашивать, что считать тем же получателем, действует ли разрешение), очередь вопросов и выданные разрешения живут в `DataSharingCubit` (`apps/codelab_desktop/lib/features/data_sharing/application/`). Cubit один на процесс и регистрируется в app scope. Домен (`DataRecipient`, `DataSharingGrant`, кодек документа хранилища) — чистый Dart в `features/data_sharing/domain/`. Порт хранилища — `DataSharingPreferences` в `lib/core/platform/` по образцу `OnboardingPreferences`.

`codelab_client_core` не меняется, поэтому гейт для CLI не становится обязательным: CLI не передаёт гейт в `localEmbeddedAgentOpener` и не оборачивает резолверы. Бинарь `codelab-agent` гейт не получает. Политика конфиденциальности говорит об этом прямо (D14).

**Альтернатива** — логика в `codelab_client_core` с портом хранилища, как `RecentProjectsStore`. Пакет общий с CLI, а CLI её не использует. Код «на вырост» запрещён §13. Требование магазинов относится только к app, хранилище — `shared_preferences` app. Если CLI понадобится то же, перенос домена в kit — отдельный change.

### D8. Модель вопроса: очередь по получателям, слияние ожидающих, отказ не запоминается

Состояние Cubit:

```dart
final class DataSharingState {
  final GrantsLoad grants;                 // sealed: GrantsLoading | GrantsLoaded(List<DataSharingGrant>) | GrantsUnreadable
  final List<PendingSharingRequest> queue; // FIFO; первый показывается диалогом
  final SharingSaveIssue? saveIssue;       // sealed: null | WithdrawNotSaved(recipient)
}
final class PendingSharingRequest { final int id; final DataRecipient recipient; final String label; }
```

Вход гейта — `Future<bool> requestProvider(ProviderEndpoint, Future<void> cancelled)` и `Future<bool> requestAgent(ConnectionProfile, Future<void> cancelled)`. Алгоритм:
1. Дождаться окончания чтения хранилища. Пока оно идёт, ответа нет (fail closed).
2. Локальный провайдер (D3) — `true` сразу, без записи и без события.
3. Есть действующее разрешение (тот же получатель, `disclosure == kDataSharingDisclosure`) — `true` сразу.
4. В очереди уже есть запрос этого получателя — ожидающий присоединяется к нему (слияние: параллельные субагенты, повтор подключения). Иначе в конец очереди ставится новый запрос, и пишется `data_sharing.requested`.
5. Пользователь нажал «Allow» — запись разрешения (D9), все ожидающие получают `true`, запрос уходит из очереди. «Don't allow» или Esc — все ожидающие получают `false`, отказ нигде не сохраняется.
6. `cancelled` ожидающего завершился — он получает `false` (ядро всё равно отдаёт `aborted`) и уходит из запроса. Запрос без ожидающих уходит из очереди, диалог закрывается (`data_sharing.request_dropped`). Ответ, нажатый после этого, игнорируется.
7. `close()` Cubit (выход из app) отвечает `false` всем ожидающим.

Отказ не запоминается. Отказ в одном ходе не должен навсегда запрещать провайдера, а «Retry» должен снова спрашивать. Цена — повторный диалог для следующего запроса того же получателя в том же ходе (например, последовательные субагенты с отклонённым провайдером). Это Q6.

**Альтернативы.**
- *Набор флагов* (`isAsking`, `isDenied`, `isLoaded`) — запрещён AGENTS.md §8. Состояние загрузки и проблема записи — закрытые иерархии.
- *Запоминать отказ до перезапуска.* Пользователь, который передумал, не нашёл бы, где разрешить: настройки только отзывают (D10).
- *Таймаут вопроса.* Ход ждёт решения пользователя, как ждёт одобрения инструмента. Отмена хода снимает вопрос (п. 6).

### D9. Хранение: `shared_preferences`, версия раскрытия, fail closed

Ключ `codelab.app.data_sharing`, значение — строка JSON:

```json
{"version": 1, "grants": [
  {"recipient": "provider", "api": "anthropicMessages", "host": "api.anthropic.com", "label": "anthropic", "disclosure": 1, "allowed_on": "2026-11-25"},
  {"recipient": "agent", "transport": "ws", "host": "agent.example.com:8443", "label": "Remote agent", "disclosure": 1, "allowed_on": "2026-11-25"},
  {"recipient": "agent", "transport": "stdio", "command": "/usr/local/bin/my-agent", "label": "My agent", "disclosure": 1, "allowed_on": "2026-11-25"}
]}
```

- `disclosure` — версия перечня данных, который видел пользователь, константа `kDataSharingDisclosure = 1` в домене app. Если строка «провайдер модели» или «внешний ACP-агент» в `PRIVACY.md` §2 начнёт перечислять новые данные, константа растёт в том же change. Записи прежней версии не действуют: не показываются в настройках и удаляются при следующей записи. App спросит снова.
- `allowed_on` — дата по часам app (`YYYY-MM-DD`), показывается в настройках как есть.
- Нет ключа — разрешений нет. Битый JSON, чужая `version` или значение не строкой — разрешений нет, значение не перезаписывается до следующей выдачи или отзыва, событие `data_sharing.store_invalid`. Отдельная запись неизвестного вида или с неполными полями пропускается.
- Сбой чтения — `GrantsUnreadable`, разрешений нет, `data_sharing.store_unreadable {error_type}`. Настройки показывают InfoBar, app спросит снова.
- Сбой записи при выдаче — разрешение действует до выхода из app, `data_sharing.save_failed {op: grant}`. После перезапуска app спросит снова (fail closed).
- Сбой записи при отзыве — разрешение отозвано в памяти (гейт отказывает или закрывает транспорт), `data_sharing.save_failed {op: withdraw}`, `saveIssue: WithdrawNotSaved`. Настройки показывают InfoBar с «Try again»: после перезапуска старое разрешение снова действовало бы, и пользователь должен это знать.
- Запись — всегда полный документ из текущего списка в памяти. Записи не накладываются: следующая ждёт предыдущую (single-flight, `concurrency.md`).

`$CODELAB_HOME` не используется: CLI разрешений не читает (D7), а настройки окна app по стеку живут в `shared_preferences` (`technology-stack.md`).

**Альтернативы.**
- *`$CODELAB_HOME/data_sharing.json`.* Общий с CLI файл имел бы смысл, только если CLI спрашивает. Песочница магазинов к тому же ограничивает доступ app к `~/.codelab`.
- *Без версии раскрытия.* Тогда изменение перечня данных не дало бы нового вопроса, и прежнее «да» распространилось бы на то, о чём пользователя не спрашивали.

### D10. Где спрашивают: onboarding, диалог, настройки (только просмотр и отзыв)

**Onboarding, шаг «Privacy».** При показе шага onboarding заново читает кандидата через `OnboardingProbe.sharingCandidate()` с таймаутом 5 с. Кандидат — закрытая иерархия:
- `RemoteProviderCandidate(endpoint)` — профиль по умолчанию встроенный, провайдер модели по умолчанию готов и не локальный. Адрес даёт `defaultProviderEndpoint(snapshot)` моста `codelab_setup` по тому же `CODELAB_HOME`, что у мастера;
- `LocalProviderCandidate` — провайдер по умолчанию локальный (D3);
- `ExternalAgentCandidate(profile)` — профиль по умолчанию внешний;
- `NoCandidate` — провайдера нет, конфиг битый, чтение не удалось или не успело.

Пока кандидат читается, карточка показывает `Checking…`, кнопка `onboarding-next` подписана `Next` и действует. Для `RemoteProviderCandidate` и `ExternalAgentCandidate` без действующего разрешения карточка показывает получателя и две кнопки: `Allow and continue` (`onboarding-privacy-allow`) — выдать разрешение и перейти на «Open a project»; `Not now` (`onboarding-next`) — перейти без разрешения. Если разрешение уже есть (вернулись кнопкой «Back»), карточка показывает `Allowed` и кнопку `Next`. Для `LocalProviderCandidate` и `NoCandidate` карточка показывает пояснение без кнопки разрешения. Onboarding завершается при любом выборе. Результат чтения после ухода с шага состояние не меняет.

**Диалог `data-sharing-dialog`.** Модальный `ContentDialog` уровня app, показывается для первого запроса очереди D8 на любом назначении навигации, кроме onboarding: агент во время onboarding не стартует (spec app-onboarding «Завершение onboarding и старт рабочего места»). Кнопки — `Allow` (`data-sharing-allow`) и `Don't allow` (`data-sharing-deny`), фокус по умолчанию — на `Don't allow`. Esc равен `Don't allow`. Решение о получателе принимает Cubit, а виджет только передаёт нажатие (PERM-001).

**Настройки «General» › «Privacy».** Строка «Data sharing» (`settings-general-data-sharing`) стоит после «No telemetry». Она перечисляет действующие разрешения (`settings-general-data-sharing-item`) с кнопкой `Withdraw` (`settings-general-data-sharing-withdraw`) или пустое состояние (`settings-general-data-sharing-empty`). Выдать разрешение заранее отсюда нельзя (Q1): вопрос задаётся тогда, когда понятно, что и кому уйдёт.

**Альтернативы.**
- *Только диалог при первом ходе, без onboarding.* Технически достаточно, но рецензент магазина и пользователь видят onboarding первым. Раскрытие и разрешение рядом честнее.
- *Обязательное разрешение для завершения onboarding.* Это запрет пользоваться программой без согласия на передачу. Он не нужен локальной модели и противоречит D1.
- *Отдельная страница настроек «Data sharing».* Блок «Privacy» на «General» уже есть, а порядок страниц фиксирован (§12.4.9). Строка в существующем блоке не требует новой страницы и пункта навигации (§13).

### D11. Отзыв, отмена и гонки

| Ситуация | Поведение |
|---|---|
| Отзыв, пока запрос модели к этому провайдеру уже в сети | запрос не обрывается: данные уже ушли, обрыв лишь потерял бы ответ. Следующий запрос (шаг хода, субагент, сжатие) спросит снова |
| Отзыв, пока открыт транспорт к внешнему агенту | обёртка транспорта закрывает его, `ConnectionLost`; идущий ход завершается как при обрыве; «Reconnect» спросит снова |
| Отмена хода, пока показан вопрос | `CancelToken` → `cancelled` гейта → ожидающий уходит; без ожидающих диалог закрывается; `aborted` в пределах цикла событий (LLM-7) |
| Ответ пользователя после отмены | игнорируется для отменённого ожидающего; если остались другие — применяется к ним; «Allow» записывается, если запрос ещё в очереди |
| Два хода (две сессии или субагенты) спрашивают одного получателя | один запрос, один диалог, один ответ всем (D8 п. 4) |
| Перезагрузка конфига во время вопроса | вопрос относится к адресу, который ядро уже выбрало для этого запроса; новый снимок строит новый `endpointOf` для следующих запросов |
| Сбой записи при отзыве | отзыв действует в памяти, InfoBar с «Try again» (D9) |
| Выход из app во время вопроса | `close()` отвечает `false`; агент закрывается своим `dispose` |
| Поздний ответ гейта после `close()` | ядро уже завершило поток; ответ игнорируется (LLM-2) |

### D12. Тексты интерфейса и ключи виджетов

Все строки берутся из ARB `en` и `ru`. Id провайдеров, хосты, команды и метки профилей показываются как есть (spec app-settings «Локализация интерфейса app»). Русские тексты — по глоссарию `docs/architecture/l10n-glossary.md`; новые термины («передача данных», «разрешение на отправку данных», «отозвать») добавляются в глоссарий в том же change.

**Диалог** (`data-sharing-dialog`):

| Ключ ARB | en | ru |
|---|---|---|
| `dataSharingDialogProviderTitle` | `Allow sending data to {provider}?` | `Разрешить отправку данных в {provider}?` |
| `dataSharingDialogProviderBody` | `To answer, the agent sends your prompt, the session history, and the files and command output it read to {provider} at {host}. {provider} handles them under its own privacy policy, which CodeLab does not control. CodeLab asks once for this provider and address.` | `Чтобы ответить, агент отправляет ваш промпт, историю сессии, а также файлы и вывод команд, которые он прочитал, в {provider} по адресу {host}. {provider} обрабатывает их по своей политике конфиденциальности, CodeLab её не контролирует. CodeLab спрашивает один раз для этого провайдера и адреса.` |
| `dataSharingDialogAgentTitle` | `Allow sending data to the agent {agent}?` | `Разрешить отправку данных агенту {agent}?` |
| `dataSharingDialogAgentBody` | `CodeLab sends this agent ({target}) your prompts, the session history, and the files and command output it asks for. Where the agent sends them next, for example to its model provider, is up to the agent, not CodeLab.` | `CodeLab отправляет этому агенту ({target}) ваши промпты, историю сессии, а также файлы и вывод команд, которые он запрашивает. Куда агент отправит их дальше, например своему провайдеру модели, решает агент, а не CodeLab.` |
| `dataSharingDialogHint` | `You can withdraw permission in Settings › General › Privacy. The privacy policy in Settings › Legal lists every request.` | `Отозвать разрешение можно в «Настройки › Общие › Конфиденциальность». Все запросы перечислены в политике конфиденциальности в «Настройки › Правовая информация».` |
| `dataSharingAllow` (`data-sharing-allow`) | `Allow` | `Разрешить` |
| `dataSharingDeny` (`data-sharing-deny`) | `Don't allow` | `Не разрешать` |

**Шаг onboarding «Privacy»**, карточка `onboarding-privacy-sharing`:

| Ключ ARB | en | ru |
|---|---|---|
| `onboardingSharingTitle` | `Permission to send data` | `Разрешение на отправку данных` |
| `onboardingSharingProvider` | `Allow CodeLab to send your prompts, the session history, and the files and command output the agent read to {provider} at {host}? You can withdraw permission later in Settings › General › Privacy.` | `Разрешить CodeLab отправлять ваши промпты, историю сессии, а также файлы и вывод команд, которые прочитал агент, в {provider} по адресу {host}? Позже разрешение можно отозвать в «Настройки › Общие › Конфиденциальность».` |
| `onboardingSharingAgent` | `Allow CodeLab to send your prompts, the session history, and the files and command output the agent asks for to the agent {agent} ({target})? Where it sends them next is up to the agent. You can withdraw permission later in Settings › General › Privacy.` | `Разрешить CodeLab отправлять ваши промпты, историю сессии, а также файлы и вывод команд, которые запрашивает агент, агенту {agent} ({target})? Куда он отправит их дальше, решает агент. Позже разрешение можно отозвать в «Настройки › Общие › Конфиденциальность».` |
| `onboardingSharingAllowed` (`onboarding-privacy-allowed`) | `Allowed: {recipient}.` | `Разрешено: {recipient}.` |
| `onboardingSharingLocal` (`onboarding-privacy-local`) | `Your model runs on this computer ({host}), so no data goes to a provider and no permission is needed.` | `Модель работает на этом компьютере ({host}), поэтому данные не уходят провайдеру и разрешение не нужно.` |
| `onboardingSharingAskLater` (`onboarding-privacy-ask-later`) | `CodeLab will ask before it first sends data to a model provider or an external agent.` | `CodeLab спросит, прежде чем впервые отправить данные провайдеру модели или внешнему агенту.` |
| `onboardingSharingChecking` | `Checking your model provider…` | `Проверяется провайдер модели…` |
| `onboardingSharingAllowButton` (`onboarding-privacy-allow`) | `Allow and continue` | `Разрешить и продолжить` |
| `onboardingSharingNotNow` (`onboarding-next` при показанном вопросе) | `Not now` | `Не сейчас` |
| `onboardingNothingToAgreeTitle` (новое значение) | `Nothing to accept in these documents` | `В этих документах принимать нечего` |

`{recipient}` — `{provider} · {host}` для провайдера и `{agent} · {target}` для агента. Текст `onboardingNothingToAgreeBody` не меняется.

**Настройки «General» › «Privacy»**, строка `settings-general-data-sharing`:

| Ключ ARB | en | ru |
|---|---|---|
| `settingsGeneralDataSharing` | `Data sharing` | `Передача данных` |
| `settingsGeneralDataSharingDescription` | `CodeLab asks before the agent first sends your prompts, the session history, files and command output to a model provider or an external agent. A model on this computer (localhost) needs no permission.` | `CodeLab спрашивает, прежде чем агент впервые отправит ваши промпты, историю сессии, файлы и вывод команд провайдеру модели или внешнему агенту. Модели на этом компьютере (localhost) разрешение не нужно.` |
| `settingsGeneralDataSharingProvider` | `Model provider · allowed {date}` | `Провайдер модели · разрешено {date}` |
| `settingsGeneralDataSharingAgent` | `External agent · allowed {date}` | `Внешний агент · разрешено {date}` |
| `settingsGeneralDataSharingWithdraw` (`settings-general-data-sharing-withdraw`) | `Withdraw` | `Отозвать` |
| `settingsGeneralDataSharingEmpty` (`settings-general-data-sharing-empty`) | `You have not allowed any service yet.` | `Вы ещё не разрешили ни одному сервису.` |
| `settingsGeneralDataSharingUnreadable` (`settings-general-data-sharing-unreadable`) | `Saved permissions could not be read. CodeLab will ask again before sending data.` | `Не удалось прочитать сохранённые разрешения. CodeLab спросит снова, прежде чем отправлять данные.` |
| `settingsGeneralDataSharingWithdrawNotSaved` (`settings-general-data-sharing-not-saved`) | `The change was not saved. Permission is withdrawn until CodeLab quits; after a restart the old permission would apply again.` | `Изменение не сохранено. Разрешение отозвано до выхода из CodeLab; после перезапуска снова действовало бы старое разрешение.` |
| `settingsGeneralDataSharingRetry` (`settings-general-data-sharing-retry`) | `Try again` | `Повторить` |

Первая строка элемента — `{label} · {target}`. В `settingsSearchKeywordsGeneral` добавляются `data sharing, permission, provider, consent` (en) и `передача данных, разрешение, провайдер, согласие` (ru).

### D13. Журнал

Логгер `codelab_desktop.data_sharing`:

| Событие | Поля |
|---|---|
| `data_sharing.loaded` | `grants` (число действующих) |
| `data_sharing.requested` | `recipient: provider \| agent`, `transport: stdio \| ws` (у агента) |
| `data_sharing.allowed` | `recipient`, `from: dialog \| onboarding` |
| `data_sharing.denied` | `recipient`, `waiters` (число ожидающих) |
| `data_sharing.request_dropped` | `recipient` — все ожидающие отменились |
| `data_sharing.withdrawn` | `recipient`, `closed_connection: true \| false` |
| `data_sharing.store_invalid` | — |
| `data_sharing.store_unreadable` | `error_type` |
| `data_sharing.save_failed` | `op: grant \| withdraw`, `error_type` |

События ядра (`agent-core/02-llm-contract.md` §2.10.6): `llm.sharing.denied {provider}`, `llm.sharing.gate_failed {provider, error_class}`. Id провайдера — имя из конфига, оно уже есть в событиях `llm.*`.

События app НЕ содержат хостов, URL, команд, меток профилей, id провайдеров, дат и текстов исключений (AGENTS.md §16; spec app-onboarding «События журнала onboarding без секретов и путей»). `onboarding.completed` получает поле `sharing: allowed | not_now | already_allowed | local | not_asked`.

### D14. Документы

Уже в этом change, до кода:
- `docs/architecture/proposals/agent-core/02-llm-contract.md` — §2.10.6 и инвариант LLM-17;
- `docs/architecture/permissions.md` — §59.
- `docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md` §12.4.9, строка «General» — строка «Data sharing».

Задачи `docs-writer`:
- `PRIVACY.md` и `PRIVACY.ru.md`. В §3 — app хранит выданные разрешения в пользовательских настройках ОС. В §6 — app спрашивает разрешение перед первой отправкой данных провайдеру модели или внешнему агенту; модель на этом компьютере не спрашивается; где отозвать; после отзыва app спросит снова; CLI `codelab` и `codelab-agent` не спрашивают, потому что запуск с настроенным провайдером и ввод промпта — уже указание отправить. Новая дата редакции в обоих файлах, копии в `apps/codelab_desktop/assets/legal/`. Слов `I agree`, `accept these terms`, `Принимаю` нет: сторож `legal_documents_test.dart` не меняется. Строки §2 не меняются, поэтому `kDataSharingDisclosure` остаётся `1`;
- README и `AGENTS.md` `codelab_embedded` (поле `sharingGate`, реэкспорт), `doc/` и README `apps/codelab_desktop` (onboarding, настройки «General»), `docs/user/` — раздел о приватности, если он описывает onboarding.

### D15. Пакеты, зависимости и сторож

| Пакет | Слой (ADR-0002) | Изменение |
|---|---|---|
| `codelab_agent_core` | agent/core | `ProviderEndpoint`, `SharingGate`, `withSharingGate`; экспорт из бареля |
| `codelab_setup` | мост | `defaultProviderEndpoint`; реэкспорт `ProviderEndpoint`, `ProviderApi` |
| `codelab_embedded` | мост | `EmbeddedHostServices.sharingGate`, параметры открывателей, реэкспорт |
| `apps/codelab_desktop` | app | feature `data_sharing`, порт `core/platform`, проводка, onboarding, «General» |

Направление зависимостей не меняется: app → `codelab_embedded`/`codelab_setup` → `codelab_agent_core`. `apps/codelab_desktop` не импортирует `package:codelab_agent_*` (PKG-4): типы ядра приходят реэкспортом мостов. Новых пакетов и зависимостей нет, allowlist (`pubspec_allowlist_test.dart`, PKG-2, `embeddedAllowlist`) и правила `rules.dart` не меняются. Основные барели `codelab_embedded` и ядра остаются web-безопасными: новые типы — чистый Dart (`web-compile`). Граф пакетов в `README.md` не меняется. `legal_documents_test.dart` не меняется: тексты интерфейса он не проверяет, а новые абзацы политики не содержат слов согласия.

## Risks / Trade-offs

- **Повторный диалог в одном ходе после отказа** (последовательные субагенты с отклонённым провайдером) → принято ради «Retry» как пути к разрешению; Q6.
- **Запрос, ушедший до отзыва, не обрывается** → данные уже переданы, обрыв не возвращает их. Политика и §59 говорят «со следующего запроса».
- **Проектный конфиг доверенного проекта или `CODELAB_*` задают другого провайдера** → onboarding его не покажет, но гейт ядра спросит при первом запросе (D4).
- **`localhost` в `/etc/hosts` указывает наружу** → правило D3 доверяет имени. Это конфигурация самого пользователя, а не атака репозитория: `providers.*` недоверенного проекта отбрасываются (CFG-3).
- **Тесты app со сценарным агентом** начнут получать диалог для сценарного провайдера → тестовая сборка app scope выдаёт разрешение фейком хранилища или передаёт разрешающий гейт; тесты самого вопроса включают настоящий Cubit (задачи 8.x).
- **Сбой записи отзыва** → честный InfoBar и «Try again» вместо молчаливого восстановления разрешения после перезапуска.
- **Не юридическая проверка** → формулировки соответствуют 5.1.2(i) по смыслу, но черновик политики ещё ждёт юриста (`Draft pending legal review.`).

## Migration Plan

Миграции нет: ключа `codelab.app.data_sharing` раньше не было. Пользователь, прошедший onboarding до выпуска, увидит диалог при первом запросе к удалённому провайдеру или при подключении внешнего агента. Откат — удаление проводки гейта в app. Ключ в `shared_preferences` тогда просто не читается.

## Open Questions

- **Q1.** Нужна ли в настройках кнопка «Allow» для получателя заранее (например, для провайдеров со страницы «Providers»)? Предложение — нет: вопрос задаётся, когда понятно, что и кому уйдёт.
- **Q2.** Внешний агент входит в область (D5). Подтвердить или вынести в отдельный change, если сборки для магазинов будут только со встроенным агентом.
- **Q3.** MCP-серверы по HTTP вне гейта (D6). Подтвердить, что для рецензии достаточно раскрытия и вопроса на каждый `tools/call` в режимах с вопросами (в `bypass` и `autopilot` вызовы идут без вопроса по выбору пользователя).
- **Q4.** Идентичность провайдера — вид API + хост + нестандартный порт (D2). Подтвердить, что смена порта на том же хосте — новый получатель.
- **Q5.** Правило роста `kDataSharingDisclosure` (D9) — любое изменение строк «провайдер модели» и «внешний ACP-агент» в `PRIVACY.md` §2, которое добавляет вид данных. Подтвердить.
- **Q6.** Отказ не запоминается (D8). Подтвердить или запоминать отказ до конца хода, если повторные диалоги окажутся навязчивыми.
