/// Результат обращения к секрету (`agent-core-architecture` §17.5.2;
/// design.md change `add-agent-secret-store`, D3).
library;

/// Исход `SecretResolver.secret` и `SecretResolver.env`.
///
/// Почему sealed-иерархия вместо `String?`: «секрет не задан» (выполнить
/// `codelab secret set`) и «хранилище недоступно» (исправить хранилище или
/// задать переменную) требуют разных действий, и текст ошибки хода у них
/// разный (приоритет «наблюдаемость» выше простоты, D3).
///
/// Как использовать: `switch` по трём веткам; значение есть только у
/// [SecretFound], и его `toString` значение не печатает.
sealed class SecretLookup {
  const SecretLookup();
}

/// Секрет найден.
final class SecretFound extends SecretLookup {
  const SecretFound(this.value, this.source);

  /// Значение; в лог, журнал и сообщения об ошибках не попадает (CFG-10).
  final String value;

  /// Откуда взято: `cache`, `env` или id бэкенда хранилища.
  final String source;

  @override
  String toString() => 'SecretFound(source: $source)';
}

/// Секрета нет в [backend].
final class SecretMissing extends SecretLookup {
  const SecretMissing(this.backend);

  final String backend;

  @override
  String toString() => 'SecretMissing(backend: $backend)';
}

/// Хранилище [backend] недоступно по причине [reason] (наш текст без
/// значения).
final class SecretUnavailable extends SecretLookup {
  const SecretUnavailable(this.backend, this.reason);

  final String backend;
  final String reason;

  @override
  String toString() => 'SecretUnavailable(backend: $backend, reason: $reason)';
}
