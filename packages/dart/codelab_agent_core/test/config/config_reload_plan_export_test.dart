import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// `planConfigReload` и `ConfigReloadPlan` доступны из основного бареля
/// (change `add-provider-setup-ui`, D11 «Итерация 6: сервер, отложенный до
/// перезапуска», задача 6.1b-1): мост настроек строит признак «ждёт
/// перезапуска» одной функцией ядра, а не копией правила. Зависимости ядра
/// (PKG-2) не меняются.
void main() {
  test('planConfigReload и ConfigReloadPlan импортируются из бареля', () {
    final ConfigLoadResult empty = CoreConfig.fromLayers(const [
      ConfigTree(
        kind: ConfigLayerKind.user,
        source: 'values',
        values: {
          'providers': {
            'p': {
              'kind': 'openai-compatible',
              'base_url': 'https://p.test/v1',
              'models': {'m': <String, Object?>{}},
            },
          },
        },
      ),
    ], environment: const {});
    final config = empty.config;
    expect(config, isNotNull, reason: empty.issues.join('\n'));

    final ConfigReloadPlan plan = planConfigReload(
      previousValues: empty.values,
      previous: config!,
      nextValues: empty.values,
      next: config,
    );

    expect(plan.isEmpty, isTrue);
  });
}
