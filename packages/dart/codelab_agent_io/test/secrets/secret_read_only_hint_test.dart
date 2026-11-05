import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Подсказка бэкенда только для чтения: одна функция для `SecretCommands`,
/// app и мастера (design.md change `add-provider-setup-ui`, D3).
void main() {
  test('предлагает secrets.backend: file с путями каталога', () {
    const readOnly = SecretReadOnly(
      backend: 'env',
      variable: 'CODELAB_SECRET_CODELAB_OPENAI',
      fileBackendOffered: true,
    );

    expect(
      secretReadOnlyHint(readOnly, '/h'),
      "secret store env is read-only. Add 'secrets.backend: file' to "
      '/h/config.yaml to store secrets in /h/secrets.yaml (plaintext, 0600), '
      'or set CODELAB_SECRET_CODELAB_OPENAI in the environment',
    );
  });

  test('без предложения file (Windows) остаётся только переменная', () {
    const readOnly = SecretReadOnly(
      backend: 'env',
      variable: 'CODELAB_SECRET_CODELAB_OPENAI',
      fileBackendOffered: false,
    );

    expect(
      secretReadOnlyHint(readOnly, r'C:\h'),
      'secret store env is read-only. Set CODELAB_SECRET_CODELAB_OPENAI in '
      'the environment',
    );
  });
}
