import 'connection_profile.dart';
import 'profile_ids.dart';
import 'profile_parsing.dart';
import 'transport_resolver.dart';

/// Тип профиля, который можно создать в форме.
///
/// Почему: встроенный агент выбирается словом `embedded`, а не записью
/// (D5/D21), поэтому создавать можно только stdio и WebSocket.
enum ProfileKind { stdio, webSocket }

/// Выбор токена WebSocket-профиля в черновике (design.md change
/// `add-app-settings-shell`, D13).
///
/// Почему: значение токена приложение не принимает и не хранит — только
/// ссылку (`AGENTS.md` §10); значения вводит «Store a new token» в change
/// `add-provider-setup-ui`.
///
/// Как использовать: `switch (choice)` по трём формам; форма «Add
/// connection profile» предлагает [NoToken] и [EnvToken], а [KeepTokenRef]
/// появляется только у существующих профилей с другой ссылкой.
sealed class ProfileTokenChoice {
  const ProfileTokenChoice();
}

/// Подключение без токена.
final class NoToken extends ProfileTokenChoice {
  const NoToken();

  @override
  bool operator ==(Object other) => other is NoToken;

  @override
  int get hashCode => (NoToken).hashCode;

  @override
  String toString() => 'NoToken()';
}

/// Токен лежит в переменной окружения [name]; профиль получает
/// `tokenRef: env:<name>`. Само значение kit не читает.
final class EnvToken extends ProfileTokenChoice {
  const EnvToken(this.name);

  final String name;

  @override
  bool operator ==(Object other) => other is EnvToken && other.name == name;

  @override
  int get hashCode => Object.hash(EnvToken, name);

  @override
  String toString() => 'EnvToken($name)';
}

/// Оставить ссылку существующего профиля как есть.
///
/// Почему: профиль мог получить ссылку не вида `env:` (имя секрета, ручная
/// правка), и форма не должна её стирать.
final class KeepTokenRef extends ProfileTokenChoice {
  const KeepTokenRef(this.ref);

  final String ref;

  @override
  bool operator ==(Object other) => other is KeepTokenRef && other.ref == ref;

  @override
  int get hashCode => Object.hash(KeepTokenRef, ref);

  // Ссылка могла оказаться самим секретом, вписанным не в то поле, поэтому
  // в журналы и сообщения тестов она не попадает.
  @override
  String toString() => 'KeepTokenRef(<redacted>)';
}

/// Поле формы, к которому относится проблема.
enum ProfileDraftField { label, id, command, args, env, url, token }

/// Вид проблемы черновика (design.md change `add-app-settings-shell`, D11).
enum ProfileDraftIssueCode {
  labelEmpty,
  idEmpty,
  idInvalid,
  idReserved,
  idTaken,
  commandEmpty,
  argsInvalid,
  envSecretLike,
  urlInvalid,

  /// URL несёт `user:password@`: секрет попал бы в `profiles.json` и ушёл бы
  /// Basic-авторизацией (`AGENTS.md` §10). Токен задаётся полем Token.
  urlUserInfo,
  tokenEnvNameInvalid,

  /// Предупреждение: `ws://` к нелокальному хосту. Не блокирует сохранение,
  /// но требует подтверждения «Save anyway» (SETUP-10).
  plaintextToRemote,
}

/// Проблема одного поля черновика.
///
/// Почему типизированная, а не исключение: форма показывает все проблемы
/// сразу, каждую у своего поля (`state-management.md` §65).
///
/// Как использовать: по [code] и [field] форма выбирает место и локализует
/// текст; [message] — английский текст по умолчанию. Он никогда не содержит
/// значений `env` и токена (SETUP-19, `AGENTS.md` §10); [subject] — имя
/// ключа `env`, если проблема в нём.
final class ProfileDraftIssue {
  const ProfileDraftIssue({
    required this.code,
    required this.field,
    required this.message,
    this.subject,
  });

  final ProfileDraftIssueCode code;
  final ProfileDraftField field;
  final String message;
  final String? subject;

  /// Предупреждение, не блокирующее сохранение.
  bool get isWarning => code == ProfileDraftIssueCode.plaintextToRemote;

  @override
  bool operator ==(Object other) =>
      other is ProfileDraftIssue &&
      other.code == code &&
      other.field == field &&
      other.subject == subject;

  @override
  int get hashCode => Object.hash(code, field, subject);

  @override
  String toString() => 'ProfileDraftIssue(${code.name}, ${field.name})';
}

/// Результат [ProfileDraft.toProfile].
sealed class ProfileDraftResult {
  const ProfileDraftResult();
}

/// Черновик без ошибок: [profile] построен, [warnings] — предупреждения,
/// которые хост обязан показать до сохранения (`plaintextToRemote`).
final class DraftAccepted extends ProfileDraftResult {
  const DraftAccepted(this.profile, {this.warnings = const []});

