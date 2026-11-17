import 'package:codelab_agent_core/codelab_agent_core.dart';
// Шов тестов, не публичный API (PKG-5): разбор строки и сам исполнитель.
import 'package:codelab_agent_core/src/commands/builtin_commands.dart';
import 'package:codelab_agent_core/src/commands/command_line.dart';
import 'package:test/test.dart';

/// Общий разбор строки команды (design.md change
/// `add-agent-builtin-slash-commands`, D3): одно слово и один `raw` и для
/// встроенных команд, и для шаблонов.
void main() {
  group('parseCommandLine', () {
    test('word and raw without the trailing \\r?\\n', () {
      expect(parseCommandLine('/compact focus\r\n'), (
        word: 'compact',
        raw: 'focus',
      ));
      expect(parseCommandLine('/compact focus\n')!.raw, 'focus');
      expect(parseCommandLine('/compact   a  b')!.raw, 'a  b');
      expect(parseCommandLine('/compact')!.raw, '');
    });

    test('not a command: a path, a leading space, a bare slash', () {
      expect(parseCommandLine('/usr/bin/foo'), isNull);
      expect(parseCommandLine(' /compact'), isNull);
      expect(parseCommandLine('/'), isNull);
      expect(parseCommandLine('compact'), isNull);
    });
  });

  group('BuiltinCommands.match', () {
    BuiltinCommands commands() => BuiltinCommands(
      compactNow: (focus, cancel) async => throw UnimplementedError(),
      mcpDeclared: false,
      servers: () => const [],
      reconnect: (id, cancelled) async {},
      setEnabled: (id, enabled, cancelled) async {},
      currentMode: () => ModeId.standard,
      setMode: (mode) async {},
      currentModel: () => 'a/m',
      hasModel: (id) => false,
      setModel: (id) async => id,
      workingDirectory: '/proj',
      commands: () => const [],
      templateNames: const {'review'},
    );

    test('raw of a command typed with CRLF has no \\r (the same parser as '
        'the templates)', () {
      final call = commands().match('/compact focus\r\n');

      expect(call, isA<BuiltinCall>());
      expect((call! as BuiltinCall).raw, 'focus');
      expect((call as BuiltinCall).name, BuiltinName.compact);
    });

    test('steps of D3: a template is not a command, an undeclared word is '
        'unknown, a path is text', () {
      final c = commands();

      expect(c.match('/review x'), isNull);
      expect(c.match('/usr/bin/foo'), isNull);
      expect(c.match(' /mode plan'), isNull);
      expect(c.match('/mcp list'), isA<UnknownCall>());
      expect(c.match('/config check'), isA<UnknownCall>());
    });

    test(
      'a non-ASCII word is not a command; the size of an unknown name is the length of the word in bytes',
      () {
        final call = commands().match('/нет x') as UnknownCall?;

        expect(call, isNull, reason: 'a non-ASCII word is not a command word');
        final ascii = commands().match('/nope') as UnknownCall;
        expect(ascii.nameBytes, 4);
      },
    );
  });
}
