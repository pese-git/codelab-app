# Расширение пакета: рецепты

Глава собирает типовые правки `codelab_agent_io`. Каждый рецепт называет файлы, порядок шагов и тесты. Скелеты кода проверены: файлы анализировались `fvm dart analyze`, тесты запускались и прошли; временные файлы удалены. Рецепты «до границы пакета» (новый ключ конфигурации, новый инструмент) начинаются в ядре — их описывает [глава 11 ядра](../../codelab_agent_core/doc/11-extending.md).

Перед любой правкой прочитайте [`AGENTS.md` пакета](../AGENTS.md) и найдите спецификацию темы ([список](README.md#спецификации-и-нормы)). Поведение, которое видно пользователю (новая подкоманда, новый файл на диске, новая переменная), требует OpenSpec change (`AGENTS.md` репозитория, §17); правка без смены контракта — прямая. TDD: красный тест сначала.

## Куда идти с задачей

| Задача | Рецепт |
|---|---|
| переменная окружения для существующего ключа конфигурации | [1](#рецепт-переменная-окружения-для-ключа) |
| подкоманда, которая правит конфигурацию | [2](#рецепт-подкоманда-записи-через-configeditrunner) |
| файл состояния, который агент не должен править | [3](#рецепт-защитить-новый-файл-состояния-perm-11) |
| новый бэкенд хранилища секретов | [4](#рецепт-бэкенд-хранилища-секретов) |
| новый каталог Markdown-файлов в `.codelab/` | [5](#рецепт-новый-каталог-markdown-файлов) |
| новое производное состояние на диске (как память модели) | [6](#рецепт-новое-файловое-состояние-агента) |
| новое событие журнала в пакете | [7](#рецепт-новое-событие-журнала) |

## Рецепт: переменная окружения для ключа

**Когда.** У ключа конфигурации уже есть схема в ядре (`schema.dart`, `SettingsRegistry`), и нужна переменная `CODELAB_<ИМЯ>`, которая его задаёт (слой 6).

**Шаги.**

1. Ключ должен существовать в ядре; если нет — начните с [главы 11 ядра](../../codelab_agent_core/doc/11-extending.md).
2. Добавьте строку в таблицу `environmentLayerVariables` (`lib/src/config/environment_layer.dart`): ключ → имя переменной. Таблица — единственный источник и для слоя, и для `config get`, который печатает `<from env:NAME>` вместо значения. Если переменная придёт в слой, но не в таблицу, её значение может попасть в вывод.
3. В `buildEnvironmentLayer` добавьте разбор значения: пустое значение равно отсутствию; нечисловое — проблема вида `type` **без значения переменной** в тексте.
4. Добавьте имя в `_knownVariables` того же файла, иначе `config.env.unknown` назовёт его опечаткой.
5. Если переменная служебная и ключа не имеет (как `CODELAB_HOME`), шаг 2 не нужен — только `_knownVariables`.
6. Обновите [`docs/ops/environment.md`](../../../../docs/ops/environment.md): документ опубликован на сайте и описывает переменные для администратора.

Фрагмент (не самостоятельный файл; `<ключ>` и `<ИМЯ>` — подстановки):

```dart
const environmentLayerVariables = {
  'agent.default_model': 'CODELAB_MODEL',
  // …
  '<ключ>': 'CODELAB_<ИМЯ>', // новая строка
};
```

**Тесты.** `test/config/config_loader_test.dart` (слой и приоритет над файлами), `test/cli/config_get_masking_test.dart` (подпись `<from env:…>`), проверка предупреждения о неизвестной переменной.

## Рецепт: подкоманда записи через `ConfigEditRunner`

**Когда.** Нужна команда вроде `codelab model set <провайдер>/<модель>`: правит один ключ и печатает результат. Общую часть (слой по флагам, повтор при конфликте, перевод исключений в коды выхода) держит `ConfigEditRunner` ([глава 9](09-subcommands.md)); писать её заново не нужно.

**Шаги.**

1. Красный тест в `test/cli/` (скелет ниже).
2. Класс опций и класс команды в `lib/src/cli/<имя>_commands.dart`.
3. Экспорт из `lib/codelab_agent_io.dart` строкой `export … show <Имена>`.
4. Разбор аргументов в приложении: `apps/codelab_agent/lib/src/cli/` и `apps/codelab_cli/lib/src/cli_args.dart`. Эти правки делают инженеры агента и клиента.
5. Мост для клиентов: список `export … show` в `packages/dart/codelab_setup/lib/io.dart` явный, поэтому новые типы туда нужно добавить (клиенты не импортируют `codelab_agent_io`).
6. Тест паритета `codelab` и `codelab-agent` и документ [`apps/codelab_agent/doc/operations.md`](../../../../apps/codelab_agent/doc/operations.md).

**Скелет** (проверен `dart analyze` и тестом ниже; файл `lib/src/cli/model_commands.dart`):

```dart
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'config_commands.dart' show ConfigCommandResult;
import 'config_edit_runner.dart';
import 'exit_codes.dart';

/// Параметры `model set`, уже разобранные приложением.
final class ModelSetOptions {
  const ModelSetOptions({
    required this.model,
    required this.cwd,
    required this.environment,
    this.project = false,
    this.local = false,
  });

  final String model;
  final String cwd;
  final Map<String, String> environment;
  final bool project;
  final bool local;
}

/// Подкоманда `model set <провайдер>/<модель>`: пишет `agent.default_model`.
final class ModelCommands {
  ModelCommands() : _runner = ConfigEditRunner();

  final ConfigEditRunner _runner;

  Future<ConfigCommandResult> set(ModelSetOptions options) async {
    final outcome = await _runner.apply(
      label: 'model set',
      environment: options.environment,
      cwd: options.cwd,
      project: options.project,
      local: options.local,
      edits: (_) => [SetValue('agent.default_model', options.model)],
    );
    return switch (outcome) {
      EditFinished(:final result) => result,
      EditWritten(:final result) => ConfigCommandResult(
        exitCode: configValidExit,
        stdout: [
          'Updated agent.default_model in ${result.path}',
          ...ConfigEditRunner.successLines(result),
        ],
      ),
    };
  }
}
```

Что здесь важно:

- `edits` — функция от снимка слоя: на повторе после конфликта она вызывается со свежим снимком. Правка, зависящая от содержимого файла (удалить прежний источник ключа), строится внутри неё.
- Проверка значения не нужна в команде: писатель проверит итог слоями и ядром. Неверный ключ, неизвестная модель, литеральный секрет вернутся как `EditFinished` с кодом `1`.
- Значение правки не попадает в текст ошибок; не добавляйте его в `stdout`.
- `shortCircuit` нужен, когда писать нечего (как у `unset` отсутствующего ключа).

**Тест** (проверен запуском; кладите в `test/cli/model_commands_test.dart`):

```dart
import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_io/src/cli/model_commands.dart';
import 'package:test/test.dart';

const _config = '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
      n: {}
agent:
  default_model: p/m
''';

void main() {
  late Directory root;
  late String home;
  late String cwd;

  setUp(() {
    // Каталог канонический: на macOS `/var` — ссылка на `/private/var`.
    root = Directory(
      Directory.systemTemp.createTempSync('model_cmd_').resolveSymbolicLinksSync(),
    );
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
    File('$home/config.yaml').writeAsStringSync(_config);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('model set writes agent.default_model', () async {
    final result = await ModelCommands().set(
      ModelSetOptions(model: 'p/n', cwd: cwd, environment: {'CODELAB_HOME': home}),
    );

    expect(result.exitCode, configValidExit);
    expect(File('$home/config.yaml').readAsStringSync(), contains('p/n'));
  });

  test('an unknown model is refused and the file stays', () async {
    final result = await ModelCommands().set(
      ModelSetOptions(model: 'p/zzz', cwd: cwd, environment: {'CODELAB_HOME': home}),
    );

    expect(result.exitCode, configInvalidExit);
    expect(File('$home/config.yaml').readAsStringSync(), _config);
  });
}
```

Во втором тесте `result.stderr` содержит (реальный текст): `~/demo/home/config.yaml:9:3: agent.default_model: p/zzz is not in the model catalog; declare it in providers.p.models`.

## Рецепт: защитить новый файл состояния (PERM-11)

**Когда.** Агент начинает хранить файл или каталог в `$CODELAB_HOME`, который влияет на поведение следующих сессий (как `state/last-model.json`), и инструмент записи не должен его править без человека.

**Шаги.**

1. Добавьте путь в список `files` функции `agentConfigPathsFor` (`lib/src/config/agent_config_paths.dart`). Пути канонизируются там же.
2. Если файл при записи **заменяется через `rename`** (так делает `FileLastModelStore`), добавьте и лексический путь в множество `lexical`: защита только по канонической цели перестанет действовать, когда ссылку заменят обычным файлом.
3. Если по файлу нужна перезагрузка на лету, добавьте его в `watchedConfigFiles`. Правило: наблюдаемое ⊆ защищаемому. Обратное не требуется: `last-model.json` защищён, но не наблюдается.
4. Тест в `test/config/agent_config_paths_test.dart`.

Фрагмент:

```dart
final files = [
  // …
  '$home/state/last-model.json',
  '$home/state',
  '$home/<новый-файл-или-каталог>', // новая строка
];
```

```dart
test('the new path is protected', () {
  final paths = agentConfigPathsFor(
    cwd: '$base/root',
    environment: env(codelabHome: '$base/state'),
  );

  expect(paths.paths, contains('$base/state/<новый-файл-или-каталог>'));
});
```

Как политика использует список — [глава 7 ядра](../../codelab_agent_core/doc/07-permissions.md#правка-конфигурации-агента).

## Рецепт: бэкенд хранилища секретов

**Когда.** Нужно хранилище ОС (keychain) или другое: после 1.0 так появятся бэкенды ОС. Сейчас `secrets.backend: keychain` даёт «not supported yet»; значение резервируется схемой ядра.

**Шаги.**

1. Реализация `DescribedSecretStore` в `lib/src/secrets/`. Правила: значения секретов в исключениях, логах и `toString()` отсутствуют; недоступность — `SecretStoreUnavailableException` с причиной без значения; `delete` идемпотентен; `write` в хранилище «только чтение» бросает `SecretStoreUnavailableException`.
2. Запуск внешних утилит — **только** через `SecretProcessRunner` (абсолютный путь, без оболочки, значение секрета не в argv, а через `stdin`). Порт сейчас возвращает только код выхода; если нужен stdout, добавьте необязательное поле результата, не меняя существующих вызывающих.
3. Выбор бэкенда — в `openSecretStore` (`open_secret_store.dart`) и проверка допустимости — в `secretsBackendProblem`. Проверка одна на загрузчик, `openSecretStore` и подкоманды, поэтому тексты совпадают.
4. Допустимые значения `secrets.backend` задаёт ядро (`schema.dart`): новое значение добавляется там.
5. `auto` не должен выбирать открытое хранилище (CFG-11); ограничения платформы описывайте в `secretsBackendProblem`, а не по месту.
6. Тесты: контракт хранилища и `SecretAdmin` над новым классом, `open_secret_store_test.dart`, `config check`. Документация: настройка агента.

**Скелет** (проверен; пример держит секреты в памяти процесса, `id` для `SecretBackendInfo` — произвольный):

```dart
import 'package:codelab_agent_core/codelab_agent_core.dart';

final class MemoryLikeSecretStore implements DescribedSecretStore {
  final _values = <String, String>{};

  @override
  SecretBackendInfo get backend =>
      const SecretBackendInfo(id: 'memory-demo', writable: true);

  @override
  Future<String?> read(String name) async => _values[name];

  @override
  Future<void> write(String name, String value) async {
    _values[name] = value;
  }

  @override
  Future<void> delete(String name) async {
    _values.remove(name);
  }

  @override
  Future<List<String>> names() async => _values.keys.toList()..sort();
}
```

Тест через `SecretAdmin` (проверен): повторная запись даёт `SecretUpdated`, а `codelab/a.b` после `codelab/a-b` — `SecretCollision`, потому что оба имени дают переменную `CODELAB_SECRET_CODELAB_A_B`.

```dart
final admin = SecretAdmin(store: MemoryLikeSecretStore(), environment: const {});

expect(await admin.store('codelab/gw', 'k1'), isA<SecretStored>());
expect(await admin.store('codelab/gw', 'k2'), isA<SecretUpdated>());
expect(await admin.store('codelab/a-b', 'x'), isA<SecretStored>());
expect(await admin.store('codelab/a.b', 'y'), isA<SecretCollision>());
```

## Рецепт: новый каталог Markdown-файлов

**Когда.** Кроме `prompts/` и `agents/` нужен ещё один каталог файлов с frontmatter (например, `hooks/`), который читают из `$CODELAB_HOME` и из доверенного проекта.

**Шаги.**

1. В ядре: тип разобранного файла и разбор (`parseCommandTemplates`/`parseAgentDefinitions` — образец); поле в `ProjectFiles`.
2. В `ProjectFilesLoader.load` вызовите `_loadMarkdownDirs(query, subdir: '<имя>', noun: '<описание для сообщений>', out: …, diagnostics: …)` по образцу `prompts` и `agents`. Граница, лимиты (100 файлов, 64 КиБ) и диагностика `untrusted_project` наследуются.
3. Если нужен frontmatter «с починкой» (как у навыков) — `readMarkdownFile(repairYaml: true)`; для остальных файлов профиль строгий.
4. Защита PERM-11: добавьте каталог в `agentConfigPathsFor` ([рецепт 3](#рецепт-защитить-новый-файл-состояния-perm-11)).
5. `config check`: диагностика должна печататься общим `_diagnosticLines` — вызовите разбор в `_fileLines`.
6. Тесты по образцу `test/project/prompt_templates_load_test.dart`: доверенный и недоверенный проект, ссылка наружу, превышение лимитов.

## Рецепт: новое файловое состояние агента

**Когда.** Агент хранит небольшое производное состояние (идентификатор, счётчик), которое не настройка и не журнал. Образец — `FileLastModelStore` (`lib/src/state/last_model_file.dart`).

**Правила образца.**

- Порт — в ядре (`LastModelStore`); реализация — здесь.
- Формат: JSON с полем `v`; неизвестные поля игнорируются; чужая версия — отказ чтения.
- Чтение: сначала `stat` (не файл — игнор), предел размера, ограниченное чтение, **без кэша**. Любая беда — `null` и предупреждение с категорией, **без содержимого**; файл не переписывается.
- Запись: `writeQueue.run(путь, …)`, уникальный `tmp` рядом и `rename`. Если файл нужен только производно, `fsync` и блокировка между процессами не нужны.
- Отсутствующий `$CODELAB_HOME` создаётся с `0700` через `SecretProcessRunner`, существующий не трогается.
- Путь входит в `agentConfigPathsFor` ([рецепт 3](#рецепт-защитить-новый-файл-состояния-perm-11)).

Скелет очереди записи по пути (внутри пакета):

```dart
import '../session/write_queue.dart'; // относительный импорт: файл лежит в lib/src/state/

Future<void> write(String path, String content) => writeQueue.run(path, () async {
  // создать каталог, записать tmp, rename
});
```

`writeQueue` общая для процесса: записи одного пути идут по очереди, ошибка одной следующую не отменяет.

## Рецепт: новое событие журнала

Пакет пишет события только там, где у кода есть `Logger`. Подкоманды используют `SilentLogger`, поэтому события добавляются в классы хостов (`ConfigWatcher`, `FileSecretStore`, `JsonlSessionStore`, `StdioProcessTransport`).

1. Имя — `область.подобласть.действие` в нижнем регистре; сверьтесь с [таблицей событий](13-troubleshooting.md#события-журнала-пакета), чтобы не завести дубль.
2. Поля — только пути, имена и категории. **Значений секретов, фрагментов файлов, текста исключения ОС и содержимого переменных окружения в полях нет** (CFG-2, CFG-10). Для ошибки пишите `error.runtimeType`.
3. Уровень: `warning` — состояние, которое человек должен исправить; `info` — выбор или переход; `debug` и `trace` — подробности. stderr внешнего процесса — только `trace`.
4. Событие, которое должно писаться не чаще раза, заведите по образцу `secrets.file.refused` (статическое множество `_refusedPaths`).
5. Тест: `RecordingLogger` и `logger.eventsOf('<событие>')` из `package:codelab_agent_core/testing.dart`; проверьте и поля, и отсутствие значений.
6. Добавьте строку в таблицу [главы 13](13-troubleshooting.md#события-журнала-пакета).

## Чего делать не нужно

- Не добавляйте зависимость в `pubspec.yaml`: allowlist проверяет сторож, расширение — через OpenSpec change.
- Не читайте `Platform.environment` внутри классов: окружение приходит параметром, иначе тест зависит от машины разработчика.
- Не пишите конфигурацию мимо `ConfigWriter` и секреты мимо `FileSecretStore`.
- Не печатайте из подкоманд (`print`): возвращайте строки в результате.
- Не импортируйте `src/` ядра: только публичный барель `package:codelab_agent_core/codelab_agent_core.dart`.

## Смотрите также

- [Глава 11 ядра: расширение ядра](../../codelab_agent_core/doc/11-extending.md)
- [Глава 9: общий слой подкоманд](09-subcommands.md), [глава 12: тестирование](12-testing.md)
