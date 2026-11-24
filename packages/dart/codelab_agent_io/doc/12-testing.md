# Тестирование пакета

Глава про то, как тестируется `codelab_agent_io`: что проверяют тесты, как они изолируются от машины разработчика, какие фейки и швы есть, как писать новый тест и какие проверки запускать. Общие уровни тестов репозитория описывает [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md); тесты ядра — [глава 12 ядра](../../codelab_agent_core/doc/12-testing.md).

Нормы: [`testing-quality`](../../../../openspec/specs/testing-quality/spec.md), раздел «Тесты» в [`AGENTS.md` пакета](../AGENTS.md). Код: `test/`.

## Что проверяют тесты

Пакет — слой между ядром и операционной системой, поэтому почти все тесты интеграционные: **настоящие файлы** во временных каталогах и **настоящие процессы** (`/bin/sh`, `chmod`, `ps`). Они идут на Dart VM, входят в `melos run check` и в локальную проверку затронутого. Устройство или симулятор не нужны (ветки `feature/*`, `hotfix/*`).

| Каталог | Файлов | Строк | Что проверяет |
|---|---|---|---|
| `test/cli/` | 15 | около 7500 | подкоманды: тексты, коды выхода, маскирование, ввод секрета |
| `test/config/` | 15 | около 7000 | загрузчик, YAML-профиль, писатель, блокировки, наблюдатель, ссылки, пути PERM-11 |
| `test/secrets/` | 9 | около 4800 | хранилища `env` и `file`, `SecretAdmin`, `SecretMigrator`, `ClientSecretAccess` |
| `test/project/` | 15 | около 4200 | загрузка файлов проекта, навыков, frontmatter, доверие |
| `test/session/` | 10 (8 тестов и 2 помощника) | около 2000 | журнал: контракт, ремонт, сбой процесса, isolate, потомки, журнал расхода |
| `test/mcp/` | 1 | около 400 | stdio-транспорт на настоящих процессах |
| `test/scripted/` | 1 | около 450 | сценарий модели |
| `test/state/` | 1 | около 250 | память последней модели |
| `test/*.dart` | 4 | — | `LocalExecutionEnv` и пути Windows |
| `test/support/` | 6 | — | вспомогательные файлы тестов |

