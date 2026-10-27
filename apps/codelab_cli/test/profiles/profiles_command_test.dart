// Команда `codelab profiles` (tasks 2.3; spec codelab-cli «Профили
// подключения CLI»; design.md change `add-codelab-cli`, D4).

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../support/fake_cli_io.dart';

void main() {
  late Directory tmp;
  late Map<String, String> environment;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('codelab_profiles_');
    environment = {'CODELAB_HOME': '${tmp.path}/home'};
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(int, FakeCliIo)> run(List<String> args) async {
    final io = FakeCliIo();
    final code = await runCodelab(
      ['profiles', ...args],
      environment: environment,
      io: io,
    );
    return (code, io);
  }

  test('add then show keeps quoted arguments', () async {
    final (added, addIo) = await run([
      'add',
      'py',
      'stdio:python -m "codelab agent" --stdio',
    ]);
    expect(added, 0);
    expect(addIo.stdoutText, 'Saved profile py.\n');

    final (shown, io) = await run(['show', 'py']);

    expect(shown, 0);
    expect(io.stdoutText, contains('type: stdio'));
    expect(io.stdoutText, contains('command: python'));
    expect(io.stdoutText, contains('args: ["-m","codelab agent","--stdio"]'));
  });

  test('a WebSocket profile stores the token reference, never a '
      'value', () async {
    environment['CODELAB_AGENT_TOKEN'] = 'super-secret-token';

    final (code, _) = await run(['add', 'remote', 'wss://agent.test/acp']);
    final (_, io) = await run(['show', 'remote']);

    expect(code, 0);
    expect(io.stdoutText, contains('uri: wss://agent.test/acp'));
    expect(io.stdoutText, contains(r'token: $CODELAB_AGENT_TOKEN'));
    final file = File('${tmp.path}/home/profiles.json').readAsStringSync();
    expect(file, isNot(contains('super-secret-token')));
    expect(io.stdoutText, isNot(contains('super-secret-token')));
  });

  test('list prints one line per profile', () async {
    await run(['add', 'default', 'stdio:codelab-agent serve --stdio']);
    await run(['add', 'remote', 'ws://127.0.0.1:8765']);

    final (code, io) = await run(['list']);

    expect(code, 0);
    expect(io.stdoutText.trimRight().split('\n'), [
      'default  stdio: codelab-agent serve --stdio',
      'remote   ws: ws://127.0.0.1:8765',
    ]);
  });

  test('list without profiles says so', () async {
    final (code, io) = await run(['list']);

    expect(code, 0);
    expect(io.stdoutText, contains('No agent profiles.'));
  });

  test('remove deletes a profile; an unknown one is an error', () async {
    await run(['add', 'py', 'stdio:codelab serve --stdio']);

    final (removed, io) = await run(['remove', 'py']);
    final (missing, missingIo) = await run(['remove', 'py']);

    expect(removed, 0);
    expect(io.stdoutText, 'Removed profile py.\n');
    expect(missing, 1);
    expect(missingIo.stderrText, contains('Unknown agent profile "py"'));
  });

  test('show of an unknown profile is an error', () async {
    final (code, io) = await run(['show', 'nope']);

    expect(code, 1);
    expect(io.stderrText, contains('Unknown agent profile "nope"'));
  });

  test('add rejects embedded, reserved and malformed ids', () async {
    for (final args in <List<String>>[
      ['add', 'x', 'embedded'],
      ['add', 'embedded', 'stdio:x'],
      ['add', 'bad id', 'stdio:x'],
      ['add', 'x', 'stdio:'],
      ['add', 'x', 'just-a-word'],
      ['add', 'x'],
      ['frobnicate'],
      [],
    ]) {
      final (code, io) = await run(args);

      expect(code, 64, reason: args.join(' '));
      expect(io.stdoutText, isEmpty, reason: args.join(' '));
    }
  });
}
