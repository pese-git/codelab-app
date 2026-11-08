import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart' show layer;

/// План перезагрузки при неявной модели по умолчанию (agent-configuration
/// «Модель по умолчанию без agent.default_model», сценарий «Отложенный
/// новый провайдер не становится моделью»; design.md change
/// `optional-default-model`, D10). Красные тесты задачи 1.3.
void main() {
  Map<String, Object?> provider(String model, {String? secret}) => {
    'kind': 'openai-compatible',
    'base_url': 'https://$model.test/v1',
    'api_key_secret': ?secret,
    'models': {model: <String, Object?>{}},
  };

  ConfigLoadResult loaded(Map<String, Object?> values) {
    final result = CoreConfig.fromLayers([
      layer(values),
    ], environment: const {});
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    return result;
  }

  test('an implicit model does not set deferred.defaultModel when a new '
      'provider with a key is deferred', () {
    final before = loaded({
      'providers': {'b': provider('y')},
    });
    final after = loaded({
      'providers': {
        'a': provider('x', secret: 'codelab/a'),
        'b': provider('y'),
      },
    });

    final plan = planConfigReload(
      previousValues: before.values,
      previous: before.config!,
      nextValues: after.values,
      next: after.config!,
    );

    expect(plan.restartRequiredKeys, ['providers.a']);
    expect(plan.deferred.providers, {'a'});
    expect(plan.deferred.defaultModel, isFalse);
    expect(plan.changedKeys, isNot(contains('agent.default_model')));
    // Итоговый снимок после подстановки отложенного: модель прежняя.
    final merged = CoreConfig.withDeferred(
      before.config!,
      after.config!,
      plan.deferred,
    );
    expect(merged.defaultModel.provider, 'b');
    expect(merged.defaultModelSource, DefaultModelSource.firstProvider);
    expect(merged.validateSnapshot(), isEmpty);
  });

  test('withDeferred recomputes the implicit model over the providers that '
      'remain after the deferred ones are excluded', () {
    // Новый провайдер `a` откладывается и исключается из снимка: неявная
    // модель считается заново по итоговым провайдерам, а не берётся из
    // `next` (D10).
    final before = loaded({
      'providers': {'b': provider('y')},
    });
    final after = loaded({
      'providers': {
        'a': provider('x', secret: 'codelab/a'),
        'b': provider('y'),
      },
    });
    expect(after.config!.defaultModel.provider, 'a', reason: 'first of next');

    final merged = CoreConfig.withDeferred(
      before.config!,
      after.config!,
      const DeferredConfigParts(providers: {'a'}),
    );

    expect(merged.providers.map((p) => p.config.name), ['b']);
    expect(merged.defaultModel.provider, 'b');
    expect(merged.defaultModel.id, 'y');
    expect(merged.defaultModelSource, DefaultModelSource.firstProvider);
  });

  test('removing the explicit key is a live change to the first provider', () {
    final before = loaded({
      'providers': {'b': provider('y'), 'a': provider('x')},
      'agent': {'default_model': 'a/x'},
    });
    final after = loaded({
      'providers': {'b': provider('y'), 'a': provider('x')},
    });

    final plan = planConfigReload(
      previousValues: before.values,
      previous: before.config!,
      nextValues: after.values,
      next: after.config!,
    );

    expect(plan.changedKeys, ['agent.default_model']);
    expect(plan.restartRequiredKeys, isEmpty);
    expect(plan.deferred.defaultModel, isFalse);
    expect(before.config!.defaultModelSource, DefaultModelSource.config);
    expect(after.config!.defaultModelSource, DefaultModelSource.firstProvider);
    expect(after.config!.defaultModel.provider, 'b');
  });
}
