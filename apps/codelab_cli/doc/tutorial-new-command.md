# Туториал: новая слэш-команда `/where`

Сквозной пример: добавляем в `codelab` команду `/where`, которая печатает папку сессии и id профиля подключения. Мы напишем тест, посмотрим, как он падает, реализуем команду, зарегистрируем её, проверим в построчном и в полноэкранном режимах и обновим документацию. Команда простая, зато проходит весь путь, который проходит любая клиентская команда. Туториал дополняет [рецепты](10-extending.md#слэш-команда); устройство REPL — [глава 03](03-repl.md). Оглавление руководства — [README](README.md).

Команда в этом туториале учебная: в репозиторий её добавлять не нужно, а правки, сделанные для снимков, откатываются в конце.

## Что понадобится

- Подготовленный репозиторий ([глава 00](00-getting-started.md#подготовка-репозитория)): `fvm`, `melos bootstrap` и сгенерированный код.
- Каталог `apps/codelab_cli` как рабочий: все команды `fvm dart …` ниже запускаются из него.
- Сеть и провайдер модели не нужны.

## Шаг 1. Как устроена команда

Команда — класс, который реализует `ReplCommand` (`lib/src/repl/repl_command.dart`): `name`, `usage`, `description` и метод `run(ReplContext context, List<String> args)`. Список команд — константа в `lib/src/repl/commands/commands.dart`; `/help`, маршрутизатор и Tab-дополнение берут команды из неё. Из `ReplContext` команда получает всё нужное: `context.cwd`, `context.profile`, `context.session`, `context.say(текст)`.

Посмотрите на самую простую существующую команду — `lib/src/repl/commands/clear.dart`:

```dart
final class ClearCommand implements ReplCommand {
  const ClearCommand();

  @override
  String get name => 'clear';

  @override
  String get usage => '/clear';

  @override
  String get description => 'clear the screen';

  @override
  Future<void> run(ReplContext context, List<String> args) async =>
      context.clearScreen();
}
```

Наша команда будет такой же, только вместо `clearScreen()` она вызовет `say`.

## Шаг 2. Сначала красный тест

Тесты команд используют `ReplHarness` (`test/support/repl_harness.dart`): он запускает настоящий `Repl` на `FakeAgent` и `FakeTerminal`, поэтому тест видит то, что увидел бы пользователь. `repl.line('/where')` вводит строку и нажимает Enter, `waitText` ждёт текст в выводе, `sentMethods` — список методов ACP, которые клиент отправил агенту.

Создайте `test/repl/commands/where_test.dart`:

```dart
// `/where` — сквозной пример руководства разработчика.

import 'package:test/test.dart';

import '../../support/repl_harness.dart';

void main() {
  late ReplHarness repl;

  setUp(() async {
    repl = ReplHarness();
    await repl.start();
  });
  tearDown(() => repl.dispose());

  test('/where prints the session folder and the profile id', () async {
    repl.line('/where');

    await repl.waitText('/work (agent)');
    expect(repl.sentMethods, isNot(contains('session/prompt')));
  });

  test('/where is listed by /help', () async {
    repl.line('/help');

    await repl.waitText('/where');
  });
}
```

Папка `/work` и id `agent` — значения, которые задаёт `ReplHarness` (`cwd: '/work'`, профиль `FakeAgent.profile`). Вторая проверка первого теста важна: команда клиентская, и запроса агенту она отправлять не должна.

Запустите тест:

```bash
fvm dart test test/repl/commands/where_test.dart
```

Тест падает: команды `/where` нет, REPL отвечает `Unknown command /where`. Итог запуска:

```text
Failing tests:
  test/repl/commands/where_test.dart: /where is listed by /help
  test/repl/commands/where_test.dart: /where prints the session folder and the profile id
```

Перед сообщениями об ошибке будут строки `TimeoutException … no "/work (agent)" in:`. Текст «in:» после них неполный: он вычисляется до того, как тест ввёл команду. Ориентируйтесь на название упавших тестов, а полный вывод смотрите флагом `-r expanded` или в самом терминале.

## Шаг 3. Реализация

Создайте `lib/src/repl/commands/where.dart`. Комментарий к классу — на русском и отвечает на три вопроса: почему, для чего, как использовать (корневой [`AGENTS.md`](../../../AGENTS.md), §15). Тексты, которые видит пользователь, — английские, как во всём CLI.

```dart
import '../repl_command.dart';

/// `/where` — папка сессии и профиль агента одной строкой.
///
/// Почему: после `/profile <id>` и `-C` легко потерять, где работает агент;
/// команда отвечает без запроса к агенту.
///
/// Как использовать: подключается в `mvpReplCommands` (`commands.dart`);
/// работает в REPL и в TUI через `ReplContext.say`.
final class WhereCommand implements ReplCommand {
  const WhereCommand();

  @override
  String get name => 'where';

  @override
  String get usage => '/where';

  @override
  String get description => 'show the session folder and the agent profile';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    context.say('${context.cwd} (${context.profile.id})');
  }
}
```

Запустите тест ещё раз. Он по-прежнему красный: команду никто не знает, пока она не зарегистрирована. Это сознательная остановка — класс написан, список ещё нет.

## Шаг 4. Регистрация

Откройте `lib/src/repl/commands/commands.dart`: импорт и одна строка в `mvpReplCommands`. Порядок в списке — порядок строк `/help`; поставим команду после `/reconnect`:

```dart
import 'where.dart';

const List<ReplCommand> mvpReplCommands = [
  // …
  ReconnectCommand(),
  WhereCommand(),
  PlanCommand(),
  // …
];
```

`replCommands` собирается из `mvpReplCommands` плюс `/provider` и `/settings`, поэтому команда попадёт и в REPL, и в TUI: оба режима используют `replCommands`. Запустите тесты команды и `/help`:

```bash
fvm dart test test/repl/commands/where_test.dart test/repl/commands/help_test.dart
```

Они зелёные: `All tests passed!`. Тесты, которые перечисляют команды (`help_test.dart`), проверяют наличие нужных, а не точное совпадение списка, поэтому новая команда их не ломает.

## Шаг 5. Проверка форматирования и анализатора

```bash
fvm dart format --set-exit-if-changed lib/src/repl/commands/where.dart lib/src/repl/commands/commands.dart test/repl/commands/where_test.dart
fvm dart analyze lib test/repl/commands/where_test.dart
```

`Formatted 3 files (0 changed)` и `No issues found!`. Затем весь набор REPL и TUI, чтобы убедиться, что общие тесты (в том числе `/help keys` и TUI) не заметили новую команду:

```bash
fvm dart test test/repl test/tui
```

## Шаг 6. Попробовать в построчном режиме

Запустите `codelab` из исходников под `tmux` (PTY): интерактивному режиму нужен терминал, а `tmux` его даёт. Нужен `CODELAB_HOME` с настроенным провайдером на loopback-адрес ([глава 00](00-getting-started.md#изоляция-codelab_home-и-ключи)).

```bash
tmux -L demo new-session -d -x 120 -y 40 "cd <репозиторий> && CODELAB_HOME=<папка> fvm dart run apps/codelab_cli/bin/codelab.dart -C <папка-проекта>"
tmux -L demo send-keys '/where' Enter
tmux -L demo capture-pane -p
```

```text
> /where
~/projects/demo (embedded)
```

В `/help` команда стоит после `/reconnect`:

```text
  /reconnect                                       reconnect and reload the session
  /where                                           show the session folder and the agent profile
  /plan                                            show the current plan
```

Снимки получены этим запуском; путь папки сессии заменён на `~/projects/demo`. Id профиля — `embedded`: профиль по умолчанию — встроенный агент. Tab-дополнение работает без дополнительных правок: `/wh` и Tab подставят `/where `.

## Шаг 7. Попробовать в полноэкранном режиме

Те же команды работают в TUI без изменений: `TuiRunner` использует тот же `replCommands`, а вывод `say` превращается в заметку в транскрипте (`TuiCommandContext.say` → `NoteMsg`).

```bash
tmux -L demo2 new-session -d -x 120 -y 40 "cd <репозиторий> && CODELAB_HOME=<папка> fvm dart run apps/codelab_cli/bin/codelab.dart -C <папка-проекта> --ui tui"
tmux -L demo2 send-keys '/where' Enter
tmux -L demo2 capture-pane -p
```

```text
> /where
~/projects/demo (embedded)
>
Enter send · Shift+Enter/Alt+Enter new line · Esc/Ctrl+C cancel · PgUp scroll · ctrl+t tasks · ctrl+o details
embedded · standard · local/demo-model
```

В снимке пустые строки сверху опущены, путь заменён на `~/projects/demo`. Строка `> /where` осталась в транскрипте: клиентский слой её не видит, поэтому `reduce` записывает команду заметкой ([глава 04](04-tui.md#reduce)).

Остановите сеансы: `tmux -L demo kill-server`, `tmux -L demo2 kill-server`.

## Шаг 8. Аргументы и ошибки

Команда без аргументов не требует разбора `args`. Если бы она принимала аргумент, ошибку использования оформляли бы так же, как другие команды:

```dart
if (args.length > 1) {
  throw UsageError('Usage: $usage');
}
```

`UsageError` (из `cli_args.dart`) REPL и TUI печатают текстом сообщения; любое другое исключение — строкой `codelab: /where: <причина>`. Подробнее — [глава 03](03-repl.md#replcontext). Для выбора из списка в REPL вместо `say` используют `context.pick(PickerSpec(...))`: REPL напечатает список, а TUI откроет пикер ([`config_option_support.dart`](../lib/src/repl/commands/config_option_support.dart) — образец).

## Шаг 9. Документация

Команда меняет то, что видит пользователь, поэтому документация меняется вместе с кодом:

- таблица команд в [руководстве пользователя](user/02-repl.md#команды-со-слэшем) получает строку `/where`;
- список команд в [главе 03](03-repl.md#реестр-команд) этого руководства — тоже.

Проверка перед pull request — только затронутое (корневой `AGENTS.md`, §21): формат, анализатор и тесты пакета; `melos run guard` не нужен, потому что импорты не менялись.

## Откат

Если вы шли по туториалу ради практики, верните репозиторий в исходное состояние:

```bash
git checkout -- lib/src/repl/commands/commands.dart
rm lib/src/repl/commands/where.dart test/repl/commands/where_test.dart
```

## Что мы использовали

| Понятие | Где посмотреть |
|---|---|
| `ReplCommand`, `ReplContext` | [глава 03](03-repl.md#replcontext) |
| реестр команд | [глава 03](03-repl.md#реестр-команд) |
| `ReplHarness`, `FakeAgent`, `FakeTerminal` | [глава 09](09-testing.md#помощники) |
| одни и те же команды в TUI | [глава 04](04-tui.md#tuicommandcontext) |
| рецепт без туториала | [глава 10](10-extending.md#слэш-команда) |
