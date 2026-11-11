// `CodeLabShellCubit.openExternalLink` и `showImage` (задачи 4.1 и 4.3 change
// `add-desktop-markdown`; spec agent-workbench-ui «Ссылки в ответе агента»,
// «Изображения в ответе агента»; design.md D5, D6, D12; DSK-7).
//
// Клик по ссылке начинает действие, а решение принимает app: Cubit ещё раз
// проверяет политику (виджет мог ошибиться), открывает адрес через порт
// платформы и пишет в журнал только схему, хост и исход — без пути, query и
// fragment (`AGENTS.md` §16). Красный: `openExternalLink`, `showImage`,
// `ExternalLinkOpener` и параметры `externalLinkOpener`/`eventLogger` фасада
// ещё не существуют.

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_io/codelab_client_io.dart'
    show IoWorkingDirectoryProvider;
import 'package:codelab_desktop/core/platform/external_link_opener.dart';
import 'package:codelab_desktop/core/platform/limited_network_image.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/core/platform/recent_projects_store.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_logger.dart';

final class _NoFolderPicker implements ProjectFolderPicker {
  @override
  Future<String?> pickFolder({String? initialDirectory}) async => null;
}

final class _MemoryRecentProjects implements RecentProjectsStore {
  final List<RecentProject> _entries = [];

  @override
  Future<List<RecentProject>> load() async => List.unmodifiable(_entries);

  @override
  Future<void> record(String path) async {
    _entries.insert(0, RecentProject(path: path, lastOpenedAt: DateTime.now()));
  }
}

/// Порт платформы с записью вызовов и заданным исходом.
final class _FakeOpener implements ExternalLinkOpener {
  ExternalLinkOutcome outcome = ExternalLinkOutcome.opened;
  bool throwOnOpen = false;
  final opened = <Uri>[];

  @override
  Future<ExternalLinkOutcome> open(Uri uri) async {
    if (throwOnOpen) throw StateError('platform exploded');
    opened.add(uri);
    return outcome;
  }
}

