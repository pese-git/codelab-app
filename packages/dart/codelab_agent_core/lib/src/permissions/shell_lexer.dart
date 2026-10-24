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
/// команды. Это не интерпретатор: переменные не раскрываются, а `cd` не
/// меняет каталог.
///
/// Как использовать: `parseShell(command)`; ошибка разбора или вложенность
/// глубже [maxShellNesting] дают [ShellParseException], которую
/// `findCritical` превращает в шаблон `unparsable command` (правило 8).
library;

/// Наибольшая допустимая глубина вложенных команд (§7.6, правило 8).
///
/// Почему: без предела вложенность из подстановок, `sh -c` и `eval` можно
/// сделать сколь угодно глубокой. Верхний уровень — глубина 0; каждая
/// подстановка, аргумент `-c` или `eval` прибавляет единицу.
const maxShellNesting = 4;

/// Команду нельзя разобрать: незакрытая кавычка или подстановка, лишняя `)`,
/// перенаправление без цели или вложенность глубже [maxShellNesting].
///
/// Почему: «лучше спросить, чем пропустить» (§7.6, правило 8) — вызывающий
/// не угадывает смысл сломанной команды, а считает её критической.
///
/// Как использовать: ловить вокруг [parseShell]; [message] — для отладки,
/// пользователю показывается только метка `unparsable command`.
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

/// Разобранная команда или вложенная команда.
///
/// Для чего: корень дерева разбора; [allSegments] и [allPipelines] обходят
/// и вложенные команды, поэтому `echo $(rm -rf /)` проверяется так же, как
/// `rm -rf /`.
///
/// Как использовать: получать из [parseShell].
final class ShellScript {
  /// Создаётся лексером.
  const ShellScript(this.pipelines);

  /// Конвейеры этого уровня в порядке записи.
  final List<ShellPipeline> pipelines;

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

final _assignment = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=');
final _redirect = RegExp(r'(\d*)(&>>|&>|>>|>\||>&|>|<<<|<<-|<<|<>|<&|<)');
final _shellCommandFlag = RegExp(r'^-[A-Za-z]*c[A-Za-z]*$');

/// Слово до снятия кавычек вместе с вложенными командами из него.
final class _Word {
  _Word(this.value, {required this.quoted, required this.nested});

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

  ShellScript parse(int depth) => _script(depth, nested: false);

  ShellScript _script(int depth, {required bool nested}) {
    if (depth > maxShellNesting) {
      throw const ShellParseException(
        'nesting is deeper than $maxShellNesting',
      );
    }
    final builder = _ScriptBuilder(depth);
    var parens = 0;
    while (true) {
      _skipBlanks();
      if (pos >= src.length) {
        if (nested) {
          throw const ShellParseException('unclosed command substitution');
        }
        if (parens > 0) {
          throw const ShellParseException('unclosed parenthesis');
        }
        return builder.finish();
      }
      final c = src[pos];
      if (c == '#') {
        _skipComment();
      } else if (c == '\n') {
        pos++;
        builder.endPipeline();
        _skipHeredocBodies();
      } else if (c == ')') {
        pos++;
        if (parens > 0) {
          parens--;
          // `(a; b) | c`: конец подоболочки завершает стадию, но не конвейер.
          builder.endStage();
        } else if (nested) {
          return builder.finish();
        } else {
          throw const ShellParseException('unexpected )');
        }
      } else if (c == '(') {
        pos++;
        parens++;
        // `f()` — определение функции; `( … )` в начале стадии — подоболочка
        // внутри того же конвейера.
        if (!builder.segmentIsEmpty) {
          builder.endPipeline();
        }
      } else if (_at('&&') || _at('||')) {
        pos += 2;
        builder.endPipeline();
      } else if (_at('|&')) {
        pos += 2;
        builder.endStage();
      } else if (c == '|') {
        pos++;
        builder.endStage();
      } else if (c == ';') {
        // `;;`, `;&` и `;;&` — разделители веток `case`.
        pos++;
        while (pos < src.length && (src[pos] == ';' || src[pos] == '&')) {
          pos++;
        }
        builder.endPipeline();
      } else if (_redirectAt() case final match?) {
        _readRedirection(match, depth, builder);
      } else if (c == '&') {
        pos++;
        builder.endPipeline();
      } else {
        builder.addWord(_readWord(depth));
      }
    }
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
      } else if (c == r'$') {
        _readDollar(buffer, nested, depth);
      } else if (c == '`') {
        _readBackticks(buffer, nested, depth);
      } else if (pos == start && _atProcessSubstitution()) {
        pos += 2;
        nested.add(_script(depth + 1, nested: true));
        buffer.write(src.substring(start, pos));
      } else if (_isMeta(c)) {
        break;
      } else {
        buffer.write(c);
        pos++;
      }
    }
    return _Word(buffer.toString(), quoted: quoted, nested: nested);
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
        _readDollar(buffer, nested, depth);
      } else if (c == '`') {
        _readBackticks(buffer, nested, depth);
      } else {
        buffer.write(c);
        pos++;
      }
    }
  }

  /// `$( … )` — вложенная команда; `$(( … ))` и `${ … }` — не команды,
  /// их текст остаётся в слове как есть (переменные не раскрываются).
  void _readDollar(StringBuffer buffer, List<ShellScript> nested, int depth) {
    final start = pos;
    if (_at(r'$((')) {
      pos += 1;
      var open = 0;
      while (true) {
        if (pos >= src.length) {
          throw const ShellParseException('unclosed arithmetic expansion');
        }
        final c = src[pos++];
        if (c == '(') {
          open++;
        } else if (c == ')' && --open == 0) {
          break;
        }
      }
    } else if (_at(r'$(')) {
      pos += 2;
      nested.add(_script(depth + 1, nested: true));
    } else if (_at(r'${')) {
      final end = src.indexOf('}', pos);
      if (end < 0) {
        throw const ShellParseException('unclosed parameter expansion');
      }
      pos = end + 1;
    } else {
      pos++;
    }
    buffer.write(src.substring(start, pos));
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
    nested.add(_Lexer(inner.toString()).parse(depth + 1));
    buffer.write(src.substring(start, pos));
  }
}

