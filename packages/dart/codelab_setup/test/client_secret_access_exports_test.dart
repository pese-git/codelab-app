import 'dart:io';

import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

/// `ClientSecretAccess` и `secretReadOnlyHint` доступны клиенту через один
/// `io.dart` (client-agent-setup «Состав моста»; change
/// `add-provider-setup-ui`, D3, D4): клиентам запрещён `package:codelab_agent_*`.
void main() {
  test('ClientSecretAccess строится через io.dart', () async {
    final root = Directory.systemTemp.createTempSync('client_secret_exports');
    addTearDown(() => root.deleteSync(recursive: true));

    final access = await ClientSecretAccess.open(
      codelabHome: '${root.path}/home',
      environment: const {'CODELAB_SECRET_CODELAB_P': 'x'},
      logger: const _QuietLogger(),
    );

    expect(access.backend, isA<SecretBackendInfo>());
    expect(access.admin, isA<SecretAdmin>());
    expect(await access.isSet('codelab/p'), isTrue);
    expect(await access.read('codelab/p'), 'x');
  });

  test('secretReadOnlyHint доступна через io.dart', () {
    const readOnly = SecretReadOnly(
      backend: 'env',
      variable: 'CODELAB_SECRET_CODELAB_P',
      fileBackendOffered: false,
    );

    expect(secretReadOnlyHint(readOnly, '/h'), contains('read-only'));
  });
}

final class _QuietLogger implements Logger {
  const _QuietLogger();

  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}
