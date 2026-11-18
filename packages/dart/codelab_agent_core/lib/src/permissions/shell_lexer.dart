/// Лексер команд инструмента `exec` для критических шаблонов
/// (`agent-core/07-permissions.md` §7.6, правила разбора 1–8).
///
/// Почему: критический шаблон нельзя искать подстрокой — `git commit -m
/// "rm -rf /"` безопасна, а `sh -c 'rm -rf ~'` опасна. Готовые парсеры shell
/// не подходят: allowlist зависимостей PKG-2 закрыт, а нужное подмножество
/// (сегменты, вложенные подстановки, `sh -c`, here-document, лаунчеры,
/// перенаправления) своё (design.md change `add-agent-core-permission-policy`,
/// D6). Код написан для CodeLab, не скопирован из стороннего кода (`AGENTS.md`
/// §5).
///
/// Для чего: превращает строку команды в дерево [ShellScript] — конвейеры,
/// стадии, слова без кавычек и лаунчеров, перенаправления и вложенные
/// команды. Это не интерпретатор: переменные не раскрываются и каталог не
/// ведётся — рабочий каталог команды считает обход `exec_dir_walk.dart` по
/// дереву [ShellScript.commands] (связки, отрицание, блоки) и по
/// происхождению вложенного текста [ShellOrigin] (§7.6.2, change
/// `harden-exec-cwd-tracking`, D2, D6–D8).
///
/// Зарезервированные слова в позиции команды (`if`, `then`, `elif`, `else`,
/// `fi`, `while`, `until`, `do`, `done`, `for`, `select`, `function`, `!`)
/// снимаются, заголовок `for`/`select` командой не считается, `case`
/// неразбираем (D10).
///
/// Как использовать: `parseShell(command)`; ошибка разбора или вложенность
/// глубже [maxShellNesting] дают [ShellParseException], которую
/// `findCritical` превращает в шаблон `unparsable command` (правило 8).
/// Плоские [ShellScript.pipelines] и [ShellScript.allSegments] остаются
/// для правил таблицы §7.6; структуру блоков даёт [ShellScript.commands].
library;

import 'dart:convert';

/// Наибольшая допустимая глубина вложенных команд (§7.6, правило 8).
///
/// Почему: без предела вложенность из подстановок, `sh -c` и `eval` можно
/// сделать сколь угодно глубокой. Верхний уровень — глубина 0; каждая
/// подстановка, аргумент `-c` или `eval` прибавляет единицу.
const maxShellNesting = 4;

/// Наибольшая глубина вложенных блоков `( )`, `{ }`, `if`, циклов (D17, M2).
///
/// Почему: обход блоков рекурсивен, а строка приходит от модели; `{ ` ×10000
/// иначе давало бы `StackOverflowError` вместо `unparsable command`.
const maxShellBlockDepth = 64;

/// Наибольшая вложенность раскрытий `${…}` (D18, C4): разбор рекурсивен.
const _maxExpansionDepth = 64;

/// Команду нельзя разобрать: незакрытая кавычка или подстановка, лишняя `)`,
/// перенаправление без цели или вложенность глубже [maxShellNesting].
///
/// Почему: «лучше спросить, чем пропустить» (§7.6, правило 8) — вызывающий
/// не угадывает смысл сломанной команды, а считает её критической.
///
/// Как использовать: ловить вокруг [parseShell]; [message] — для отладки,
/// пользователю показывается метка `unparsable command`, а не [message].
final class ShellParseException implements Exception {
  /// Создаётся лексером; снаружи не нужна.
  const ShellParseException(this.message);

  /// Причина отказа по-английски, для логов и тестов.
  final String message;

  @override
  String toString() => 'ShellParseException: $message';
}

/// Перенаправление сегмента (§7.6, правило 7).
///
/// Почему: запись на диск, в `/etc/sudoers` или в конфигурацию агента видна
/// только по цели перенаправления, а не по имени команды (`cat x > /dev/sda`).
///
/// Для чего: хранит оператор без номера дескриптора, номер [fd] и цель без
/// кавычек — независимо от того, была цель слитной (`>/dev/sda`) или
/// отдельным словом (`> /dev/sda`).
///
/// Как использовать: правила записи смотрят только на [writes].
final class ShellRedirection {
  /// Создаётся лексером.
  const ShellRedirection(this.operator, this.target, {this.fd});

  /// Оператор: `>`, `>>`, `>|`, `&>`, `&>>`, `>&`, `<`, `<<`, `<<-`, `<<<`,
  /// `<>`, `<&`.
  final String operator;

  /// Цель без кавычек; у here-document — слово-разделитель.
  final String target;

  /// Явный номер дескриптора (`2>`), иначе `null`.
  final int? fd;

  /// Пишет ли перенаправление в файл. `>&1` и `>&-` только дублируют или
  /// закрывают дескриптор, файл не открывают.
  bool get writes {
    if (!operator.contains('>')) {
      return false;
    }
    if (operator == '>&') {
      return !(target == '-' || RegExp(r'^\d+$').hasMatch(target));
    }
    return true;
  }
}

/// Сегмент — простая команда между операторами (§7.6, правило 5).
///
/// Почему: правила таблицы §7.6 применяются к команде, которую shell
/// действительно запустит: без присваиваний `NAME=value` и лаунчеров вроде
/// `sudo -u x` или `timeout 5`, иначе `sudo rm -rf /` выглядел бы как `sudo`.
///
/// Для чего: [words] начинаются с имени запускаемой команды, [privileged]
/// помнит снятый `sudo`/`doas`/`pkexec` или команду `su`, [nested] — все
/// вложенные команды сегмента (подстановки в словах и целях, аргумент `-c`
/// у shell, аргументы `eval`).
///
/// Как использовать: сравнивать [commandName] (базовое имя, правило 6) и
/// [arguments]; вложенные команды обходить через [ShellScript.allSegments].
final class ShellSegment {
  /// Создаётся лексером.
  const ShellSegment({
    required this.words,
    this.redirections = const [],
    this.privileged = false,
    this.nested = const [],
    this.launcherDir,
    this.launcherOutputs = const [],
    this.riskyEnvironment = false,
    this.launcherWords = const [],
    this.commandTextIndex,
    this.launchers = const [],
    this.lookupOnly = false,
    this.commandWordGlob = false,
    this.commandWordSplit = false,
  });

  /// Слова без кавычек, начиная с имени команды; пустой список у сегмента
  /// из одних перенаправлений (`> /dev/null`) или одного `sudo`.
  final List<String> words;

  /// Перенаправления в порядке записи.
  final List<ShellRedirection> redirections;

  /// Сегмент запущен с повышением прав (§7.6, правило 5).
  final bool privileged;

  /// Вложенные команды сегмента.
  final List<ShellScript> nested;

  /// Каталог, в который лаунчер переводит команду: значение `env -C DIR` /
  /// `--chdir`, `sudo -D DIR` / `--chdir`; `null` — лаунчер каталог не
  /// менял. Нужен, чтобы относительные пути команды считались от него
  /// (PERM-11, §7.6.1; R5-4).
  final String? launcherDir;

  /// Файлы, в которые пишет сам лаунчер (`time -o FILE`, `--output FILE`):
  /// это цели записи, а не слова команды (PERM-11, §7.6.1; R5-4).
  final List<String> launcherOutputs;

  /// Среди присваиваний сегмента (`NAME=… cmd`, `env NAME=…`, `export
  /// NAME=…`) есть переменная, подменяющая поведение git так, что итог
  /// неизвестен: `GIT_CONFIG_*`, `GIT_EXEC_PATH`, `GIT_DIR`, `GIT_WORK_TREE`.
  /// Правила PERM-11 считают такой сегмент критичным всегда (fail closed).
  final bool riskyEnvironment;

  /// Слова, снятые с начала сегмента: присваивания (`NAME=… cmd`), `env` с
  /// его опциями и присваиваниями, `sudo`, `time` и прочие лаунчеры (§7.6,
  /// правило 5). Непусто ⇒ команда запущена не напрямую; исключения E1
  /// навыков (D9, Q37) в этом случае не действуют (fail closed).
  final List<String> launcherWords;

  /// Индекс слова в [words], которое `sh -c CMD` исполняет как текст команды
  /// (`null` — не shell или первым идёт файл скрипта). Остальные слова после
  /// него — обычные аргументы (`$0`, `$1`), и путь среди них проверяется как
  /// путь (PERM-11: `bash -c 'rm "$0"' <путь с пробелом>`).
  final int? commandTextIndex;

  /// Имена снятых лаунчеров по порядку (`env`, `sudo`, `time`, `command`,
  /// …); присваивания `NAME=…` и значения опций сюда не входят. Нужны обходу
  /// каталога: `command cd` и `builtin cd` — встроенный `cd`, `time cd`
  /// объединяет состояния, остальные лаунчеры запускают внешнюю программу,
  /// которая каталог оболочки не меняет (change `harden-exec-cwd-tracking`,
  /// D7).
  final List<String> launchers;

  /// Среди снятых `command` есть `-v`/`-V`: команда только ищется и ничего не
  /// исполняет (`command -v cd`, `command -p command -v cd`), каталог не
  /// меняется (D17, A3).
  final bool lookupOnly;

  /// В первом слове команды есть незакавыченные `*?[{`: оболочка раскроет его
  /// в другое слово, имя команды заранее неизвестно (D17, A2). Слова `[` и
  /// `[[` не в счёт.
  final bool commandWordGlob;

  /// Первое слово команды может разбиться на слова при раскрытии: до первой
  /// `/` в нём есть незакавыченное раскрытие, кроме `HOME` и `CODELAB_HOME`
  /// (D17, A2).
  final bool commandWordSplit;

  /// Базовое имя команды (`/bin/rm` → `rm`) или `null` без слов.
  String? get commandName => words.isEmpty ? null : baseName(words.first);

