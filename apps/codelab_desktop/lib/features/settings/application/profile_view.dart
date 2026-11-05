import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ConnectionProfile,
        EmbeddedProfile,
        EnvTokenRef,
        ProfileTokenRef,
        SecretTokenRef,
        StdioProfile,
        UnsupportedTokenRef,
        WebSocketProfile,
        profileOrigin;

// Origin адреса профиля — формула kit; реэкспорт сохраняет прежний импорт
// `profileOrigin` из этого файла у остальных файлов app.
export 'package:codelab_client_core/codelab_client_core.dart'
    show profileOrigin;

/// Заголовок профиля: `label`, а при пустом `label` и при `label` из значения
/// `--agent` (`stdio:…`, `ws://…`, `wss://…`; так CLI заполняет `label`
/// профиля, созданного из строки) — `id`. Иначе вся командная строка
/// повторялась бы в заголовке строки, в подтверждении «Remove» и на экране
/// подключения (D4). Одна функция для всех мест.
String profileTitle(ConnectionProfile profile) {
  final text = profile.label.trim();
  final fromAgentArgument =
      text.startsWith('stdio:') ||
      text.startsWith('ws://') ||
      text.startsWith('wss://');
  return text.isEmpty || fromAgentArgument ? profile.id : profile.label;
}

/// Сводка профиля для строки: команда или адрес, без аргументов, `env` и
/// значения токена (spec app-settings «Список профилей на странице
/// «Connection»»).
String profileSummary(ConnectionProfile profile) => switch (profile) {
  StdioProfile(:final command) => command,
  WebSocketProfile(:final uri) => profileOrigin(uri),
  EmbeddedProfile() => 'Runs inside CodeLab; no separate process.',
};

/// Источник токена WebSocket-профиля для строки: только имя, не значение.
///
/// Почему закрытая иерархия: у токена четыре видимых исхода (D13, D14), и
/// виджет обязан разобрать каждый.
sealed class ProfileTokenView {
  const ProfileTokenView();
}

/// `tokenRef` не задан: подключение без токена.
final class NoTokenView extends ProfileTokenView {
  const NoTokenView();

  @override
  bool operator ==(Object other) => other is NoTokenView;

  @override
  int get hashCode => (NoTokenView).hashCode;
}

/// Токен берётся из переменной окружения [name]; [isSet] — есть ли она и
/// непуста ли в окружении app (само значение не читается в состояние).
final class EnvTokenView extends ProfileTokenView {
  const EnvTokenView(this.name, {required this.isSet});

  final String name;
  final bool isSet;

  @override
  bool operator ==(Object other) =>
      other is EnvTokenView && other.name == name && other.isSet == isSet;

  @override
  int get hashCode => Object.hash(EnvTokenView, name, isSet);

  @override
  String toString() => 'EnvTokenView($name, isSet: $isSet)';
}

/// Токен лежит в хранилище секретов агента под именем [name] (`secret:<имя>`,
/// design.md change `add-provider-setup-ui`, D14).
///
/// [backend] — идентификатор бэкенда для тега `<backend> · set|missing`;
/// [isSet] — есть ли секрет (`ProfileSecrets.isSet`, значение не читается).
/// Имя секрета — не секрет и показывается текстом.
final class SecretTokenView extends ProfileTokenView {
  const SecretTokenView(
    this.name, {
    required this.backend,
    required this.isSet,
  });

  final String name;
  final String backend;
  final bool isSet;

  @override
  bool operator ==(Object other) =>
      other is SecretTokenView &&
      other.name == name &&
      other.backend == backend &&
      other.isSet == isSet;

  @override
  int get hashCode => Object.hash(SecretTokenView, name, backend, isSet);

  @override
  String toString() => 'SecretTokenView($name, $backend, isSet: $isSet)';
}

/// Ссылка, которую эта версия не разрешает.
///
/// Саму ссылку тип не хранит: в поле имени переменной могли вставить значение
/// токена, и показывать её нельзя нигде (M2, D13).
final class UnsupportedTokenView extends ProfileTokenView {
  const UnsupportedTokenView();

  @override
  bool operator ==(Object other) => other is UnsupportedTokenView;

  @override
  int get hashCode => (UnsupportedTokenView).hashCode;
}

/// Источник токена [profile] по правилу kit (`ProfileTokenRef`, D15).
///
/// [environment] — окружение app; читается только факт «задана и непуста».
/// [secretBackend] и [secretIsSet] — бэкенд хранилища и признак «секрет
/// задан» для ссылки `secret:`; Cubit получает их заранее (`isSet`) и
/// значение секрета не читает.
ProfileTokenView tokenViewOf(
  WebSocketProfile profile,
  Map<String, String> environment, {
  String secretBackend = 'env',
  bool Function(String name)? secretIsSet,
}) {
  final ref = profile.tokenRef;
  if (ref == null) {
    return const NoTokenView();
  }
  return switch (ProfileTokenRef.parse(ref)) {
    EnvTokenRef(:final name) => EnvTokenView(
      name,
      isSet: (environment[name] ?? '').isNotEmpty,
    ),
    SecretTokenRef(:final name) => SecretTokenView(
      name,
      backend: secretBackend,
      isSet: secretIsSet?.call(name) ?? false,
    ),
    UnsupportedTokenRef() => const UnsupportedTokenView(),
  };
}
