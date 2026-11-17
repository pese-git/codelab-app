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

  // change `bind-mcp-secrets-to-origin`, D6; agent-secrets «Ссылки MCP-сервера
  // проектного слоя привязаны к адресу», п. 6. Проектный сервер не меняется в
  // файле, но правка глобального слоя меняет его вердикт: план не откладывает
  // его, а итоговый снимок несёт новый `blockedReason`, и шаг 7а заменяет
  // сервер в живых сессиях через `sameConnection`.
  group('a global edit that changes the binding of a project MCP server', () {
    const secretRef = r'Bearer ${secret:codelab/mcp/github/authorization}';

    Map<String, Object?> github() => {
      'name': 'github',
      'type': 'http',
      'url': 'https://api.githubcopilot.com/mcp/',
      'headers': <String, Object?>{'Authorization': secretRef},
    };

    ConfigLoadResult withProject({required bool bound}) {
      final user = <String, Object?>{
        'trusted_projects': ['/proj'],
        'providers': {'a': provider('x')},
        'mcp': {
          'servers': [if (bound) github()],
        },
      };
      final result = CoreConfig.fromLayers(
        [
          layer(user),
          layer({
            'mcp': {
              'servers': [
                {
                  'name': 'gh-team',
                  'type': 'http',
                  'url': 'https://api.githubcopilot.com/mcp/x',
                  'headers': <String, Object?>{'Authorization': secretRef},
                },
              ],
            },
          }, kind: ConfigLayerKind.project),
        ],
        environment: const {},
        projectRoot: '/proj',
      );
      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      return result;
    }

    ConfigReloadPlan plan(ConfigLoadResult before, ConfigLoadResult after) =>
        planConfigReload(
          previousValues: before.values,
          previous: before.config!,
          nextValues: after.values,
          next: after.config!,
        );

    McpServerConfig team(CoreConfig config) =>
        config.mcpServers.singleWhere((s) => s.name == 'gh-team');

    test('removing the binding blocks the project server at once', () {
      final before = withProject(bound: true);
      final after = withProject(bound: false);
      expect(team(before.config!).blockedReason, isNull);

      final result = plan(before, after);
      final merged = CoreConfig.withDeferred(
        before.config!,
        after.config!,
        result.deferred,
      );

      expect(result.restartRequiredKeys, isEmpty);
      expect(result.deferred.servers, isEmpty);
      expect(team(merged).blockedReason, isNotNull);
      expect(team(merged).sameConnection(team(before.config!)), isFalse);
    });

    test('adding the binding unblocks the project server at once', () {
      final before = withProject(bound: false);
      final after = withProject(bound: true);

      final result = plan(before, after);
      final merged = CoreConfig.withDeferred(
        before.config!,
        after.config!,
        result.deferred,
      );

      expect(team(merged).blockedReason, isNull);
      expect(team(merged).secretValues.keys, ['headers.Authorization']);
      // Сам новый глобальный сервер `github` с подстановкой ждёт перезапуска
      // (R0-4); привязку проектному серверу он даёт сразу (D6).
      expect(result.restartRequiredKeys, ['mcp.servers[github]']);
    });
  });
}
