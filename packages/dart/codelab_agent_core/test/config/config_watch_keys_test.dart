import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Ключи `config.watch` и `config.poll_interval` (agent-configuration
/// «Ключи config.watch и config.poll_interval»; design.md change
/// `add-config-writer-and-reload`, D7, D4).
void main() {
  group('applied keys', () {
    test('both keys are accepted without config.key.not_applied and reach '
        'HostSettings (scenario "Применяемые ключи")', () {
      final result = load([
        layer({
          ...baseValues(),
          'config': {'watch': false, 'poll_interval': '5s'},
        }),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(warningsOf(result, 'config.key.not_applied'), isEmpty);
      expect(result.host!.configWatch, isFalse);
      expect(result.host!.configPollInterval, const Duration(seconds: 5));
      expect(result.values['config.watch'], false);
      expect(result.values['config.poll_interval'], '5s');
    });

    test('without the keys HostSettings carries none: the host applies '
        'true and 2s', () {
      final result = load([layer(baseValues())]);

      expect(result.host!.configWatch, isNull);
      expect(result.host!.configPollInterval, isNull);
    });

    test('the interval is 1s..60s with the range in the message', () {
      for (final bad in ['500ms', '61s', '2m']) {
        final result = load([
          layer({
            ...baseValues(),
            'config': {'poll_interval': bad},
          }),
        ]);

        final issue = issuesAt(result, 'config.poll_interval').single;
        expect(issue.message, contains('1s'), reason: bad);
        expect(issue.message, contains('60s'), reason: bad);
        expect(result.config, isNull);
      }
      for (final good in ['1s', '60s', '1m']) {
        final result = load([
          layer({
            ...baseValues(),
            'config': {'poll_interval': good},
          }),
        ]);

        expect(result.issues, isEmpty, reason: good);
      }
    });

    test('types are checked and an unknown key of the section is a '
        'problem', () {
      final wrongType = load([
        layer({
          ...baseValues(),
          'config': {'watch': 'yes'},
        }),
      ]);
      final unknown = load([
        layer({
          ...baseValues(),
          'config': {'watchh': true},
        }),
      ]);

      expect(
        issuesAt(wrongType, 'config.watch').single.kind,
        ConfigIssueKind.type,
      );
      expect(
        issuesAt(unknown, 'config.watchh').single.kind,
        ConfigIssueKind.unknownKey,
      );
    });
  });

  group('layers (agent-configuration "Недопустимый интервал и проектный '
      'слой")', () {
    Map<String, Object?> watchOff() => {
      'config': {'watch': false},
    };

    test('the project layer 3 drops config even for a trusted project', () {
      for (final trusted in [
        <String>[],
        ['/proj'],
      ]) {
        final result = load([
          layer({...baseValues(), 'trusted_projects': trusted}),
          layer(watchOff(), kind: ConfigLayerKind.project),
        ], projectRoot: '/proj');

        final dropped = warningsOf(result, 'config.project.untrusted_key');
        expect(dropped.map((w) => w.key), ['config'], reason: '$trusted');
        expect(result.host!.configWatch, isNull, reason: '$trusted');
      }
    });

    test('config.local.yaml of an untrusted project follows the rules of '
        'layer 3, of a trusted one is read', () {
      final untrusted = load([
        layer(baseValues()),
        layer(watchOff(), kind: ConfigLayerKind.projectLocal),
      ], projectRoot: '/proj');
      final trusted = load([
        layer({
          ...baseValues(),
          'trusted_projects': ['/proj'],
        }),
        layer(watchOff(), kind: ConfigLayerKind.projectLocal),
      ], projectRoot: '/proj');

      expect(
        warningsOf(untrusted, 'config.project.untrusted_key').map((w) => w.key),
        ['config'],
      );
      expect(untrusted.host!.configWatch, isNull);
      expect(trusted.host!.configWatch, isFalse);
    });

    test('the --config layer is not limited', () {
      final result = load([
        layer(baseValues()),
        layer(watchOff(), kind: ConfigLayerKind.extra),
      ], projectRoot: '/proj');

      expect(result.host!.configWatch, isFalse);
    });
  });
}
