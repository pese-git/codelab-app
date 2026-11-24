# Расширение клиента: рецепты

Пять типовых задач: слэш-команда, флаг запуска, подкоманда, клавиша TUI, сообщение и команда ядра экрана. Каждый рецепт показывает, какие места затронуть, и содержит скелет кода. Скелеты проверены на этой ветке: временные правки с тестами прошли `fvm dart analyze` и `fvm dart test`, после чего были отменены. Оглавление руководства — [README](README.md).

## Прежде чем писать код

- Изменение, которое меняет поведение продукта, публичный контракт или безопасность, начинается с OpenSpec change (корневой [`AGENTS.md`](../../../AGENTS.md), §17): новый флаг, команда или клавиша — это поведение продукта. Рецепты ниже описывают реализацию, а не решение, нужна ли возможность.
- Читайте ближайший [`AGENTS.md`](../AGENTS.md): он задаёт, где разрешены `dart:io`, мосты и тестовые пакеты. Нарушение поймает `melos run guard`.
- Пишите тест раньше кода и называйте e2e-тест по критерию матрицы (`cli/<id>`), если он доказывает критерий ([глава 09](09-testing.md#имена-тестов--доказательства-матрицы-целей)).
- Комментарии к коду — на русском, по схеме «почему, для чего, как использовать» (корневой `AGENTS.md`, §15). Тексты, которые видит пользователь, в CLI английские (`strings.dart`).
- Документация меняется вместе с кодом: [руководство пользователя](user-guide.md), [эксплуатация](operations.md) и эта глава, если они описывают изменённое.

## Слэш-команда

Сквозной пример с тестом, регистрацией и проверкой в REPL и TUI — [туториал](tutorial-new-command.md). Кратко, что затрагивается:

1. Класс `ReplCommand` в `lib/src/repl/commands/<имя>.dart`: `name`, `usage`, `description`, `run(ReplContext, List<String>)`.
2. Регистрация в `lib/src/repl/commands/commands.dart`: обычная команда добавляется в `mvpReplCommands`; список `replCommands` собирается из него плюс `/provider` и `/settings`. REPL и TUI используют `replCommands`; `/help`, маршрутизатор и Tab берут команды из одного списка, отдельных мест регистрации нет.
3. Всё, что команда печатает, идёт через `context.say(...)`; список выбора — через `context.pick(PickerSpec(...))`; запрос к агенту — через `context.session` и `context.workspace`.
4. Ошибка использования — `throw UsageError('Usage: $usage')`: REPL и TUI напечатают её текстом.

Если команде нужен вывод, который в REPL и TUI выглядит по-разному, добавьте узкий член в `ReplContext` (как `pick` и `showPlan`). Интерфейс реализуют `Repl`, `TuiCommandContext` и два тестовых контекста (`test/repl/commands/narrow_context_test.dart`, `settings_test.dart`): новый член сломает компиляцию всех четырёх, и это нормально.

Команда не должна обращаться к терминалу и клиентскому слою в обход `ReplContext`, а `repl/` не должен зависеть от `tui/`: общие описания выбора живут в `repl/picker_spec.dart` именно поэтому.

## Флаг или режим запуска

Пример: флаг `--no-history`, при котором REPL и TUI не читают и не пишут `cli_history`. Затрагиваются три места: парсер, потребитель, тест.

`lib/src/cli_args.dart`: объявление, поле, заполнение и, если флаг не должен сочетаться с подкомандами записи, `_connectionFlags`.

```dart
// ArgParser _parser(): рядом с `no-color`.
..addFlag(
  'no-history',
  negatable: false,
  help: 'Interactive mode: do not read or write the input history.',
)

// CliOptions: конструктор и поле.
required this.noHistory,
// …
/// `--no-history`: REPL и TUI не читают и не пишут `cli_history`.
final bool noHistory;

// CliOptions _options(…): заполнение из разбора.
noHistory: results.flag('no-history'),

// const _connectionFlags = [ … ]: флаг не применим к config, provider, mcp, secret.
'no-history',
```

Потребитель — `lib/src/run.dart` в `_runRepl` и `_runTui` (в headless история не используется). Хранилище без файла живёт рядом с интерфейсом в `lib/src/input/history.dart`:

```dart
/// Хранилище без файла: `--no-history` не читает и не пишет `cli_history`.
final class NoHistory implements HistoryStore {
  const NoHistory();

  @override
  Future<List<String>> load() async => const [];

  @override
  Future<void> save(List<String> entries) async {}
}
```

```dart
// В _runRepl и _runTui: вместо `HistoryFile(home.historyFile)`.
history: options.noHistory
    ? const NoHistory()
    : HistoryFile(home.historyFile),
```

В `run.dart` понадобится `import 'input/history.dart';`: `NoHistory` определён там, а `HistoryFile` до этого приходил транзитивно. Без импорта анализатор скажет `The name 'NoHistory' isn't a class`.

Тест — в `test/cli_args_test.dart` или рядом:

```dart
test('--no-history is parsed', () {
  expect(parseCliArgs(const ['--no-history']).noHistory, isTrue);
  expect(parseCliArgs(const []).noHistory, isFalse);
});

test('--no-history does not apply to config', () {
  expect(
    () => parseCliArgs(const ['--no-history', 'config', 'check']),
    throwsA(
      isA<UsageError>().having(
        (e) => e.message,
        'message',
        '--no-history does not apply to config check',
      ),
    ),
  );
});
```

Что ещё помнить:

- `--help` печатает список опций из `_parser().usage`: новый флаг появится в нём сам, а текст строки `Usage:` (`cliUsage`) правят только для подкоманд.
- Парсер проверяет сочетания, которые не требуют чтения файлов: взаимоисключающие флаги, флаги, неприменимые к режиму, — через `UsageError` в `parseCliArgs`. Тексты ошибок не должны цитировать значения, если среди них мог быть секрет.
- Режим запуска (новая ветка выбора режима) — это значение `CliCommand` и ветка `switch` в `_run`: компилятор потребует её ([подкоманда](#подкоманда)).
- Новое значение опции со списком допустимых (`allowed`) задавайте перечислением, как `ApprovePolicy` или `UiMode`: `ArgParser` проверит значение сам, а `help` покажет варианты.

## Подкоманда

Пример: `codelab home` печатает `CODELAB_HOME`. Подкоманда без агента проходит три места: `CliCommand`, парсер и `_run`.

`lib/src/cli_args.dart`:

```dart
// enum CliCommand: новое значение.
/// `codelab home`: печатает `CODELAB_HOME`.
home,

// ArgParser _parser(): регистрация подкоманды.
..addCommand('home', ArgParser())

// parseCliArgs: ветка ДО общего случая `profiles`.
if (results.command case final command? when command.name == 'home') {
  if (command.rest.isNotEmpty) {
    throw const UsageError('home takes no arguments');
  }
  return _options(CliCommand.home, results);
}
```

Порядок важен: любая зарегистрированная подкоманда, не имеющая своей ветки, попадает в последнюю ветку `parseCliArgs` и превращается в `CliCommand.profiles`. Подкоманда запишется, но выполнит чужую логику.

`lib/src/run.dart`, в `switch` функции `_run`:

```dart
case CliCommand.home:
  io.stdout.writeln(CodelabHome.resolve(environment).path);
  return okExit;
```

`switch` по `CliCommand` исчерпывающий: пока ветки нет, анализатор не пропустит сборку.

Тест через `runCodelab` и `FakeCliIo`:

```dart
test('codelab home prints CODELAB_HOME and exits with 0', () async {
  final io = FakeCliIo();

  final code = await runCodelab(
    ['home'],
    environment: {'CODELAB_HOME': '/data/codelab'},
    io: io,
  );

  expect(code, 0);
  expect(io.stdoutText, '/data/codelab\n');
  expect(io.stderrText, isEmpty);
});

test('codelab home with an argument is a usage error', () async {
  final io = FakeCliIo();

  final code = await runCodelab(['home', 'x'], environment: {}, io: io);

  expect(code, 64);
  expect(io.stdoutText, isEmpty);
  expect(io.stderrText, contains('home takes no arguments'));
});
```

Дальнейшие решения:

- **Подкоманде, которой нужен агент**, тоже нужен свой `CliCommand` и ветка в `_run`. Её функция получает профиль (`resolveAgentProfile`), собирает `buildCliRuntime` и закрывается в `finally` вместе с сигналами, как `_runHeadless`. Скопируйте его заготовку ([глава 02](02-startup-and-composition.md#заготовка-каждого-режима)).
- **Подкоманда, которая правит конфигурацию агента**, не реализуется в CLI: она делегируется общей команде моста `codelab_setup/io.dart` из `run.dart`, чтобы вывод и байты файлов совпали с `codelab-agent` ([глава 07](07-config-and-setup.md)). Парсинг и листовые подкоманды — в `cli_args.dart`, выполнение — функция `_run<Имя>` в `run.dart`.
- **Флаги подключения** (`--agent`, `-p`, `--ui`, …) к подкоманде записи не применяются: добавьте вызов `_rejectConnectionFlags` по образцу `config`.
- **Файлы `CODELAB_HOME`.** Подкоманда не должна создавать `sessions/`, `profiles.json` и `cli_history`: не вызывайте `CodelabHome.ensureExists`, если не пишете в каталог сами.
- Зарезервированные слова `sessions`, `update`, `login`, `logout`, `trajectory` дают `Unknown command`: если реализуете одну из них, удалите слово из `_laterCommands`.

## Клавиша TUI

Пример: Ctrl+G переключает режим показа мыслей по кругу `dim` → `collapsed` → `hidden` (то же, что `/thoughts`). Цепочка: действие `KeyAction`, привязка, перевод клавиши пакета в наш `Key`, ветка в `reduce`.

1. `lib/src/input/key_decoder.dart`: новая клавиша в `enum Key` (нужна, только если клавиши ещё нет).

   ```dart
   /// Переключить показ мыслей в TUI (`cycleThoughts`).
   ctrlG('Ctrl+G'),
   ```

2. `lib/src/input/key_bindings.dart`: действие в `enum KeyAction` и привязка в `KeyBindings.tui`. Новое значение идёт после `toggleDetails`, у которого `;` в конце списка меняется на `,`: `;` ставится у последнего значения.

   ```dart
   /// Только TUI: следующий режим показа мыслей `dim` → `collapsed` →
   /// `hidden`, как `/thoughts`.
   cycleThoughts('cycle the thoughts display');

   // KeyBindings.tui:
   KeyBinding(KeyScope.any, Key.ctrlG, KeyAction.cycleThoughts),
   ```

3. `lib/src/tui/tui_input.dart`: перевод сочетания пакета в `Key`.

   ```dart
   // _key(): в switch по text.toLowerCase() при ctrl.
   'g' => Key.ctrlG,
   ```

4. `lib/src/tui/core/tui_update.dart`: ветка в `_action`.

   ```dart
   import '../../render/terminal_renderer.dart' show ThoughtsMode;
   // …
   case KeyAction.cycleThoughts:
     final next = ThoughtsMode
         .values[(model.thoughts.index + 1) % ThoughtsMode.values.length];
     return (model.copyWith(thoughts: next), const []);
   ```

5. `lib/src/repl/repl.dart`: `Repl._handle` тоже исчерпывающий `switch` по `KeyAction`. Действие только для TUI добавляется в ветку, которая ничего не делает:

   ```dart
   case KeyAction.scrollUp ||
       KeyAction.scrollDown ||
       KeyAction.follow ||
       KeyAction.toggleTasks ||
       KeyAction.toggleDetails ||
       KeyAction.cycleThoughts:
     return;
   ```

Анализатор не даст забыть пятый шаг и ветку в `_action`: оба `switch` исчерпывающие. Строка подсказок строится из `RegistryKeyMap.hinted`: чтобы клавиша попала в неё, добавьте действие и короткую подпись туда. `/help keys` печатает таблицу из `KeyBindings.tui` само.

Тест ядра:

```dart
test('Ctrl+G cycles the thoughts display', () {
  var model = TuiModel.initial(
    profile: 'embedded',
    size: const TerminalSize(columns: 80, rows: 24),
  );
  final seen = <ThoughtsMode>[];
  for (var i = 0; i < 3; i++) {
    final (next, cmds) = reduce(
      model,
      KeyMsg(const SpecialKey(Key.ctrlG), at: DateTime.utc(2026, 11, 25)),
    );
    expect(cmds, isEmpty);
    model = next;
    seen.add(model.thoughts);
  }

  expect(seen, [ThoughtsMode.collapsed, ThoughtsMode.hidden, ThoughtsMode.dim]);
});

test('/help keys lists Ctrl+G', () {
  expect(KeyBindings.tui.helpLines().join('\n'), contains('Ctrl+G'));
});
```

Что учесть:

- Клавиши REPL и TUI — две таблицы (`KeyBindings.mvp` и `.tui`); действие, привязанное в одной, в другой не работает. Тест `key_bindings_test.dart` проверяет, что `/help keys` содержит подписи всех привязок.
- Если для сочетания нужен новый байт в построчном режиме, его добавляют в таблицу `_controlKeys` декодера `KeyDecoder` (`0x07: Key.ctrlG`) и привязку — в `KeyBindings.mvp`.
- `dart_tui` присылает Ctrl+J как Enter, поэтому Ctrl+J в таблицу TUI не добавляют.
- Клавиши, которые работают в зоне одобрения и в оверлеях, обрабатываются в `_approvalKey` и `overlayKey` отдельно: действие из `_action` туда не попадает.

## Сообщение и команда ядра экрана

Новое событие ядра экрана — подкласс `TuiMsg`, новое действие — подкласс `TuiCmd`. Обе иерархии `sealed`, и компилятор требует разобрать каждый вариант. Пример: сообщение `BellMsg` (кто-то просит позвонить), которое `reduce` превращает в команду `BellCmd`, а адаптер исполняет.

`lib/src/tui/core/tui_msg.dart` и `tui_cmd.dart` (чисто, без пакета и `dart:io`):

```dart
/// Звонок: пример нового сообщения ядра экрана.
final class BellMsg extends TuiMsg {
  const BellMsg();
}

/// Звонок: пример новой команды ядра экрана.
final class BellCmd extends TuiCmd {
  const BellCmd();

  @override
  bool operator ==(Object other) => other is BellCmd;

  @override
  int get hashCode => (BellCmd).hashCode;
}
```

`==` у команды нужен тестам: команды сравниваются по значению.

`lib/src/tui/core/tui_update.dart`, в `switch` функции `reduce`:

```dart
BellMsg() => (model, const [BellCmd()]),
```

`lib/src/tui/tui_effects.dart`, в `_cmd`:

```dart
BellCmd() => () => DomainMsg(const NoteMsg('ding')),
```

Исполнение команды — всегда в адаптере: `Cmd` возвращает сообщение, которое `TuiApp.update` снова отдаст `reduce`. Если действие может бросить исключение, оберните его в `_guarded`: исключение превратится в `EffectFailedMsg`, а не в необработанную ошибку поверх кадра. Сообщение попадает в `reduce` от адаптера: `TuiInput` переводит клавиши и вставку, а `TuiRunner` и `TuiCommandContext` шлют остальное через `program.send(DomainMsg(...))`.

Тест ядра:

```dart
test('BellMsg asks the adapter to ring', () {
  final model = TuiModel.initial(
    profile: 'embedded',
    size: const TerminalSize(columns: 80, rows: 24),
  );

  final (next, cmds) = reduce(model, const BellMsg());

  expect(next, same(model));
  expect(cmds, [const BellCmd()]);
});
```

Без шагов с `reduce` и `_cmd` анализатор сообщает `non_exhaustive_switch_expression` в `tui_update.dart` и `tui_effects.dart`: пропустить ветку нельзя. Если действию нужны сеть, файл или процесс, ядро по-прежнему их не получает: ввод-вывод остаётся в `TuiEffects` или `TuiCommandContext`, а результат возвращается сообщением.

## Чего делать не нужно

- Не импортировать `package:dart_tui/` вне `lib/src/tui/` и `dart:io` в `lib/src/tui/core/`: сторож не пропустит.
- Не импортировать `package:codelab_setup/io.dart` вне `run.dart`, `package:codelab_embedded/io.dart` вне `composition_root.dart`, `package:codelab_acp_testing/` и `codelab_embedded/testing.dart` вне `lib/src/scenario/`.
- Не хранить состояние сессии, очередь и одобрения в CLI: владелец — клиентский слой; режим только отображает `SessionView`.
- Не печатать секреты, значения аргументов stdio-профиля и значения `--agent` без разбора: используйте `describeProfile`, `argumentCount` и фиксированные тексты ([глава 08](08-profiles-and-home.md#что-печатается-о-профиле)).
- Не печатать текст сессии в терминал без `sanitizeTerminalText`.
- Не добавлять `print`: вывод идёт через `CliIo`, `Terminal` и `StringSink` режимов.

## Смотрите также

- [Туториал: новая слэш-команда](tutorial-new-command.md)
- [Глава 09: тестирование](09-testing.md)
- [`AGENTS.md`](../AGENTS.md) приложения
