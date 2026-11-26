# 02. Хранилища и расширение

Глава описывает файлы, которые пакет читает и пишет, поведение при сбоях, рецепт нового JSON-хранилища и частые проблемы. Где лежат файлы и кто их пишет в продукте — в [каталоге `CODELAB_HOME`](../../../../docs/ops/codelab-home.md); здесь — как это сделано в коде.

## Общая запись и чтение

Все JSON-хранилища работают через `lib/src/stores/json_file.dart`. Эти функции в барель не входят: ими пользуются адаптеры пакета.

| Функция | Что делает |
|---|---|
| `readJsonObject(path)` | нет файла — `null`; файл не JSON-объект или битый — `FormatException` |
| `writeJsonObject(path, value)` | пишет JSON с отступом в два пробела через `writeBytesAtomically` |
| `writeBytesAtomically(path, bytes)` | создаёт каталог, пишет байты во временный файл `<path>.<pid>.<суффикс>.tmp` с `flush: true`, затем делает `rename`; при ошибке удаляет временный файл |

Из этого следует:

- Прерванная запись оставляет целый старый или целый новый файл. Полуфайла под настоящим именем не бывает.
- Два писателя не мешают друг другу: у каждого свой временный файл. Побеждает последний `rename`.
- Права прежнего файла не переносятся: в `dart:io` нет API установки режима без запуска процесса. Секреты в эти файлы не пишутся, поэтому это не проблема.
- Файл после записи не заканчивается переводом строки.

Хранилище не подменяет битый файл пустым списком молча: оно бросает `FormatException`, а решение принимает хост.

## `profiles.json`

Хранит `JsonFileProfileStore` — порт `ProfileStore`. Файл общий у `codelab` и CodeLab app. Ниже — файл, который записал `codelab profiles add` на изолированном `CODELAB_HOME`:

```bash
codelab profiles add local "stdio:/bin/sh -c cat"
codelab profiles add remote ws://127.0.0.1:9/acp
```

```json
{
  "version": 1,
  "profiles": [
    {
      "type": "stdio",
      "id": "local",
      "label": "stdio:/bin/sh -c cat",
      "command": "/bin/sh",
      "args": [
        "-c",
        "cat"
      ],
      "env": {},
      "runInProjectDirectory": true
    },
    {
      "type": "webSocket",
      "id": "remote",
      "label": "ws://127.0.0.1:9/acp",
      "uri": "ws://127.0.0.1:9/acp",
      "tokenRef": "env:CODELAB_AGENT_TOKEN"
    }
  ]
}
```

Поле `tokenRef` в этом примере появилось потому, что `codelab profiles add` подставляет ссылку по умолчанию: значение токена в файл не попадает никогда, только ссылка. Если у профиля нет `tokenRef`, ключа в записи нет.

Встроенного агента в файле нет: он выбирается словом `embedded` или `default`. Права файла — по `umask` (в прогоне `-rw-r--r--`): права не ставятся ни при создании файла, ни при замене (`writeBytesAtomically`: `writeAsBytes` и `rename`, без `chmod`). Каталог `$CODELAB_HOME` получает права `0700` только от интерактивных режимов и подкоманды `profiles` терминала `codelab` (`CodelabHome.ensureExists`), `cli_history` — `0600`; app права не ставит. Значения `args` и `env` stdio-профиля в `profiles.json` открыты: не кладите в них токены, для WebSocket используйте ссылку `env:` или `secret:`.

| Поле | Тип | Замечание |
|---|---|---|
| `version` | число | сейчас `1`; другое значение — `FormatException` |
| `profiles` | список | порядок хранения сохраняется |
| `type` | строка | `stdio` или `webSocket`; другой, в том числе `embedded`, — `FormatException` |
| `id`, `label` | строки | обязательны |
| `command`, `args`, `env`, `runInProjectDirectory` | у `stdio` | `args` и `env` приводятся к строкам; `runInProjectDirectory` читается как `true`, только если значение равно `true` |
| `uri`, `tokenRef` | у `webSocket` | `tokenRef` необязателен |

Операции:

- `load` — порядок как в файле, записи прежнего вида `default` возвращаются как есть.
- `save` заменяет профиль с тем же `id` на месте или добавляет в конец. `EmbeddedProfile` и id `embedded` и `default` (`reservedProfileIds`) отклоняются `ArgumentError` до чтения файла, файл не меняется.
- `remove` возвращает `true`, если профиль был; без профиля возвращает `false` и файл не трогает. Так удаляется и старая запись `default`.

