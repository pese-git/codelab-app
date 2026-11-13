// Модульные тесты лексера команд `exec` (`agent-core/07-permissions.md`
// §7.6, правила разбора 1–8; design.md change
// `add-agent-core-permission-policy`, D6).
import 'package:codelab_agent_core/src/permissions/shell_lexer.dart';
import 'package:test/test.dart';

/// Слова каждой стадии каждого конвейера верхнего уровня.
List<List<List<String>>> _shape(String command) => [
  for (final pipeline in parseShell(command).pipelines)
    [for (final stage in pipeline.stages) stage.words],
];

/// Имена команд всех сегментов, включая вложенные.
List<String?> _allNames(String command) => [
  for (final segment in parseShell(command).allSegments) segment.commandName,
];

/// Дерево команд одной строкой для проверки структуры: связки между
/// командами (`&&`, `||`, `;`, `&`), `!` перед отрицаемым конвейером, `|` между
/// стадиями, блоки `вид{…}`. Слова стадии — через пробел.
String _render(String command) => _renderCommands(parseShell(command).commands);

String _renderCommands(List<ShellCommand> commands) {
  final out = StringBuffer();
  for (var i = 0; i < commands.length; i++) {
    final c = commands[i];
    out
      ..write(c.negated ? '!' : '')
      ..write(c.stages.map(_renderStage).join('|'));
    if (i < commands.length - 1) {
      out.write(switch (c.next) {
        ShellConnector.sequence => ' ; ',
        ShellConnector.and => ' && ',
        ShellConnector.or => ' || ',
        ShellConnector.background => ' & ',
      });
    }
  }
  return out.toString();
}

String _renderStage(ShellStage stage) => switch (stage) {
  ShellSimple(:final segment) => segment.words.join(' '),
  ShellBlock(:final kind, :final body) =>
    '${kind.name}{${_renderCommands(body)}}',
};