  /// Слова после имени команды.
  List<String> get arguments => words.isEmpty ? const [] : words.sublist(1);
}

/// Конвейер: стадии, соединённые `|` или `|&`.
///
/// Почему: «скачать и выполнить» — это связь стадий одного конвейера
/// (`curl x | sh`), а не свойство одной команды (§7.6, таблица).
final class ShellPipeline {
  /// Создаётся лексером.
  const ShellPipeline(this.stages);

  /// Стадии слева направо.
  final List<ShellSegment> stages;
}

/// Откуда взят текст вложенной команды (change `harden-exec-cwd-tracking`,
/// D8, §7.6.2).
///
/// Почему: каталог, в котором исполнится вложенный текст, зависит от того,
/// кто его исполняет: подоболочка и новый процесс получают копию состояния,
/// `eval` продолжает текущую оболочку, а `git`, `find -execdir` и `trap`
/// запускают его в каталоге, которого обход не знает.
///
/// Для чего: обход `exec_dir_walk.dart` выбирает по значению начальное
/// состояние вложенного обхода и то, выходят ли его смены каталога наружу.
enum ShellOrigin {
  /// Строка команды целиком.
  root,

  /// `$( … )`, `` ` … ` ``, `<( … )`, `>( … )`: подоболочка, наружу ничего
  /// не выходит.
  substitution,

  /// Новый процесс в каталоге родителя: `sh -c`, `env -S`, `watch`,
  /// `script -c`, `find -exec`/`-ok`, `rg --pre`.
  command,

  /// `eval`: текущая оболочка, смены каталога действуют дальше.
  eval,

  /// Каталог исполнения неизвестен: опции и переменные `git`,
  /// переменные-команды (`GIT_PAGER`, `EDITOR`, …), `find -execdir`/`-okdir`,
  /// `trap`.
  foreign,
}

/// Связка конвейера со следующим (D2).
///
/// Почему: `cd X && make` исполняет `make` только после успешного `cd`, а
/// `cd X; make` — всегда; без различия связок либо теряется точность, либо
/// пропускается неудачный `cd` (пример 6 proposal).
enum ShellConnector {
  /// `;`, перевод строки или конец блока.
  sequence,

  /// `&&`: следующий конвейер — после успеха.
  and,

  /// `||`: следующий конвейер — после неуспеха.
  or,

  /// `&`: в фон (подоболочка) уходит весь and-or список, а не последний
  /// конвейер (`A && B &` — `{ A && B; } &`), следующая команда идёт сразу.
  background,
}

/// Вид блока составной команды (D6).
enum ShellBlockKind {
  /// `( … )`: подоболочка.
  subshell,

  /// `{ …; }`: группа в текущей оболочке.
  group,

  /// `if … fi`: условие, `then` и `else` — одна последовательность.
  conditional,

  /// `while`/`until`/`for`/`select … done`.
  loop,

  /// Тело функции: `name() { … }`, `function name { … }`.
  function,
}

/// Стадия конвейера: простая команда или блок.
///
/// Почему sealed: обход обязан разобрать оба вида; новый вид стадии без
/// ветки в обходе — ошибка компиляции, а не пропуск проверки.
sealed class ShellStage {
  const ShellStage();
}

/// Простая команда — стадия-сегмент.
final class ShellSimple extends ShellStage {
  /// Создаётся лексером.
  const ShellSimple(this.segment);

  /// Сегмент.
  final ShellSegment segment;
}

/// Блок составной команды как стадия конвейера (D6).
///
/// Для чего: хранит [body] — команды блока по порядку — и перенаправления,
/// стоящие после закрывающего слова (`done < in.txt`, `} > out`): они
/// относятся к блоку и проверяются в состоянии на выходе (D10).
final class ShellBlock extends ShellStage {
  /// Создаётся лексером.
  ShellBlock(this.kind, this.body, {this.variable});

  /// Переменная цикла `for NAME`/`select NAME`: цикл её записывает (D17, A5).
  final String? variable;

  /// Вид блока.
  final ShellBlockKind kind;

  /// Команды блока.
  final List<ShellCommand> body;

  ShellSegment? _redirections;

  /// Сегмент из одних перенаправлений после закрывающего слова или `null`.
  ShellSegment? get redirections => _redirections;
}

/// Конвейер дерева команд со связкой и отрицанием (D2).
///
/// Почему отдельно от плоского [ShellPipeline]: плоский вид сохранён для
/// правил таблицы §7.6 (`curl … | sh`), а модель каталога нуждается в
/// структуре: какая связка за конвейером, под `!` ли он, какие стадии —
/// блоки.
final class ShellCommand {
  /// Создаётся лексером.
  const ShellCommand(this.stages, {required this.next, required this.negated});

  /// Стадии слева направо.
  final List<ShellStage> stages;

  /// Связка с командой, которая идёт следом; у последней команды уровня —
  /// [ShellConnector.sequence].
  final ShellConnector next;

  /// Перед конвейером стоит `!`.
  final bool negated;
}

/// Разобранная команда или вложенная команда.
///
/// Для чего: корень дерева разбора; [allSegments] и [allPipelines] обходят
/// и вложенные команды, поэтому `echo $(rm -rf /)` проверяется так же, как
/// `rm -rf /`. [commands] — то же дерево со связками и блоками для обхода
/// каталога; сегменты в обоих видах — одни и те же объекты.
///
/// Как использовать: получать из [parseShell].
final class ShellScript {
  /// Создаётся лексером.
  const ShellScript(
    this.pipelines, {
    this.commands = const [],
    this.origin = ShellOrigin.root,
  });

  /// Конвейеры этого уровня в порядке записи; блоки уплощены.
  final List<ShellPipeline> pipelines;

  /// Команды этого уровня со связками, отрицанием и блоками (D2, D6).
  final List<ShellCommand> commands;

  /// Откуда взят текст (D8).
  final ShellOrigin origin;

  /// Сегменты этого уровня без вложенных.
  Iterable<ShellSegment> get segments =>
      pipelines.expand((pipeline) => pipeline.stages);

  /// Все сегменты, включая вложенные, в порядке обхода в глубину.
  Iterable<ShellSegment> get allSegments sync* {
    for (final segment in segments) {
      yield segment;
      for (final script in segment.nested) {
        yield* script.allSegments;
      }
    }
  }

  /// Все конвейеры, включая вложенные.
  Iterable<ShellPipeline> get allPipelines sync* {
    for (final pipeline in pipelines) {
      yield pipeline;
      for (final stage in pipeline.stages) {
        for (final script in stage.nested) {
          yield* script.allPipelines;
        }
      }
    }
  }
}

/// Разбирает [command] по правилам §7.6.
///
/// Как использовать: вызывает `findCritical`; бросает [ShellParseException]
/// на сломанной команде и вложенности глубже [maxShellNesting].
ShellScript parseShell(String command) => _Lexer(command).parse(0);

/// Базовое имя пути (`/usr/bin/sudo` → `sudo`); правило 6 §7.6.
String baseName(String path) {
  var p = path;
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  final i = p.lastIndexOf('/');
  return i < 0 || p.length == 1 ? p : p.substring(i + 1);
}

/// Shell, у которых аргумент после `-c` — команда (§7.6, правило 3).
const shellNames = {'sh', 'bash', 'zsh', 'dash', 'ksh'};

/// Слово-присваивание: `NAME=`, `NAME+=`, `NAME[i]=`, `NAME[i]+=` (D17, A5).
///
/// Почему шире `NAME=`: `a+=1 rm -rf /` и `a[0]=x cmd` — те же префиксные
/// присваивания, иначе слово `a+=1` читалось бы как имя команды.
final assignmentWord = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=');

/// Имя переменной в слове-присваивании или операнде (`GIT_EDITOR+=x` →
/// `GIT_EDITOR`).
final variableNamePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*');
final _redirect = RegExp(r'(\d*)(&>>|&>|>>|>\||>&|>|<<<|<<-|<<|<>|<&|<)');

/// Слово до снятия кавычек вместе с вложенными командами из него.
final class _Word {
  _Word(
    this.value, {
    required this.quoted,
    required this.nested,
    this.glob = false,
    this.splitRisk = false,
  });

  /// До первой литеральной `/` есть незакавыченное раскрытие, кроме `$HOME`,
  /// `${HOME}`, `$CODELAB_HOME`, `${CODELAB_HOME}`: значение с пробелом
  /// разобьётся на слова, и слово может оказаться `cd` (D17, A2).
  final bool splitRisk;

  /// В слове есть незакавыченные `*`, `?`, `[` или `{`: оболочка раскроет его
  /// в другие слова, и имя команды заранее неизвестно (D17, A2).
  final bool glob;

  final String value;

  /// Было ли в слове экранирование или кавычки: `"{"` — не группа.
  final bool quoted;
  final List<ShellScript> nested;
}

/// Посимвольный разбор одной строки команды.
///
/// Почему отдельный экземпляр на строку: аргумент `sh -c`, `eval` и
/// обратные кавычки разбираются как новая строка со своей позицией, а
/// подстановка `$( … )` — рекурсией того же экземпляра до парной `)`.
final class _Lexer {
  _Lexer(this.src);

  final String src;
  int pos = 0;

  /// Here-document, тела которых начинаются со следующего перевода строки.
  final _heredocs = <({String delimiter, bool stripTabs})>[];

  ShellScript parse(int depth, {ShellOrigin origin = ShellOrigin.root}) =>
      _script(depth, nested: false, origin: origin);

