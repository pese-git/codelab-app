import 'connection_profile.dart';
import 'profile_secrets.dart';
import 'secret_source.dart';

/// Допустимое имя переменной окружения в ссылке `env:<NAME>`.
final _variableName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Разобранная ссылка на токен WebSocket-профиля (`WebSocketProfile.tokenRef`).
///
/// Почему: app и CLI хранят токен профиля только ссылкой (`AGENTS.md` §10), а
/// правило «что значит ссылка» должно быть одно — иначе профиль, созданный в
/// app со ссылкой `env:DEVBOX_TOKEN`, не заработал бы в CLI (design.md change
/// `add-app-settings-shell`, D15). Поддержаны две формы: `env:<NAME>` и
/// `secret:<имя>` (design.md change `add-provider-setup-ui`, D13); всё
/// остальное — [UnsupportedTokenRef].
///
/// Для чего: [ProfileSecretSource] читает по ней значение, страница
/// «Connection» app показывает по ней источник токена («From $NAME» или «не
/// поддерживается»), не обращаясь к значению.
///
/// Как использовать: `switch (ProfileTokenRef.parse(ref)) { EnvTokenRef(:final
/// name) => …, SecretTokenRef(:final name) => …, UnsupportedTokenRef() => … }`. Разбор не бросает исключений и
/// значения токена не видит.
sealed class ProfileTokenRef {
  const ProfileTokenRef();

