import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Найденный `codelab.toml` не читается (agent-configuration «Найденный
/// codelab.toml не читается»; критерий `core/config-legacy-found-warning`;
/// design.md change `add-agent-configuration`, D12; решение пользователя
/// 2026-10-29). Файл ни разу не открывается: проверка — существование.
void main() {
  late Directory root;
  late String home;
  late String cwd;
  late ConfigLoader loader;

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    final created = Directory.systemTemp.createTempSync('config_legacy_test');
    root = Directory(created.resolveSymbolicLinksSync());
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
    loader = ConfigLoader();
  });

  tearDown(() => root.deleteSync(recursive: true));

  // Модель приходит флагом: слоям из файлов она не нужна.
  final flags = ConfigTree(
    kind: ConfigLayerKind.flags,
    source: 'flags',
    values: {
      'providers': {
        'p': {
          'kind': 'openai-compatible',
          'base_url': 'https://llm.test/v1',
          'models': {'m': <String, Object?>{}},
        },
      },
      'agent': {'default_model': 'p/m'},
    },
  );

  ConfigLoadResult load({
    String? dir,
    String? extraConfig,
    bool scripted = false,
  }) => loader.load(
    cwd: dir ?? cwd,
    environment: {'CODELAB_HOME': home},
    flags: flags,
    extraConfig: extraConfig,
    scripted: scripted,
  );

  List<ConfigIssue> legacy(ConfigLoadResult result) => [
    for (final w in result.warnings)
      if (w.event == 'config.legacy_found') w,
  ];

  test('only codelab.toml: one warning per cwd, no content, no issues', () {
    write('$cwd/codelab.toml', 'this is [not toml sk-toml-secret\n');
    write('$home/auth.toml', 'token = "sk-auth-secret"\n');

    final first = load();
    final second = load();

    expect(first.issues, isEmpty);
    expect(first.config, isNotNull);
    final warning = legacy(first).single;
    expect(warning.level, LogLevel.warning);
    expect(warning.fields['files'], ['$home/auth.toml', '$cwd/codelab.toml']);
    expect(
      warning.message,
      'codelab.toml is not used by the Dart agent: '
      '$home/auth.toml, $cwd/codelab.toml. Move the settings to config.yaml '
      'manually; the key mapping is in '
      'docs/architecture/proposals/agent-core/15-configuration.md, '
      'section 15.7.',
    );
    expect(warning.toString(), isNot(contains('sk-toml-secret')));
    expect(warning.toString(), isNot(contains('sk-auth-secret')));
    expect(legacy(second), isEmpty, reason: 'once per process and cwd');
  });

  test('another cwd gets its own warning', () {
    write('$cwd/codelab.toml', 'x');
    final other = '${root.path}/other';
    write('$other/codelab.local.toml', 'x');

    load();
    final result = load(dir: other);

    expect(legacy(result).single.fields['files'], [
      '$other/codelab.local.toml',
    ]);
  });

  test('the file is never opened: an unreadable one still counts', () {
    write('$cwd/codelab.toml', 'x');
    Process.runSync('chmod', ['000', '$cwd/codelab.toml']);
    addTearDown(() => Process.runSync('chmod', ['644', '$cwd/codelab.toml']));

    final result = load();

    expect(result.issues, isEmpty);
    expect(legacy(result), hasLength(1));
  });

  test('config.yaml next to codelab.toml: no warning', () {
    write('$home/config.yaml', 'budget:\n  max_steps: 5\n');
    write('$cwd/codelab.toml', 'x');

    final result = load();

    expect(result.issues, isEmpty);
    expect(legacy(result), isEmpty);
  });

  test('a project config.yaml is enough to stay silent', () {
    write('$cwd/.codelab/config.local.yaml', 'budget:\n  max_steps: 5\n');
    write('$home/codelab.toml', 'x');

    expect(legacy(load()), isEmpty);
  });

  test('--config with a codelab.toml around: no warning', () {
    write('$cwd/codelab.toml', 'x');
    write('${root.path}/x.yaml', 'budget:\n  max_steps: 5\n');

    expect(legacy(load(extraConfig: '${root.path}/x.yaml')), isEmpty);
  });

  test('with a script the files are not looked for', () {
    write('$cwd/codelab.toml', 'x');

    expect(legacy(load(scripted: true)), isEmpty);
  });

  test('codelab.toml.example is a template and is not looked for', () {
    write('$cwd/codelab.toml.example', 'x');
    write('$home/codelab.toml.example', 'x');

    expect(legacy(load()), isEmpty);
  });
}
