import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

void main() {
  test('the main barrel re-exports the pure config types', () {
    // Компиляция реэкспорта: тип должен быть виден клиенту без импорта ядра.
    const ConfigLoadResult? loaded = null;
    const ConfigIssueKind? kind = null;
    const ConfigIssue? issue = null;

    expect([loaded, kind, issue], everyElement(isNull));
  });

  test('io.dart exposes the shared config check command', () {
    final result = ConfigCommands().check(
      const CheckOptions(cwd: '/definitely/not/here', environment: {}),
    );

    // Несуществующий --cwd — ошибка использования, а не проблема конфига.
    expect(result.exitCode, configUsageExit);
    expect(configValidExit, 0);
    expect(configInvalidExit, 1);
  });
}