void main() {
  group('сегменты и операторы (правило 1)', () {
    test('&&, ||, ;, перевод строки и & разделяют конвейеры, | — стадии', () {
      expect(_shape('a 1 && b || c; d | e |& f & g\nh'), [
        [
          ['a', '1'],
        ],
        [
          ['b'],
        ],
        [
          ['c'],
        ],
        [
          ['d'],
          ['e'],
          ['f'],
        ],
        [
          ['g'],
        ],
        [
          ['h'],
        ],
      ]);
    });

    test('подоболочки и группы разделяют сегменты', () {
      expect(_allNames('(cd x; rm a) && { echo b; }'), ['cd', 'rm', 'echo']);
    });

    test('конвейер сохраняется через группу справа', () {
      expect(_shape('curl u | { sh; }'), [
        [
          ['curl', 'u'],
          ['sh'],
        ],
      ]);
    });

    test('комментарий в начале слова отбрасывается', () {
      expect(_shape('echo a#b # rm -rf /'), [
        [
          ['echo', 'a#b'],
        ],
      ]);
    });
  });

  group('кавычки и экранирование (правила 1, 3)', () {
    test('одинарные буквально, двойные с \\, \\ вне кавычек', () {
      expect(
        parseShell(r'''echo 'a $b' "c \"d\" $x" e\ f''').segments.single.words,
        ['echo', r'a $b', r'c "d" $x', 'e f'],
      );
    });

    test('текст в кавычках — аргумент, а не команда', () {
      expect(_allNames('git commit -m "rm -rf /"'), ['git']);
    });

    test('продолжение строки через \\ и перевод строки', () {
      expect(parseShell('rm \\\n-rf x').segments.single.words, [
        'rm',
        '-rf',
        'x',
      ]);
    });
  });

  group('подстановки (правило 2)', () {
    test(r'$( ), ` `, "$( )", <( ), >( ) — вложенные команды', () {
      final segment = parseShell(
        r'echo $(rm a) `ls b` "x $(pwd)" <(cat c) >(tee d)',
      ).segments.single;
      expect(segment.commandName, 'echo');
      expect(
        [
          for (final script in segment.nested)
            for (final s in script.segments) s.commandName,
        ],
        ['rm', 'ls', 'pwd', 'cat', 'tee'],
      );
    });

    test('подстановка в цели перенаправления тоже разбирается', () {
      expect(_allNames(r'echo x > $(rm y)'), ['echo', 'rm']);
    });

    test(r'арифметика $(( )) и ${ } командами не считаются', () {
      expect(_allNames(r'echo $((1 + 2)) ${HOME}'), ['echo']);
    });
  });

  group('sh -c и eval (правило 3)', () {
    test('аргумент после -c у shell разбирается как команда', () {
      for (final shell in ['sh', 'bash', 'zsh', 'dash', 'ksh']) {
        expect(_allNames("$shell -c 'rm -rf build'"), [shell, 'rm']);
      }
      expect(_allNames("bash -lc 'rm x'"), ['bash', 'rm']);
    });

    test('без -c аргумент shell — файл, а не команда', () {
      expect(_allNames("bash 'rm -rf x'"), ['bash']);
    });

    test('аргументы eval разбираются как команда', () {
      expect(_allNames("eval 'rm' -rf build"), ['eval', 'rm']);
    });
  });

  group('here-document (правило 4)', () {
    test('тело — данные, не команды', () {
      expect(_allNames('cat <<EOF\nrm -rf /\nEOF\necho done'), ['cat', 'echo']);
    });

    test("<<- и разделитель в кавычках, табуляции перед концом", () {
      expect(_allNames("cat <<-'END' | wc\n\trm x\n\tEND\nls"), [
        'cat',
        'wc',
        'ls',
      ]);
    });

    test('перенаправление после here-document сохраняется', () {
      final segment = parseShell('cat <<EOF > out\nx\nEOF').segments.single;
      expect(
        [for (final r in segment.redirections) '${r.operator} ${r.target}'],
        ['<< EOF', '> out'],
      );
    });
  });

  group('лаунчеры и присваивания (правила 5, 6)', () {
    test('снимаются вместе с опциями', () {
      final segment = parseShell(
        'A=1 sudo -u x env -i B=2 timeout -s KILL 5 nice -n 5 nohup time -p '
        'stdbuf -oL command exec builtin rm -rf build',
      ).segments.single;
      expect(segment.words, ['rm', '-rf', 'build']);
      expect(segment.privileged, isTrue);
    });

    test('xargs с флагами', () {
      expect(parseShell('xargs -0 -n 1 -I {} rm {}').segments.single.words, [
        'rm',
        '{}',
      ]);
    });

    test('doas, pkexec и su запоминаются как привилегированные', () {
      expect(parseShell('doas -u root id').segments.single.words, ['id']);
      expect(parseShell('doas id').segments.single.privileged, isTrue);
      expect(parseShell('pkexec id').segments.single.privileged, isTrue);
      expect(parseShell("su -c 'id'").segments.single.privileged, isTrue);
      expect(parseShell('echo sudo').segments.single.privileged, isFalse);
    });

    test('имя команды — базовое имя пути', () {
      expect(parseShell('/bin/rm -rf x').segments.single.commandName, 'rm');
      expect(parseShell('/usr/bin/sudo /bin/rm x').segments.single.words, [
        '/bin/rm',
        'x',
      ]);
    });
  });

  group('перенаправления (правило 7)', () {
    String redirections(String command) => [
      for (final r in parseShell(command).segments.single.redirections)
        '${r.fd ?? ''}${r.operator}${r.target}',
    ].join(' ');

    test('слитно и отдельным словом', () {
      expect(redirections('cat x >/dev/sda'), '>/dev/sda');
      expect(redirections('cat x > /dev/sda'), '>/dev/sda');
      expect(redirections('echo hi>>f'), '>>f');
    });

    test('>|, &>, N> и дублирование дескриптора', () {
      expect(
        redirections('cmd >| a &> b 3> c 2>&1 < d'),
        '>|a &>b 3>c 2>&1 <d',
      );
    });

    test('сегмент только из перенаправления сохраняется', () {
      expect(redirections('> /dev/null'), '>/dev/null');
    });

    test('запись или нет', () {
      final rs = parseShell(
        'cmd > a 2>&1 < b >&c',
      ).segments.single.redirections;
      expect([for (final r in rs) r.writes], [true, false, false, true]);
    });

    test('без цели — ошибка разбора', () {
      expect(() => parseShell('echo >'), throwsA(isA<ShellParseException>()));
    });
  });

  group('глубина и ошибки (правило 8)', () {
    test('глубина 4 допустима, 5 — ошибка', () {
      expect(_allNames(r'echo $(echo $(echo $(echo $(rm x))))').last, 'rm');
      expect(
        () => parseShell(r'echo $(echo $(echo $(echo $(echo $(rm x)))))'),
        throwsA(isA<ShellParseException>()),
      );
      // Вложенность через eval и sh -c считается так же, как подстановки.
      expect(_allNames('eval eval eval eval rm x').last, 'rm');
      expect(
        () => parseShell('eval eval eval eval eval rm x'),
        throwsA(isA<ShellParseException>()),
      );
      expect(
        () => parseShell(r"sh -c 'eval eval eval $(rm x)'"),
        throwsA(isA<ShellParseException>()),
      );
    });

    test('незакрытые кавычки и подстановки', () {
      for (final command in [
        'echo "abc',
        "echo 'abc",
        r'echo $(ls',
        'echo `ls',
        r'echo ${HOME',
        "sh -c 'echo \"x'",
        'echo )',
      ]) {
        expect(
          () => parseShell(command),
          throwsA(isA<ShellParseException>()),
          reason: command,
        );
      }
    });
  });

  group('env -S / --split-string (PERM-11, §7.6.1)', () {
    test('значение разбирается как текст sh -c', () {
      for (final command in [
        "env -S 'rm x'",
        "env --split-string='rm x'",
        "env -S'rm x'",
        "env -iS 'rm x'",
      ]) {
        expect(_allNames(command), contains('rm'), reason: command);
      }
    });

    test('обычный env не добавляет команд', () {
      expect(_allNames('env FOO=1 ls'), ['ls']);
    });
  });

  group('env -S: границы разбора (ревью)', () {
    test('остаток после значения -S не разбирается как опции env', () {
      expect(_allNames('env -S rm -rf /'), contains('rm'));
      expect(_allNames("env -S'' rm -rf /"), contains('rm'));
      expect(_allNames('env --split-string= rm -rf /'), contains('rm'));
    });

    test('значение с опциями env даёт команду', () {
      expect(_allNames("env -S '-i rm x'"), contains('rm'));
      expect(_allNames("env -S '-S rm x'"), contains('rm'));
    });
  });

  group('env -S: токенизатор значения (PERM-11, §7.6.1)', () {
    test('метасимволы shell в значении — данные аргументов', () {
      for (final command in [
        "env -S 'rm ; -rf x'",
        "env -S 'rm & -rf x'",
        "env -S 'rm | -rf x'",
        "env -S 'rm <<x -rf'",
      ]) {
        expect(_allNames(command).whereType<String>(), ['rm'], reason: command);
      }
    });
  });

  // Дерево команд для модели рабочего каталога (change
  // `harden-exec-cwd-tracking`, D2, D6–D8, D10): связки, блоки, снятые
  // лаунчеры, происхождение вложенного текста.
  group('связки, отрицание и блоки (D2, D6, D10)', () {
    test('связка конвейера со следующим: &&, ||, ;, &, перевод строки', () {
      expect(_render('a && b || c; d | e & f\ng'), 'a && b || c ; d|e & f ; g');
    });

    test('! — отрицание конвейера, а не команда', () {
      expect(_render('! a && b'), '!a && b');
      expect(_allNames('! rm x'), ['rm']);
    });

    test('зарезервированные слова сняты: у сегментов команды a, b, c, d', () {
      expect(_allNames('if a; then b; elif c; else d; fi'), [
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(_allNames('while a; do b; done'), ['a', 'b']);
      expect(_allNames('until a; do b; done'), ['a', 'b']);
      expect(_allNames('if ! a; then b; fi'), ['a', 'b']);
    });

    test('плоский вид конвейеров не меняется', () {
      expect(_shape('if a; then b; fi'), [
        [
          ['a'],
        ],
        [
          ['b'],
        ],
      ]);
    });

    test('заголовок for/select — не команда; подстановка в нём остаётся', () {
      expect(_allNames('for f in x y; do cat "\$f"; done'), ['cat']);
      expect(_allNames('select f in x y; do cat "\$f"; done'), ['cat']);
      expect(_allNames('for f; do cat "\$f"; done'), ['cat']);
      expect(
        _allNames(r'for f in $(ls d); do cat "$f"; done').whereType<String>(),
        ['ls', 'cat'],
      );
    });

    test('блоки: подоболочка, группа, if, цикл', () {
      expect(_render('(a; b) && { c; }'), 'subshell{a ; b} && group{c}');
      expect(
        _render('if a; then b; elif c; else d; fi'),
        'conditional{a ; b ; c ; d}',
      );
      expect(_render('while a; do b; done'), 'loop{a ; b}');
      expect(_render('for f in x; do a; done'), 'loop{a}');
      expect(_render('a; (b; (c))'), 'a ; subshell{b ; subshell{c}}');
    });

    test('связка после блока принадлежит блоку', () {
      expect(_render('if a; then b; fi && c'), 'conditional{a ; b} && c');
      expect(_render('(a) || b'), 'subshell{a} || b');
      expect(_render('{ a; } & b'), 'group{a} & b');
    });

    test('тело функции: name() { … } и function name { … }', () {
      expect(_render('f(){ a; }; b'), 'function{a} ; b');
      expect(_render('function f { a; }; b'), 'function{a} ; b');
      expect(_render('function f() { a; }'), 'function{a}');
      expect(_render('f() ( a )'), 'function{a}');
    });

    test('блок стадией конвейера', () {
      expect(_render('{ a; } | c'), 'group{a}|c');
      expect(_render('( a ) | c'), 'subshell{a}|c');
      expect(_render('if a; then b; fi | c'), 'conditional{a ; b}|c');
      expect(_render('a | { b; }'), 'a|group{b}');
    });

    test('перенаправление после done и } принадлежит блоку', () {
      final loop =
          parseShell(
                'while read l; do echo "\$l"; done < in.txt',
              ).commands.single.stages.single
              as ShellBlock;
      expect(loop.kind, ShellBlockKind.loop);
      expect(
        [
          for (final r in loop.redirections!.redirections)
            '${r.operator}${r.target}',
        ],
        ['<in.txt'],
      );
      final group =
          parseShell('{ a; } > out').commands.single.stages.single
              as ShellBlock;
      expect(group.redirections!.redirections.single.target, 'out');
      expect(group.redirections!.redirections.single.writes, isTrue);
      expect(group.redirections!.words, isEmpty);
    });

    test('case по-прежнему неразбираем; лишние и незакрытые блоки — тоже', () {
      for (final command in [
        'case x in a) b;; esac',
        'for ((i=0; i<3; i++)); do a; done',
        'if a; then b',
        'fi',
        'then a',
        'do a',
        '{ a',
        'if a; then b; done',
      ]) {
        expect(
          () => parseShell(command),
          throwsA(isA<ShellParseException>()),
          reason: command,
        );
      }
    });

    test('for/select без in: do закрывает заголовок; in даёт список', () {
      expect(_allNames('for x do a; done'), ['a']);
      expect(_allNames('select x do a; done'), ['a']);
      expect(_render('for x do a; done'), 'loop{a}');
      expect(_render('for x in p q; do a; done'), 'loop{a}');
      expect(_render('for x; do a; done'), 'loop{a}');
      expect(_render('for x\ndo a; done'), 'loop{a}');
      expect(_render('for x in p q\ndo a; done'), 'loop{a}');
      for (final command in ['for x y; do a; done', 'for; do a; done']) {
        expect(
          () => parseShell(command),
          throwsA(isA<ShellParseException>()),
          reason: command,
        );
      }
    });

    test(
      '! и другие зарезервированные слова после перенаправления — слова',
      () {
        expect(_allNames('>/dev/null ! cd /tmp'), ['!']);
        expect(_allNames('>/dev/null if x'), ['if']);
      },
    );

    test('двойное отрицание — ошибка разбора', () {
      expect(() => parseShell('! ! a'), throwsA(isA<ShellParseException>()));
      expect(_allNames('! a && ! b'), ['a', 'b']);
    });

    test('переменная заголовка цикла хранится у блока', () {
      final loop =
          parseShell('for x in a; do b; done').commands.single.stages.single
              as ShellBlock;
      expect(loop.variable, 'x');
    });

    test('command -v/-V: только поиск; лаунчер с путём — внешний (A3)', () {
      ShellSegment seg(String c) => parseShell(c).segments.single;
      expect(seg('command -v cd x').lookupOnly, isTrue);
      expect(seg('command -pV cd').lookupOnly, isTrue);
      expect(seg('command command -v cd').lookupOnly, isTrue);
      expect(seg('command cd x').lookupOnly, isFalse);
      expect(seg('/usr/bin/command cd x').launchers, ['external command']);
    });

    test('маска и скобки в первом слове команды (A2)', () {
      ShellSegment seg(String c) => parseShell(c).segments.single;
      expect(seg('[c]d x').commandWordGlob, isTrue);
      expect(seg('{cd,x}').commandWordGlob, isTrue);
      expect(seg('c? x').commandWordGlob, isTrue);
      expect(seg('"[c]d" x').commandWordGlob, isFalse);
      expect(seg('[ -f x ]').commandWordGlob, isFalse);
      expect(seg('[[ -f x ]]').commandWordGlob, isFalse);
      expect(seg('cd x').commandWordGlob, isFalse);
    });

    test('раскрытие до первой / без кавычек может разбиться на слова (A2)', () {
      bool split(String c) => parseShell(c).segments.single.commandWordSplit;
      expect(split(r'$d/run'), isTrue);
      expect(split(r'${d}/run'), isTrue);
      expect(split(r'$(x)/run'), isTrue);
      expect(split(r'$d x'), isTrue);
      expect(split(r'"$d"/run'), isFalse);
      expect(split(r'"${d}"/run'), isFalse);
      expect(split(r'$HOME/bin/tool'), isFalse);
      expect(split(r'${HOME}/bin/tool'), isFalse);
      expect(split(r'${CODELAB_HOME}/x'), isFalse);
      expect(split(r'./$x'), isFalse);
      expect(split(r'$HOMEX/run'), isTrue);
      expect(split('cd x'), isFalse);
    });

    test('+= и NAME[i]= — присваивания, а не имя команды (A5)', () {
      expect(parseShell('a+=1 rm x').segments.single.words, ['rm', 'x']);
      expect(parseShell('a[0]=1 rm x').segments.single.words, ['rm', 'x']);
      expect(parseShell('a[0]+=1 rm x').segments.single.words, ['rm', 'x']);
    });

    test('предел вложенности блоков', () {
      expect(_allNames('${'{ ' * 64}a;${' }' * 64}'), ['a']);
      expect(
        () => parseShell('${'{ ' * 65}a;${' }' * 65}'),
        throwsA(isA<ShellParseException>()),
      );
      expect(() => parseShell('{ ' * 100), throwsA(isA<ShellParseException>()));
      expect(_allNames('${'{ ' * 10}a;${' }' * 10}'), ['a']);
    });

    test('слово в кавычках и аргумент не считаются зарезервированными', () {
      expect(_allNames('"if" x'), ['if']);
      expect(_allNames('echo if then fi'), ['echo']);
      expect(_allNames(r'\! x'), ['!']);
    });
  });

  group('снятые лаунчеры (D7)', () {
    List<String> launchers(String command) =>
        parseShell(command).segments.single.launchers;

    test('имена снятых лаунчеров по порядку', () {
      expect(launchers('env cd x'), ['env']);
      expect(launchers('command cd x'), ['command']);
      expect(launchers('builtin cd x'), ['builtin']);
      expect(launchers('time cd x'), ['time']);
      expect(launchers('sudo -D d cd x'), ['sudo']);
      expect(launchers('A=1 nohup time rm x'), ['nohup', 'time']);
      expect(launchers('cd x'), isEmpty);
      expect(launchers('A=1 cd x'), isEmpty);
    });
  });

  group('происхождение вложенного текста (D8)', () {
    ShellOrigin originOf(String command, {int index = 0}) =>
        parseShell(command).segments.first.nested[index].origin;

    test('подстановки', () {
      expect(originOf(r'echo $(a)'), ShellOrigin.substitution);
      expect(originOf('echo `a`'), ShellOrigin.substitution);
      expect(originOf('cat <(a)'), ShellOrigin.substitution);
      expect(originOf('tee >(a)'), ShellOrigin.substitution);
      expect(originOf('echo x > \$(a)'), ShellOrigin.substitution);
    });

    test('новый процесс: sh -c, env -S, watch, script -c, find -exec, rg', () {
      expect(originOf("sh -c 'a'"), ShellOrigin.command);
      expect(originOf("bash -lc 'a'"), ShellOrigin.command);
      expect(originOf("env -S 'a'"), ShellOrigin.command);
      expect(originOf("watch -n 1 'a'"), ShellOrigin.command);
      expect(originOf("script -c 'a' /dev/null"), ShellOrigin.command);
      expect(originOf(r'find . -exec a {} \;'), ShellOrigin.command);
      expect(originOf(r'find . -ok a {} \;'), ShellOrigin.command);
      expect(originOf("rg --pre a x"), ShellOrigin.command);
    });

    test('eval — текущая оболочка; подстановка в его словах — своя', () {
      expect(originOf('eval a'), ShellOrigin.eval);
      final nested = parseShell(r'eval $(x) a').segments.single.nested;
      expect(nested.map((s) => s.origin), [
        ShellOrigin.substitution,
        ShellOrigin.eval,
      ]);
    });

    test('чужой каталог: git, переменные-команды, execdir, trap', () {
      expect(originOf("git -c core.pager=a log"), ShellOrigin.foreign);
      expect(originOf("git -c 'alias.x=!a' x"), ShellOrigin.foreign);
      expect(originOf('GIT_PAGER=a git log'), ShellOrigin.foreign);
      expect(originOf('EDITOR=a git commit'), ShellOrigin.foreign);
      expect(originOf(r'find . -execdir a {} \;'), ShellOrigin.foreign);
      expect(originOf(r'find . -okdir a {} \;'), ShellOrigin.foreign);
      expect(originOf("trap 'a' EXIT"), ShellOrigin.foreign);
    });

    test('trap: первый аргумент — команда; сброс и опции — нет', () {
      expect(_allNames("trap 'rm -rf /' EXIT"), ['trap', 'rm']);
      expect(_allNames("trap -- 'rm x' INT TERM"), ['trap', 'rm']);
      expect(_allNames('trap - EXIT'), ['trap']);
      expect(_allNames('trap -p'), ['trap']);
      expect(_allNames("trap '' INT"), ['trap']);
    });

    test('верхний уровень — root', () {
      expect(parseShell('a').origin, ShellOrigin.root);
    });
  });

  group(r"ANSI-C строки $'…'", () {
    List<String> words(String c) =>
        parseShell(c).pipelines.first.stages.first.words;

    test('escape-последовательности раскрываются', () {
      expect(words(r"echo $'a\nb'"), ['echo', 'a\nb']);
      expect(words(r"echo $'a\x20b\101A'"), ['echo', 'a bAA']);
      expect(words(r"echo $'it\'s'"), ['echo', "it's"]);
      expect(words(r"echo $'\q'"), ['echo', r'\q']);
    });

    test('байтовые escape декодируются как UTF-8', () {
      expect(words(r"echo $'\320\241'"), ['echo', 'С']);
      expect(words(r"echo $'\xd0\xa1x\xd0\xb5'"), ['echo', 'Сxе']);
      for (final bad in [r"echo $'\xd0\u0041\xa1'", r"echo $'\xff'"]) {
        expect(() => parseShell(bad), throwsA(isA<ShellParseException>()));
      }
      expect(words(r"echo $'\562m'"), ['echo', 'rm']);
    });

    test('незакрытая строка неразбираема', () {
      expect(
        () => parseShell(r"echo $'abc"),
        throwsA(isA<ShellParseException>()),
      );
    });
  });
}
