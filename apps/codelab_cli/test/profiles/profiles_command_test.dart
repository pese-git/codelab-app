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
    expect(io.stdoutText, contains('token: env CODELAB_AGENT_TOKEN'));
    final file = File('${tmp.path}/home/profiles.json').readAsStringSync();
    expect(file, isNot(contains('super-secret-token')));
    expect(io.stdoutText, isNot(contains('super-secret-token')));
  });

  test('list prints one line per profile', () async {
    await run(['add', 'dev', 'stdio:codelab-agent serve --stdio']);
    await run(['add', 'remote', 'ws://127.0.0.1:8765']);

    final (code, io) = await run(['list']);

    expect(code, 0);
    expect(io.stdoutText.trimRight().split('\n'), [
      'dev     stdio: codelab-agent serve --stdio',
      'remote  ws: ws://127.0.0.1:8765',
    ]);
    expect(io.stderrText, isEmpty);
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

  test('add rejects embedded as an id and as a value with the built-in '
      'hint and leaves the store unchanged', () async {
    for (final args in <List<String>>[
      ['add', 'x', 'embedded'],
      ['add', 'embedded', 'stdio:x'],
      ['add', 'embedded', 'embedded'],
    ]) {
      final (code, io) = await run(args);

      expect(code, 64, reason: args.join(' '));
      expect(io.stdoutText, isEmpty, reason: args.join(' '));
      expect(
        io.stderrText,
        contains('embedded is built in; use --agent embedded'),
        reason: args.join(' '),
      );
    }
    expect(File('${tmp.path}/home/profiles.json').existsSync(), isFalse);
  });

  test('add rejects malformed ids and values', () async {
    for (final args in <List<String>>[
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

  group('reserved ids and the old "default" record (D21)', () {
    const oldDefault =
        '{"type": "stdio", "id": "default", '
        '"label": "Default", "command": "/opt/secret-agent", '
        '"args": ["--key", "hidden-arg"], "env": {"HIDDEN": "hidden-env"}, '
        '"runInProjectDirectory": false}';
    const dev =
        '{"type": "stdio", "id": "dev", "label": "Dev", '
        '"command": "dev-agent", "args": [], "env": {}, '
        '"runInProjectDirectory": false}';
    const warning =
        'profile "default" in profiles.json is ignored: default is the '
        'built-in agent; remove it with codelab profiles remove default';

    File profilesFile() => File('${tmp.path}/home/profiles.json');

    void writeProfiles(List<String> records) {
      profilesFile().createSync(recursive: true);
      profilesFile().writeAsStringSync(
        '{"version": 1, "profiles": [${records.join(', ')}]}',
      );
    }

    test('add rejects default as an id and as a value, the file is '
        'unchanged', () async {
      writeProfiles([dev]);
      final before = profilesFile().readAsStringSync();

      for (final args in <List<String>>[
        ['add', 'default', 'stdio:x'],
        ['add', 'x', 'default'],
      ]) {
        final (code, io) = await run(args);

        expect(code, 64, reason: args.join(' '));
        expect(io.stdoutText, isEmpty, reason: args.join(' '));
        expect(
          io.stderrText,
          contains('default is the built-in agent; use --agent embedded'),
          reason: args.join(' '),
        );
      }
      expect(profilesFile().readAsStringSync(), before);
    });

    test('add rejects an id that breaks the kit rule with the text of the '
        'rule, the file is unchanged', () async {
      writeProfiles([dev]);
      final before = profilesFile().readAsStringSync();

      for (final id in ['Dev', '-x', 'a:b', 'a' * 65]) {
        final (code, io) = await run(['add', id, 'stdio:x']);

        expect(code, 64, reason: id);
        expect(io.stdoutText, isEmpty, reason: id);
        expect(io.stderrText, contains('Invalid profile id'), reason: id);
        expect(io.stderrText, contains('lowercase'), reason: id);
      }
      expect(profilesFile().readAsStringSync(), before);
    });

    test('list hides the old default record and warns once, without the '
        'record data; the file is unchanged', () async {
      writeProfiles([oldDefault, dev]);
      final before = profilesFile().readAsStringSync();

      final (code, io) = await run(['list']);

      expect(code, 0);
      expect(io.stdoutText.trimRight().split('\n'), ['dev  stdio: dev-agent']);
      expect(io.stderrText.trimRight(), warning);
      for (final hidden in ['/opt/secret-agent', 'hidden-arg', 'hidden-env']) {
        expect(io.stderrText + io.stdoutText, isNot(contains(hidden)));
      }
      expect(profilesFile().readAsStringSync(), before);
    });

    test('list with only the old default record says there are no '
        'profiles and still warns', () async {
      writeProfiles([oldDefault]);

      final (code, io) = await run(['list']);

      expect(code, 0);
      expect(io.stdoutText, contains('No agent profiles.'));
      expect(io.stdoutText, isNot(contains('profiles add default')));
      expect(io.stderrText.trimRight(), warning);
    });

    test('show default prints the built-in profile and warns once', () async {
      writeProfiles([oldDefault, dev]);

      final (code, io) = await run(['show', 'default']);

      expect(code, 0);
      expect(io.stdoutText, contains('type: embedded'));
      expect(io.stdoutText, contains('hostProfile: embedded-cli'));
      expect(io.stderrText.trimRight(), warning);
      expect(io.stderrText + io.stdoutText, isNot(contains('/opt/secret')));
    });

    test('show default without the old record prints the built-in profile '
        'and does not warn', () async {
      writeProfiles([dev]);

      final (code, io) = await run(['show', 'default']);

      expect(code, 0);
      expect(io.stdoutText, contains('type: embedded'));
      expect(io.stderrText, isEmpty);
    });

    test('remove default deletes the old record, then list is quiet', () async {
      writeProfiles([oldDefault, dev]);

      final (removed, removeIo) = await run(['remove', 'default']);
      final (listed, listIo) = await run(['list']);

      expect(removed, 0);
      expect(removeIo.stdoutText, 'Removed profile default.\n');
      expect(profilesFile().readAsStringSync(), isNot(contains('"default"')));
      expect(listed, 0);
      expect(listIo.stderrText, isEmpty);
      expect(listIo.stdoutText, contains('dev'));
    });
  });

  test(
    'a token reference that is not env: is never printed (show, list)',
    () async {
      Directory('${tmp.path}/home').createSync(recursive: true);
      File('${tmp.path}/home/profiles.json').writeAsStringSync(
        '{"version":1,"profiles":[{"id":"leaky","label":"Leaky",'
        '"type":"webSocket","uri":"wss://agent.test/acp",'
        '"tokenRef":"sk-test-leak-123"}]}',
      );

      for (final args in [
        ['show', 'leaky'],
        ['list'],
      ]) {
        final (code, io) = await run(args);
        expect(code, 0, reason: '$args');
        expect(
          io.stdoutText + io.stderrText,
          isNot(contains('sk-test-leak-123')),
        );
      }
      final (_, io) = await run(['show', 'leaky']);
      expect(
        io.stdoutText,
        contains(
          'token: unrecognized token reference (not supported in this version)',
        ),
      );
    },
  );
}
