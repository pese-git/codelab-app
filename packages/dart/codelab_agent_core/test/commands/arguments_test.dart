import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Разбор и подстановка аргументов шаблона (agent-slash-commands
/// «Разворачивание команды»; `agent-core/17-2-skills-and-templates.md`
/// §17.2.6; SKL-8; design.md change `add-agent-project-files`, D8).
void main() {
  group('splitArguments', () {
    test('splits on any whitespace', () {
      expect(splitArguments('a  b\tc\nd'), ['a', 'b', 'c', 'd']);
      expect(splitArguments(''), isEmpty);
      expect(splitArguments('   '), isEmpty);
    });

    test('quotes group a word and are removed', () {
      expect(splitArguments('lib/parser "error handling"'), [
        'lib/parser',
        'error handling',
      ]);
      expect(splitArguments("'a b' c"), ['a b', 'c']);
    });

    test('an empty quoted string is an empty argument', () {
      expect(splitArguments('a "" b'), ['a', '', 'b']);
    });

    test('inside double quotes only \\" and \\\\ are escapes', () {
      expect(splitArguments(r'"say \"hi\" \\ \n"'), [r'say "hi" \ \n']);
    });

    test('inside single quotes there are no escapes', () {
      expect(splitArguments(r"'a\b\'"), [r'a\b\']);
    });

    test('outside quotes a backslash yields the next character', () {
      expect(splitArguments(r'a\ b \"c'), ['a b', '"c']);
    });

    test('a trailing backslash stays literal', () {
      expect(splitArguments(r'a\'), [r'a\']);
    });

    test('an unclosed quote is closed by the end of the input', () {
      expect(splitArguments('"error handling'), ['error handling']);
      expect(splitArguments("x 'open end"), ['x', 'open end']);
    });

    test('adjacent quoted parts join into one word', () {
      expect(splitArguments('a"b c"d'), ['ab cd']);
    });

    test('does not execute anything: dollar and backticks are text', () {
      expect(splitArguments(r'$(rm -rf) `ls`'), [r'$(rm', '-rf)', '`ls`']);
    });
  });

  group('substituteArguments', () {
    String sub(String body, String raw) =>
        substituteArguments(body, raw, splitArguments(raw));

    test(r'$ARGUMENTS is the raw text as typed', () {
      expect(sub(r'All: $ARGUMENTS', 'a  "b c"'), 'All: a  "b c"');
    });

    test(r'$1..$9 are the arguments, a missing one is empty', () {
      expect(sub(r'[$1][$2][$3]', 'a b'), '[a][b][]');
      expect(sub(r'$9', 'a'), '');
    });

    test(r'$$ is a literal dollar', () {
      expect(sub(r'cost $$5 and $$ARGUMENTS', ''), r'cost $5 and $ARGUMENTS');
    });

    test(r'$10 is $1 followed by 0', () {
      expect(sub(r'$10', 'a b'), 'a0');
    });

    test(r'$ before another character stays literal, $0 too', () {
      expect(sub(r'a $ b $x $0 end$', ''), r'a $ b $x $0 end$');
    });

    test(r'a value that looks like $ARGUMENTS is not expanded again', () {
      expect(sub(r'X $1', r"'$ARGUMENTS'"), r'X $ARGUMENTS');
      expect(sub(r'X $1 $2', r'$2 b'), r'X $2 b');
      expect(sub(r'X $ARGUMENTS', r'$1'), r'X $1');
    });

    test('without placeholders a non-empty raw is appended', () {
      expect(sub('Do it', 'lib/x'), 'Do it\n\nARGUMENTS: lib/x');
    });

    test('without placeholders and with empty raw the body is unchanged', () {
      expect(sub('Do it', ''), 'Do it');
    });

    test(r'an escaped dollar is not a placeholder, so raw is appended', () {
      expect(sub(r'cost $$1', 'x'), 'cost \$1\n\nARGUMENTS: x');
    });

    test('with a placeholder raw is not appended', () {
      expect(sub(r'only $1', 'x y'), 'only x');
    });

    // Литерал доллара обратной косой (agent-slash-commands «Разворачивание
    // команды», сценарии «Литерал доллара…»; design.md change
    // `add-agent-skills`, D8; решения Q7, Q15 (а), Q28). Функция одна для
    // шаблонов и навыков.
    group(r'literal dollar: \$ and $$ (Q15 (а))', () {
      test(r'scenario "Литерал доллара через обратную косую": \$1 is the '
          r'text $1, $1 still substitutes', () {
        expect(sub(r'cost \$1, arg $1', 'x'), r'cost $1, arg x');
      });

      test(r'scenario "Литерал доллара удвоением": $$1 is the text $1', () {
        expect(sub(r'cost $$1, arg $1', 'x'), r'cost $1, arg x');
      });

      test(r'scenario "Литерал доллара в навыке": \$HOME and $$PATH', () {
        expect(
          sub(r'Use \$HOME and $$PATH; topic: $1', 'cache'),
          r'Use $HOME and $PATH; topic: cache',
        );
      });

      test(r'\$ARGUMENTS and \$1 stay the literals $ARGUMENTS and $1', () {
        // Тело только с `\$…` — «без плейсхолдеров»: хвост дописывается (D18).
        expect(
          sub(r'\$ARGUMENTS \$1', 'a b'),
          '\$ARGUMENTS \$1\n\nARGUMENTS: a b',
        );
        expect(
          sub(r'\$ARGUMENTS and $ARGUMENTS', 'a b'),
          r'$ARGUMENTS and a b',
        );
      });

      test(r'a lone \$ gives $ and is not a placeholder', () {
        expect(sub(r'price: \$', ''), r'price: $');
        expect(sub(r'\$ then $1', 'q'), r'$ then q');
      });

      test(r'a backslash before any other character stays literal', () {
        expect(sub(r'a\nb \x $1', 'q'), r'a\nb \x q');
        expect(sub(r'tail\', ''), r'tail\');
      });

      test(r'a double backslash is copied as is and the next $ is parsed '
          r'by the ordinary rule (D18): \\$1 gives \\x', () {
        expect(sub(r'\\$1', 'x'), r'\\x');
        expect(sub(r'a\\$1', 'x'), r'a\\x');
        expect(sub(r'\\$$', ''), r'\\$');
        expect(sub(r'C:\\dir\\$1', 'f'), r'C:\\dir\\f');
      });

      test(r'a substituted value with \$ is not scanned again', () {
        // Разбор аргументов снимает `\` вне кавычек: `$1` — это `$ARGUMENTS`.
        expect(sub(r'X $1', r'\$ARGUMENTS'), r'X $ARGUMENTS');
        expect(sub(r'X $ARGUMENTS', r'\$1'), r'X \$1');
      });

      test(r'\$ does not make a body "with placeholders": the tail stays '
          '(scenario "Хвост ARGUMENTS без плейсхолдеров")', () {
        expect(sub(r'cost \$1', 'x'), 'cost \$1\n\nARGUMENTS: x');
        expect(
          sub(r'cost \$ARGUMENTS', 'x y'),
          'cost \$ARGUMENTS\n\nARGUMENTS: x y',
        );
        expect(sub(r'cost \$1', ''), r'cost $1');
      });

      test(r'a real placeholder next to \$ cancels the tail', () {
        expect(sub(r'\$1 is $1', 'x'), r'$1 is x');
      });
    });

    test('scenario "Отсутствующий аргумент": a missing positional argument '
        'is an empty string (Q28)', () {
      expect(sub(r'[$1|$2]', 'a'), '[a|]');
      expect(sub(r'[$1|$2|$3]', ''), '[||]');
    });

    test('templates stay as before: bodies without backslash behave as '
        'in the pre-skills tests', () {
      expect(
        sub(
          r'Review $1 focusing on $2. All: $ARGUMENTS',
          'lib "error handling"',
        ),
        'Review lib focusing on error handling. All: lib "error handling"',
      );
      expect(sub('Do it', 'lib/x'), 'Do it\n\nARGUMENTS: lib/x');
    });
  });
}
