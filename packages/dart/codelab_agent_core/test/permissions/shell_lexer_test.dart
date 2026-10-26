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
}
