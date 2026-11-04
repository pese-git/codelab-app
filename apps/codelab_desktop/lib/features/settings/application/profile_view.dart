import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ConnectionProfile,
        EmbeddedProfile,
        EnvTokenRef,
        ProfileTokenRef,
        StdioProfile,
        UnsupportedTokenRef,
        WebSocketProfile;

/// `scheme://host[:port]` адреса [uri] без userinfo, пути и query.
///
/// Почему: страница и журнал показывают, куда подключён app, но путь и query
/// могут нести токен, а userinfo — пароль (design.md change
/// `add-app-settings-shell`, D10, D17).
///
/// Как использовать: единственный способ превратить URL профиля в текст для
/// экрана настроек; порт показывается, только если он указан явно.
String profileOrigin(Uri uri) =>
    '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

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
/// Почему закрытая иерархия: у токена четыре видимых исхода (D13), и виджет
/// обязан разобрать каждый.
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
ProfileTokenView tokenViewOf(
  WebSocketProfile profile,
  Map<String, String> environment,
) {
  final ref = profile.tokenRef;
  if (ref == null) {
    return const NoTokenView();
  }
  return switch (ProfileTokenRef.parse(ref)) {
    EnvTokenRef(:final name) => EnvTokenView(
      name,
      isSet: (environment[name] ?? '').isNotEmpty,
    ),
    UnsupportedTokenRef() => const UnsupportedTokenView(),
  };
}
