# Расширение клиентского слоя

Рецепты ниже — для самых частых задач: подключить новый вид агента или хранилище, добавить команду палитры, показать новое поле сессии, добавить заметку в ленту, принять новое расширение `_meta.codelab.*`. Каждый рецепт опирается на реальный прецедент в коде. Скелеты, помеченные «проверен», собраны во временном файле и прогнаны (`fvm dart analyze`, запуск или тест), затем файл удалён.

Перед любым рецептом: прочитайте [`AGENTS.md`](../AGENTS.md) пакета и проверьте, нужен ли OpenSpec change. Новое поведение продукта, новое публичное API и новые зависимости пакета — предмет change (корневой `AGENTS.md` §17). Реализация без изменения контракта — нет.

## Общий порядок

1. Найдите прецедент: поле, заметка или порт, похожие на новое. Таблица «что изменить — куда смотреть» — [глава 0](00-getting-started.md).
2. Красный тест, затем код.
3. Если меняется публичное API — экспорт в `lib/codelab_client_core.dart` и проверка потребителей (`codelab_client_io`, `apps/codelab_cli`, `apps/codelab_desktop`).
4. Если меняется `freezed`-модель — `fvm dart run build_runner build --delete-conflicting-outputs` в пакете.
5. Прогон по [проверкам перед pull request](00-getting-started.md#проверки-перед-pull-request).
6. Обновите документ: этот каталог, `README.md` и `AGENTS.md` пакета, если изменилось описанное в них.

## Рецепт: свой резолвер транспорта

Задача: подключить агента, которого `ConfigTransportResolver` не открывает — например, встроенного или тестового.

Профиль выбирает резолвер через `supports`; `open` возвращает `AcpTransport`. Резолвер регистрирует composition root в списке `resolvers`; слой берёт первый, чей `supports` истинен ([глава 3](03-connection.md)).

Скелет (проверен: подключается, передаёт папку, на чужой профиль даёт `ConnectionFailed`):

```dart
final class DemoResolver implements TransportResolver {
  DemoResolver(this._create);

  final AcpTransport Function(String directory) _create;

  @override
  bool supports(ConnectionProfile profile) =>
      profile is EmbeddedProfile && profile.hostProfile == 'demo';

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async => _create(projectDirectory);
}
```

Подключение:

```dart
final workspace = ClientWorkspace(
  backend: AcpClientBackend(application),
  resolvers: [DemoResolver((directory) => transport)],
);
await workspace.connect(
  const ConnectionProfile.embedded(
    id: 'demo',
    label: 'Demo agent',
    hostProfile: 'demo',
  ),
  projectDirectory: '/work',
);
```

Реальный вывод прогона (первая строка — после подключения встроенным профилем `demo`, остальные — после `connect` с неподдерживаемым stdio-профилем):

```text
ConnectionView.connected() dirs=[/work]
ClientWorkspaceException: No transport resolver supports profile "X".
ConnectionView.failed(reason: ConnectionFailureReason.startFailed, message: No transport resolver supports profile "X".)
```

Что учесть, если резолвер владеет ресурсом (процессом, встроенным агентом):

- `open` может быть вытеснен новым `connect`: транспорт, который не достался бэкенду, слой закрывает сам, но ресурс за ним освобождает резолвер. `EmbeddedTransportResolver` (`apps/codelab_cli/lib/src/embedded_transport_resolver.dart`) сериализует `open`, а результат вытесненного `open` освобождает и бросает `EmbeddedOpenCancelledException`;
- исключение из `open` становится `ConnectionFailed(startFailed)` и уходит вызывающему `connect`;
- `projectDirectory` — корень процесса агента, а не обязательно проект;
- слой не знает ядра агента: резолвер встроенного агента живёт в composition root, а не в пакете (`codelab_client_core` не может зависеть от `codelab_embedded`). У app и CLI он свой, и оба обязаны вести себя одинаково — правка в одном требует парной правки в другом.

Тест — по образцу `test/connection/config_transport_resolver_test.dart`.

## Рецепт: хранилище профилей в памяти

Задача: реализовать порт хранилища для теста или хоста без файлов.

Порт `ProfileStore` небольшой: `load`, `save`, `remove`. Правила: `save` заменяет профиль с тем же `id` на месте или добавляет новый в конец; зарезервированный `id` отклоняется `ArgumentError`; `remove` возвращает `true`, если профиль был ([глава 13](13-ports-and-stores.md)).

Скелет (проверен вместе с `ProfileCommitter` и `ProfileDraft`):

```dart
final class MemoryProfileStore implements ProfileStore {
  final _profiles = <ConnectionProfile>[];

  @override
  Future<List<ConnectionProfile>> load() async => List.of(_profiles);

  @override
  Future<void> save(ConnectionProfile profile) async {
    if (reservedProfileIds.contains(profile.id)) {
      throw ArgumentError.value(profile.id, 'profile.id', 'reserved');
    }
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    index < 0 ? _profiles.add(profile) : _profiles[index] = profile;
  }

  @override
  Future<bool> remove(String id) async {
    final before = _profiles.length;
    _profiles.removeWhere((p) => p.id == id);
    return _profiles.length != before;
  }
}
```

Использование вместе с `ProfileCommitter` (для хранилища секретов нужна своя реализация `ProfileSecrets`; в проверенном скелете это двойник, который всегда отвечает `ReadOnly`):

```dart
final committer = ProfileCommitter(store: MemoryProfileStore(), secrets: secrets);
final result = await committer.save(
  ProfileDraft(
    kind: ProfileKind.webSocket,
    label: 'Dev box',
    id: suggestProfileId('Dev box'),
    url: 'wss://devbox.example.test/acp',
  ),
);
// ProfileSaved(dev-box)
```

Реальный вывод: `ProfileSaved(dev-box)`, а `load()` возвращает один профиль с `id` `dev-box`. Другие порты — тем же образом: `WorkspaceSnapshotStore` (`read`, `write`, `clear`), `RecentProjectsStore` (`load`, `record`), `ThemeLibrary`. Двойники слоя для тестов — `InMemoryWorkspaceSnapshotStore`, `InMemoryThemeLibrary`; для профилей — `FakeProfileStore` в `test/support/profile_fakes.dart`. Реализацию на `dart:io` кладут в `codelab_client_io`, а не в слой.

## Рецепт: команда палитры хоста

Задача: добавить команду в палитру приложения или CLI.

Команда хоста — `HostCommand(id, name, label, description)`. Хост сам решает, что она делает; слой лишь ставит её в каталог и ищет. Недоступную команду объявляют `isAvailable: false`: она станет заглушкой, которую вытеснит одноимённая команда агента.

Скелет (проверен):

```dart
final catalog = CommandCatalog(
  host: const [
    HostCommand(
      id: 'logs',
      name: 'logs',
      label: 'Show logs',
      description: 'Open the log view',
    ),
  ],
  agent: session.current.agentCommands,
);
final shown = catalog.search('/lo'); // команды, найденные по запросу
```

Реальный вывод поиска — в [главе 9](09-options-commands-plan.md). Если хост показывает `label` и `description` на своём языке, дополнительные строки поиска кладут в `searchAliases`, чтобы команда находилась по обоим языкам. Тест — по образцу `test/commands/command_catalog_test.dart`.

## Рецепт: новое поле в `SessionView`

Задача: показать хосту новое значение сессии. Прецедент — `approvalWaits` (change `fix-usage-pane-live-cards`).

Сначала определите источник значения:

- **Выводится из `AcpSession`** (ходы, одобрения, план, опции): значение считает чистая функция от снимка. Пример формы функции. `toolCallCountOf` — учебная новая функция, в коде пакета её нет; скелет проверен отдельно и компилируется:

  ```dart
  /// Сколько вызовов инструментов видно в сессии.
  int toolCallCountOf(AcpSession session) =>
      session.turns.fold(0, (sum, turn) => sum + turn.toolCalls.length);
  ```

  В `SessionView` добавляется поле с `@Default` (`lib/src/workspace/workspace_state.dart`); `_SessionHandle._sessionFields` заполняет его вызовом функции: так значение пересчитывается при каждой публикации и не может разойтись со снимком. Вид хранят в подходящем файле: `session/session_views.dart` для видов управляющих элементов или `transcript/`, если оно из ленты.
- **Живёт только в слое** (очередь, расход, `configOptionInFlight`): значение хранит `_SessionHandle`, поле публикуется через `_publish(_current.copyWith(revision: _current.revision + 1, поле: …))`. Решите заранее, что его сбрасывает: смена соединения и `session/load` ([глава 10](10-usage.md) — пример с `usage`). `_sessionFields` такое поле не трогает.

Затем:

1. Красный тест на `KitAgent`: прислать обновления, проверить `session.current`.
2. Добавить вид и поле, сгенерировать `freezed`.
3. Если вид новый — экспортировать его из барелей (`lib/codelab_client_core.dart`).
4. Проверить `revision`: одно изменение сессии — одна ревизия, повтор снимка (`identical`) ревизию не меняет.
5. Обновить описание поля в этом руководстве ([глава 2](02-state-ownership.md), таблица) и в `README.md` пакета.

Что НЕЛЬЗЯ: разбирать `_meta` в виджетах; класть в `SessionView` DTO протокола как долгоживущее состояние (корневой `AGENTS.md` §7).

## Рецепт: новая заметка в ленте

Задача: сообщить пользователю итог, которого нет в обновлениях агента. Прецедент — `turnStopped` (`add-provider-setup-ui`, Q33) и её причина `TurnStoppedReason` (`add-desktop-localization`, D6).

1. `NoticeKind` — новое значение (`transcript_item.dart`).
2. Если у заметки есть причина, из которой хост строит текст, — новый наследник `sealed class NoticeReason` с `==` и `hashCode`. Текст `NoticeItem.text` остаётся английским для CLI; хост по `reason` строит свой.
3. Заметку строит проекция. **Обе** ветки обязаны дать одинаковый результат: инкрементальный `_TurnProjection` и эталон `projectTranscript`. Заметки конца хода собирает общая функция `_notices`, поэтому правка в ней попадает в обе. Заметки, добавляемые рабочим пространством (`detached`, `reconnected`), идут через `_SessionHandle.notify`.
4. Тесты: `test/transcript/notice_reason_test.dart` (причины равны в обеих проекциях) и свойство на корпусе фикстур.
5. Хосты разбирают `NoticeKind` и `NoticeReason` `switch`: после добавления значения app и CLI не скомпилируются, пока не обработают его. Обновите их и документацию.
6. Реплей `session/load` не получает заметок исхода: агент не передаёт `stopReason` ([глава 7](07-transcript.md)); не делайте заметку зависимой от него без обоснования.

## Рецепт: новое расширение `_meta.codelab.*`

Задача: показать данные, которые агент CodeLab кладёт в `_meta.codelab.*`. Прецеденты — `subagent`, `task`, `outcome`, `parentToolCallId`, usage.

Разбор `_meta.codelab.*` — только здесь и в `codelab_client_acp` (`AGENTS.md` пакета, §5). Порядок:

1. В `codelab_client_acp` — разбор сырых данных в модель ядра клиента (прецеденты: `subagentMetaOf`, `outcomeOf`, `parentToolCallIdOf` в `domain/domain_models.dart`) и, если нужно, объявление в `codelabClientExtensionsMeta`. Агент шлёт расширение только объявившему клиенту (так сделано для `usage`).
2. Здесь — **терпимый** разбор в готовое поле представления (прецеденты: `parseSubagentCall`, `parseSubagentSummary`, `taskMetaOf`): любая неверная форма, неизвестные ключи и отсутствие дают `null`, а не ошибку; поздний кадр без поля не стирает известное значение.
3. Поле кладётся в вид (`ToolCallView`, `PlanEntryView`, `ApprovalStateView`…) и доходит до хоста готовым; `_meta` у хоста нет.
4. Тесты на неверную форму и «поздний кадр без поля».
5. Новая форма на проводе — это ещё и контракт: обновите спецификацию через OpenSpec change (корневой `AGENTS.md` §3.4: придумывать поля ACP нельзя).

## Рецепт: новый член порта `AgentBackend`

Новая операция ядра клиента, нужная слою, добавляется в порт, а не вызывается в обход (`ClientWorkspace` работает только через `AgentBackend`):

1. Член порта в `agent_backend.dart` с doc-комментарием «почему, для чего, как» (`AGENTS.md` репозитория, §15).
2. Реализация в `AcpClientBackend` — делегирование.
3. Во **всех** фейках порта: `_FakeBackend` в `test/protocol/protocol_frame_log_test.dart` и `FakeFrameBackend` в `apps/codelab_desktop/test/support/fake_protocol_workspace.dart`. Первый бросает при случайном обращении через `noSuchMethod`, но явные члены нужны, если новая операция вызывается в тесте.
4. Тест: `ClientWorkspace` вызывает операцию; поздний ответ прежнего соединения отбрасывается (`backend.generation` до и после `await`).

## Рецепт: новая проблема черновика профиля

1. Значение в `ProfileDraftIssueCode`, при необходимости — в `ProfileDraftField` (`profile_draft.dart`).
2. Проверка в `_validate*`; сообщение английское, **без значений `env` и токена**. Предупреждение, не блокирующее сохранение, помечается `isWarning`.
3. Тест в `test/connection/profile_draft_test.dart`.
4. Хосты локализуют текст по `code` и `field`: добавьте строки в app (ARB) и CLI.
5. Правило, которое защищает секреты (как `envSecretLike`), должно жить в `toProfile`, а не только в UI: вызывающий не должен получить профиль в обход правил.
