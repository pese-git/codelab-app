import 'dart:convert';
import 'dart:io';

import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

import 'support/corpus_invariants.dart';

/// Fixtures of stage 0 (`dart-agent-and-clients/09-05-stage-0-foundation.md`,
/// task 0.7). The list grows only together with the corpus.
const _stage0Fixtures = {
  'acp/initialize-capabilities',
  'acp/session-new-modes-config',
  'acp/prompt-text-end-turn',
  'acp/prompt-cancel-mid-tool',
  'acp/prompt-tool-permission-allow',
  'acp/prompt-tool-permission-reject-continues',
  'acp/tool-status-lifecycle',
  'acp/tool-read-range',
  'acp/tool-exec-terminal-embed',
  'acp/prompt-update-plan',
  'acp/set-config-option-model',
  'acp/errors-unknown-session-update-tolerated',
};

/// Fixtures of stage 4 in the agent package (design.md change
/// `add-dart-agent-acp-server`, D8): 33 of §14.2; the transport fixtures go
/// to `add-codelab-agent-binary`, the spill fixtures to
/// `add-agent-core-output-spill`.
const _stage4Fixtures = {
  'acp/compaction-long-session-continues',
  'acp/config-effort-option',
  'acp/errors-bad-frame-survives',
  'acp/multi-session-concurrent-prompts',
  'acp/permission-allow-always-scoped',
  'acp/permission-critical-pattern-in-bypass',
  'acp/permission-options-all-four',
  'acp/permission-outcome-cancelled',
  'acp/prompt-anthropic-tool-call',
  'acp/prompt-cancel-during-terminal',
  'acp/prompt-cancel-mid-stream',
  'acp/prompt-failed-provider-auth',
  'acp/prompt-max-turn-requests',
  'acp/prompt-network-drop',
  'acp/prompt-parallel-tool-calls',
  'acp/prompt-provider-error',
  'acp/prompt-streaming-text',
  'acp/prompt-thought-chunk',
  'acp/prompt-turn-budget-exceeded',
  'acp/session-info-title',
  'acp/session-list-cwd-filter',
  'acp/session-load-interrupted-turn',
  'acp/session-load-replay',
  'acp/set-mode-bypass-no-prompt',
  'acp/set-mode-plan-rejects-edit',
  'acp/set-mode-updates-current-mode',
  'acp/tool-edit-ambiguous-match-error',
  'acp/tool-edit-exact-replace',
  'acp/tool-exec-terminal-env-array',
  'acp/tool-invalid-args-error',
  'acp/tool-list-dir',
  'acp/tool-search-content',
  'acp/tool-write-permission-diff',
};

void main() {
  final corpus = loadFixtureCorpus();
  final protocolDirectory = protocolSpecDirectory();

  test('the corpus holds exactly the stage 0 and stage 4 fixtures', () {
    expect(_stage4Fixtures, hasLength(33));
    expect(corpus.map((f) => f.id).toSet(), {
      ..._stage0Fixtures,
      ..._stage4Fixtures,
    });
  });

  for (final fixture in corpus) {
    group(fixture.id, () {
      test('FIX-1: spec references exist', () {
        expect(
          specReferenceViolations(
            fixture,
            protocolDirectory: protocolDirectory,
          ),
          isEmpty,
        );
      });

      test('FIX-4: no undeclared extensions', () {
        expect(undeclaredExtensionViolations(fixture), isEmpty);
      });
    });
  }

  group('invariant checks on a temporary corpus', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('acp_fixture_invariants_');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    AcpFixture write(
      String name, {
      List<String> spec = const ['05-Prompt Turn.md#cancellation'],
      List<String>? extensions,
      Map<String, Object?> frame = const {
        'jsonrpc': '2.0',
        'method': 'session/cancel',
        'params': {'sessionId': r'${sessionId}'},
      },
    }) {
      File('${dir.path}/$name.json').writeAsStringSync(
        jsonEncode({
          'id': 'acp/$name',
          'spec': spec,
          'description': 'Временная фикстура теста инвариантов.',
          'extensions': ?extensions,
          'setup': <String, Object?>{},
          'frames': [
            {'dir': 'c2a', 'frame': frame},
          ],
        }),
      );
      return loadFixtureCorpus(
        directory: dir.path,
      ).singleWhere((f) => f.id == 'acp/$name');
    }

    test('a valid reference passes', () {
      expect(
        specReferenceViolations(
          write('valid'),
          protocolDirectory: protocolDirectory,
        ),
        isEmpty,
      );
    });

    test('a reference to a missing file names the fixture and the link', () {
      expect(
        specReferenceViolations(
          write('missing-file', spec: ['99-Nothing.md#cancellation']),
          protocolDirectory: protocolDirectory,
        ),
        [contains('acp/missing-file: spec "99-Nothing.md#cancellation"')],
      );
    });

    test('a reference to a missing anchor fails', () {
      expect(
        specReferenceViolations(
          write('missing-anchor', spec: ['05-Prompt Turn.md#no-such-part']),
          protocolDirectory: protocolDirectory,
        ),
        [contains('no anchor #no-such-part')],
      );
    });

    test('a reference without an anchor fails', () {
      expect(
        specReferenceViolations(
          write('no-anchor', spec: ['05-Prompt Turn.md']),
          protocolDirectory: protocolDirectory,
        ),
        [contains('no #anchor')],
      );
    });

    test('_meta.codelab without extensions fails', () {
      final frame = {
        'jsonrpc': '2.0',
        'id': 1,
        'result': {
          'stopReason': 'cancelled',
          '_meta': {
            'codelab': {'outcome': 'cancelled'},
          },
        },
      };
      expect(undeclaredExtensionViolations(write('meta', frame: frame)), [
        contains(r'$.frames[0].result._meta.codelab'),
      ]);
      expect(
        undeclaredExtensionViolations(
          write('meta-declared', frame: frame, extensions: ['outcome']),
        ),
        isEmpty,
      );
    });

    test('data.codelab and _codelab/* methods without extensions fail', () {
      expect(
        undeclaredExtensionViolations(
          write(
            'data',
            frame: {
              'jsonrpc': '2.0',
              'id': 1,
              'error': {
                'code': -32603,
                'message': 'failed',
                'data': {
                  'codelab': {'errorClass': 'auth'},
                },
              },
            },
          ),
        ),
        hasLength(1),
      );
      expect(
        undeclaredExtensionViolations(
          write(
            'method',
            frame: {'jsonrpc': '2.0', 'method': '_codelab/session/steer'},
          ),
        ),
        hasLength(1),
      );
    });
  });

  group('markdown anchors', () {
    test('headings become slugs, explicit anchors are kept', () {
      expect(
        markdownAnchors(
          '# Prompt Turn\n'
          '### 5. Tool Invocation and Status Reporting\n'
          '#### <span class="font-mono">WriteTextFileResponse</span>\n'
          '## The `_meta` Field\n'
          '<a id="fs-write_text_file" />\n',
        ),
        {
          'prompt-turn',
          '5-tool-invocation-and-status-reporting',
          'writetextfileresponse',
          'the-_meta-field',
          'fs-write_text_file',
        },
      );
    });
  });
}