Очереди операций у этого хранилища нет: `save` читает файл, меняет список и пишет его обратно. Два `save` без ожидания одного экземпляра могут потерять правку одного из них.

## `recent_projects.json`

Хранит `JsonFileRecentProjectsStore` — порт `RecentProjectsStore`. Файл общий у `codelab` и app. Пример после трёх вызовов `record` (путь `demo` открыт дважды) с подставленными часами:

```json
{
  "version": 1,
  "projects": [
    {
      "path": "/home/user/projects/demo",
      "lastOpenedAt": "2026-11-25T10:00:02.000Z"
    },
    {
      "path": "/home/user/projects/other",
      "lastOpenedAt": "2026-11-25T10:00:01.000Z"
    }
  ]
}
```

Запись `{path, lastOpenedAt}` — `RecentProject.toJson()` из `codelab_client_core`; время в ISO 8601. Правило списка — `mergeRecentProjects`: одна запись на путь с наибольшим временем, последний открытый первым, не больше `recentProjectsLimit` (10). В хранилище правила нет.

- `record(path)` отмечает путь как открытый. Пустой путь — `ArgumentError` до чтения файла.
- `merge(projects)` сливает список с текущим по тому же правилу. Он нужен одному потребителю — разовому переносу из прежнего хранилища app — и в порт не входит.
- Конструктор принимает `clock` для детерминированных тестов.
- Операции одного экземпляра идут по очереди (`_enqueue`): два `record` подряд без `await` не теряются, а ошибка одной операции не отменяет следующие.
- Между процессами очереди нет. При одновременной записи из `codelab` и app одна запись может потеряться, файл остаётся целым.

## Что происходит при пропавшем и битом файле

| Состояние файла | `profiles.json` | `recent_projects.json` |
|---|---|---|
| нет файла | `load` — пустой список; `remove` — `false`, файл не создаётся | `load` — пустой список; `record` создаёт файл |
| не JSON, не объект | `FormatException` | `FormatException` |
| `version` другая или не задана | `FormatException: Unsupported profiles version in <путь>.` | `FormatException: Unsupported recent projects version in <путь>.` |
| нет списка | `Expected a "profiles" list in <путь>.` | `Expected a "projects" list in <путь>.` |
| запись неверного вида | `Invalid profile record in <путь>.` или `Unknown profile type "<тип>" in <путь>.` | `Expected a non-empty "path" in <путь>.` и подобные |

Главное правило: **нечитаемый файл не перезаписывается**. `save`, `remove`, `record` и `merge` сначала читают файл, а чтение бросает исключение до записи. Так хранилище не затирает данные более нового клиента или ручную правку пользователя. Чтобы сбросить файл, его удаляют руками при закрытых клиентах.

Реальные тексты ошибок, полученные на тестовых файлах:

```text
FormatException: Expected a non-empty "path" in ~/.codelab/recent_projects.json.
FormatException: Invalid profile record in ~/.codelab/profiles.json.
FormatException: Unknown profile type "ssh" in ~/.codelab/profiles.json.
```

Что с `FormatException` делает хост, решает он сам. `codelab profiles list` печатает `codelab: Cannot read agent profiles: <причина>` и завершается с кодом `64`. При записи недавнего проекта `codelab` ошибку глотает: код выхода не меняется, а с `--verbose` в stderr выходит строка с типом ошибки без текста (`run.dart`, `_recordRecentProject`) — текст содержит путь.

## `themes/*.json`

Темы читает и импортирует `IoThemeLibrary(home:)` — порт `ThemeLibrary`; JSON в формате темы разбирает `codelab_client_core`, пакет только переносит байты. Правила:

- `list` смотрит только `*.json` прямо в `<home>/themes`; подкаталоги не обходятся, ссылки читаются как файлы. Результат отсортирован по имени.
- Нет каталога — пустой список. Не каталог или не перечисляется — `ThemeCatalogException` (`notADirectory`, `unreadable`).
- Файл читается не больше 64 КиБ + 1 байт (`themeFileMaxBytes`). Сбой чтения одного файла — не исключение, а запись с ошибкой (`tooLarge`, `notUtf8`, `unreadable`).
- `read(name)` принимает только имя по шаблону (`isValidThemeName`) и строит путь из него: `..` и разделители не пройдут.
- `import` копирует файл байт в байт через `writeBytesAtomically`, под именем из поля `name` темы, а не из имени источника. Пересериализация JSON изменила бы файл пользователя.

