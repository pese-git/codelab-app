import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Валидация цен модели `providers.<id>.models.<m>.cost_*` (change
/// `add-usage-extension`, решение пользователя 2026-11-16, D20 п. 2): цена —
/// конечное число не меньше нуля; ноль (бесплатная модель) допустим.
/// Бесконечность и NaN достижимы из TOML (`inf`, `nan`) и из YAML (`.inf`).
void main() {
  const keys = [
    'cost_input',
    'cost_output',
    'cost_cache_read',
    'cost_cache_write',
  ];

  ConfigLoadResult run(Map<String, Object?> model) => load([
    layer({
      'providers': {
        'p': {
          'kind': 'openai-compatible',
          'base_url': 'https://llm.test/v1',
          'models': {'m': model},
        },
      },
      'agent': {'default_model': 'p/m'},
    }),
  ]);

  Map<String, Object?> priced(String key, num value) => {
    'cost_input': 1,
    'cost_output': 2,
    key: value,
  };

  test('нулевые цены допустимы', () {
    final result = run({
      'cost_input': 0,
      'cost_output': 0,
      'cost_cache_read': 0,
      'cost_cache_write': 0,
    });

    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
  });

  test('текст проблемы фиксирован и не содержит значения цены', () {
    final result = run(priced('cost_input', -123.456));

    final issue = issuesAt(result, 'providers.p.models.m.cost_input').single;
    expect(issue.message, 'must be a finite number not less than 0');
    expect('$issue', isNot(contains('123')));
    expect(result.config, isNull);
  });

  test('нулевая и дробная цена: проблем нет, ModelCost разрешён', () {
    final result = run({
      'cost_input': 0,
      'cost_output': 2,
      'cost_cache_read': 0.3,
    });

    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    expect(
      result.config!.defaultModel.cost,
      const ModelCost(input: 0, output: 2, cacheRead: 0.3),
    );
  });

  test('цена из верхнего слоя app-storage проверяется так же', () {
    final result = load([
      layer(baseValues()),
      layer({
        'providers': {
          'p': {
            'models': {
              'm': {'cost_input': 1, 'cost_output': -2},
            },
          },
        },
      }, kind: ConfigLayerKind.appStorage),
    ]);

    expect(
      issuesAt(result, 'providers.p.models.m.cost_output'),
      hasLength(1),
      reason: result.issues.join('\n'),
    );
    expect(result.config, isNull);
  });

  for (final key in keys) {
    for (final (name, value) in <(String, num)>[
      ('отрицательное', -1),
      ('бесконечность', double.infinity),
      ('минус бесконечность', double.negativeInfinity),
      ('NaN', double.nan),
    ]) {
      test('$key: $name значение отклоняется по пути ключа', () {
        final result = run(priced(key, value));

        expect(
          issuesAt(result, 'providers.p.models.m.$key'),
          hasLength(1),
          reason: result.issues.join('\n'),
        );
      });
    }
  }

  // `budget.max_cost` / `subagents.max_cost`: `nan` и `inf` из TOML/YAML
  // раньше проходили проверку `<= 0` и молча отключали бюджет стоимости.
  for (final path in ['budget', 'subagents']) {
    for (final (name, value) in <(String, num)>[
      ('бесконечность', double.infinity),
      ('минус бесконечность', double.negativeInfinity),
      ('NaN', double.nan),
    ]) {
      test('$path.max_cost: $name отклоняется', () {
        final result = load([
          layer({
            path: {'max_cost': value},
          }),
        ]);

        expect(
          issuesAt(result, '$path.max_cost'),
          hasLength(1),
          reason: result.issues.join('\n'),
        );
      });
    }
  }
}
