# `codelab-agent`: рецепты

Типовые правки приложения. Каждый рецепт опирается на реальный код: флаг разобран на `--max-steps`, подкоманда — по образцу `secret`, `config`, `provider`, `mcp`. Скелет с `...` — сокращённый намеренно. Скелет подкоманды в разделе «Новая подкоманда» проверен: код в копии приложения прошёл `fvm dart analyze`, а собранная команда напечатала версию (`0.1.0`, код `0`) и на лишнем слове ответила кодом `64`.

Перед правкой прочитайте [`AGENTS.md`](../AGENTS.md) приложения. Изменение поведения, флагов, кодов выхода или публичных контрактов начинается с OpenSpec change (корневой `AGENTS.md`, §17). Поведения агента в приложении нет: если правка про инструменты, цикл хода или разрешения, она в `codelab_agent_*` ([рецепты расширения ядра](../../../packages/dart/codelab_agent_core/doc/11-extending.md)).

## Новый флаг `serve`

Шаги — в [разработке](development.md#как-добавить-флаг-serve). Здесь — как они выглядят в коде на примере флага `--max-steps` (число шагов модели за ход, ключ конфигурации `budget.max_steps`).

1. Опция в `_serveParser` (`lib/src/cli/serve_args.dart`) с англоязычной справкой и именем переменной в скобках:

   ```dart
   ..addOption(
     'max-steps',
     help: 'Model steps per turn, a positive integer (CODELAB_MAX_STEPS).',
   )
   ```

2. Проверка в `parseServeResults`. Ошибка — `UsageError` (код `64`), текст называет флаг и присланное значение, но не секрет:

   ```dart
   final maxStepsText = serve.option('max-steps');
   int? maxSteps;
   if (maxStepsText != null) {
     maxSteps = int.tryParse(maxStepsText);
     if (maxSteps == null || maxSteps < 1) {
       throw UsageError('--max-steps must be a positive integer: $maxStepsText');
     }
   }
   ```

   Если значение может оказаться секретом (токен, заголовок, ключ), его в текст ошибки не включают: пишут только число слов или имя флага.

3. Значение уходит в слой флагов `_flagsLayer`, а не в поле для ядра. Приоритет «флаг сильнее переменной» обеспечивает порядок слоёв загрузчика:

   ```dart
   if (maxSteps != null) {
     values['budget'] = {'max_steps': maxSteps};
   }
   ```

4. Переменная — в таблице `environmentLayerVariables` пакета `codelab_agent_io` (`lib/src/config/environment_layer.dart`): `'budget.max_steps': 'CODELAB_MAX_STEPS'`. Второго пути настройки ядра не создавайте. Нечисловая переменная — проблема конфигурации с кодом `64`, а не ошибка использования.
5. Красный тест до кода (`test/serve_flags_test.dart`): значение доходит до слоя, неверные значения дают `UsageError`, переменная не попадает в слой флагов.

   ```dart
   test('--max-steps goes to budget.max_steps of the flags', () {
     final options = parse([...scripted, '--max-steps', '7']);

     expect(options.flags.values['budget'], {'max_steps': 7});
     expect(parse(scripted).flags.values['budget'], isNull);
   });

   test('--max-steps must be a positive integer', () {
     for (final bad in ['0', '-1', 'abc', '2.5']) {
       expect(
         () => parse([...scripted, '--max-steps', bad]),
         usageError(contains('--max-steps')),
         reason: bad,
       );
     }
   });
   ```

6. Документация: таблица флагов в [эксплуатации](operations.md#флаги-serve), перечень переменных [`docs/ops/environment.md`](../../../docs/ops/environment.md), справка (она строится из `_serveParser.usage`, отдельно её не правят).
7. Если флаг нужен только тестам, как `--llm-script` и `--sessions-dir`, добавьте `hide: true`: справка его не покажет (проверяет `the usage text hides --llm-script and --sessions-dir`).

Если флаг не ключ конфигурации, а параметр запуска (как `--host`, `--port`, `--token-env`), он попадает в поле `ServeOptions`, и тогда тест проверяет поле, а не слой.

## Новая подкоманда

Образец — `secret`, `config`, `provider`, `mcp`: в бинаре только оболочка `package:args`, а тексты, правила и коды выхода живут в общем классе `codelab_agent_io`, чтобы `codelab` печатал то же. Новую команду с логикой пишите сначала в `codelab_agent_io` ([устройство подкоманд](internals.md#подкоманды)); в приложении остаётся тонкий файл. Ниже — скелет самой оболочки на простой команде `version`, которая печатает версию и сервер не запускает (пример выбран для показа структуры).

1. Файл `lib/src/cli/version_cli.dart`: парсер, справка, функция выполнения. Функция принимает `IOSink` для stdout и stderr (тест подставляет свои), возвращает код выхода и не бросает исключений в ожидаемых случаях.

   ```dart
   import 'dart:io';

   import 'package:args/args.dart';

   import '../host/agent_host.dart';
   import '../serve/exit_codes.dart';
   import 'write_cli_support.dart';

   /// Парсер команды `version`: подкоманд и флагов нет.
   final ArgParser versionParser = ArgParser();

   /// Справка команды `version` (в stderr при коде `64`).
   String versionUsage() => 'Usage: codelab-agent version';

   /// Выполняет `codelab-agent version`: печатает версию и возвращает код выхода.
   Future<int> runVersionCommand(
     ArgResults version, {
     required IOSink out,
     required IOSink err,
   }) async {
     if (version.rest.isNotEmpty) {
       // Слова не цитируются: только число, как у остальных команд.
       return usageFailure(
         err,
         'unknown version arguments (${version.rest.length})',
         versionUsage(),
       );
     }
     out.writeln(agentVersion);
     return okExit;
   }
   ```

2. Регистрация в верхнем парсере (`lib/src/cli/serve_args.dart`) и строка в справке `serveUsage()`:

   ```dart
   final ArgParser _parser = ArgParser()
     ..addCommand('serve', _serveParser)
     ...
     ..addCommand('secret', secretParser)
     ..addCommand('version', versionParser);
   ```

   В `serveUsage()` добавьте строку `codelab-agent version`.

3. Маршрутизация в `runCodelabAgent` (`lib/src/run.dart`): ветка выполняется до `parseServeResults`, как у остальных подкоманд, чтобы команда не требовала транспорта и не загружала конфигурацию `serve`:

   ```dart
   if (top.command case final version? when version.name == 'version') {
     return runVersionCommand(version, out: stdout, err: stderr);
   }
   ```

   И строка `'version' => versionUsage()` в `switch` справки при ошибке разбора: справка должна быть справкой той команды, которую начал писать пользователь.

4. Если команда принимает значения, которые могут оказаться секретами, добавьте её имя в `_quietCommandOf` (`lib/src/run.dart`): тогда ошибка разбора argv не процитирует присланные слова. Для `version` это не нужно.
5. Исключения подкоманды ловит `run.dart`: оберните ветку в `try` по образцу `config` (`codelab-agent: <команда> failed: <ТипИсключения>`, код `1`) — текст исключения мог бы цитировать значение.
6. Тесты: разбор и логика — юнит-тестом с подставленными `IOSink` (образец — `config_run_test.dart`, `IOOverrides.runZoned`); код выхода и вывод — процессным тестом (`AgentProcess.start(['version'])`); справка — `serve_flags_test.dart`.
7. Документация: [эксплуатация](operations.md) (раздел «Запуск»), [`docs/user/configuration.md`](../../../docs/user/configuration.md), если команда видна пользователю. В `AGENTS.md` приложения перечисляются подкоманды: его правит владелец правил.

Проверка скелета в копии приложения (команды запускались как `codelab-agent version` и `codelab-agent version x`). Первая напечатала версию и завершилась кодом `0`:

```text
0.1.0
```

Вторая — кодом `64` и текстом в stderr:

```text
codelab-agent: unknown version arguments (1)

Usage: codelab-agent version
```

## Изменить сужение профиля для транспорта

Хост ядра у бинаря один, а транспорты разные: у WebSocket клиент может быть на другой машине. Различия задаёт `narrowing` в `AgentHost.build` (`lib/src/host/agent_host.dart`): набор возможностей, которые транспорт выключает. Профиль можно только сужать (HOST-2), расширить нельзя; список возможностей — [глава 2 руководства по ядру](../../../packages/dart/codelab_agent_core/doc/02-assembly-and-hosts.md#профиль-и-capabilities).

```dart
final narrowing = <HostCapability, CapabilityState>{
  if (!stdio)
    HostCapability.fileListing: const CapabilityOff(
      'WebSocket: клиент может быть не на этой машине',
    ),
  ...
};
```

1. Добавьте запись в `narrowing` с причиной: она попадёт в запись `host.plan` как `off`, и по ней оператор поймёт, почему возможности нет.
2. Если порт ядра тоже надо отключить (как загрузчик файлов проекта у `--ws`), не передавайте его в `AgentCoreServices` для этого транспорта (`projectFiles`, `skillFiles`, `hostFiles`, `projectConfig` у `--ws` равны `null`), и запишите причину событием (`project_files.skipped`).
3. Тест хоста по образцу из [тестирования](testing.md#тест-хоста-в-процессе): `host.plan` содержит возможность в `off`.
4. Обновите таблицу «Различия режимов» в [эксплуатации](operations.md#различия-режимов) и таблицу режимов в [устройстве](internals.md#сборка-хоста-agenthost).

## Новое событие лога

Хост пишет через `Logger` ядра, который реализует `HostLogger`. Имя события — `домен.действие`, поля — словарь без значений секретов, токенов и текстов промптов.

```dart
logger.log(
  LogLevel.warning,
  'serve.ws.non_loopback',
  fields: {'host': options.host},
);
```

1. Выберите уровень: `info` — жизненный цикл, `warning` — подозрительное, но не ошибка, `error` — отказ. `debug` и `trace` оператор включает осознанно.
2. Поля — только то, что безопасно: имя секрета можно, значение, длину и хеш — нельзя; текст исключения, который мог процитировать значение, заменяйте типом (`error.runtimeType`).
3. Добавьте событие в таблицу [логов эксплуатации](operations.md#логи-и-диагностика) и в тест (`log_sinks_test.dart` для приёмников, процессный тест для события `serve`).
4. stdout не используйте: в режиме `--stdio` он несёт кадры ACP.

## Смотрите также

- [Разработка](development.md);
- [устройство](internals.md);
- [тестирование](testing.md);
- [частые проблемы](troubleshooting.md).