/// Собирает сегменты и конвейеры одного уровня разбора.
final class _ScriptBuilder {
  _ScriptBuilder(this.depth);

  final int depth;
  final _pipelines = <ShellPipeline>[];
  var _stages = <ShellSegment>[];
  var _words = <_Word>[];
  var _redirections = <ShellRedirection>[];
  var _nested = <ShellScript>[];

  bool get segmentIsEmpty => _words.isEmpty && _redirections.isEmpty;

  void addWord(_Word word) {
    // `{` и `}` в позиции команды — границы группы, а не слова (правило 1).
    if (!word.quoted &&
        (word.value == '{' || word.value == '}') &&
        _words.isEmpty) {
      endStage();
      return;
    }
    _words.add(word);
    _nested.addAll(word.nested);
  }

  void addRedirection(ShellRedirection redirection, List<ShellScript> nested) {
    _redirections.add(redirection);
    _nested.addAll(nested);
  }

  void endStage() {
    if (!segmentIsEmpty) {
      _stages.add(_segment());
    }
    _words = [];
    _redirections = [];
    _nested = [];
  }

  void endPipeline() {
    endStage();
    if (_stages.isNotEmpty) {
      _pipelines.add(ShellPipeline(_stages));
      _stages = [];
    }
  }

  ShellScript finish() {
    endPipeline();
    return ShellScript(_pipelines);
  }

  ShellSegment _segment() {
    final all = [for (final word in _words) word.value];
    final (:privileged, :start) = _stripLaunchers(all);
    final words = all.sublist(start);
    final nested = [..._nested];
    if (words.isNotEmpty) {
      final name = baseName(words.first);
      if (shellNames.contains(name)) {
        final i = _shellCommandIndex(words);
        if (i != null) {
          nested.add(_Lexer(words[i]).parse(depth + 1));
        }
      } else if (name == 'eval' && words.length > 1) {
        nested.add(_Lexer(words.sublist(1).join(' ')).parse(depth + 1));
      }
    }
    return ShellSegment(
      words: List.unmodifiable(words),
      redirections: List.unmodifiable(_redirections),
      privileged: privileged,
      nested: List.unmodifiable(nested),
    );
  }
}

/// Индекс строки команды у `sh -c CMD` (в том числе `-lc`, `-ec`): `null`,
/// если первым позиционным словом идёт файл скрипта.
int? _shellCommandIndex(List<String> words) {
  for (var i = 1; i < words.length; i++) {
    final w = words[i];
    if (w == '--' || !(w.startsWith('-') || w.startsWith('+'))) {
      return null;
    }
    if (_shellCommandFlag.hasMatch(w)) {
      return i + 1 < words.length ? i + 1 : null;
    }
    if (w == '-o' || w == '+o' || w == '--rcfile' || w == '--init-file') {
      i++;
    }
  }
  return null;
}

/// Снимает присваивания и лаунчеры с опциями из начала сегмента (§7.6,
/// правило 5) и возвращает индекс настоящей команды.
({bool privileged, int start}) _stripLaunchers(List<String> words) {
  var privileged = false;
  var i = 0;
  while (i < words.length) {
    final word = words[i];
    if (_assignment.hasMatch(word)) {
      i++;
      continue;
    }
    switch (baseName(word)) {
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
        return (privileged: true, start: i);
      case 'env':
        i = _skipOptions(
          words,
          i + 1,
          const {'-u', '-C', '-S'},
          const {'--unset', '--chdir', '--split-string'},
        );
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
        i = _skipOptions(words, i + 1, const {});
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
        return (privileged: privileged, start: i);
    }
  }
  return (privileged: privileged, start: i);
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