  ShellScript _script(
    int depth, {
    required bool nested,
    ShellOrigin origin = ShellOrigin.root,
  }) {
    if (depth > maxShellNesting) {
      throw const ShellParseException(
        'nesting is deeper than $maxShellNesting',
      );
    }
    final builder = _ScriptBuilder(depth, origin);
    while (true) {
      _skipBlanks();
      if (pos >= src.length) {
        if (nested) {
          throw const ShellParseException('unclosed command substitution');
        }
        return builder.finish();
      }
      final c = src[pos];
      if (c == '#') {
        _skipComment();
      } else if (c == '\n') {
        pos++;
        builder.endPipeline(ShellConnector.sequence);
        _skipHeredocBodies();
      } else if (c == ')') {
        pos++;
        if (builder.insideBlock) {
          // `(a; b) | c`: конец подоболочки завершает стадию, но не конвейер.
          builder.closeBlock(')');
        } else if (nested) {
          return builder.finish();
        } else {
          throw const ShellParseException('unexpected )');
        }
      } else if (c == '(') {
        pos++;
        _openParen(builder);
      } else if (_at('&&')) {
        pos += 2;
        builder.endPipeline(ShellConnector.and);
      } else if (_at('||')) {
        pos += 2;
        builder.endPipeline(ShellConnector.or);
      } else if (_at('|&')) {
        pos += 2;
        builder.pipe();
      } else if (c == '|') {
        pos++;
        builder.pipe();
      } else if (c == ';') {
        // `;;`, `;&` и `;;&` — разделители веток `case`.
        pos++;
        while (pos < src.length && (src[pos] == ';' || src[pos] == '&')) {
          pos++;
        }
        builder.endPipeline(ShellConnector.sequence);
      } else if (_redirectAt() case final match?) {
        _readRedirection(match, depth, builder);
      } else if (c == '&') {
        pos++;
        builder.endPipeline(ShellConnector.background);
      } else {
        builder.addWord(_readWord(depth));
      }
    }
  }

  /// Скобка `(` после пробелов: определение функции `f()`, подоболочка или
  /// `for ((`, которую разобрать нельзя.
  ///
  /// Почему здесь: решение зависит от следующего символа (`)` сразу за `(`
  /// — пустые скобки определения), а не только от состояния построителя.
  void _openParen(_ScriptBuilder builder) {
    if (builder.inHeader) {
      // Арифметический `for ((i=0; i<n; i++))` содержит `;`, которые
      // оборвали бы заголовок: fail closed (D10).
      throw const ShellParseException('arithmetic for is not supported');
    }
    final closes = _nextNonBlankIs(')');
    if (!builder.segmentIsEmpty) {
      if (builder.canBeFunctionName && closes) {
        // `f ( )`: имя функции — слово перед скобками; в дереве его нет.
        pos = src.indexOf(')', pos) + 1;
        builder.beginFunction();
        return;
      }
      builder.endPipeline(ShellConnector.sequence);
    }
    if (builder.pendingFunction && closes) {
      // `function f()`: пустые скобки после имени.
      pos = src.indexOf(')', pos) + 1;
      return;
    }
    builder.openBlock(ShellBlockKind.subshell, ')');
  }

  bool _nextNonBlankIs(String char) {
    var i = pos;
    while (i < src.length && (src[i] == ' ' || src[i] == '\t')) {
      i++;
    }
    return i < src.length && src[i] == char;
  }

  bool _at(String s) => src.startsWith(s, pos);

  void _skipBlanks() {
    while (pos < src.length) {
      final c = src[pos];
      if (c == ' ' || c == '\t' || c == '\r') {
        pos++;
      } else if (c == '\\' && pos + 1 < src.length && src[pos + 1] == '\n') {
        pos += 2;
      } else {
        return;
      }
    }
  }

  void _skipComment() {
    final end = src.indexOf('\n', pos);
    pos = end < 0 ? src.length : end;
  }

  /// Пропускает тела here-document: строки до разделителя — данные, а не
  /// команды (правило 4). Без разделителя тело длится до конца строки
  /// команды, как и в shell.
  void _skipHeredocBodies() {
    for (final heredoc in _heredocs) {
      while (pos < src.length) {
        final end = src.indexOf('\n', pos);
        final line = src.substring(pos, end < 0 ? src.length : end);
        pos = end < 0 ? src.length : end + 1;
        final text = heredoc.stripTabs
            ? line.replaceFirst(RegExp('^\t+'), '')
            : line;
        if (text == heredoc.delimiter) {
          break;
        }
      }
    }
    _heredocs.clear();
  }

  /// Оператор перенаправления в текущей позиции. `<(` и `>(` — подстановки
  /// процесса, они читаются как слово.
  Match? _redirectAt() {
    final match = _redirect.matchAsPrefix(src, pos);
    if (match == null) {
      return null;
    }
    final op = match[2]!;
    if ((op == '<' || op == '>') &&
        match.end < src.length &&
        src[match.end] == '(') {
      return null;
    }
    return match;
  }

  void _readRedirection(Match match, int depth, _ScriptBuilder builder) {
    pos = match.end;
    final op = match[2]!;
    _skipBlanks();
    if (pos >= src.length || _isMeta(src[pos]) && !_atProcessSubstitution()) {
      throw ShellParseException('missing target of $op');
    }
    final word = _readWord(depth);
    if (op == '<<' || op == '<<-') {
      _heredocs.add((delimiter: word.value, stripTabs: op == '<<-'));
    }
    final fd = match[1]!;
    builder.addRedirection(
      ShellRedirection(op, word.value, fd: fd.isEmpty ? null : int.parse(fd)),
      word.nested,
    );
  }

  bool _atProcessSubstitution() =>
      (_at('<(') || _at('>(')) && pos + 1 < src.length;

  static bool _isMeta(String c) =>
      c == ' ' ||
      c == '\t' ||
      c == '\r' ||
      c == '\n' ||
      c == ';' ||
      c == '&' ||
      c == '|' ||
      c == '(' ||
      c == ')' ||
      c == '<' ||
      c == '>';

  _Word _readWord(int depth) {
    final buffer = StringBuffer();
    final nested = <ShellScript>[];
    final start = pos;
    var quoted = false;
    var glob = false;
    var slashSeen = false;
    var splitRisk = false;
    while (pos < src.length) {
      final c = src[pos];
      if (c == '\\') {
        if (pos + 1 >= src.length) {
          pos++;
          break;
        }
        final next = src[pos + 1];
        pos += 2;
        if (next != '\n') {
          buffer.write(next);
          quoted = true;
        }
      } else if (c == "'") {
        final end = src.indexOf("'", pos + 1);
        if (end < 0) {
          throw const ShellParseException('unclosed single quote');
        }
        buffer.write(src.substring(pos + 1, end));
        pos = end + 1;
        quoted = true;
      } else if (c == '"') {
        _readDoubleQuoted(buffer, nested, depth);
        quoted = true;
      } else if (c == r'$' && pos + 1 < src.length && src[pos + 1] == "'") {
        _readAnsiC(buffer);
        quoted = true;
      } else if (c == r'$' && pos + 1 < src.length && src[pos + 1] == '"') {
        // `$"…"` — локализуемая строка bash: без каталога перевода она
        // равна `"…"`, поэтому `$` перед кавычкой пропускается.
        pos++;
      } else if (c == r'$') {
        // Хост знает значения `HOME` и `CODELAB_HOME`, слов в них нет.
        if (!slashSeen && _hostVariable.matchAsPrefix(src, pos) == null) {
          splitRisk = true;
        }
        _readDollar(buffer, nested, depth);
      } else if (c == '`') {
        splitRisk = splitRisk || !slashSeen;
        _readBackticks(buffer, nested, depth);
      } else if (pos == start && _atProcessSubstitution()) {
        pos += 2;
        nested.add(
          _script(depth + 1, nested: true, origin: ShellOrigin.substitution),
        );
        buffer.write(src.substring(start, pos));
      } else if (_isMeta(c)) {
        break;
      } else {
        if (c == '*' || c == '?' || c == '[' || c == '{') {
          glob = true;
        }
        slashSeen = slashSeen || c == '/';
        buffer.write(c);
        pos++;
      }
    }
    return _Word(
      buffer.toString(),
      quoted: quoted,
      nested: nested,
      glob: glob,
      splitRisk: splitRisk,
    );
  }

