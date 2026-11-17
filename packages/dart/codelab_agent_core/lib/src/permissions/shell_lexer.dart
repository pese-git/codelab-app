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

import 'dart:convert';

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
      } else if (c == r'$' && pos + 1 < src.length && src[pos + 1] == "'") {
        _readAnsiC(buffer);
        quoted = true;
      } else if (c == r'$' && pos + 1 < src.length && src[pos + 1] == '"') {
        // `$"…"` — локализуемая строка bash: без каталога перевода она
        // равна `"…"`, поэтому `$` перед кавычкой пропускается.
        pos++;
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
    final (:privileged, :start, :split) = _stripLaunchers(all);
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
        if (_assignment.hasMatch(w)) w,
      if (words.isNotEmpty && _declarations.contains(baseName(words.first)))
        for (final w in words.skip(1))
          if (_assignment.hasMatch(w)) w,
    ];
    // `env -S 'cmd'` — значение исполняется как строка команды (§7.6.1).
    if (split != null) {
      nested.add(_Lexer(_envSplitText(all, split)).parse(depth + 1));
    }
    for (final w in assigned) {
      final eq = w.indexOf('=');
      final key = w.substring(0, eq);
      if (_riskyEnvironment.hasMatch(key)) {
        risky = true;
      } else if (_commandEnvironment.contains(key)) {
        final value = w.substring(eq + 1).replaceFirst(RegExp(r'^\|+'), '');
        if (value.isNotEmpty) {
          nested.add(_Lexer(value).parse(depth + 1));
        }
      }
    }
    if (words.isNotEmpty) {
      final name = baseName(words.first);
      if (shellNames.contains(name)) {
        final i = _shellCommandIndex(words);
        if (i != null) {
          nested.add(_Lexer(words[i]).parse(depth + 1));
        }
      } else if (name == 'eval' && words.length > 1) {
        nested.add(_Lexer(words.sublist(1).join(' ')).parse(depth + 1));
      } else {
        for (final text in _commandOptionValues(name, words)) {
          nested.add(_Lexer(text).parse(depth + 1));
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
    );
  }
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
    if (!word.startsWith('-') && !_assignment.hasMatch(word)) {
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

/// Снимает присваивания и лаунчеры с опциями из начала сегмента (§7.6,
/// правило 5) и возвращает индекс настоящей команды.
({bool privileged, int start, _EnvScan? split}) _stripLaunchers(
  List<String> words,
) {
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
        return (privileged: true, start: i, split: null);
      case 'env':
        final scan = _scanEnv(words, i + 1);
        if (scan.splitAt != null) {
          // После значения `-S` команда внутри него (см. [_envSplitText]).
          return (privileged: privileged, start: words.length, split: scan);
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
        return (privileged: privileged, start: i, split: null);
    }
  }
  return (privileged: privileged, start: i, split: null);
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
Iterable<String> _commandOptionValues(String? name, List<String> words) sync* {
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
            yield command.startsWith('!') ? command.substring(1) : command;
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
          yield words[++i];
        } else if (words[i].startsWith('--pre=')) {
          yield words[i].substring('--pre='.length);
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
        yield command.join(' ');
      }
    case 'script':
      for (var i = 1; i < words.length; i++) {
        if ((words[i] == '-c' || words[i] == '--command') &&
            i + 1 < words.length) {
          yield words[++i];
        } else if (words[i].startsWith('--command=')) {
          yield words[i].substring('--command='.length);
        }
      }
    case 'find':
      for (var i = 1; i < words.length; i++) {
        if (const {'-exec', '-execdir', '-ok', '-okdir'}.contains(words[i])) {
          final command = <String>[];
          for (i++; i < words.length; i++) {
            if (words[i] == ';' || words[i] == '+') {
              break;
            }
            command.add(words[i]);
          }
          if (command.isNotEmpty) {
            yield command.join(' ');
          }
        }
      }
  }
}

/// Встроенные команды, задающие переменные окружения следующим командам
/// цепочки (`export GIT_PAGER=…; git log`).
const _declarations = {'export', 'declare', 'typeset', 'readonly', 'local'};

/// Переменные, значение которых программы исполняют как команду (pager,
/// редакторы, ssh, askpass, `LESSOPEN`): разбираются как вложенный `sh -c`.
const _commandEnvironment = {
  'GIT_PAGER', 'PAGER', 'GIT_EXTERNAL_DIFF', 'GIT_EDITOR', 'EDITOR', 'VISUAL',
  'GIT_SEQUENCE_EDITOR', 'GIT_SSH_COMMAND', 'GIT_SSH', 'GIT_ASKPASS',
  'SSH_ASKPASS', 'LESSOPEN', 'LESSCLOSE', //
};

/// Переменные, меняющие поведение git неизвестным образом.
final _riskyEnvironment = RegExp(
  r'^(GIT_CONFIG_COUNT|GIT_CONFIG_KEY_\d+|GIT_CONFIG_VALUE_\d+|'
  r'GIT_CONFIG_PARAMETERS|GIT_EXEC_PATH|GIT_DIR|GIT_WORK_TREE)$',
);