Число тестов и время полного прогона — в [главе 00](00-getting-started.md#тесты-пакета).

## Контрактные наборы ядра

Часть тестов — это общий контракт порта, написанный один раз в ядре и запущенный на реализации пакета:

| Контракт | Файл в ядре | Где запускается |
|---|---|---|
| `ExecutionEnv` | `codelab_agent_core/test/env/execution_env_contract.dart` | `test/local_execution_env_test.dart` на `LocalExecutionEnv` |
| `SessionStore` | `codelab_agent_core/test/session/session_store_contract.dart` | `test/session/jsonl_session_store_test.dart` (`sessionStoreContract`) на `JsonlSessionStore` |

Так файловая реализация ведёт себя так же, как реализация в памяти. Тест импортирует контракт по относительному пути (`import '../../../codelab_agent_core/test/…'`) — допустимое исключение, потому что контракт принадлежит ядру, а не пакету.

## Изоляция

Правила для любого нового теста:

- **Временные каталоги.** `Directory.systemTemp.createTempSync(...)` и `deleteSync(recursive: true)` в `tearDown`. На macOS `/var` — ссылка на `/private/var`, поэтому каталог канонизируется (`resolveSymbolicLinksSync()`): загрузчик и хранилища называют файлы по каноническому пути, и сравнение строк иначе не сойдётся. В `test/session/journal_helpers.dart` для этого `tempRoot`.
- **Окружение — параметром.** `CODELAB_HOME`, `HOME` и остальное передаются словарём; тест не читает настоящий `~/.codelab`. `Platform.environment` внутри тестируемых классов не читается.
- **Время и случайность — швами.** `FakeClock` из `package:codelab_agent_core/testing.dart` вместо часов, `Random` фиксируется там, где важен порядок. Тесты времени (таймауты, завершение дерева процессов) задают пределы «не позже N секунд» с запасом, а не точное время.
- **Секреты — тестовые.** Хранилища секретов работают только во временном `CODELAB_HOME` с тестовыми значениями.
- **Платформа — подменой.** Ветки Windows проверяются параметром `platform: 'windows'` у `ConfigLoader.load`, `openSecretStore`, `SecretCommands`; CI работает на Linux, `taskkill` и права NTFS проверяются вручную.

## Швы и фейки

| Шов | Где | Для чего |
|---|---|---|
| `SecretProcessRunner` | `test/support/fake_secret_process_runner.dart`: `FakeSecretProcessRunner` | записывает вызовы `chmod`, порядок и размер tmp в момент вызова (проверка «права до значения»); `beforeRun`, `skipChmod`, `skipWhen`, `failWhen` имитируют отказ, «успех без эффекта», `EPERM` у не-владельца |
| `SecretInput` | `test/support/fake_secret_input.dart`: `FakeSecretInput` | сценарий `secret set` (терминал или канал, ошибка кодировки, многострочная вставка), журнал обращений `events` |
| `ConfigWriteSeam` | параметр `seam` у `ConfigWriter` и `ConfigEditRunner` | вклиниться между записью tmp и `rename` или после обнаружения устаревшей блокировки |
| harness писателя | `test/support/config_writer_harness.dart`: `ConfigWriterHarness` | временные `CODELAB_HOME` и `cwd`, фейковые часы, генератор, порт `chmod` и писатель одной строкой (`ConfigWriterHarness.create()`, `dispose()`) |
| `DirectoryEventsFactory`, `ConfigFileProbe` | параметры `ConfigWatcher` и `FileConfigSource` | подавать события каталога и состояние файла вручную; в паре с `FakeClock` |
| `FileSync` | параметр `sync` у `JsonlSessionStore` | считать вызовы `fsync` |
| `ProjectFilesLoader.testing` | конструктор | окружение без `PathResolver`, хук `beforeOpen` для подмены файла после проверки |
| `openStore`, `platform`, `processRunner`, `clock`, `random`, `writeSeam` | параметры подкоманд (`@visibleForTesting`) | фейковое хранилище, платформа, процессы |
| `line_echo.dart` | `test/support/line_echo.dart` | дочерний процесс для `stdio_process_transport_test.dart`: команды `env:NAME`, `pwd`, `big:N`, `stderr:N`, `exit:N`; на EOF выходит с кодом 0 |
| `crash_child.dart` | `test/session/crash_child.dart` | дочерний процесс, который тест убивает `SIGKILL` для проверки ремонта |
| `dartExecutable()` | `test/support/dart_executable.dart` | настоящий `dart` для дочерних процессов: под `flutter test` `Platform.resolvedExecutable` — это `flutter_tester`, и он печатает в stdout адрес VM service (так в CI падали тесты stdio MCP) |

Внутренние швы помечены `@visibleForTesting` и `@internal`; рабочий код их не использует. Приватные ветки fail-closed, недостижимые обычным путём, проверяются именно ими: например, окружение без `PathResolver` у `ProjectFilesLoader.testing`.

## Как написать тест

### Загрузчик на временных каталогах

Проверен запуском (`fvm dart test`); имя `test/config/project_layer_test.dart` — для примера.

```dart
import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

const _config = '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
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
      Directory.systemTemp.createTempSync('io_guide_').resolveSymbolicLinksSync(),
    );
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
    File('$home/config.yaml').writeAsStringSync(_config);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('the project layer is read from .codelab', () {
    File('$cwd/.codelab/config.local.yaml')
      ..parent.createSync()
      ..writeAsStringSync('budget:\n  max_steps: 7\n');

    final loaded = ConfigLoader().load(
      cwd: cwd,
      environment: {'CODELAB_HOME': home},
    );

    expect(loaded.issues, isEmpty);
    expect(loaded.sources, hasLength(3));
    expect(loaded.sources.last, endsWith('config.local.yaml'));
  });

  test('a link out of .codelab is refused', () {
    File('${root.path}/outside.yaml').writeAsStringSync('budget: {max_steps: 9}\n');
    Directory('$cwd/.codelab').createSync();
    Link('$cwd/.codelab/config.yaml').createSync('${root.path}/outside.yaml');

    final loaded = ConfigLoader().load(
      cwd: cwd,
      environment: {'CODELAB_HOME': home},
    );

    expect(loaded.config, isNull);
    expect(loaded.issues.single.message, contains('resolves outside'));
  });
}
```

Тест не читает `~/.codelab`, не зависит от окружения и не оставляет файлов. Это образец для любого теста слоя конфигурации.

### Команда на реальном процессе

Образец — `test/local_exec_test.dart`: окружение с `hostEnvironment`, в котором «секретная» переменная; команда `env` показывает, что она не дошла. Ненулевой код выхода — `Ok`; таймаут — `Err(ExecError(timeout))`. Дерево процессов проверяется по маркеру в `ps -A -o args=` (команда `sleep 60.4321`). Проверка по pid и `ps -o stat= -p <pid>` с оговоркой про зомби (после `SIGKILL` запись живёт, пока init её не подберёт) — в `test/mcp/stdio_process_transport_test.dart`.

### Журнал сессии

Используйте `journal_helpers.dart`: `tempRoot`, `storeAt(root, fsync:, sync:)`, `headerOf(id)`, `userRecord(id, parent, text)`, `journalFile(root, id)`. Образец ремонта: записать журнал текстом (оборванная последняя строка), открыть `store.open(id)`, сравнить файл, `.corrupt` и снимок; затем `append` и повторное открытие в новом хранилище.

### Наблюдатель за файлами

Две стратегии:

- **Детерминированная.** `ConfigWatcher` с `DirectoryEventsFactory` и `FakeClock`: тест сам кладёт события в поток и сдвигает время. Так проверяются debounce, фильтр служебных файлов, опрос и containment.
- **Настоящая.** Тесты на настоящем `Directory.watch` (`config_watcher_test.dart`, `file_config_source_test.dart`) ждут сигнал без прогрева. Помощник `rewriteUntil` ([глава 10](10-scripted-model.md#rewriteuntil)) в тестах этого пакета не вызывается: его единственный вызов — `packages/dart/codelab_embedded/test/embedded_config_reload_test.dart`. Событие `config.watch.debounce` отмечает, что debounce запущен.

### Секреты

Хранилище `file` проверяется на реальных правах во временном каталоге (`0644`, ссылки, `$CODELAB_HOME` с записью для группы) на macOS и Linux; `chmod` — на `FakeSecretProcessRunner` или на настоящем `/bin/chmod`. Скрытый ввод — на `FakeSecretInput` (для `SecretCommands`) и на фейковом `Stdin` (для `StdinSecretInput`). Настоящий pty проверяется вручную (задача 8.7 change `add-agent-secret-store`).

## Какие проверки запускать

По разделу «Проверка перед pull request» [`AGENTS.md` репозитория](../../../../AGENTS.md), §21. Локально:

```bash
fvm dart format --set-exit-if-changed <изменённые файлы>
cd packages/dart/codelab_agent_io
fvm dart analyze
fvm dart test
```

Если менялись импорты, `pubspec.yaml` или правила сторожа — `melos run guard`. Если менялся путь встроенного агента или клиентский слой, через который с ним работает CLI, — `melos run conformance:embedded` и `melos run test:e2e:cli:embedded`. Если менялся публичный API пакета — ещё и тесты зависимых пакетов (`apps/codelab_agent`, `codelab_embedded`, `codelab_setup`). Если менялся опубликованный на сайте документ — `cd site && npm ci && npm run verify`.

Правка только в `doc/` кодовых проверок не требует.

## Правила TDD пакета

- Красный тест раньше кода; тест называет требование спецификации или решение `design.md` в комментарии.
- Тесты не зависят от порядка, часов и сети. Время — `FakeClock`, пределы — с запасом.
- Новое поведение `LocalExecutionEnv` проверяется контрактом ядра и на реальных файлах.
- Утечка значений секретов в вывод, исключение или лог проверяется явно: тест ищет значение в тексте и в записях `RecordingLogger`.

## Смотрите также

- [Глава 12 ядра: тестирование агента](../../codelab_agent_core/doc/12-testing.md)
- [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md)
- [Глава 13: частые проблемы](13-troubleshooting.md)