  /// ANSI-C строка `$'…'`: escape-последовательности (`\n`, `\t`, `\xHH`,
  /// `\NNN`, `\uHHHH`, `\cX`, …) раскрываются, остальное — данные.
  ///
  /// Почему: иначе `rm -rf $'\x2f'` скрывает цель от критических шаблонов
  /// (слово читалось бы как `$\x2f`), а `$'rm\n-rf'` разваливало бы аргументы
  /// (`env -S $'rm\n-rf …'`; PERM-11, §7.6.1). Подстановки внутри не
  /// выполняются.
  ///
  /// Для чего: возвращает в [buffer] то, что увидит программа. Байтовые
  /// escape (`\xHH`, `\NNN`, код `& 0xFF`) собираются в байты и декодируются
  /// как UTF-8, невалидная последовательность — [ShellParseException].
  /// Как и bash,
  /// символ с кодом 0 (`\0`, `\x00`, `\u0000`, `\c@`) обрывает остаток
  /// строки до закрывающей `'`, а слово после кавычки склеивается с тем, что
  /// было до обрыва (`$'r\0zz'm` — это `rm`). Код выше 0x10FFFF и `\c` перед
  /// кавычкой или обратной чертой неоднозначны — [ShellParseException]
  /// (fail closed, правило 8 §7.6).
  ///
  /// Расхождение с bash 3.2 (`/bin/sh` на macOS): он не знает `\u` и `\U` и
  /// оставляет их буквально, а мы раскрываем. Это расхождение в сторону
  /// ложных срабатываний, поэтому допустимо.
  void _readAnsiC(StringBuffer buffer) {
    pos += 2;
    const simple = {
      'n': '\n', 't': '\t', 'r': '\r', 'v': '\v', 'f': '\f', 'a': '\x07', //
      'b': '\b', 'e': '\x1b', 'E': '\x1b', '\\': '\\', "'": "'", '"': '"',
      '?': '?',
    };
    // После NUL символы разбираются (чтобы найти закрывающую `'`), но
    // в слово не попадают.
    var discard = false;
    // Подряд идущие байтовые escape (`\xHH`, `\NNN`) копятся как байты и
    // декодируются как UTF-8 на границе: bash отдаёт программе сырые байты,
    // и путь с кириллицей, записанный `\320\241…`, должен совпасть с
    // защищаемым, а не превратиться в символы Latin-1.
    final pending = <int>[];
    void flush() {
      if (pending.isNotEmpty) {
        // Невалидный UTF-8 — fail closed: bash склеивает байты соседних
        // `$'…'` (`$'\320'$'\241'` — одна `С`), а мы декодируем каждую часть
        // отдельно, и половинки защищаемого пути с кириллицей стали бы
        // U+FFFD и ускользнули бы от правил. Цена: `echo $'\xff'` требует
        // подтверждения (правило 8 §7.6, PERM-11, §7.6.1).
        try {
          buffer.write(utf8.decode(pending));
        } on FormatException {
          throw const ShellParseException('invalid UTF-8 in ANSI-C quote');
        }
        pending.clear();
      }
    }

    void emitByte(int byte) {
      if (byte == 0) {
        flush();
        discard = true;
      } else if (!discard) {
        pending.add(byte);
      }
    }

    void emitChar(int code) {
      if (code == 0) {
        flush();
        discard = true;
      } else if (!discard) {
        if (code > 0x10FFFF) {
          throw const ShellParseException('code point is out of range');
        }
        flush();
        buffer.writeCharCode(code);
      }
    }

    while (true) {
      if (pos >= src.length) {
        throw const ShellParseException('unclosed ANSI-C quote');
      }
      final c = src[pos++];
      if (c == "'") {
        flush();
        return;
      }
      if (c != '\\') {
        if (!discard) {
          flush();
          buffer.write(c);
        }
        continue;
      }
      if (pos >= src.length) {
        throw const ShellParseException('unclosed ANSI-C quote');
      }
      final n = src[pos++];
      final plain = simple[n];
      if (plain != null) {
        emitChar(plain.codeUnitAt(0));
        continue;
      }
      if (n == 'c') {
        // `\cX` — управляющий символ `X & 0x1f` (`\c@` — NUL).
        if (pos >= src.length || src[pos] == "'" || src[pos] == '\\') {
          throw const ShellParseException('ambiguous \\c in ANSI-C quote');
        }
        emitChar(src.codeUnitAt(pos++) & 0x1f);
        continue;
      }
      final digits = switch (n) {
        'x' => 2,
        'u' => 4,
        'U' => 8,
        _ => n.codeUnitAt(0) >= 0x30 && n.codeUnitAt(0) <= 0x37 ? 2 : 0,
      };
      final radix = n == 'x' || n == 'u' || n == 'U' ? 16 : 8;
      var j = pos;
      while (j < src.length &&
          j - pos < digits &&
          int.tryParse(src[j], radix: radix) != null) {
        j++;
      }
      final text = (radix == 8 ? n : '') + src.substring(pos, j);
      final code = int.tryParse(text, radix: radix);
      if (code == null) {
        // Неизвестный escape остаётся как есть, как в bash.
        if (!discard) {
          flush();
          buffer
            ..write('\\')
            ..write(n);
        }
      } else {
        pos = j;
        if (n == 'u' || n == 'U') {
          emitChar(code);
        } else {
          // `\xHH` и `\NNN` — байт; восьмеричный код усекается `& 0xFF`
          // (`\400` — NUL, `\562` — `r`), как в bash.
          emitByte(code & 0xFF);
        }
      }
    }
  }

  /// Двойные кавычки: `\` экранирует только `$`, `` ` ``, `"`, `\` и
  /// перевод строки; подстановки внутри остаются командами (правило 2).
  void _readDoubleQuoted(
    StringBuffer buffer,
    List<ShellScript> nested,
    int depth,
  ) {
    pos++;
    while (true) {
      if (pos >= src.length) {
        throw const ShellParseException('unclosed double quote');
      }
      final c = src[pos];
      if (c == '"') {
        pos++;
        return;
      }
      if (c == '\\' && pos + 1 < src.length) {
        final next = src[pos + 1];
        if (r'$`"\'.contains(next) || next == '\n') {
          if (next != '\n') {
            buffer.write(next);
          }
          pos += 2;
          continue;
        }
        buffer.write(c);
        pos++;
      } else if (c == r'$') {
        _readDollar(buffer, nested, depth, inQuotes: true);
      } else if (c == '`') {
        _readBackticks(buffer, nested, depth);
      } else {
        buffer.write(c);
        pos++;
      }
    }
  }

  /// `$( … )` — вложенная команда; `${ … }` и `$(( … ))` — раскрытия, внутри
  /// которых тоже исполняются подстановки (`${x:-$(rm -rf /)}`,
  /// `$(( $(rm -rf /) 0 ))`). Переменные не раскрываются, текст остаётся в
  /// слове как есть (change `harden-exec-cwd-tracking`, N1).
  ///
  /// [inQuotes] — вызов из двойных кавычек: там `${…}` с одинарной кавычкой
  /// или `$'…'` внутри bash и dash читают по-разному, поэтому разбор отказывает
  /// (D18, C2).
  void _readDollar(
    StringBuffer buffer,
    List<ShellScript> nested,
    int depth, {
    bool inQuotes = false,
  }) {
    final start = pos;
    if (_at(r'$((')) {
      final end = _arithmeticEnd();
      if (end > 0) {
        pos = end;
      } else {
        // Не арифметика: `$((rm -rf /) )` оболочка читает как `$( (…) )` —
        // подстановку с подоболочкой. Тело разбирается как команда.
        pos += 2;
        nested.add(
          _script(depth + 1, nested: true, origin: ShellOrigin.substitution),
        );
      }
    } else if (_at(r'$(')) {
      pos += 2;
      nested.add(
        _script(depth + 1, nested: true, origin: ShellOrigin.substitution),
      );
    } else if (_at(r'${')) {
      _readBraced(nested, depth, inQuotes: inQuotes);
    } else {
      pos++;
    }
    buffer.write(src.substring(start, pos));
  }

  /// Индекс после `))`, если `$((` — арифметика без подстановок внутри, иначе
  /// `-1`: тогда тело разбирается как команда.
  ///
  /// Почему: арифметика внутри исполняет `$(…)` и обратные кавычки, а при
  /// несмежных `) )` оболочка вообще читает скобки как подстановку с
  /// подоболочкой; любое сомнение — путь «команда» (fail closed).
  int _arithmeticEnd() {
    var depth = 2;
    for (var i = pos + 3; i < src.length; i++) {
      final c = src[i];
      // Подстановки, кавычки, `\`, `${` и `#` внутри арифметики: оболочки
      // читают их по-разному, любое сомнение — путь «команда» (D18, C3).
      if (c == '`' ||
          c == "'" ||
          c == '"' ||
          c == '\\' ||
          c == '#' ||
          c == r'$' && i + 1 < src.length && '({'.contains(src[i + 1])) {
        return -1;
      }
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 1) {
          return i + 1 < src.length && src[i + 1] == ')' ? i + 2 : -1;
        }
      }
    }
    return -1;
  }

  /// `${ … }` с учётом `\}`, кавычек и вложенных подстановок: `}` внутри
  /// кавычек или после `\` тело не закрывает, а `$(…)`, `` `…` `` и `${…}`
  /// внутри разбираются (N1).
  ///
  /// Вложенность раскрытий ограничена [_maxExpansionDepth] (D18, C4); `$'…'`
  /// разбирается как ANSI-C строка (C1); в двойных кавычках ([inQuotes])
  /// одинарная кавычка и `$'` — ошибка разбора (C2).
  void _readBraced(
    List<ShellScript> nested,
    int depth, {
    required bool inQuotes,
  }) {
    if (++_expansionDepth > _maxExpansionDepth) {
      throw const ShellParseException('expansions are nested too deeply');
    }
    try {
      _readBracedBody(nested, depth, inQuotes: inQuotes);
    } finally {
      _expansionDepth--;
    }
  }

  var _expansionDepth = 0;

  void _readBracedBody(
    List<ShellScript> nested,
    int depth, {
    required bool inQuotes,
  }) {
    pos += 2;
    final sink = StringBuffer();
    while (true) {
      if (pos >= src.length) {
        throw const ShellParseException('unclosed parameter expansion');
      }
      final c = src[pos];
      if (c == '}') {
        pos++;
        return;
      }
      if (c == '\\') {
        pos += 2;
      } else if (c == "'") {
        if (inQuotes) {
          throw const ShellParseException('quote in a quoted expansion');
        }
        final end = src.indexOf("'", pos + 1);
        if (end < 0) {
          throw const ShellParseException('unclosed single quote');
        }
        pos = end + 1;
      } else if (c == '"') {
        _readDoubleQuoted(sink, nested, depth);
      } else if (c == r'$' && _at(r"$'")) {
        if (inQuotes) {
          throw const ShellParseException('ANSI-C quote in a quoted expansion');
        }
        _readAnsiC(sink);
      } else if (c == r'$' && _at(r'$"')) {
        pos++;
      } else if (c == r'$') {
        _readDollar(sink, nested, depth, inQuotes: inQuotes);
      } else if (c == '`') {
        _readBackticks(sink, nested, depth);
      } else {
        pos++;
      }
    }
  }

  /// Обратные кавычки: тело без экранирования `` \` ``, `\$`, `\\`
  /// разбирается как отдельная строка на глубину больше.
  void _readBackticks(
    StringBuffer buffer,
    List<ShellScript> nested,
    int depth,
  ) {
    final start = pos;
    pos++;
    final inner = StringBuffer();
    while (true) {
      if (pos >= src.length) {
        throw const ShellParseException('unclosed backquote');
      }
      final c = src[pos];
      if (c == '\\' && pos + 1 < src.length && r'`$\'.contains(src[pos + 1])) {
        inner.write(src[pos + 1]);
        pos += 2;
      } else if (c == '`') {
        pos++;
        break;
      } else {
        inner.write(c);
        pos++;
      }
    }
    nested.add(
      _Lexer(
        inner.toString(),
      ).parse(depth + 1, origin: ShellOrigin.substitution),
    );
    buffer.write(src.substring(start, pos));
  }
}