  final ConnectionProfile profile;
  final List<ProfileDraftIssue> warnings;
}

/// Профиль не построен: [issues] содержит минимум одну ошибку.
final class DraftRejected extends ProfileDraftResult {
  const DraftRejected(this.issues);

  final List<ProfileDraftIssue> issues;
}

/// Неизменяемый черновик профиля подключения stdio или WebSocket.
///
/// Почему: правила формы («Add connection profile» app, будущий `codelab
/// profiles add`) должны быть одни и в kit; в Cubit-е app их повторил бы
/// CLI, и правила id разошлись бы (design.md change
/// `add-app-settings-shell`, D11).
///
/// Для чего: [validate] отдаёт проблемы по полям, [toProfile] — единственный
/// путь из черновика в `ConnectionProfile`, и правила безопасности
/// (секретоподобный `env`, зарезервированный id) проверяются в нём, а не
/// только в UI (`state-management.md` §65).
///
/// Как использовать: форма держит черновик в состоянии, меняет `copyWith`;
/// текстовые поля [args] и [env] хранятся как ввод пользователя. `existingIds`
/// — id уже сохранённых профилей (занятость сравнивается без учёта
/// регистра). Для stdio поля WebSocket игнорируются и наоборот.
final class ProfileDraft {
  const ProfileDraft({
    required this.kind,
    this.id = '',
    this.label = '',
    this.command = 'codelab-agent',
    this.args = 'serve --stdio',
    this.env = '',
    this.runInProjectDirectory = true,
    this.url = '',
    this.token = const NoToken(),
  });

  final ProfileKind kind;
  final String id;
  final String label;
  final String command;

  /// Строка аргументов; разбирает `parseShellWords`.
  final String args;

  /// Строки `KEY=value`; разбирает `parseEnvLines`.
  final String env;
  final bool runInProjectDirectory;
  final String url;
  final ProfileTokenChoice token;

  ProfileDraft copyWith({
    ProfileKind? kind,
    String? id,
    String? label,
    String? command,
    String? args,
    String? env,
    bool? runInProjectDirectory,
    String? url,
    ProfileTokenChoice? token,
  }) => ProfileDraft(
    kind: kind ?? this.kind,
    id: id ?? this.id,
    label: label ?? this.label,
    command: command ?? this.command,
    args: args ?? this.args,
    env: env ?? this.env,
    runInProjectDirectory: runInProjectDirectory ?? this.runInProjectDirectory,
    url: url ?? this.url,
    token: token ?? this.token,
  );

  /// Все проблемы и предупреждения черновика; пусто — профиль строится.
  List<ProfileDraftIssue> validate(Iterable<String> existingIds) {
    final issues = <ProfileDraftIssue>[];
    if (label.trim().isEmpty) {
      issues.add(
        const ProfileDraftIssue(
          code: ProfileDraftIssueCode.labelEmpty,
          field: ProfileDraftField.label,
          message: 'Name is required.',
        ),
      );
    }
    _validateId(existingIds, issues);
    switch (kind) {
      case ProfileKind.stdio:
        _validateStdio(issues);
      case ProfileKind.webSocket:
        _validateWebSocket(issues);
    }
    return List.unmodifiable(issues);
  }

  /// Строит профиль, если нет ошибок (предупреждения не блокируют).
  ///
  /// Повторяет [validate] сам: вызывающий не может получить профиль в обход
  /// правил.
  ProfileDraftResult toProfile(Iterable<String> existingIds) {
    final issues = validate(existingIds);
    final errors = [
      for (final issue in issues)
        if (!issue.isWarning) issue,
    ];
    if (errors.isNotEmpty) {
      return DraftRejected(errors);
    }
    final warnings = [
      for (final issue in issues)
        if (issue.isWarning) issue,
    ];
    final profile = switch (kind) {
      ProfileKind.stdio => ConnectionProfile.stdio(
        id: id,
        label: label.trim(),
        command: command.trim(),
        args: parseShellWords(args),
        env: parseEnvLines(env),
        runInProjectDirectory: runInProjectDirectory,
      ),
      ProfileKind.webSocket => ConnectionProfile.webSocket(
        id: id,
        label: label.trim(),
        uri: Uri.parse(url.trim()),
        tokenRef: switch (token) {
          NoToken() => null,
          EnvToken(:final name) => 'env:$name',
          KeepTokenRef(:final ref) => ref,
        },
      ),
    };
    return DraftAccepted(profile, warnings: warnings);
  }

