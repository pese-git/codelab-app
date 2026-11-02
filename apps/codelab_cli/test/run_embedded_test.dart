// Встроенный агент в `runCodelab` (tasks 3.3; spec codelab-cli «Профили
// подключения CLI», «Встроенный агент в CLI»; design.md change
// `add-embedded-agent-mode`, D6, D8, D13 п. 1): выбор профиля без `--agent`,
// код `64` на невалидный конфиг, шов `embeddedOpener`.

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cli_io.dart';

/// Логгер, который ничего не пишет: агент в этих тестах молчит.
final class _NoLogger implements Logger {
  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}

const _script = {
  'model': {
    'provider': 'scripted',
    'modelId': 'scripted-1',
    'contextWindow': 32768,
  },
  'steps': [
    {
      'reply': [
        {'text': 'hello from the embedded agent'},
      ],
      'stopReason': 'stop',
    },
  ],
};

void main() {
  late Directory tmp;
  late Directory project;
  late String home;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('codelab_run_embedded_');
    project = Directory('${tmp.path}/project')..createSync();
    home = '${tmp.path}/home';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  EmbeddedAgentOpener scripted() => scriptedEmbeddedAgentOpener(
    llm: _script,
    codelabHome: home,
    logger: _NoLogger(),
  );

  test('without --agent and without profiles.json the embedded agent runs '
      'the turn (spec «Без профиля по умолчанию запускается встроенный '
      'агент»)', () async {
    final io = FakeCliIo();

    final code = await runCodelab(
      ['-p', 'hi', '-C', project.path],
      environment: {'CODELAB_HOME': home},
      io: io,
      embeddedOpener: scripted(),
    );

    expect(code, 0, reason: io.stderrText);
    expect(io.stdoutText, 'hello from the embedded agent\n');
  });

  test('--agent embedded beats the "default" profile: the process of '
      '"default" is not started (spec «Встроенный агент явно»)', () async {
    Directory(home).createSync(recursive: true);
    File('$home/profiles.json').writeAsStringSync(
      '{"version": 1, "profiles": [{"type": "stdio", "id": "default", '
      '"label": "Default", "command": "/nonexistent/agent", "args": [], '
      '"env": {}, "runInProjectDirectory": false}]}',
    );
    final io = FakeCliIo();

    final code = await runCodelab(
      ['-a', 'embedded', '-p', 'hi', '-C', project.path],
      environment: {'CODELAB_HOME': home},
      io: io,
      embeddedOpener: scripted(),
    );

    expect(code, 0, reason: io.stderrText);
    expect(io.stdoutText, 'hello from the embedded agent\n');
  });

  test('without --agent the "default" profile beats the embedded agent '
      '(spec «Профиль default сильнее встроенного агента»)', () async {
    Directory(home).createSync(recursive: true);
    File('$home/profiles.json').writeAsStringSync(
      '{"version": 1, "profiles": [{"type": "stdio", "id": "default", '
      '"label": "Default", "command": "/nonexistent/agent", "args": [], '
      '"env": {}, "runInProjectDirectory": false}]}',
    );
    final io = FakeCliIo();

    final code = await runCodelab(
      ['-p', 'hi', '-C', project.path],
      environment: {'CODELAB_HOME': home},
      io: io,
      embeddedOpener: scripted(),
    );

    // Агент из "default" не запускается — это ошибка подключения, а не ход
    // встроенного агента.
    expect(code, 1);
    expect(io.stdoutText, isEmpty);
    expect(io.stderrText, contains('/nonexistent/agent'));
  });

  test('a broken profiles.json without --agent is 64 and the embedded agent '
      'is not started', () async {
    Directory(home).createSync(recursive: true);
    File('$home/profiles.json').writeAsStringSync('{not json');
    var opened = 0;
    final io = FakeCliIo();

    final code = await runCodelab(
      ['-p', 'hi', '-C', project.path],
      environment: {'CODELAB_HOME': home},
      io: io,
      embeddedOpener: ({required cwd, required hostProfile}) {
        opened++;
        throw StateError('must not be called');
      },
    );

    expect(code, 64);
    expect(io.stdoutText, isEmpty);
    expect(io.stderrText, contains('Cannot read agent profiles'));
    expect(opened, 0);
  });

  test('EmbeddedAgentConfigException is 64: the text goes to stderr, stdout '
      'stays empty (spec «Невалидный конфиг встроенного агента»)', () async {
    final io = FakeCliIo();

    final code = await runCodelab(
      ['-a', 'embedded', '-p', 'hi', '-C', project.path],
      environment: {'CODELAB_HOME': home},
      io: io,
      embeddedOpener: ({required cwd, required hostProfile}) async =>
          throw EmbeddedAgentConfigException(const [], home: '/the/home'),
    );

    expect(code, 64);
    expect(io.stdoutText, isEmpty);
    expect(
      io.stderrText,
      contains(
        'Configure the embedded agent in /the/home/config.yaml; '
        'check it with: codelab config check',
      ),
    );
  });

  test('the opener receives the session folder and the embedded-cli host '
      'profile', () async {
    final calls = <({String cwd, String hostProfile})>[];
    final inner = scripted();
    final io = FakeCliIo();

    await runCodelab(
      ['-p', 'hi', '-C', project.path],
      environment: {'CODELAB_HOME': home},
      io: io,
      embeddedOpener: ({required cwd, required hostProfile}) {
        calls.add((cwd: cwd, hostProfile: hostProfile));
        return inner(cwd: cwd, hostProfile: hostProfile);
      },
    );

    expect(calls, [(cwd: project.path, hostProfile: 'embedded-cli')]);
  });

  test('without a config the real opener gives 64 with the config hint, '
      'nothing in stdout (spec «Без профиля и без конфига»)', () async {
    final io = FakeCliIo();

    final code = await runCodelab(
      ['-p', 'hi', '-C', project.path],
      environment: {'CODELAB_HOME': home, 'HOME': tmp.path},
      io: io,
    );

    expect(code, 64, reason: io.stderrText);
    expect(io.stdoutText, isEmpty);
    expect(
      io.stderrText,
      contains(
        'Configure the embedded agent in $home/config.yaml; '
        'check it with: codelab config check',
      ),
    );
  });

  test('an invalid project config names the problem with file and line '
      '(spec «Невалидный конфиг встроенного агента»)', () async {
    Directory('${project.path}/.codelab').createSync();
    File(
      '${project.path}/.codelab/config.yaml',
    ).writeAsStringSync('budget:\n  max_steps: 0\n');
    final io = FakeCliIo();

    final code = await runCodelab(
      ['-a', 'embedded', '-p', 'hi', '-C', project.path],
      environment: {'CODELAB_HOME': home, 'HOME': tmp.path},
      io: io,
    );

    expect(code, 64, reason: io.stderrText);
    expect(io.stdoutText, isEmpty);
    expect(io.stderrText, contains('budget.max_steps'));
    expect(io.stderrText, contains('config.yaml'));
  });
}
