import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Позиции проблем (agent-configuration, сценарий «Слой без позиций»;
/// `agent-core-architecture` §15.5, §15.12).
void main() {
  test('a layer with positions gives line and column', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'budget': {'max_steps': 'x'},
        }),
        source: '/h/config.yaml',
        positions: {'budget.max_steps': const ConfigPosition(7, 15)},
      ),
    ]);

    final issue = issuesAt(result, 'budget.max_steps').single;
    expect((issue.line, issue.column), (7, 15));
    expect(issue.source, '/h/config.yaml');
    expect(
      issue.toString(),
      startsWith('/h/config.yaml:7:15: budget.max_steps'),
    );
  });

  test('app-storage without positions names the source and the key only', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'budget': {'max_steps': 'x'},
        }),
        kind: ConfigLayerKind.appStorage,
      ),
    ]);

    final issue = issuesAt(result, 'budget.max_steps').single;
    expect(issue.line, isNull);
    expect(issue.column, isNull);
    expect(issue.source, 'app-storage');
    expect(issue.toString(), startsWith('app-storage: budget.max_steps: '));
    expect(RegExp(r':\d+:\d+').hasMatch(issue.toString()), isFalse);
  });

  test('a semantic issue is attributed to the layer that set the final '
      'value', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'budget': {'max_steps': 10},
        }),
        source: '/h/config.yaml',
      ),
      layer(
        {
          'budget': {'max_steps': 0},
        },
        kind: ConfigLayerKind.extra,
        source: '/x.yaml',
        positions: {'budget.max_steps': const ConfigPosition(2, 3)},
      ),
    ]);

    final issue = issuesAt(result, 'budget.max_steps').single;
    expect(issue.source, '/x.yaml');
    expect((issue.line, issue.column), (2, 3));
  });
}
