import 'dart:io';

import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/src/io/classify_provider_check_error.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Вид отказа проверки по ТИПУ ошибки `dart:io`, не по тексту (как
/// `classifyProbeFailure` change `add-app-settings-shell`; design.md change
/// `add-provider-setup-ui`, D8). Исключения построены вручную, сети нет.
void main() {
  group('classifyProviderCheckError', () {
    test('TlsException и наследники → tlsError', () {
      for (final error in <Object>[
        const HandshakeException('x'),
        const TlsException('x'),
        const CertificateException('x'),
      ]) {
        expect(
          classifyProviderCheckError(error),
          ProviderCheckFailureKind.tlsError,
          reason: '${error.runtimeType}',
        );
      }
    });

    test('SocketException с errno и без → unreachable', () {
      for (final code in [null, 61, 111, 10061, 8]) {
        expect(
          classifyProviderCheckError(
            SocketException(
              'x',
              osError: code == null ? null : OSError('', code),
            ),
          ),
          ProviderCheckFailureKind.unreachable,
          reason: '$code',
        );
      }
    });

    test('чужой тип и текст про handshake — не наш случай', () {
      expect(
        classifyProviderCheckError(StateError('HandshakeException')),
        isNull,
      );
      expect(
        classifyProviderCheckError(http.ClientException('HandshakeException')),
        isNull,
      );
    });
  });

  test(
    'HttpProviderCheck с классификатором: HandshakeException → tlsError',
    () async {
      final check = HttpProviderCheck(
        () => MockClient((_) async => throw const HandshakeException('x')),
        classifier: classifyProviderCheckError,
      );

      final result = await check.listModels(
        'openai-compatible',
        Uri.parse('https://h/v1'),
        null,
      );

      expect(
        (result as CheckFailure).failure.kind,
        ProviderCheckFailureKind.tlsError,
      );
    },
  );
}
