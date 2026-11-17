import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import '../support/config_writer_harness.dart';

/// `ConfigLoader.validateCandidate` (design.md change
/// `add-config-writer-and-reload`, D5, шаг 6 §17.5.5): проверка итогового
/// текста слоя теми же слоями и `fromLayers`, что у загрузки, без записи.
void main() {
  late Directory root;
  late String home;
  late String cwd;
  late ConfigLoader loader;

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('validate_candidate_test')
          .resolveSymbolicLinksSync(),
    );
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
    loader = ConfigLoader();
  });

  tearDown(() => root.deleteSync(recursive: true));

  Map<String, String> env([Map<String, String> extra = const {}]) => {
    'CODELAB_HOME': home,
    ...extra,
  };

  test('кандидат заменяет слой: файл на диске не читается', () {
    File('$home/config.yaml').writeAsStringSync('budget: [not valid\n');

    final result = loader.validateCandidate(
      const ConfigTarget.user(),
      baseConfig,
      cwd: cwd,
      environment: env(),
    );

    expect(result.issues, isEmpty);
    expect(
      File('$home/config.yaml').readAsStringSync(),
      'budget: [not valid\n',
    );
  });

  test('кандидат для файла, которого ещё нет', () {
    final result = loader.validateCandidate(
      const ConfigTarget.user(),
      baseConfig,
      cwd: cwd,
      environment: env(),
    );

    expect(result.issues, isEmpty);
    expect(File('$home/config.yaml').existsSync(), isFalse);
  });

  test('проблемы называют файл слоя, а не tmp', () {
    final result = loader.validateCandidate(
      const ConfigTarget.user(),
      '${baseConfig}budget:\n  max_steps: 0\n',
      cwd: cwd,
      environment: env(),
    );

    final issue = result.issues.single;
    expect(issue.key, 'budget.max_steps');
    expect(issue.source, '$home/config.yaml');
    expect(issue.line, isNotNull);
  });

  test('ошибка синтаксиса кандидата — проблема, а не исключение', () {
    final result = loader.validateCandidate(
      const ConfigTarget.user(),
      'a: [unclosed\n',
      cwd: cwd,
      environment: env(),
    );

    expect(result.issues, isNotEmpty);
  });

  test('другие слои остаются: проектный кандидат поверх пользовательского', () {
    File('$home/config.yaml').writeAsStringSync(baseConfig);

    final result = loader.validateCandidate(
      ConfigTarget.projectLocal(cwd),
      'agent:\n  default_model: p/n\n',
      cwd: cwd,
      environment: env(),
    );

    expect(result.issues, isEmpty);
  });

  test('недоверенный проект: ключи кандидата отброшены предупреждением', () {
    File('$home/config.yaml').writeAsStringSync(baseConfig);

    final result = loader.validateCandidate(
      ConfigTarget.project(cwd),
      'mcp:\n  servers:\n    - name: docs\n      type: http\n'
      '      url: https://docs.test/mcp\n',
      cwd: cwd,
      environment: env(),
    );

    expect(result.issues, isEmpty);
    expect(
      result.warnings.where((w) => w.event == 'config.project.untrusted_key'),
      isNotEmpty,
    );
  });

  test('незаданная переменная — предупреждение, а не проблема', () {
    final result = loader.validateCandidate(
      const ConfigTarget.user(),
      baseConfig.replaceFirst('https://llm.test/v1', r'${NOT_SET_URL}'),
      cwd: cwd,
      environment: env(),
    );

    expect(result.issues, isEmpty);
    expect(
      result.warnings.map((w) => w.message),
      contains('variable NOT_SET_URL is not set'),
    );
  });

  test('значения кандидата не попадают в проблемы', () {
    final result = loader.validateCandidate(
      const ConfigTarget.user(),
      '${baseConfig}budget:\n  max_steps: not-a-real-key-visible\n',
      cwd: cwd,
      environment: env(),
    );

    expect(
      result.issues.map((i) => i.toString()).join('\n'),
      isNot(contains('not-a-real-key-visible')),
    );
  });
}
