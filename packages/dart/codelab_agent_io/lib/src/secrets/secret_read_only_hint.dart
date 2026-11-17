import 'secret_admin.dart';

/// Подсказка для бэкенда секретов только для чтения (design.md change
/// `add-agent-secret-store`, D8, п. 3; change `add-provider-setup-ui`, D3).
///
/// Почему одна функция: `codelab secret set`, мастер провайдера CLI и страницы
/// codelab-app обязаны говорить одно и то же, а текст зависит от настоящего
/// пути `$CODELAB_HOME` и от платформы. Раньше текст жил приватным методом
/// `SecretCommands`; вынос не меняет вывод CLI (`secret_commands_test.dart`).
///
/// Для чего: превратить [SecretReadOnly] (данные без языка) в строку. Клиент
/// получает готовую строку, Cubit-ы и автоматы мастера текст не строят.
///
/// Как использовать: `secretReadOnlyHint(readOnly, home)`, где [home] —
/// настоящий `$CODELAB_HOME`. При `fileBackendOffered` предлагается
/// `secrets.backend: file` (открытый файл `0600`), на Windows — только
/// переменная окружения (D7, D14). Значений секретов в тексте нет.
String secretReadOnlyHint(SecretReadOnly readOnly, String home) {
  final head = 'secret store ${readOnly.backend} is read-only.';
  return readOnly.fileBackendOffered
      ? "$head Add 'secrets.backend: file' to $home/config.yaml to store "
            'secrets in $home/secrets.yaml (plaintext, 0600), or set '
            '${readOnly.variable} in the environment'
      : '$head Set ${readOnly.variable} in the environment';
}