/// Кадр открытого блока: команды, собранные внутри него.
///
/// Почему: дерево [ShellScript.commands] строится тем же проходом, что и
/// плоские конвейеры, а блок закрывается только парным словом (`)`, `}`,
/// `fi`, `done`), поэтому открытые блоки лежат в стеке (D6).
final class _Frame {
  _Frame(this.kind, this.closer);

  /// Вид блока; `null` у корня.
  final ShellBlockKind? kind;

  /// Слово, которым блок закрывается: `)`, `}`, `fi`, `done`.
  final String closer;

  final commands = <ShellCommand>[];

  /// Стадии конвейера, который собирается сейчас.
  var stages = <ShellStage>[];

  /// Перед собираемым конвейером стоит `!`.
  var negated = false;

  /// Переменная заголовка `for`/`select`.
  String? variable;
}

/// Собирает сегменты и конвейеры одного уровня разбора.
///
/// Почему две структуры: плоские [ShellScript.pipelines] нужны правилам
/// таблицы §7.6 и существующим тестам, а дерево [ShellScript.commands] —
/// обходу рабочего каталога (§7.6.2). Они строятся из одних событий и делят
/// одни объекты [ShellSegment], поэтому расходиться им не из-за чего.
/// Исключение: имя функции в `f()` есть только в плоском виде (сегмент `f`),
/// в дереве его нет.
final class _ScriptBuilder {
  _ScriptBuilder(this.depth, this.origin);

  final int depth;
  final ShellOrigin origin;

  // Плоский вид.
  final _pipelines = <ShellPipeline>[];
  var _stages = <ShellSegment>[];
  var _words = <_Word>[];
  var _redirections = <ShellRedirection>[];
  var _nested = <ShellScript>[];

  // Дерево: стек блоков и состояние разбора составных команд.
  final _frames = [_Frame(null, '')];
  _Frame get _frame => _frames.last;

  /// Только что закрыт блок: перенаправления дальше принадлежат ему, а слово
  /// без разделителя — ошибка.
  var _afterBlock = false;

  /// За `f()` или `function f` ждём тело функции.
  var _pendingFunction = false;
  var _expectFunctionName = false;

  /// Читается заголовок `for`/`select`: его слова командой не считаются.
  var _inHeader = false;
  var _headerNested = <ShellScript>[];

  /// 0 — ждём имя переменной, 1 — после имени (`in` или `do`), 2 — список
  /// после `in`.
  var _headerStage = 0;

  bool get segmentIsEmpty => _words.isEmpty && _redirections.isEmpty;
  bool get insideBlock => _frames.length > 1;
  bool get inHeader => _inHeader;
  bool get pendingFunction => _pendingFunction;

  /// Единственное слово сегмента может быть именем функции: `f` перед `()`.
  bool get canBeFunctionName =>
      _words.length == 1 &&
      _redirections.isEmpty &&
      !_inHeader &&
      !_afterBlock &&
      !_words.single.quoted &&
      !assignmentWord.hasMatch(_words.single.value);

  void addWord(_Word word) {
    if (_inHeader) {
      _headerWord(word);
      return;
    }
    if (_expectFunctionName) {
      _expectFunctionName = false;
      _pendingFunction = true;
      return;
    }
    // Зарезервированное слово — только в пустом сегменте: после
    // перенаправления (`>/dev/null ! cd /tmp`) оболочка читает его как имя
    // команды (D17, H1).
    if (segmentIsEmpty && !word.quoted && _reservedWord(word.value)) {
      return;
    }
    if (_afterBlock) {
      throw const ShellParseException('unexpected word after a block');
    }
    _words.add(word);
    _nested.addAll(word.nested);
  }

  /// Зарезервированное слово в позиции команды (D10): снимается и меняет
  /// стек блоков. `true` — слово обработано.
  bool _reservedWord(String word) {
    switch (word) {
      case '!':
        if (_frame.negated) {
          throw const ShellParseException('double negation');
        }
        _frame.negated = true;
      case 'if':
        openBlock(ShellBlockKind.conditional, 'fi');
      case 'while' || 'until':
        openBlock(ShellBlockKind.loop, 'done');
      case 'for' || 'select':
        openBlock(ShellBlockKind.loop, 'done');
        _inHeader = true;
        _headerStage = 0;
        _headerNested = [];
      case 'then' || 'elif' || 'else':
        _separator('fi');
      case 'do':
        _separator('done');
      case 'fi' || 'done' || '}':
        closeBlock(word);
      case '{':
        openBlock(ShellBlockKind.group, '}');
      case 'function':
        _expectFunctionName = true;
      case 'case' || 'esac':
        // `case` не разбирается, как и раньше (`)` ветки): fail closed.
        throw const ShellParseException('case is not supported');
      default:
        return false;
    }
    return true;
  }

  /// Слово заголовка `for`/`select` (D10, D17 B1): имя, затем `in` со списком
  /// или сразу `do`. Подстановки в списке остаются вложенными командами,
  /// остальное — данные. Любое другое слово — ошибка разбора: иначе заголовок
  /// съел бы тело.
  void _headerWord(_Word word) {
    final plain = word.quoted ? null : word.value;
    switch (_headerStage) {
      case 0:
        _frame.variable = word.value;
        _headerStage = 1;
      case 1 when plain == 'in':
        _headerStage = 2;
      case 1 || 2 when plain == 'do':
        endPipeline(ShellConnector.sequence);
        _separator('done');
      case 2:
        _headerNested.addAll(word.nested);
      default:
        throw const ShellParseException('unexpected word in a for header');
    }
  }

  /// `then`, `elif`, `else`, `do` — продолжение блока: условие и ветки
  /// проходят одну последовательность (D6).
  void _separator(String closer) {
    if (!insideBlock || _frame.closer != closer || _afterBlock) {
      throw ShellParseException('unexpected separator for $closer');
    }
  }

  void addRedirection(ShellRedirection redirection, List<ShellScript> nested) {
    _redirections.add(redirection);
    _nested.addAll(nested);
  }

  /// Открывает блок [kind], который закроет слово [closer].
  void openBlock(ShellBlockKind kind, String closer) {
    if (_afterBlock) {
      throw const ShellParseException('unexpected block after a block');
    }
    if (_frames.length > maxShellBlockDepth) {
      // Обход рекурсивен: без предела глубокие блоки дают StackOverflowError.
      throw const ShellParseException('blocks are nested too deeply');
    }
    final effective = _pendingFunction ? ShellBlockKind.function : kind;
    _pendingFunction = false;
    _frames.add(_Frame(effective, closer));
  }

  /// Закрывает блок словом [closer] (`)`, `}`, `fi`, `done`).
  void closeBlock(String closer) {
    if (!insideBlock || _frame.closer != closer || _inHeader) {
      throw ShellParseException('unexpected $closer');
    }
    // `(a; b) | c`: закрытие блока завершает стадию, но не конвейер.
    endStage();
    _treeEndCommand(ShellConnector.sequence);
    final frame = _frames.removeLast();
    _frame.stages.add(
      ShellBlock(frame.kind!, frame.commands, variable: frame.variable),
    );
    _afterBlock = true;
  }

  /// `f()`: единственное слово сегмента — имя функции, его в дереве нет.
  /// Плоский вид сохраняет сегмент `f`, как до разбора блоков.
  void beginFunction() {
    _stages.add(_segment());
    _pipelines.add(ShellPipeline(_stages));
    _stages = [];
    _words = [];
    _redirections = [];
    _nested = [];
    _pendingFunction = true;
  }

  /// `|` и `|&`: завершает стадию, следующая стадия — того же конвейера.
  void pipe() {
    endStage();
    _afterBlock = false;
  }

  void endStage() {
    if (!segmentIsEmpty) {
      final segment = _segment();
      _stages.add(segment);
      _addToTree(segment);
    }
    _words = [];
    _redirections = [];
    _nested = [];
  }

  void _addToTree(ShellSegment segment) {
    if (_afterBlock &&
        segment.words.isEmpty &&
        _frame.stages.lastOrNull is ShellBlock) {
      // `done < in.txt`, `} > out`: перенаправления относятся к блоку (D10).
      final block = _frame.stages.last as ShellBlock;
      if (block._redirections == null) {
        block._redirections = segment;
        return;
      }
    }
    _frame.stages.add(ShellSimple(segment));
  }

  /// Завершает конвейер связкой [connector] со следующим (D2).
  void endPipeline(ShellConnector connector) {
    if (_inHeader) {
      _endHeader();
    }
    endStage();
    if (_stages.isNotEmpty) {
      _pipelines.add(ShellPipeline(_stages));
      _stages = [];
    }
    _treeEndCommand(connector);
  }

  /// Заголовок `for`/`select` кончился: подстановки из него остаются
  /// сегментом без слов, остальное в дерево не попадает.
  void _endHeader() {
    if (_headerStage == 0) {
      throw const ShellParseException('for without a variable name');
    }
    _inHeader = false;
    if (_headerNested.isNotEmpty) {
      final segment = ShellSegment(
        words: const [],
        nested: List.unmodifiable(_headerNested),
      );
      _stages.add(segment);
      _frame.stages.add(ShellSimple(segment));
    }
    _headerNested = [];
  }

