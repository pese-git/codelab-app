import 'dart:io';

import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../support/real_home.dart';

/// Правила правки строк настроек агента (client-agent-setup «Правила правки
/// строк настроек агента»; design.md change `add-app-general-page`, D6).
///
/// Снимки строит настоящий `FileAgentConfigStore` на временном `CODELAB_HOME`:
/// источник и маску определяет загрузчик, а не тест.
void main() {
  const leak = 'sk-test-leak-0123456789';
  late RealHome home;

  setUp(() => home = RealHome.create('setting_edit_rules_'));
  tearDown(() => home.dispose());

  SettingFieldView row(List<SettingFieldView> rows, String key) =>
      rows.singleWhere((r) => r.key == key, orElse: () => fail('нет $key'));

  const validConfig = '''
agent:
  default_model: gw/m
$gatewayProvider''';

  test('ключ из реестра scope shared не отклоняется по ключу', () {
    expect(settingKeyEditRefusalOf('compaction.enabled'), isNull);
  });

  test('неизвестный ключ — UnknownSetting', () {
    expect(settingKeyEditRefusalOf('no.such.key'), isA<UnknownSetting>());
  });

  test('ключ fileOnly — UnknownSetting', () {
    expect(
      settingKeyEditRefusalOf('providers.gw.api_key'),
      isA<UnknownSetting>(),
    );
    expect(settingKeyEditRefusalOf('agent.fallback'), isA<UnknownSetting>());
  });

  test('trusted_projects — TrustBoundarySetting', () {
    expect(
      settingKeyEditRefusalOf('trusted_projects'),
      isA<TrustBoundarySetting>(),
    );
  });

  test('ключ-секрет (тип secretName) — SecretSetting', () {
    expect(
      settingKeyEditRefusalOf('providers.gw.api_key_secret'),
      isA<SecretSetting>(),
    );
  });

  test('порядок веток: секрет из окружения — SecretSetting, а не '
      'ExternalSourceSetting', () async {
    home.writeConfig('''
agent:
  default_model: gw/m
$gatewayProvider    api_key_secret: gw-key
''');
    final secret = row(
      settingFieldsOf(await home.load()),
      'providers.gw.api_key_secret',
    );
    // Тот же дескриптор, но значение «пришло» из окружения.
    final fromEnv = SettingFieldView(
      key: secret.key,
      descriptor: secret.descriptor,
      value: secret.value,
      source: const ConfigSourceView(
        kind: ConfigSourceKind.environment,
        label: 'env',
      ),
    );

    expect(settingEditRefusalOf(fromEnv), isA<SecretSetting>());
  });

  test('источник config: budget.max_steps из --config — '
      'ExternalSourceSetting(config)', () async {
    home.writeConfig(validConfig);
    final extra = '${home.root.path}/extra.yaml';
    await _write(extra, 'budget:\n  max_steps: 12\n');
    final steps = row(
      settingFieldsOf(await home.load({'CODELAB_CONFIG': extra})),
      'budget.max_steps',
    );

    final refusal = settingEditRefusalOf(steps);

    expect(refusal, isA<ExternalSourceSetting>());
    expect(
      (refusal! as ExternalSourceSetting).source.kind,
      ConfigSourceKind.extraFile,
    );
  });

  test(
    'источник env: CODELAB_MAX_STEPS — ExternalSourceSetting(env)',
    () async {
      home.writeConfig(validConfig);
      final steps = row(
        settingFieldsOf(await home.load({'CODELAB_MAX_STEPS': '11'})),
        'budget.max_steps',
      );

      final refusal = settingEditRefusalOf(steps);

      expect(refusal, isA<ExternalSourceSetting>());
      expect(
        (refusal! as ExternalSourceSetting).source.kind,
        ConfigSourceKind.environment,
      );
    },
  );

  test('замаскированное значение — MaskedSetting; токена нет ни в отказе, '
      'ни в строке', () async {
    home.writeConfig('''
agent:
  default_model: gw/m
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.test/v1?token=$leak
    models:
      m:
        context_window: 8000
''');
    final url = row(
      settingFieldsOf(await home.load()),
      'providers.gw.base_url',
    );
    expect(url.masked, isTrue, reason: 'предусловие: строка замаскирована');

    final refusal = settingEditRefusalOf(url);

    expect(refusal, isA<MaskedSetting>());
    expect(refusal.toString(), isNot(contains(leak)));
    expect(url.toString(), isNot(contains(leak)));
  });

  test('обычный ключ в слое user можно править', () async {
    home.writeConfig('''
agent:
  default_model: gw/m
compaction:
  enabled: false
$gatewayProvider''');
    final enabled = row(
      settingFieldsOf(await home.load()),
      'compaction.enabled',
    );
    expect(enabled.sourceName, 'user', reason: 'предусловие');

    expect(settingEditRefusalOf(enabled), isNull);
  });

  test('ключ без заданного значения (default) можно править', () async {
    home.writeConfig(validConfig);
    final steps = row(settingFieldsOf(await home.load()), 'budget.max_steps');

    expect(settingEditRefusalOf(steps), isNull);
  });
}

Future<void> _write(String path, String text) async =>
    File(path).writeAsStringSync(text);