void main() {
  late _FakeOpener opener;
  late RecordingLogger events;
  late CodeLabShellCubit cubit;
  late FakeAcpTransport agent;
  late AcpClientApplication application;

  setUp(() {
    opener = _FakeOpener();
    events = RecordingLogger();
    agent = FakeAcpTransport();
    application = AcpClientApplication(transport: FakeAcpTransport());
    cubit = CodeLabShellCubit(
      profile: codelabAgentStdioProfile,
      application: application,
      stdioTransportFactory: (_) => agent,
      webSocketTransportFactory: (_) => FakeAcpTransport(),
      workingDirectoryProvider: const IoWorkingDirectoryProvider(),
      projectFolderPicker: _NoFolderPicker(),
      recentProjectsStore: _MemoryRecentProjects(),
      externalLinkOpener: opener,
      eventLogger: events,
    );
  });

  tearDown(() async {
    await cubit.close();
    await application.dispose();
  });

  Map<String, Object?> linkEvent() =>
      events.entries.singleWhere((e) => e['event'] == 'link.open');

  group('openExternalLink', () {
    test(
      'opens an https link once and logs scheme, host and outcome only',
      () async {
        await cubit.openExternalLink(
          Uri.parse('https://example.com/a?token=abc#frag'),
        );

        expect(opener.opened, [
          Uri.parse('https://example.com/a?token=abc#frag'),
        ]);
        final event = linkEvent();
        expect(event['scheme'], 'https');
        expect(event['host'], 'example.com');
        expect(event['outcome'], 'opened');
        // Только эти поля: путь, query и fragment в журнал не попадают.
        expect(event.keys.toSet(), {
          'event',
          'level',
          'scheme',
          'host',
          'outcome',
        });
        expect('$event', isNot(contains('token=abc')));
        expect('$event', isNot(contains('/a')));
        expect(cubit.state.linkNote, isNull);
      },
    );

    test('mailto reaches the port without cc, bcc, body and attach', () async {
      await cubit.openExternalLink(
        Uri.parse(
          'mailto:a@b.com?cc=x&bcc=y&body=z&attach=/etc/passwd&subject=hi',
        ),
      );

      expect(opener.opened.single.toString(), 'mailto:a@b.com?subject=hi');
    });

    test('a very long host is cut to 255 characters in the log', () async {
      final host = '${'a' * 300}.example';
      await cubit.openExternalLink(Uri.parse('https://$host/x'));

      expect((linkEvent()['host'] as String).length, lessThanOrEqualTo(255));
    });

    test('a broken mailto subject still opens, without the subject', () async {
      await cubit.openExternalLink(Uri.parse('mailto:a@b?subject=%E0%A4'));

      expect(opener.opened.single.toString(), 'mailto:a@b');
      expect(linkEvent()['outcome'], 'opened');
    });

    test('a port that throws is "failed": event, note, no exception', () async {
      opener.throwOnOpen = true;

      await cubit.openExternalLink(Uri.parse('https://example.com/a'));

      expect(linkEvent()['outcome'], 'failed');
      expect(cubit.state.linkNote, "Couldn't open the link.");
    });

    test('userinfo links never reach the port', () async {
      await cubit.openExternalLink(Uri.parse('https://good.com@evil.com'));

      expect(opener.opened, isEmpty);
      expect(linkEvent()['outcome'], 'rejectedScheme');
    });

    test('mailto is logged without the address', () async {
      await cubit.openExternalLink(
        Uri.parse('mailto:dev@example.com?subject=s'),
      );

      expect(opener.opened, hasLength(1));
      final event = linkEvent();
      expect(event['scheme'], 'mailto');
      expect('$event', isNot(contains('dev@example.com')));
      expect('$event', isNot(contains('subject')));
    });

    test(
      'checks the policy again: a bad scheme never reaches the port',
      () async {
        for (final value in [
          'file:///etc/passwd',
          'javascript:alert(1)',
          'data:text/html,hi',
          'vscode://open',
          '//evil.example/a',
          'https://',
        ]) {
          await cubit.openExternalLink(Uri.parse(value));
        }

        expect(opener.opened, isEmpty);
        final outcomes = [
          for (final e in events.entries)
            if (e['event'] == 'link.open') e['outcome'],
        ];
        expect(outcomes, everyElement('rejectedScheme'));
        expect(outcomes, hasLength(6));
      },
    );

    test('a platform refusal shows the note and logs "failed"', () async {
      opener.outcome = ExternalLinkOutcome.failed;

      await cubit.openExternalLink(Uri.parse('https://example.com/a'));

      expect(cubit.state.linkNote, "Couldn't open the link.");
      expect(linkEvent()['outcome'], 'failed');
    });

    test('the note goes away after the next successful open', () async {
      opener.outcome = ExternalLinkOutcome.failed;
      await cubit.openExternalLink(Uri.parse('https://example.com/a'));
      expect(cubit.state.linkNote, isNotNull);

      opener.outcome = ExternalLinkOutcome.opened;
      await cubit.openExternalLink(Uri.parse('https://example.com/b'));

      expect(cubit.state.linkNote, isNull);
    });

    test('dismissLinkNote clears the note', () async {
      opener.outcome = ExternalLinkOutcome.failed;
      await cubit.openExternalLink(Uri.parse('https://example.com/a'));

      cubit.dismissLinkNote();

      expect(cubit.state.linkNote, isNull);
    });
  });

  group('reportImageFailure', () {
    Map<String, Object?> imageEvent() =>
        events.entries.singleWhere((e) => e['event'] == 'image.load');

    test('logs host and the rejection code only, without the address', () {
      cubit.reportImageFailure(
        'agent-2#image:https://x.example/p/y.png?d=secret',
        const ImageRejectedException(ImageRejection.tooLarge),
      );

      final event = imageEvent();
      expect(event['host'], 'x.example');
      expect(event['reason'], 'too_large');
      expect(event.keys.toSet(), {'event', 'level', 'host', 'reason'});
      expect('$event', isNot(contains('secret')));
      expect('$event', isNot(contains('y.png')));
    });

    test('every rejection maps to its code', () {
      for (final rejection in ImageRejection.values) {
        events.entries.clear();
        cubit.reportImageFailure(
          'agent-2#image:https://x.example/y.png',
          ImageRejectedException(rejection),
        );
        expect(imageEvent()['reason'], rejection.code, reason: '$rejection');
      }
    });

    test('a foreign error is "decode" and its text never reaches the log', () {
      cubit.reportImageFailure(
        'agent-2#image:https://x.example/y.png',
        StateError('https://x.example/y.png?d=secret'),
      );

      final event = imageEvent();
      expect(event['reason'], 'decode');
      expect('$event', isNot(contains('secret')));
    });

    test('a very long host is cut to 255 characters', () {
      cubit.reportImageFailure(
        'agent-2#image:https://${'a' * 300}.example/y.png',
        const ImageRejectedException(ImageRejection.timeout),
      );

      expect((imageEvent()['host'] as String).length, lessThanOrEqualTo(255));
    });

    test('a key that is not an https image is ignored', () {
      cubit
        ..reportImageFailure(
          'agent-2#image:http://x.example/y.png',
          const ImageRejectedException(ImageRejection.timeout),
        )
        ..reportImageFailure(
          'not-an-image-key',
          const ImageRejectedException(ImageRejection.timeout),
        );

      expect(events.entries.where((e) => e['event'] == 'image.load'), isEmpty);
    });
  });

  group('showImage', () {
    Future<void> sessionReady() async {
      await cubit.selectProject('/workspace');
      await cubit.connect();
      final sent = agent.sent.first;
      final create = cubit.createSession();
      final request = await sent as dynamic;
      agent.emitInbound(
        JsonRpcMessage.response(
          id: request.id as JsonRpcId,
          result: const {'sessionId': 'session-1'},
        ),
      );
      await create;
    }

    test(
      'remembers the choice by row and url and logs the host only',
      () async {
        await sessionReady();
        const key = 'agent-2#image:https://x.example/p/y.png?d=secret';

        cubit.showImage(key);

        expect(cubit.state.shownImages, {key});
        final event = events.entries.singleWhere(
          (e) => e['event'] == 'image.show',
        );
        expect(event['host'], 'x.example');
        expect(event.keys.toSet(), {'event', 'level', 'host'});
        expect('$event', isNot(contains('secret')));
        expect('$event', isNot(contains('y.png')));
      },
    );

    test('without an active session it does nothing', () {
      cubit.showImage('agent-2#image:https://x.example/y.png');

      expect(cubit.state.shownImages, isEmpty);
      expect(events.entries.where((e) => e['event'] == 'image.show'), isEmpty);
    });

    test('ignores a key that is not an https image of a row', () async {
      await sessionReady();

      cubit
        ..showImage('agent-2#image:http://x.example/y.png')
        ..showImage('agent-2#image:data:image/png;base64,AAAA')
        ..showImage('not-an-image-key');

      expect(cubit.state.shownImages, isEmpty);
    });
  });
}
