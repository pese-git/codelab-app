import 'secret_source.dart';

/// Допустимое имя переменной окружения в ссылке `env:<NAME>`.
final _variableName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Разобранная ссылка на токен WebSocket-профиля (`WebSocketProfile.tokenRef`).
///
/// Почему: app и CLI хранят токен профиля только ссылкой (`AGENTS.md` §10), а
/// правило «что значит ссылка» должно быть одно — иначе профиль, созданный в
/// app со ссылкой `env:DEVBOX_TOKEN`, не заработал бы в CLI (design.md change
/// `add-app-settings-shell`, D15). Форму «имя секрета» добавит change
/// `add-provider-setup-ui`, поэтому сейчас всё, кроме `env:<NAME>`, —
/// [UnsupportedTokenRef].
///
/// Для чего: [ProfileSecretSource] читает по ней значение, страница
/// «Connection» app показывает по ней источник токена («From $NAME» или «не
/// поддерживается»), не обращаясь к значению.
///
/// Как использовать: `switch (ProfileTokenRef.parse(ref)) { EnvTokenRef(:final
/// name) => …, UnsupportedTokenRef() => … }`. Разбор не бросает исключений и
/// значения токена не видит.
sealed class ProfileTokenRef {
  const ProfileTokenRef();

  /// `env:<NAME>` с допустимым именем (`^[A-Za-z_][A-Za-z0-9_]*$`) —
  /// [EnvTokenRef]; всё остальное, включая `env:` с недопустимым именем и
  /// имя секрета, — [UnsupportedTokenRef].
  factory ProfileTokenRef.parse(String ref) {
    const prefix = 'env:';
    if (ref.startsWith(prefix)) {
      final name = ref.substring(prefix.length);
      if (_variableName.hasMatch(name)) {
        return EnvTokenRef(name);
      }
    }
    return UnsupportedTokenRef(ref);
  }
}

/// Токен лежит в переменной окружения процесса [name].
final class EnvTokenRef extends ProfileTokenRef {
  const EnvTokenRef(this.name);

  final String name;

  /// Ссылка в форме, которую хранит профиль: `env:<name>`.
  String get ref => 'env:$name';

  @override
  bool operator ==(Object other) => other is EnvTokenRef && other.name == name;

  @override
  int get hashCode => Object.hash(EnvTokenRef, name);

  @override
  String toString() => 'EnvTokenRef($name)';
}

/// Ссылка, которую эта версия не умеет разрешать: имя секрета или
/// искажённый `env:`. Подключение с ней идёт без токена.
final class UnsupportedTokenRef extends ProfileTokenRef {
  const UnsupportedTokenRef(this.ref);

  /// Исходная ссылка: может оказаться самим секретом, вписанным не в то поле,
  /// поэтому хосты её не выводят (CLI печатает общий текст).
  final String ref;

  @override
  bool operator ==(Object other) =>
      other is UnsupportedTokenRef && other.ref == ref;

  @override
  int get hashCode => Object.hash(UnsupportedTokenRef, ref);

  // Значение скрыто: ссылка может быть секретом, а `toString` попадает в
  // журналы и сообщения тестов. У `EnvTokenRef` остаётся имя переменной — оно
  // не секрет.
  @override
  String toString() => 'UnsupportedTokenRef(<redacted>)';
}

/// [SecretSource] токенов профилей: значение читается из окружения процесса
/// по [ProfileTokenRef].
///
/// Почему: один источник на app и CLI (design.md change
/// `add-app-settings-shell`, D15): прежний `EnvSecretSource` CLI и
/// `InMemorySecretSource` app разошлись бы при первом расширении ссылки.
///
/// Для чего: `ConfigTransportResolver` читает через него Bearer-токен в
/// момент открытия WebSocket; значение нигде не сохраняется и не
/// логируется.
///
/// Как использовать: composition root передаёт
/// `ProfileSecretSource(Platform.environment)` (окружение — аргумент, чтобы
/// ядро оставалось web-безопасным и тестируемым). Пустая или отсутствующая
/// переменная и [UnsupportedTokenRef] дают `null` — подключение без токена.
final class ProfileSecretSource implements SecretSource {
  const ProfileSecretSource(this._environment);

  final Map<String, String> _environment;

  @override
  Future<String?> read(String ref) async {
    final parsed = ProfileTokenRef.parse(ref);
    if (parsed is! EnvTokenRef) {
      return null;
    }
    final value = _environment[parsed.name];
    return value == null || value.isEmpty ? null : value;
  }
}