## Рецепт: добавить JSON-хранилище

Пример: хранилище закреплённых папок `pinned_folders.json`. Порт — в `codelab_client_core`, реализация — здесь.

1. **Проверьте, что оно нужно.** Адаптер оправдан, если файл общий для app и CLI или порт нужен нескольким хостам. Правила списка, лимиты, зарезервированные значения — не здесь, а чистыми функциями в `codelab_client_core`, как `mergeRecentProjects` (AGENTS.md §13, `AGENTS.md` пакета, §2). Если решение меняет контракт продукта, начните с OpenSpec change (AGENTS.md §17).
2. **Объявите порт в `codelab_client_core`.** Это абстрактный интерфейс без `dart:io`; двойник для тестов хоста кладут рядом.
3. **Создайте файл `lib/src/stores/json_file_<имя>_store.dart`.** Скелет:

   ```dart
   import 'package:codelab_client_core/codelab_client_core.dart';

   import 'json_file.dart';

   /// [PinnedFoldersStore] в `$CODELAB_HOME/pinned_folders.json`.
   ///
   /// Почему: список общий у app и CLI, а правила списка живут в kit.
   /// Как использовать: `JsonFilePinnedStore(path)`. Нет файла — пустой
   /// список; файл нечитаем — `FormatException`, и запись файл не меняет.
   final class JsonFilePinnedStore implements PinnedFoldersStore {
     JsonFilePinnedStore(this.path);

     final String path;

     static const _version = 1;

     Future<void> _tail = Future<void>.value();

     @override
     Future<List<String>> load() => _enqueue(_read);

     @override
     Future<void> pin(String folder) => _enqueue(() async {
       final current = await _read();
       if (current.contains(folder)) return;
       await writeJsonObject(path, {
         'version': _version,
         'folders': [...current, folder],
       });
     });

     Future<T> _enqueue<T>(Future<T> Function() operation) {
       final result = _tail.then((_) => operation());
       _tail = result.then<void>((_) {}, onError: (Object _) {});
       return result;
     }

     Future<List<String>> _read() async {
       final json = await readJsonObject(path);
       if (json == null) return const [];
       if (json['version'] != _version) {
         throw FormatException('Unsupported pinned folders version in $path.');
       }
       final folders = json['folders'];
       if (folders is! List<Object?> || folders.any((f) => f is! String)) {
         throw FormatException('Expected a "folders" list of strings in $path.');
       }
       return [for (final f in folders) f! as String];
     }
   }
   ```

   Здесь `PinnedFoldersStore` — порт из шага 2. Очередь `_enqueue` копирует приём `JsonFileRecentProjectsStore`: без неё две правки подряд читают один и тот же файл и теряют одну. Версию и строгое чтение оставьте: так нечитаемый файл не затрётся.
4. **Не пишите секреты.** В файл идут только ссылки (`tokenRef`), значения отдаёт `SecretSource` при открытии.
5. **Экспортируйте класс из `lib/codelab_client_io.dart`.** Файл `json_file.dart` в барель не добавляйте.
6. **Напишите тесты в `test/stores/`** по образцу `json_file_stores_test.dart`: временная папка в `setUp` и её удаление в `tearDown`; нет файла; запись переживает новый экземпляр хранилища; битый файл — `FormatException`, байты на месте; два вызова без `await`.
7. **Подключите в composition root** клиента (`apps/codelab_cli/lib/src/composition_root.dart` или `run.dart`, `apps/codelab_desktop/lib/app/app_scope.dart`). Путь строится от `resolveCodelabHome`. Cubit-ы и виджеты получают порт, а не адаптер.
8. **Добавьте файл в [каталог `CODELAB_HOME`](../../../../docs/ops/codelab-home.md)** и в таблицу этого руководства.
9. **Проверьте.**

   ```bash
   fvm dart format --set-exit-if-changed packages/dart/codelab_client_io
   cd packages/dart/codelab_client_io
   fvm dart analyze
   fvm dart test
   ```

   Если менялись `pubspec.yaml` или импорты между пакетами, добавьте `melos run guard`. Адаптер другого вида (файлы, процессы, сокеты) добавляют теми же шагами, кроме 3: форму задаёт порт, а тест использует настоящие файлы во временной папке или `/bin/sh`.

Скелет проверен: он компилировался с локально объявленным портом и проходил три теста (нет файла, битый файл остаётся нетронутым, запись переживает новый экземпляр).

