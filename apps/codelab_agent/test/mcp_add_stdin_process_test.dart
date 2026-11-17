import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// `codelab-agent mcp add --header-stdin | --env-stdin` как процесс
/// (agent-binary «Флаги stdin у mcp add бинаря»; design.md change
/// `add-config-literal-secrets-and-migrate`, D11, R8-5). Процессы во
/// временных `CODELAB_HOME` и `HOME`, значения выдуманные.
void main() {
  late Directory temp;
  late String home;

  final token = 'ghp_${'abcdef0123' * 3}abcdef';

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_agent_mcp_stdin_');
    home = '${temp.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    File('$home/config.yaml').writeAsStringSync('secrets:\n  backend: file\n');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<(int, String, String)> run(List<String> args, {String? stdin}) async {
    final agent = await AgentProcess.start(
      args,
      environment: {'CODELAB_HOME': home, 'HOME': temp.path},
      workingDirectory: temp.path,
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      await agent.exitCode;
    });
    if (stdin != null) {
      agent.sendLine(stdin);
    }
    await agent.closeStdin();
    final code = await agent.exitCode.timeout(const Duration(seconds: 60));
    final out = StringBuffer();
    String? line;
    while ((line = await agent.nextStdoutLine()) != null) {
      out.writeln(line);
    }
    return (code, out.toString(), agent.stderrText);
  }

  test('--env-stdin: the value goes to the store, the file gets a '
      'reference', () async {
    final (code, out, err) = await run([
      'mcp',
      'add',
      'gh',
      '--type',
      'stdio',
      '--command',
      'gh-mcp',
      '--env-stdin',
      'GITHUB_TOKEN',
    ], stdin: token);

    expect(code, 0, reason: err);
    expect('$out$err', isNot(contains(token)));
    expect(
      File('$home/secrets.yaml').readAsStringSync(),
      contains('codelab/mcp/gh/github_token'),
    );
    final file = File('$home/config.yaml').readAsStringSync();
    expect(
      file,
      contains(r"GITHUB_TOKEN: '${secret:codelab/mcp/gh/github_token}'"),
    );
    expect(file, isNot(contains(token)));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('--header-stdin with --header-scheme', () async {
    final (code, out, err) = await run([
      'mcp',
      'add',
      'gh',
      '--type',
      'http',
      '--url',
      'https://gh.test/mcp',
      '--header-stdin',
      'Authorization',
      '--header-scheme',
      'Bearer',
    ], stdin: token);

    expect(code, 0, reason: err);
    expect('$out$err', isNot(contains(token)));
    expect(
      File('$home/config.yaml').readAsStringSync(),
      contains(
        r"Authorization: 'Bearer ${secret:codelab/mcp/gh/authorization}'",
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('two -stdin flags and a scheme without --header-stdin are usage '
      'errors; nothing is stored', () async {
    for (final extra in [
      ['--header-stdin', 'A', '--env-stdin', 'B'],
      ['--header-scheme', 'Bearer'],
    ]) {
      final (code, _, err) = await run([
        'mcp',
        'add',
        'gh',
        '--type',
        'http',
        '--url',
        'https://gh.test/mcp',
        ...extra,
      ], stdin: token);

      expect(code, 64, reason: err);
      expect(err, isNot(contains(token)));
    }
    expect(File('$home/secrets.yaml').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 180)));

  test('the help lists the stdin flags', () async {
    final (code, _, err) = await run(['mcp']);

    expect(code, 64);
    expect(err, contains('--header-stdin'));
    expect(err, contains('--header-scheme'));
    expect(err, contains('--env-stdin'));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