  void _validateId(Iterable<String> existingIds, List<ProfileDraftIssue> out) {
    void add(ProfileDraftIssueCode code, String message) => out.add(
      ProfileDraftIssue(
        code: code,
        field: ProfileDraftField.id,
        message: message,
      ),
    );
    final lower = id.toLowerCase();
    if (id.isEmpty) {
      add(ProfileDraftIssueCode.idEmpty, 'Id is required.');
    } else if (isReservedProfileId(lower)) {
      add(
        ProfileDraftIssueCode.idReserved,
        '"$lower" is reserved for the built-in agent.',
      );
    } else if (existingIds.any((existing) => existing.toLowerCase() == lower)) {
      add(ProfileDraftIssueCode.idTaken, 'A profile with this id exists.');
    } else if (!isValidProfileId(id)) {
      add(
        ProfileDraftIssueCode.idInvalid,
        'Use lowercase letters, digits, ".", "_" and "-" (up to 64 characters).',
      );
    }
  }

  void _validateStdio(List<ProfileDraftIssue> out) {
    if (command.trim().isEmpty) {
      out.add(
        const ProfileDraftIssue(
          code: ProfileDraftIssueCode.commandEmpty,
          field: ProfileDraftField.command,
          message: 'Command is required.',
        ),
      );
    }
    try {
      parseShellWords(args);
    } on FormatException {
      out.add(
        const ProfileDraftIssue(
          code: ProfileDraftIssueCode.argsInvalid,
          field: ProfileDraftField.args,
          message: 'Arguments have an unclosed quote.',
        ),
      );
    }
    for (final key in parseEnvLines(env).keys) {
      if (_looksLikeSecret(key)) {
        // Значение в текст не попадает намеренно (SETUP-19).
        out.add(
          ProfileDraftIssue(
            code: ProfileDraftIssueCode.envSecretLike,
            field: ProfileDraftField.env,
            subject: key,
            message:
                '$key looks like a secret. Set it in the system environment '
                r'or reference it from the agent config as ${secret:…}.',
          ),
        );
      }
    }
  }

  void _validateWebSocket(List<ProfileDraftIssue> out) {
    final uri = Uri.tryParse(url.trim());
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        (scheme != 'ws' && scheme != 'wss') ||
        uri.host.isEmpty) {
      out.add(
        const ProfileDraftIssue(
          code: ProfileDraftIssueCode.urlInvalid,
          field: ProfileDraftField.url,
          message: 'Enter a ws:// or wss:// URL with a host.',
        ),
      );
    } else if (uri.userInfo.isNotEmpty) {
      // Сообщение без значения: userinfo — потенциальный секрет (SETUP-19).
      out.add(
        const ProfileDraftIssue(
          code: ProfileDraftIssueCode.urlUserInfo,
          field: ProfileDraftField.url,
          message:
              'Remove the user name and password from the URL; '
              'use the Token setting instead.',
        ),
      );
    } else if (scheme == 'ws' && !_isLocalHost(uri.host)) {
      out.add(
        const ProfileDraftIssue(
          code: ProfileDraftIssueCode.plaintextToRemote,
          field: ProfileDraftField.url,
          message:
              'ws:// sends data unencrypted to a remote host. Prefer wss://.',
        ),
      );
    }
    final choice = token;
    if (choice is EnvToken && !_variableName.hasMatch(choice.name)) {
      out.add(
        const ProfileDraftIssue(
          code: ProfileDraftIssueCode.tokenEnvNameInvalid,
          field: ProfileDraftField.token,
          message:
              'Variable name: letters, digits and "_", not starting '
              'with a digit.',
        ),
      );
    }
  }
}

final _variableName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

bool _looksLikeSecret(String key) {
  final upper = key.toUpperCase();
  return upper == 'KEY' ||
      upper == 'TOKEN' ||
      upper == 'SECRET' ||
      upper.endsWith('_KEY') ||
      upper.endsWith('_TOKEN') ||
      upper.endsWith('_SECRET');
}

bool _isLocalHost(String host) {
  final lower = host.toLowerCase();
  return lower == 'localhost' ||
      lower == '::1' ||
      RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(lower);
}

/// Типы профилей, которые поддерживает хотя бы один резолвер (SETUP-22).
///
/// Почему: на хосте без stdio-резолвера (web) форма не должна предлагать
/// stdio, иначе профиль нельзя будет открыть.
///
/// Как использовать: `profileKindsFor(resolvers)` на тех же резолверах, что
/// получает `ClientWorkspace`; порядок — stdio, затем WebSocket.
List<ProfileKind> profileKindsFor(Iterable<TransportResolver> resolvers) {
  final samples = {
    ProfileKind.stdio: const StdioProfile(
      id: 'sample',
      label: 'sample',
      command: 'sample',
    ),
    ProfileKind.webSocket: WebSocketProfile(
      id: 'sample',
      label: 'sample',
      uri: Uri.parse('ws://localhost'),
    ),
  };
  return [
    for (final MapEntry(:key, :value) in samples.entries)
      if (resolvers.any((resolver) => resolver.supports(value))) key,
  ];
}