  void _treeEndCommand(ShellConnector connector) {
    final frame = _frame;
    if (frame.stages.isNotEmpty) {
      frame.commands.add(
        ShellCommand(frame.stages, next: connector, negated: frame.negated),
      );
      frame.stages = [];
    }
    frame.negated = false;
    _afterBlock = false;
  }

  ShellScript finish() {
    if (insideBlock) {
      throw const ShellParseException('unclosed block');
    }
    endPipeline(ShellConnector.sequence);
    return ShellScript(
      _pipelines,
      commands: _frames.single.commands,
      origin: origin,
    );
  }

  ShellSegment _segment() {
    final all = [for (final word in _words) word.value];
    final (:privileged, :start, :split, :launchers, :lookup) = _stripLaunchers(
      all,
    );
    final words = all.sublist(start);
    // При `env -S` слова от опции `-S` и дальше — вложенная команда, а не
    // префикс лаунчеров: пути и присваивания считаются по словам до неё.
    final prefix = all.sublist(0, split?.splitAt ?? start);
    final (dir: launcherDir, outputs: launcherOutputs) = _launcherPaths(prefix);
    final nested = [..._nested];
    var risky = false;
    // Присваивания: в префиксе (`NAME=… cmd`, `env NAME=…`) и аргументы
    // `export`/`declare`. Значение переменной-команды — вложенный текст.
    final assigned = [
      for (final w in prefix)
        if (assignmentWord.hasMatch(w)) w,
      if (words.isNotEmpty &&
          declarationCommands.contains(baseName(words.first)))
        for (final w in words.skip(1))
          if (assignmentWord.hasMatch(w)) w,
    ];
    // `env -S 'cmd'` — значение исполняется как строка команды (§7.6.1).
    if (split != null) {
      nested.add(
        _Lexer(
          _envSplitText(all, split),
        ).parse(depth + 1, origin: ShellOrigin.command),
      );
    }
    for (final w in assigned) {
      final eq = w.indexOf('=');
      final key = variableNamePattern.firstMatch(w)![0]!;
      if (_riskyEnvironment.hasMatch(key)) {
        risky = true;
      } else if (commandEnvironmentVariables.contains(key)) {
        final value = w.substring(eq + 1).replaceFirst(RegExp(r'^\|+'), '');
        if (value.isNotEmpty) {
          // Пейджер и редактор запускает программа, возможно, из корня
          // рабочего дерева, а не из каталога оболочки (D8).
          nested.add(
            _Lexer(value).parse(depth + 1, origin: ShellOrigin.foreign),
          );
        }
      }
    }
    if (words.isNotEmpty) {
      final name = baseName(words.first);
      if (shellNames.contains(name)) {
        final i = _shellCommandIndex(words);
        if (i != null) {
          nested.add(
            _Lexer(words[i]).parse(depth + 1, origin: ShellOrigin.command),
          );
        }
      } else if (name == 'eval' && words.length > 1) {
        nested.add(
          _Lexer(
            words.sublist(1).join(' '),
          ).parse(depth + 1, origin: ShellOrigin.eval),
        );
      } else if (name == 'trap') {
        // Действие `trap` исполнится позже, в неизвестном состоянии (D8).
        if (_trapAction(words) case final action?) {
          nested.add(
            _Lexer(action).parse(depth + 1, origin: ShellOrigin.foreign),
          );
        }
      } else {
        for (final (:text, :origin) in _commandOptionValues(name, words)) {
          nested.add(_Lexer(text).parse(depth + 1, origin: origin));
        }
      }
    }
    return ShellSegment(
      words: List.unmodifiable(words),
      redirections: List.unmodifiable(_redirections),
      privileged: privileged,
      nested: List.unmodifiable(nested),
      launcherDir: launcherDir,
      launcherOutputs: List.unmodifiable(launcherOutputs),
      riskyEnvironment: risky,
      launcherWords: List.unmodifiable(prefix),
      commandTextIndex:
          words.isNotEmpty && shellNames.contains(baseName(words.first))
          ? _shellCommandIndex(words)
          : null,
      launchers: List.unmodifiable(launchers),
      lookupOnly: lookup,
      commandWordSplit: start < _words.length && _words[start].splitRisk,
      commandWordGlob:
          start < _words.length &&
          _words[start].glob &&
          const {'[', '[['}.contains(_words[start].value) == false,
    );
  }
}

/// Действие `trap ACTION SIGNAL…` или `null`: опции (`-p`, `-l`) и `--`
/// пропускаются, `-` и пустая строка — сброс и игнорирование, а не команда.
String? _trapAction(List<String> words) {
  var i = 1;
  while (i < words.length && words[i].startsWith('-') && words[i] != '-') {
    if (words[i++] == '--') {
      break;
    }
  }
  if (i >= words.length || words[i] == '-' || words[i].isEmpty) {
    return null;
  }
  return words[i];
}

/// Значения опций снятых лаунчеров, важные для путей: каталог (`env -C`,
/// `sudo -D`, `--chdir`) и файлы вывода (`time -o`, `--output`). Слова
/// [prefix] — всё, что [_stripLaunchers] снял с начала сегмента.
({String? dir, List<String> outputs}) _launcherPaths(List<String> prefix) {
  String? dir;
  final outputs = <String>[];
  String? launcher;
  for (var i = 0; i < prefix.length; i++) {
    final word = prefix[i];
    if (!word.startsWith('-') && !assignmentWord.hasMatch(word)) {
      launcher = baseName(word);
      continue;
    }
    String? value;
    var long = '';
    if (word.contains('=') && word.startsWith('--')) {
      long = word.substring(0, word.indexOf('='));
      value = word.substring(word.indexOf('=') + 1);
    } else if (i + 1 < prefix.length) {
      long = word;
      value = prefix[i + 1];
    }
    if (value == null) {
      continue;
    }
    final chdir = switch (launcher) {
      'env' => long == '-C' || _envLongName(long) == 'chdir',
      'sudo' || 'doas' => long == '-D' || long == '--chdir',
      _ => false,
    };
    if (chdir) {
      dir = value;
    } else if (launcher == 'time' && (long == '-o' || long == '--output')) {
      outputs.add(value);
    }
  }
  return (dir: dir, outputs: outputs);
}

/// Длинные опции bash без значения (разбор `_shellCommandIndex`). Список —
/// по bash(1), раздел INVOCATION, описан своими словами, текст не копируется;
/// с
/// значением — [_shellLongWithValue]. Остальные длинные опции неоднозначны:
/// команда неразбираема (fail closed).
const _shellLongPlain = {
  '--login',
  '--noprofile',
  '--norc',
  '--posix',
  '--restricted',
  '--verbose',
  '--debugger',
  '--noediting',
  '--version',
  '--help',
  '--dump-strings',
  '--dump-po-strings',
  '--pretty-print',
};
const _shellLongWithValue = {'--rcfile', '--init-file'};

/// Индекс строки команды у `sh -c CMD` (в том числе `-lc`, `-ec`): `null`,
/// если первым позиционным словом идёт файл скрипта.
///
/// Источник правил разбора — bash(1), раздел INVOCATION, и dash(1); описано
/// своими словами. Разбор повторяет порядок bash/dash: однобуквенные опции допустимы и после
/// `-c` (`bash -c -l CMD`); текст команды — первое слово, не являющееся
/// опцией или её значением, если `-c` был. Значение забирают `-o`/`+o`,
/// `-O`/`+O` и каждая буква `o`/`O` в кластере по одному слову по порядку
/// (`-co pipefail CMD`, `-ceo x CMD`), `--rcfile` и `--init-file`. Неизвестная
/// длинная опция — [ShellParseException] (fail closed): иначе значение опции
/// принималось бы за текст и вложенная команда не проверялась бы (PERM-11).
int? _shellCommandIndex(List<String> words) {
  var hasC = false;
  for (var i = 1; i < words.length; i++) {
    final w = words[i];
    if (w == '--' || w == '-') {
      return hasC && i + 1 < words.length ? i + 1 : null;
    }
    if (!(w.startsWith('-') || w.startsWith('+'))) {
      return hasC ? i : null;
    }
    if (w.startsWith('--')) {
      if (_shellLongWithValue.contains(w)) {
        i++;
      } else if (!_shellLongPlain.contains(w)) {
        throw const ShellParseException('unknown shell long option');
      }
      continue;
    }
    if (!RegExp(r'^[-+][A-Za-z]+$').hasMatch(w)) {
      throw const ShellParseException('unknown shell option');
    }
    for (final letter in w.substring(1).split('')) {
      if (letter == 'c' && w.startsWith('-')) {
        hasC = true;
      } else if (letter == 'o' || letter == 'O') {
        i++;
      }
    }
  }
  return null;
}

final _hostVariable = RegExp(
  r'\$(\{(HOME|CODELAB_HOME)\}|(HOME|CODELAB_HOME)(?![A-Za-z0-9_]))',
);

final _lookupOption = RegExp(r'^-[A-Za-z]*[vV]');

/// Лаунчеры, которые снимает [_stripLaunchers] и имена которых сохраняются
/// в [ShellSegment.launchers] (D7). `su` — сама команда и сюда не входит.
const _launcherNames = {
  'sudo',
  'doas',
  'pkexec',
  'env',
  'nohup',
  'builtin',
  'nice',
  'time',
  'command',
  'exec',
  'timeout',
  'stdbuf',
  'xargs',
};

