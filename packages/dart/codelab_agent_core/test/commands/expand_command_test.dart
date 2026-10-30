import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Выбор команды в тексте промпта (agent-slash-commands «Разворачивание
/// команды»; §17.2.6 шаги 1 и 4; design.md change `add-agent-project-files`,
/// D8).
void main() {
  CommandTemplate template(String name, String body) => CommandTemplate(
    name: name,
    description: name,
    body: body,
    scope: ExtensionScope.user,
    path: '/h/prompts/$name.md',
  );

  final templates = [
    template('review', r'Review $1 focusing on $2. All: $ARGUMENTS'),
    template('t', r'[$1]'),
    template('bare', 'Just text'),
    template('a:b', 'colon'),
  ];

  CommandExpansion expand(String text) => expandCommand(text, templates);

  test('the E-07 example expands to the body with substituted arguments', () {
    final result = expand('/review lib/parser "error handling"');

    expect(result, isA<Expanded>());
    result as Expanded;
    expect(
      result.text,
      'Review lib/parser focusing on error handling. '
      'All: lib/parser "error handling"',
    );
    expect(result.command.source, SlashCommandSource.template.wire);
    expect(result.command.name, 'review');
    expect(result.command.args, 'lib/parser "error handling"');
  });

  test('a command without arguments has an empty raw', () {
    final result = expand('/bare') as Expanded;

    expect(result.text, 'Just text');
    expect(result.command.args, '');
  });

  test('raw drops leading spaces and one final newline only', () {
    expect((expand('/bare   x  y \n') as Expanded).command.args, 'x  y ');
    expect((expand('/bare\n\nx') as Expanded).command.args, 'x');
  });

  test('CRLF: the final \\r\\n is dropped, no \\r reaches the arguments', () {
    final result = expand('/t x\r\n') as Expanded;

    expect(result.command.args, 'x');
    expect(result.command.args, isNot(contains('\r')));
    expect(result.text, '[x]');
  });

  test('CRLF: spec scenario /t lib\\r\\n gives [lib|lib]', () {
    final result =
        expandCommand('/t lib\r\n', [template('t', r'[$ARGUMENTS|$1]')])
            as Expanded;

    expect(result.text, '[lib|lib]');
  });

  test('an unclosed quote is closed by the end of the input', () {
    expect((expand('/t "error handling') as Expanded).text, '[error handling]');
  });

  test('a value is not expanded again', () {
    final body = [template('t', r'X $1')];

    final result = expandCommand("/t '\$ARGUMENTS'", body) as Expanded;

    expect(result.text, r'X $ARGUMENTS');
  });

  group('not a command', () {
    for (final text in [
      '/nope x',
      '/usr/bin/foo is broken',
      'review lib',
      ' /review lib',
      '/',
      '/ review',
      '/-x',
      '/Review lib',
      '',
    ]) {
      test('"$text" goes to the model unchanged', () {
        expect(expand(text), isA<NotACommand>());
      });
    }

    test('a command word may hold colon, underscore and dash', () {
      expect(expand('/a:b'), isA<Expanded>());
      expect(expandCommand('/x_y-z', templates), isA<NotACommand>());
    });
  });
}
