// Порт открытия внешних ссылок (задача 4.1 change `add-desktop-markdown`;
// design.md D5, D12; DSK-7; `platform-integration.md`).
//
// Порт — вторая линия защиты: даже если политика app пропустила бы адрес,
// схема вне `http`/`https`/`mailto` не доходит до платформы. Красный:
// `external_link_opener.dart` ещё нет.

import 'package:codelab_desktop/core/platform/external_link_opener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Uri> launched;

  UrlLauncherExternalLinkOpener opener({
    Future<bool> Function(Uri uri)? launch,
  }) => UrlLauncherExternalLinkOpener(
    launch: (uri) {
      launched.add(uri);
      return launch == null ? Future.value(true) : launch(uri);
    },
  );

  setUp(() => launched = []);

  test('opens http, https and mailto through the platform', () async {
    for (final value in [
      'https://example.com/a?q=1',
      'http://example.com',
      'mailto:dev@example.com',
    ]) {
      expect(
        await opener().open(Uri.parse(value)),
        ExternalLinkOutcome.opened,
        reason: value,
      );
    }
    expect(launched, hasLength(3));
  });

  test('rejects other schemes before the platform is called', () async {
    for (final value in [
      'file:///etc/passwd',
      'ssh://host/path',
      'javascript:alert(1)',
      'data:text/html,hi',
      'vscode://open',
      'xmpp:a@b',
      '//evil.example/a',
      '/relative',
      'https://',
      'mailto:',
    ]) {
      expect(
        await opener().open(Uri.parse(value)),
        ExternalLinkOutcome.rejectedScheme,
        reason: value,
      );
    }
    expect(launched, isEmpty);
  });

  test('a platform refusal is "failed", not an exception', () async {
    final refusing = opener(launch: (uri) async => false);
    expect(
      await refusing.open(Uri.parse('https://example.com')),
      ExternalLinkOutcome.failed,
    );
  });

  test('a platform error is "failed" too', () async {
    final failing = opener(launch: (uri) => throw StateError('no handler'));
    expect(
      await failing.open(Uri.parse('https://example.com')),
      ExternalLinkOutcome.failed,
    );
  });
}