/// Снимает присваивания и лаунчеры с опциями из начала сегмента (§7.6,
/// правило 5) и возвращает индекс настоящей команды.
({
  bool privileged,
  int start,
  _EnvScan? split,
  List<String> launchers,
  bool lookup,
})
_stripLaunchers(List<String> words) {
  var privileged = false;
  var lookup = false;
  var i = 0;
  // Имена снятых лаунчеров (D7): `command cd` — встроенный `cd`, `env cd` —
  // внешняя программа.
  final launchers = <String>[];
  while (i < words.length) {
    final word = words[i];
    if (assignmentWord.hasMatch(word)) {
      i++;
      continue;
    }
    final name = baseName(word);
    if (_launcherNames.contains(name)) {
      // Лаунчер с путём (`/usr/bin/command`) — внешняя программа, а не
      // встроенная команда оболочки (D17, A3).
      launchers.add(word.contains('/') ? 'external $name' : name);
    }
    switch (name) {
      case 'sudo':
        privileged = true;
        i = _skipOptions(
          words,
          i + 1,
          const {'-u', '-g', '-C', '-D', '-p', '-r', '-t', '-T', '-U', '-R'},
          const {'--user', '--group', '--chdir', '--prompt', '--other-user'},
        );
      case 'doas':
        privileged = true;
        i = _skipOptions(words, i + 1, const {'-u', '-C'});
      case 'pkexec':
        privileged = true;
        i = _skipOptions(words, i + 1, const {'--user'});
      case 'su':
        // `su` — сама команда: её аргументы — опции, а не другая команда.
        return (
          privileged: true,
          start: i,
          split: null,
          launchers: launchers,
          lookup: lookup,
        );
      case 'env':
        final scan = _scanEnv(words, i + 1);
        if (scan.splitAt != null) {
          // После значения `-S` команда внутри него (см. [_envSplitText]).
          return (
            privileged: privileged,
            start: words.length,
            split: scan,
            launchers: launchers,
            lookup: lookup,
          );
        }
        i = scan.next;
      case 'nohup' || 'builtin':
        i++;
      case 'nice':
        i = _skipOptions(words, i + 1, const {'-n'}, const {'--adjustment'});
      case 'time':
        i = _skipOptions(
          words,
          i + 1,
          const {'-f', '-o'},
          const {'--format', '--output'},
        );
      case 'command':
        final next = _skipOptions(words, i + 1, const {});
        lookup =
            lookup ||
            words.sublist(i + 1, next).any((o) => _lookupOption.hasMatch(o));
        i = next;
      case 'exec':
        i = _skipOptions(words, i + 1, const {'-a'});
      case 'timeout':
        i = _skipOptions(
          words,
          i + 1,
          const {'-s', '-k'},
          const {'--signal', '--kill-after'},
        );
        // Первое позиционное слово `timeout` — длительность.
        if (i < words.length) {
          i++;
        }
      case 'stdbuf':
        i = _skipOptions(
          words,
          i + 1,
          const {'-i', '-o', '-e'},
          const {'--input', '--output', '--error'},
        );
      case 'xargs':
        i = _skipOptions(
          words,
          i + 1,
          const {'-I', '-L', '-n', '-P', '-s', '-d', '-E', '-a'},
          const {
            '--max-args',
            '--max-procs',
            '--max-lines',
            '--max-chars',
            '--delimiter',
            '--arg-file',
            '--eof',
            '--process-slot-var',
          },
        );
      default:
        return (
          privileged: privileged,
          start: i,
          split: null,
          launchers: launchers,
          lookup: lookup,
        );
    }
  }
  return (
    privileged: privileged,
    start: i,
    split: null,
    launchers: launchers,
    lookup: lookup,
  );
}

/// Длинные опции `env` (GNU coreutils): общий список для разбора опций и
/// путей лаунчера, чтобы два прохода не разошлись (PERM-11, §7.6.1).
const _envLongOptions = [
  'ignore-environment',
  'chdir',
  'null',
  'unset',
  'split-string',
  'debug',
  'argv0',
  'block-signal',
  'default-signal',
  'ignore-signal',
  'list-signal-handling',
  'version',
  'help',
];

/// Длинные опции `env`, у которых значение обязательно.
const _envLongWithValue = {'chdir', 'unset', 'argv0'};

/// Короткие опции `env`, берущие значение (остаток слова или следующее
/// слово): GNU `-u -C -S -a` и BSD/macOS `-P altpath`, `-L`, `-U`.
const _envShortWithValue = 'uCSaPLU';

/// Короткие опции `env` без значения: `-i`, `-0`, `-v`. Любая другая
/// короткая опция неизвестна — `env` её отвергает, а команда считается
/// неразбираемой (fail closed, правило 8 §7.6).
const _envShortFlags = 'i0v';

/// Полное имя длинной опции `env` по слову [word] (`--sp`, `--split-s`) или
/// `null`. `getopt_long` принимает любой однозначный префикс, поэтому
/// сокращения тоже опции; неоднозначный префикс `env` отвергает, и команда
/// не запускается.
String? _envLongName(String word) {
  if (!word.startsWith('--') || word.length < 3) {
    return null;
  }
  final prefix = word.substring(2);
  if (_envLongOptions.contains(prefix)) {
    return prefix;
  }
  final found = _envLongOptions.where((n) => n.startsWith(prefix)).toList();
  return found.length == 1 ? found.single : null;
}

/// Итог разбора опций `env`: [next] — индекс первого слова после опций;
/// при `-S` — [splitAt] (индекс опции), [splitValue] и [valueEnd] (индекс
/// после слова-значения): после значения опций больше нет.
typedef _EnvScan = ({int next, int? splitAt, String splitValue, int valueEnd});

/// Единственный проход по опциям `env` с позиции [i].
///
/// Почему: `env -S 'cmd'` исполняет значение как командную строку, а слова
/// после него `env` дописывает в argv, и разбор опций (`getopt`, optstring
/// с `+`) на этом заканчивается. Значение `-S` нельзя пропускать как
/// аргумент обычной опции: иначе у сегмента не остаётся команды, и он
/// считается «только чтением» (PERM-11, `07-permissions` §7.6.1).
///
/// Как использовать: [_stripLaunchers] берёт [_EnvScan.next] или, если
/// есть [_EnvScan.splitAt], пересобирает команду через [_envSplitText].
/// Поддержаны `-S`, `-S<текст>`, кластеры (`-iS`), `--split-string[=]` и
/// однозначные сокращения длинных опций.
_EnvScan _scanEnv(List<String> words, int i) {
  _EnvScan stop(int next) =>
      (next: next, splitAt: null, splitValue: '', valueEnd: next);
  while (i < words.length) {
    final w = words[i];
    if (w == '--') {
      return stop(i + 1);
    }
    if (!w.startsWith('-')) {
      return stop(i);
    }
    if (w.startsWith('--')) {
      final eq = w.indexOf('=');
      final name = _envLongName(eq > 0 ? w.substring(0, eq) : w);
      if (name == 'split-string') {
        if (eq > 0) {
          return (
            next: words.length,
            splitAt: i,
            splitValue: w.substring(eq + 1),
            valueEnd: i + 1,
          );
        }
        return (
          next: words.length,
          splitAt: i,
          splitValue: i + 1 < words.length ? words[i + 1] : '',
          valueEnd: i + 1 < words.length ? i + 2 : i + 1,
        );
      }
      i += eq < 0 && _envLongWithValue.contains(name) ? 2 : 1;
      continue;
    }
    var consumed = 1;
    for (var c = 1; c < w.length; c++) {
      if (!_envShortWithValue.contains(w[c])) {
        if (!_envShortFlags.contains(w[c])) {
          throw ShellParseException('unknown env option -${w[c]}');
        }
        continue;
      }
      final glued = w.substring(c + 1);
      if (w[c] == 'S') {
        final hasNext = glued.isEmpty && i + 1 < words.length;
        return (
          next: words.length,
          splitAt: i,
          splitValue: glued.isNotEmpty ? glued : (hasNext ? words[i + 1] : ''),
          valueEnd: hasNext ? i + 2 : i + 1,
        );
      }
      if (glued.isEmpty) {
        consumed = 2;
      }
      break;
    }
    i += consumed;
  }
  return stop(i);
}