  /// `env:<NAME>` с допустимым именем (`^[A-Za-z_][A-Za-z0-9_]*$`) —
  /// [EnvTokenRef]; `secret:<имя>` с именем по правилу [isValidSecretName] —
  /// [SecretTokenRef]; всё остальное, включая искажённые префиксы, голое имя
  /// секрета без префикса и `secret:Bad Name`, — [UnsupportedTokenRef].
  /// Голое значение остаётся неподдерживаемым: это может быть токен,
  /// вписанный не в то поле.
  factory ProfileTokenRef.parse(String ref) {
    const envPrefix = 'env:';
    const secretPrefix = 'secret:';
    if (ref.startsWith(envPrefix)) {
      final name = ref.substring(envPrefix.length);
      if (_variableName.hasMatch(name)) {
        return EnvTokenRef(name);
      }
    } else if (ref.startsWith(secretPrefix)) {
      final name = ref.substring(secretPrefix.length);
      if (isValidSecretName(name)) {
        return SecretTokenRef(name);
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

/// Токен лежит в хранилище секретов агента под именем [name]
/// (`secret:<имя>`, design.md change `add-provider-setup-ui`, D13).
///
/// Почему префикс `secret:`: старая сборка (change `add-app-settings-shell`)
/// видит такую ссылку как неподдерживаемую и подключается без токена, не
/// портя файл. Имя секрета — не секрет, поэтому в `toString` оно есть.
final class SecretTokenRef extends ProfileTokenRef {
  const SecretTokenRef(this.name);

  final String name;

  /// Ссылка в форме, которую хранит профиль: `secret:<name>`.
  String get ref => 'secret:$name';

  @override
  bool operator ==(Object other) =>
      other is SecretTokenRef && other.name == name;

  @override
  int get hashCode => Object.hash(SecretTokenRef, name);

  @override
  String toString() => 'SecretTokenRef($name)';
}

/// Ссылка, которую эта версия не умеет разрешать: голое имя секрета,
/// `secret:` с недопустимым именем или искажённый `env:`. Подключение с ней идёт без токена.
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
/// или из хранилища секретов по [ProfileTokenRef].
///
/// Почему: один источник на app и CLI (design.md change
/// `add-app-settings-shell`, D15): прежний `EnvSecretSource` CLI и
/// `InMemorySecretSource` app разошлись бы при первом расширении ссылки.
///
/// Для чего: `ConfigTransportResolver` читает через него Bearer-токен в
/// момент открытия WebSocket; значение нигде не сохраняется и не
/// логируется. Кэша нет намеренно: замена секрета другим процессом видна при
/// следующем открытии транспорта (spec acp-client-kit «Ссылка на токен
/// профиля»).
///
/// Как использовать: composition root передаёт
/// `ProfileSecretSource(Platform.environment, stored: profileSecrets)`
/// (окружение и порт — аргументы, чтобы ядро оставалось web-безопасным и
/// тестируемым). `env:` читает переменную, `secret:` — `stored.read(имя)`.
/// Пустое значение, отсутствующий секрет, отсутствие порта `stored` и
/// [UnsupportedTokenRef] дают `null` — подключение без токена. Исключение
/// порта не глотается: открытие транспорта должно завершиться видимой
/// ошибкой, а не тихим подключением без токена.
final class ProfileSecretSource implements SecretSource {
  const ProfileSecretSource(this._environment, {ProfileSecrets? stored})
    : _stored = stored;

  final Map<String, String> _environment;
  final ProfileSecrets? _stored;

  @override
  Future<String?> read(String ref) async {
    final value = switch (ProfileTokenRef.parse(ref)) {
      EnvTokenRef(:final name) => _environment[name],
      SecretTokenRef(:final name) => await _stored?.read(name),
      UnsupportedTokenRef() => null,
    };
    return value == null || value.isEmpty ? null : value;
  }

  /// `true` — по [profile] серверу уходит непустой токен; значение не
  /// читается и наружу не выходит.
  ///
  /// Почему: тексту отказа по токену («отверг» или «требует») нужен только
  /// факт «ушёл ли токен», а читать секрет ради `bool` нельзя: хранилище ОС
  /// получило бы лишний запрос, а значение — лишнюю точку утечки (D13).
  ///
  /// Для чего: `env:` — непустая переменная окружения; `secret:` —
  /// `ProfileSecrets.isSet` (как [isSecretMissing]); без ссылки,
  /// неподдерживаемая ссылка, не-WebSocket профиль и сбой порта — `false`.
  Future<bool> hasToken(ConnectionProfile profile) async {
    if (profile is! WebSocketProfile) {
      return false;
    }
    final ref = profile.tokenRef;
    if (ref == null) {
      return false;
    }
    return switch (ProfileTokenRef.parse(ref)) {
      EnvTokenRef(:final name) => (_environment[name] ?? '').isNotEmpty,
      SecretTokenRef() => !await isSecretMissing(profile),
      UnsupportedTokenRef() => false,
    };
  }

  /// `true` — [profile] ссылается на `secret:<имя>`, а секрета нет (или порт
  /// `stored` не передан, или хранилище не отвечает).
  ///
  /// Почему: подключение без токена при `secret:` без значения — не ошибка
  /// (spec acp-client-kit «Ссылка на токен профиля»), но пользователь должен
  /// узнать причину отказа сервера. Хост пишет предупреждение
  /// [secretMissingWarning] до подключения (design.md change
  /// `add-provider-setup-ui`, D13).
  ///
  /// Для чего: проверка наличия через `ProfileSecrets.isSet` — значение
  /// второй раз не читается, и хранилище ОС не получает лишнего запроса;
  /// переменная переопределения уже учтена в `isSet` порта.
  ///
  /// Как использовать: `await source.isSecretMissing(profile)` перед
  /// `connect`. Для других ссылок (`env:`, без токена, неподдерживаемая) и
  /// не-WebSocket профилей — `false`: их предупреждения устроены иначе.
  /// Исключения порта не пробрасываются: «не удалось проверить» для
  /// предупреждения то же, что «нет».
  Future<bool> isSecretMissing(ConnectionProfile profile) async {
    if (profile is! WebSocketProfile) {
      return false;
    }
    final ref = profile.tokenRef;
    if (ref == null) {
      return false;
    }
    final parsed = ProfileTokenRef.parse(ref);
    if (parsed is! SecretTokenRef) {
      return false;
    }
    final stored = _stored;
    if (stored == null) {
      return true;
    }
    try {
      return !await stored.isSet(parsed.name);
    } on Object catch (_) {
      return true;
    }
  }
}

/// Текст предупреждения D13 для профиля [profileId] с пустым секретом токена.
///
/// Только id профиля: имя секрета не секрет, но диагностика держится правила
/// «только `profile_id`» (design.md change `add-provider-setup-ui`, D13).
/// Сами предупреждения пишут хосты (журнал app, stderr CLI).
String secretMissingWarning(String profileId) =>
    'Profile $profileId has no stored secret value; connecting without '
    'a token.';
