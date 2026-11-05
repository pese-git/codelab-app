/// Статус ключа провайдера для страниц настроек (`dart-agent-and-clients`
/// §12.4.5; design.md change `add-provider-setup-ui`, D3, D10; SETUP-1).
library;

/// Где ключ провайдера и есть ли он — без чтения значения.
///
/// Почему запечатанная иерархия: страница строит подпись и подсказку по виду
/// статуса, а новый вид не должен пройти мимо `switch`.
///
/// Для чего: единый ответ на вопрос «задан ли ключ» для app и CLI. Статус
/// строится по ИМЕНАМ (`names()` хранилища, переменные окружения); значение не
/// читается и не попадает ни в поля, ни в [label] (SETUP-1).
sealed class KeyStatusView {
  const KeyStatusView();

  /// Подпись статуса для строки провайдера: `Key: in file`,
  /// `Key: missing in file`, `Key: env OPENAI_API_KEY (set)`, `No key`.
  String get label;
}

/// `api_key_secret`: секрет есть в хранилище [backendId] (или задан
/// переменной переопределения — тогда [backendId] `env`).
final class KeyInSecretStore extends KeyStatusView {
  const KeyInSecretStore({required this.name, required this.backendId});

  final String name;
  final String backendId;

  @override
  String get label => 'Key: in $backendId';

  @override
  bool operator ==(Object other) =>
      other is KeyInSecretStore &&
      other.name == name &&
      other.backendId == backendId;

  @override
  int get hashCode => Object.hash(KeyInSecretStore, name, backendId);

  @override
  String toString() => 'KeyInSecretStore($name, $backendId)';
}

/// `api_key_secret` указывает на секрет, которого нет в хранилище
/// [backendId]: провайдер не получит ключ.
final class KeySecretMissing extends KeyStatusView {
  const KeySecretMissing({required this.name, required this.backendId});

  final String name;
  final String backendId;

  @override
  String get label => 'Key: missing in $backendId';

  @override
  bool operator ==(Object other) =>
      other is KeySecretMissing &&
      other.name == name &&
      other.backendId == backendId;

  @override
  int get hashCode => Object.hash(KeySecretMissing, name, backendId);

  @override
  String toString() => 'KeySecretMissing($name, $backendId)';
}

/// `api_key_env`: ключ берётся из переменной [name]; [isSet] — задана ли она
/// (непустое значение) в окружении агента.
final class KeyFromEnv extends KeyStatusView {
  const KeyFromEnv({required this.name, required this.isSet});

  final String name;
  final bool isSet;

  @override
  String get label => 'Key: env $name (${isSet ? 'set' : 'not set'})';

  @override
  bool operator ==(Object other) =>
      other is KeyFromEnv && other.name == name && other.isSet == isSet;

  @override
  int get hashCode => Object.hash(KeyFromEnv, name, isSet);

  @override
  String toString() => 'KeyFromEnv($name, ${isSet ? 'set' : 'not set'})';
}

/// Ключ не нужен или не задан (локальный сервер без авторизации).
final class KeyNone extends KeyStatusView {
  const KeyNone();

  @override
  String get label => 'No key';

  @override
  bool operator ==(Object other) => other is KeyNone;

  @override
  int get hashCode => (KeyNone).hashCode;

  @override
  String toString() => 'KeyNone';
}

/// Ключ записан значением в файле конфига (`api_key`, R8-4): работает, но
/// лежит открытым текстом; `codelab secret migrate` переносит его в хранилище.
///
/// Почему отдельный вид: «No key» про такого провайдера было бы ложью, а
/// показывать значение нельзя.
final class KeyLiteralInConfig extends KeyStatusView {
  const KeyLiteralInConfig();

  @override
  String get label => 'Key: in config file (plain text)';

  @override
  bool operator ==(Object other) => other is KeyLiteralInConfig;

  @override
  int get hashCode => (KeyLiteralInConfig).hashCode;

  @override
  String toString() => 'KeyLiteralInConfig';
}