/// Разбирает значение `env -S` по правилам самого `env`, а не shell.
///
/// Почему: `env` метасимволы shell не знает — `;`, `&`, `|`, `<<` и перевод
/// строки там обычные символы аргументов (первое слово — программа, остальные
/// — её аргументы). Отдать значение shell-лексеру значит потерять аргументы
/// (`-S 'rm ; -rf ${HOME}'` выглядело бы как две команды без `-rf`).
///
/// Для чего: возвращает текст для [_Lexer], где каждое слово значения —
/// в одинарных кавычках ([_shQuote]), а `${VAR}` — вне них, чтобы правила
/// видели раскрытие `${HOME}`/`${CODELAB_HOME}`.
///
/// Правила: разделители — пробел и `\t \n \v \f \r`; кавычки `'…'` (внутри
/// только `\\` и `\'`) и `"…"`; `\_`, `\t`, `\n`, `\v`, `\f`, `\r` вне кавычек —
/// разделитель, в двойных — пробельный символ; `\\ \" \' \$ \#` — сам
/// символ; `\c` обрывает значение; `#` в начале слова — комментарий до
/// конца; `${NAME}` — подстановка. Всё прочее — [ShellParseException]
/// (голый `$`, незакрытые кавычки и скобка, другие `\x`): fail closed,
/// правило 8 §7.6 (PERM-11, §7.6.1).
String _envSplitWords(String value) {
  const blanks = ' \t\n\v\f\r';
  final words = <String>[];
  final word = StringBuffer();
  final literal = StringBuffer();
  var inWord = false;

  void flushLiteral() {
    if (literal.isNotEmpty) {
      word.write(_shQuote(literal.toString()));
      literal.clear();
    }
  }

  void endWord() {
    flushLiteral();
    if (inWord) {
      words.add(word.isEmpty ? "''" : word.toString());
    }
    word.clear();
    inWord = false;
  }

  // Подстановка `${NAME}`: возвращает индекс после `}`.
  int substitution(int i) {
    final close = value.indexOf('}', i);
    final braced = i + 1 < value.length && value[i + 1] == '{';
    final name = close < 0 || !braced ? '' : value.substring(i + 2, close);
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
      throw const ShellParseException('bad substitution in env -S');
    }
    flushLiteral();
    word.write('\${$name}');
    inWord = true;
    return close;
  }

  // Escape вне одинарных кавычек: `true` — разобран, `false` — `\c`.
  bool escape(int i, {required bool quoted}) {
    if (i + 1 >= value.length) {
      throw const ShellParseException('dangling backslash in env -S');
    }
    final n = value[i + 1];
    if (n == 'c') {
      return false;
    }
    if ('_tnvfr'.contains(n)) {
      if (quoted) {
        literal.write(n == '_' ? ' ' : blanks['_tnvfr'.indexOf(n)]);
        inWord = true;
      } else {
        endWord();
      }
    } else if ('\\"\'\$#'.contains(n)) {
      literal.write(n);
      inWord = true;
    } else {
      throw ShellParseException('unsupported escape \\$n in env -S');
    }
    return true;
  }

  var i = 0;
  scan:
  while (i < value.length) {
    final c = value[i];
    if (blanks.contains(c)) {
      endWord();
      i++;
    } else if (c == '#' && !inWord) {
      break;
    } else if (c == "'") {
      inWord = true;
      i++;
      while (true) {
        if (i >= value.length) {
          throw const ShellParseException('unclosed quote in env -S');
        }
        if (value[i] == "'") {
          break;
        }
        if (value[i] == r'\') {
          final n = i + 1 < value.length ? value[i + 1] : '';
          if (n != r'\' && n != "'") {
            throw ShellParseException('unsupported escape \\$n in env -S');
          }
          literal.write(n);
          i += 2;
        } else {
          literal.write(value[i++]);
        }
      }
      i++;
    } else if (c == '"') {
      inWord = true;
      i++;
      while (true) {
        if (i >= value.length) {
          throw const ShellParseException('unclosed quote in env -S');
        }
        final d = value[i];
        if (d == '"') {
          break;
        }
        if (d == r'\') {
          if (!escape(i, quoted: true)) {
            break scan;
          }
          i += 2;
        } else if (d == r'$') {
          i = substitution(i) + 1;
        } else {
          literal.write(d);
          i++;
        }
      }
      i++;
    } else if (c == r'\') {
      if (!escape(i, quoted: false)) {
        break;
      }
      i += 2;
    } else if (c == r'$') {
      i = substitution(i) + 1;
    } else {
      literal.write(c);
      inWord = true;
      i++;
    }
  }
  endWord();
  return words.join(' ');
}

/// Слово в одинарных кавычках: `'` заменяется на `'\''`.
String _shQuote(String word) => "'${word.replaceAll("'", r"'\''")}'";

/// Текст, который исполнил бы `env`: слова до `-S` (лаунчеры и опции),
/// обработанное значение и остаток в кавычках.
///
/// Почему: значение `-S` само может начинаться с опций и присваиваний
/// `env` (`-S '-i rm …'`, `-S '-C dir rm …'`), поэтому разбирается как
/// `env <значение> <остаток>`, а не как `sh -c`. Остаток экранируется
/// (`'#'`, `'x;'` остаются данными). Глубину ограничивает
/// [maxShellNesting] (PERM-11, §7.6.1).
String _envSplitText(List<String> words, _EnvScan scan) {
  return [
    for (final w in words.sublist(0, scan.splitAt!)) _shQuote(w),
    _envSplitWords(scan.splitValue),
    for (final w in words.sublist(scan.valueEnd)) _shQuote(w),
  ].join(' ');
}

/// Пропускает опции лаунчера с позиции [i]; опции из [withValue] и
/// [longWithValue] забирают следующее слово, `--` завершает опции.
int _skipOptions(
  List<String> words,
  int i,
  Set<String> withValue, [
  Set<String> longWithValue = const {},
]) {
  while (i < words.length) {
    final w = words[i];
    if (w == '--') {
      return i + 1;
    }
    if (!w.startsWith('-')) {
      return i;
    }
    i += withValue.contains(w) || longWithValue.contains(w) ? 2 : 1;
  }
  return i;
}

/// Ключи конфигурации `git`, значение которых git исполняет как команду
/// (`git -c core.pager=…`).
final _gitCommandKey = RegExp(
  r'^(core\.(pager|fsmonitor|sshcommand|editor|askpass|gitproxy)|'
  r'interactive\.difffilter|diff\.external|diff\..*\.(textconv|command)|sequence\.editor|alias\..+|'
  r'credential\.helper|gpg\..*program|merge\..*\.driver|'
  r'filter\..*\.(clean|smudge|process)|pager\..+|web\.browser|'
  r'(browser|difftool|mergetool)\..*\.cmd|receive\.procreceive)$',
  caseSensitive: false,
);

/// Значения опций, которые сами исполняются как команды: `git -c KEY=CMD`
/// для ключей [_gitCommandKey] (у `alias.*` ведущий `!` снимается),
/// `rg --pre CMD`, `find -exec|-execdir|-ok|-okdir CMD … ;|+`. Каждое
/// разбирается как вложенный текст той же семантикой, что `sh -c`, поэтому
/// его сегменты проходят все правила PERM-11 и §7.6 (R5-4, повторное ревью).
///
/// Вместе с текстом возвращается [ShellOrigin] (D8): `git` запускает команду
/// из корня рабочего дерева, `find -execdir` — из каждого найденного
/// каталога ([ShellOrigin.foreign]); `rg --pre`, `watch`, `script -c`,
/// `find -exec`/`-ok` идут в каталоге самого процесса ([ShellOrigin.command]).
Iterable<({String text, ShellOrigin origin})> _commandOptionValues(
  String? name,
  List<String> words,
) sync* {
  switch (name) {
    case 'git':
      for (var i = 1; i < words.length && words[i].startsWith('-'); i++) {
        final w = words[i];
        final glued = w.length > 2 && w.startsWith('-c') && w[2] != '-';
        if ((w == '-c' && i + 1 < words.length) || glued) {
          // `-c k=v` и слитная форма `-ck=v`.
          final value = glued ? w.substring(2) : words[++i];
          final eq = value.indexOf('=');
          if (eq > 0 && _gitCommandKey.hasMatch(value.substring(0, eq))) {
            final command = value.substring(eq + 1);
            yield (
              text: command.startsWith('!') ? command.substring(1) : command,
              origin: ShellOrigin.foreign,
            );
          }
        } else if (const {
          '-C',
          '--git-dir',
          '--work-tree',
          '--namespace',
        }.contains(w)) {
          i++;
        }
      }
    case 'rg':
      for (var i = 1; i < words.length; i++) {
        if (words[i] == '--pre' && i + 1 < words.length) {
          yield (text: words[++i], origin: ShellOrigin.command);
        } else if (words[i].startsWith('--pre=')) {
          yield (
            text: words[i].substring('--pre='.length),
            origin: ShellOrigin.command,
          );
        }
      }
    case 'watch':
      // Остаток после опций — строка команды (`watch -n 1 "cmd"`).
      final command = <String>[];
      for (var i = 1; i < words.length; i++) {
        final w = words[i];
        if (command.isEmpty && w.startsWith('-')) {
          if (w == '-n' || w == '--interval') {
            i++;
          }
        } else {
          command.add(w);
        }
      }
      if (command.isNotEmpty) {
        yield (text: command.join(' '), origin: ShellOrigin.command);
      }
    case 'script':
      for (var i = 1; i < words.length; i++) {
        if ((words[i] == '-c' || words[i] == '--command') &&
            i + 1 < words.length) {
          yield (text: words[++i], origin: ShellOrigin.command);
        } else if (words[i].startsWith('--command=')) {
          yield (
            text: words[i].substring('--command='.length),
            origin: ShellOrigin.command,
          );
        }
      }
    case 'find':
      for (var i = 1; i < words.length; i++) {
        if (const {'-exec', '-execdir', '-ok', '-okdir'}.contains(words[i])) {
          final origin = words[i].endsWith('dir')
              ? ShellOrigin.foreign
              : ShellOrigin.command;
          final command = <String>[];
          for (i++; i < words.length; i++) {
            if (words[i] == ';' || words[i] == '+') {
              break;
            }
            command.add(words[i]);
          }
          if (command.isNotEmpty) {
            yield (text: command.join(' '), origin: origin);
          }
        }
      }
  }
}

/// Встроенные команды, задающие переменные окружения следующим командам
/// цепочки (`export GIT_PAGER=…; git log`).
const declarationCommands = {
  'export',
  'declare',
  'typeset',
  'readonly',
  'local',
};

/// Переменные, значение которых программы исполняют как команду (pager,
/// редакторы, ssh, askpass, `LESSOPEN`): разбираются как вложенный `sh -c`.
///
/// Публичны: обход каталога узнаёт косвенную запись такой переменной
/// (`read EDITOR`, `printf -v`; D17, L1).
const commandEnvironmentVariables = {
  'GIT_PAGER', 'PAGER', 'GIT_EXTERNAL_DIFF', 'GIT_EDITOR', 'EDITOR', 'VISUAL',
  'GIT_SEQUENCE_EDITOR', 'GIT_SSH_COMMAND', 'GIT_SSH', 'GIT_ASKPASS',
  'SSH_ASKPASS', 'LESSOPEN', 'LESSCLOSE', //
};

/// Переменные, меняющие поведение git неизвестным образом.
final _riskyEnvironment = RegExp(
  r'^(GIT_CONFIG_COUNT|GIT_CONFIG_KEY_\d+|GIT_CONFIG_VALUE_\d+|'
  r'GIT_CONFIG_PARAMETERS|GIT_EXEC_PATH|GIT_DIR|GIT_WORK_TREE)$',
);
