// Функция composition root «нужен ли провайдер» (задача 3.12 change
// `add-provider-setup-ui`; design.md D26): снимок настоящего
// `FileAgentConfigStore` на временном `CODELAB_HOME` и признак моста
// `providerSetupNeeded`.
//
// Только временная папка: настоящий `~/.codelab` и хранилище секретов
// разработчика не читаются (`CODELAB_HOME` задан явно, бэкенд секретов —
// `file` внутри этой папки).

import 'dart:io';

import 'package:codelab_desktop/app/embedded_logger.dart';
import 'package:codelab_desktop/app/provider_setup_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('codelab-probe-');
    addTearDown(() => home.deleteSync(recursive: true));
  });

  Future<bool> probe() => providerSetupNeededAt(
    '${home.path}/project',
    codelabHome: home.path,
    environment: {'CODELAB_HOME': home.path},
    logger: CodeLabEmbeddedLogger(),
  );

  void config(String yaml) =>
      File('${home.path}/config.yaml').writeAsStringSync(yaml);

  test('an empty home needs a provider', () async {
    expect(await probe(), isTrue);
  });

  // Change `optional-default-model` (D3, D12): `agent.default_model`
  // необязателен, агент стартует на первом провайдере, мастер не нужен.
  test('a provider without a default model does not need the wizard', () async {
    config('''
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.example/v1
    models:
      m:
        context_window: 8000
''');
    expect(await probe(), isFalse);
  });

  test(
    'another config problem is not a missing provider: max_steps 0',
    () async {
      config('''
agent:
  default_model: gw/m
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.example/v1
    models:
      m:
        context_window: 8000
budget:
  max_steps: 0
''');
      expect(await probe(), isFalse);
    },
  );

  test('a default model outside the catalog of a configured provider is an '
      'ordinary config error', () async {
    config('''
agent:
  default_model: gw/typo
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.example/v1
    models:
      m:
        context_window: 8000
''');
    expect(await probe(), isFalse);
  });
}