## Частые проблемы

Тексты ошибок взяты из кода; пути в примерах замаскированы.

### `codelab profiles list` печатает `Cannot read agent profiles`

**Симптом.** `codelab: Cannot read agent profiles: Unsupported profiles version in ~/.codelab/profiles.json.` или `…: Unexpected character`; код выхода `64`.

**Причина.** `JsonFileProfileStore.load` бросил `FormatException`: файл не JSON, версия не `1` или запись неверного вида (таблица выше).

**Что сделать.** Откройте файл и исправьте или удалите его при закрытых клиентах. Хранилище файл не чинит и не перезаписывает.

### `codelab profiles add` и `remove` падают с трассой стека

**Симптом.** При битом `profiles.json` команды `add` и `remove` завершаются кодом `255` и печатают `Unhandled exception: FormatException: …` вместо `Cannot read agent profiles`.

**Причина.** `list` и `show` читают файл через `_load` и превращают исключение в код `64`, а `add` и `remove` вызывают `store.save` и `store.remove` напрямую, и `runCodelab` ловит только `UsageError` и `EmbeddedAgentConfigException` (`apps/codelab_cli/lib/src/profiles/profiles_command.dart`, `run.dart`). Хранилище при этом ведёт себя правильно: файл не меняется. Это замечание к CLI, а не к пакету.

**Что сделать.** Исправьте или удалите файл, как в предыдущем случае.

### Недавние проекты не пополняются

**Симптом.** Папка, открытая в `codelab` или app, не появляется в списке; в `codelab` нет ни ошибки, ни другого кода выхода.

**Причина.** `recent_projects.json` нечитаем или в незнакомом формате: `record` бросает `FormatException` и не пишет. `codelab` ошибку глотает.

**Что сделать.** Запустите `codelab --verbose`: в stderr будет `codelab: cannot record a recent project: FormatException`. Закройте клиенты и удалите файл — он создастся заново.

### В `profiles.json` нет только что сохранённого профиля

**Симптом.** `save` с id `default` или `embedded` бросает `ArgumentError: … the id is reserved for the built-in agent`; `EmbeddedProfile` — `an embedded profile is built in and is not saved`.

**Причина.** Эти имена — встроенный агент. Он в файле не хранится (`reservedProfileIds`, `isReservedProfileId` в `codelab_client_core`).

**Что сделать.** Выберите другой id. Встроенного агента выбирают словом `embedded` или `default`, без записи.

### Одна из недавних записей пропала

**Симптом.** После одновременной работы `codelab` и app нет недавнего проекта.

**Причина.** Между процессами очереди и блокировки нет: последний `rename` побеждает.

**Что сделать.** Ничего: папка вернётся при следующем открытии. Файл остаётся целым.

### `CodelabHomeException`

**Симптом.** `CODELAB_HOME: ~user is not supported, use an absolute path`; `Cannot find the home folder: set CODELAB_HOME or HOME.`

**Причина.** `resolveCodelabHome` не смогла построить путь: значение вида `~user/…`, `~` без `HOME` и `USERPROFILE` или нет ни `CODELAB_HOME`, ни домашнего каталога. Правило — в [каталоге `CODELAB_HOME`](../../../../docs/ops/codelab-home.md#где-лежит-каталог).

**Что сделать.** Задайте `CODELAB_HOME` абсолютным путём. Хост сам решает, как показать ошибку: `codelab` завершается с кодом `64`, app показывает причину на странице.

### Подключение по `ws://` идёт без токена

**Симптом.** Агент по `ws://` отклоняет подключение как неавторизованное, хотя токен задан.

**Причина.** Резолвер читает токен только если у профиля есть `tokenRef`, а в `ioTransportResolver` передан `secrets`. Без одного из двух токена нет.

**Что сделать.** Проверьте `tokenRef` в `profiles.json` и что хост передал `SecretSource`. В `codelab` это `ProfileSecretSource` в `composition_root.dart`.

### `UnsupportedConnectionProfileException`

**Симптом.** Хост не может открыть профиль `embedded`.

**Причина.** `ioTransportResolver` встроенного агента не открывает.

**Что сделать.** Добавьте в `ClientWorkspace(resolvers: …)` резолвер встроенного агента рядом с `ioTransportResolver`, как в `composition_root.dart` терминального клиента.

Сквозной разбор: [настройки на клиенте](../../codelab_client_core/doc/settings-on-client.md).
