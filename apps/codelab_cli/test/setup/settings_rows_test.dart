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
}
