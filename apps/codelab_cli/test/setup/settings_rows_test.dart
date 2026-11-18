// Порядок строк `/settings`: блок на провайдера (design.md change
// `add-provider-setup-ui`, D17: «`providers.*` — по одному блоку на
// провайдера»). Строки общие для REPL и экрана TUI (`settingRowsOf`).

import 'package:codelab_cli/src/repl/picker_spec.dart';
import 'package:codelab_cli/src/setup/settings_rows.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../support/setup_fakes.dart';

Map<String, Object?> _provider() => {
  'kind': 'openai-compatible',
  'base_url': 'https://gw.test/v1',
  'models': {
    'm': {'context_window': 8000},
  },
};

void main() {
  AgentConfigSnapshot snapshot(Map<String, Map<String, Object?>> providers) =>
      snapshotOf(user: {'providers': providers});

  List<String> keys(AgentConfigSnapshot snap) => [
    for (final row in settingRowsOf(snap)) row.key,
  ];

  test('два провайдера: все строки первого подряд, затем второго; провайдеры '
      'по алфавиту id', () {
    final order = keys(snapshot({'zeta': _provider(), 'alpha': _provider()}));
    final providerKeys = [
      for (final key in order)
        if (key.startsWith('providers.')) key,
    ];

    final ids = [for (final key in providerKeys) key.split('.')[1]];
    final firstZeta = ids.indexOf('zeta');
    expect(ids.take(firstZeta).toSet(), {'alpha'}, reason: '$providerKeys');
    expect(ids.skip(firstZeta).toSet(), {'zeta'}, reason: '$providerKeys');
    expect(firstZeta, greaterThan(0));
  });

  test('внутри блока сохраняется порядок дескрипторов реестра', () {
    final one = keys(snapshot({'alpha': _provider()}));
    final two = keys(snapshot({'alpha': _provider(), 'zeta': _provider()}));

    final alphaIn2 = [
      for (final key in two)
        if (key.startsWith('providers.alpha.')) key,
    ];
    expect([
      for (final key in one)
        if (key.startsWith('providers.alpha.')) key,
    ], alphaIn2);
  });

  test('строки не-провайдеров остаются на своих местах', () {
    final plain = keys(snapshotOf());
    final withProviders = keys(
      snapshot({'zeta': _provider(), 'alpha': _provider()}),
    );

    expect([
      for (final key in withProviders)
        if (!key.startsWith('providers.')) key,
    ], plain);
  });

  test('список /settings REPL идёт тем же порядком', () {
    final snap = snapshot({'zeta': _provider(), 'alpha': _provider()});

    final PickerSpec spec = settingsPickerOf(snap);

    expect([
      for (final item in spec.items) item.line.replaceFirst('/settings ', ''),
    ], keys(snap));
  });

  // Задача 1.3 change `add-app-general-page` (spec client-agent-setup «Тексты
  // CLI не меняются», D6): тексты отказов `/settings` фиксируются побайтно до
  // перевода CLI на мост `settingEditRefusalOf`; после 1.4 остаются теми же.
  group('тексты отказов /settings не меняются', () {
    const secretText = 'Use codelab secret set <name>';

    SettingFieldView row(AgentConfigSnapshot snap, String key) =>
        settingRowsOf(snap).singleWhere((r) => r.key == key);

    test('UnknownSetting: неизвестный ключ и ключ не из shared', () {
      expect(
        settingKeyRefusal('no.such.key'),
        'Unknown setting no.such.key. Run /settings to list them.',
      );
    });

    test('TrustBoundarySetting', () {
      expect(
        settingKeyRefusal('trusted_projects'),
        'trusted_projects is a trust boundary; it cannot be changed here.',
      );
    });

    test('SecretSetting: ключ с именем секрета', () {
      expect(settingKeyRefusal('providers.gw.api_key_secret'), secretText);
    });

    test('ExternalSourceSetting: источники config и env', () {
      final snap = snapshotOf(
        values: const {'budget.max_steps': 9, 'agent.effort': 'high'},
        external: const {
          'budget.max_steps': ConfigSourceKind.environment,
          'agent.effort': ConfigSourceKind.extraFile,
        },
      );

      expect(
        settingRowRefusal(row(snap, 'budget.max_steps')),
        'budget.max_steps is set by env; it cannot be changed here.',
      );
      expect(
        settingRowRefusal(row(snap, 'agent.effort')),
        'agent.effort is set by config; it cannot be changed here.',
      );
    });

    test('MaskedSetting: замаскированное значение', () {
      const leaking = 'bash:curl -H "Authorization: Bearer sk-test-leak-1"';
      final snap = snapshotOf(
        user: {
          'permissions': {
            'deny': [leaking],
          },
        },
        values: const {
          'permissions.deny': [leaking],
        },
      );

      expect(settingRowRefusal(row(snap, 'permissions.deny')), secretText);
    });

    test('обычный ключ: отказа нет', () {
      final snap = snapshotOf();

      expect(settingKeyRefusal('compaction.enabled'), isNull);
      expect(settingRowRefusal(row(snap, 'compaction.enabled')), isNull);
    });
  });
}
