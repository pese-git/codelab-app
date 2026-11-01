// Дочерний процесс для `test/secrets/secret_process_runner_test.dart`: по
// режиму из argv выбирает код выхода, так как `IoSecretProcessRunner` отдаёт
// только код. Не копия чужого кода: набор режимов придуман под сценарии порта
// (design.md change `add-agent-secret-store`, D5).
//
//   env    -> 0, если в окружении нет ни одной переменной родителя
//             (`PATH`, `HOME`, `CODELAB_SECRET_*`), иначе 3
import 'dart:io';

void main(List<String> args) {
  if (args.first == 'env') {
    final leaked = Platform.environment.keys.any(
      (name) => name == 'PATH' || name == 'HOME' || name.startsWith('CODELAB_'),
    );
    exit(leaked ? 3 : 0);
  }
}
