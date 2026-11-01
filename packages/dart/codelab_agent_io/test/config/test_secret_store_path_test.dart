import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Путь тестового хранилища секретов из окружения (change
/// `add-embedded-agent-mode`, D5): правило живёт рядом с загрузчиком, который
/// знает имя переменной. Вариант с `-DCODELAB_ALLOW_TEST_SECRETS=true`
/// покрывает процессный тест `codelab_embedded/test/io/
/// test_secret_store_process_test.dart`: define вычисляется при компиляции, и
/// в одном прогоне тестов оба варианта не проверить.
void main() {
  test(
    'in a regular build the variable is not read',
    () {
      expect(
        testSecretStorePath({'CODELAB_TEST_SECRET_STORE': '/store'}),
        isNull,
      );
    },
    skip: const bool.fromEnvironment('CODELAB_ALLOW_TEST_SECRETS')
        ? 'сборка с define: покрыто процессным тестом codelab_embedded'
        : false,
  );

  test('an absent or empty variable is null', () {
    expect(testSecretStorePath(const {}), isNull);
    expect(testSecretStorePath({'CODELAB_TEST_SECRET_STORE': ''}), isNull);
  });
}
