import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// `config check` и цены моделей (agent-configuration «Цены моделей
/// конфигурации», сценарий «Отрицательная цена»; change `add-usage-extension`,
/// D20 п. 2): проблема печатается с путём ключа и фиксированным текстом без
/// значения, код — ошибка. Каталоги — временные, реальный `~/.codelab` не
/// затрагивается.
void main() {
  late Directory root;

  setUp(() {
    final created = Directory.systemTemp.createTempSync('config_check_cost_');
    root = Directory(created.resolveSymbolicLinksSync());
    Directory('${root.path}/home').createSync();
    Directory('${root.path}/uh').createSync();
    Directory('${root.path}/proj').createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  test(
    'cost_input = -1: ненулевой код, путь ключа и текст без значения',
    () async {
      File('${root.path}/home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m:
        cost_input: -1
        cost_output: 2
agent:
  default_model: p/m
''');

      final result = await ConfigCommands().check(
        CheckOptions(
          cwd: '${root.path}/proj',
          environment: {
            'CODELAB_HOME': '${root.path}/home',
            'HOME': '${root.path}/uh',
          },
        ),
      );

      expect(result.exitCode, configInvalidExit);
      final out = [...result.stdout, ...result.stderr].join('\n');
      expect(out, contains('providers.p.models.m.cost_input'));
      expect(out, contains('must be a finite number not less than 0'));
      expect(out, isNot(contains('-1')));
      expect(out, isNot(contains('Config: valid')));
    },
  );
}
