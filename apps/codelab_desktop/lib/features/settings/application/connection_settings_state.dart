import 'package:codelab_client_core/codelab_client_core.dart'
    show
        Connected,
        Connecting,
        ConnectionFailed,
        ConnectionLost,
        ConnectionProfile,
        ConnectionView,
        EmbeddedProfile,
        Reconnecting,
        WebSocketProfile,
        ownTokenSecretName;

import '../../../l10n/app_localizations.dart';
import 'profile_view.dart';

/// Состояние подключения окна для бейджа строки текущего профиля.
///
/// Почему отдельный enum: бейдж показывает три исхода без текста ошибки — её
/// показывает баннер соединения рабочего места (design.md change
/// `add-app-settings-shell`, D4, находка ручного прогона итерации 2).
///
/// Подпись бейджа строит presentation по значению (`add-desktop-localization`,
/// D5, правило 8): enum не хранит английский заголовок.
enum ConnectionRowStatus {
  connecting,
  connected,
  failed;

  /// Статус по состоянию соединения workspace; `null` — бейджа нет.
  static ConnectionRowStatus? of(ConnectionView connection) =>
      switch (connection) {
        Connecting() || Reconnecting() => connecting,
        Connected() => connected,
        ConnectionFailed() || ConnectionLost() => failed,
        _ => null,
      };
}

/// Строка страницы «Connection»: профиль и его роли.
///
/// Почему отдельная модель, а не `ConnectionProfile`: страница показывает не
/// всё, что есть в профиле (нет аргументов, `env` и пути URL), и не даёт
/// виджету решать, какие действия доступны (AGENTS.md §10: политика не в
/// presentation; §15: логики нет в `build()`).
///
/// Для чего: единственное, что читает виджет строки. [isDefault] и
/// [isCurrent] — две разные роли (D5): профиль по умолчанию и профиль, к
/// которому окно подключено сейчас (живое соединение). Невозможные сочетания закрыты фабриками: строка «not
/// saved» всегда текущая.
///
/// Как использовать: создаёт только `ConnectionSettingsCubit` через
/// [ConnectionProfileRow.embedded], [ConnectionProfileRow.stored] и
/// [ConnectionProfileRow.unsaved]; виджет показывает поля и включает
/// действия по [canRemove] и [hasFileActions].
final class ConnectionProfileRow {
  const ConnectionProfileRow._({
    required this.profile,
    required this.title,
    required this.summary,
    required this.token,
    required this.isDefault,
    required this.isCurrent,
    required this.isUnsaved,
    required this.status,
    this.isSelected = false,
  });

  /// Встроенный агент: не из файла, всегда первый.
  factory ConnectionProfileRow.embedded({
    required ConnectionProfile profile,
    required AppLocalizations l10n,
    required bool isDefault,
    required bool isCurrent,
    required ConnectionRowStatus? status,
    bool isSelected = false,
  }) => ConnectionProfileRow._(
    profile: profile,
    title: localizedProfileTitle(profile, l10n),
    summary: profileSummary(profile, l10n),
    token: null,
    isDefault: isDefault,
    isCurrent: isCurrent,
    isSelected: isSelected,
    isUnsaved: false,
    status: status,
  );

  /// Профиль из `profiles.json`.
  factory ConnectionProfileRow.stored({
    required ConnectionProfile profile,
    required AppLocalizations l10n,
    required ProfileTokenView? token,
    required bool isDefault,
    required bool isCurrent,
    required ConnectionRowStatus? status,
    bool isSelected = false,
  }) => ConnectionProfileRow._(
    profile: profile,
    title: localizedProfileTitle(profile, l10n),
    summary: profileSummary(profile, l10n),
    token: token,
    isDefault: isDefault,
    isCurrent: isCurrent,
    isSelected: isSelected,
    isUnsaved: false,
    status: status,
  );

  /// Профиль текущего окна, которого нет в файле: «Current connection (not
  /// saved)» (D4). Он текущий по определению.
  factory ConnectionProfileRow.unsaved({
    required ConnectionProfile profile,
    required AppLocalizations l10n,
    required ProfileTokenView? token,
    required ConnectionRowStatus? status,
    bool isSelected = false,
  }) => ConnectionProfileRow._(
    profile: profile,
    title: localizedProfileTitle(profile, l10n),
    summary: profileSummary(profile, l10n),
    token: token,
    isDefault: false,
    isCurrent: true,
    isSelected: isSelected,
    isUnsaved: true,
    status: status,
  );

  final ConnectionProfile profile;

  /// Заголовок строки на языке интерфейса (`localizedProfileTitle`): строка —
  /// функция «(профиль, язык)», её пересобирает Cubit при смене языка (D5).
  final String title;

  /// Команда или `scheme://host:port` (`profileSummary`).
  final String summary;

  /// Источник токена; только у WebSocket-профилей.
  final ProfileTokenView? token;

  final bool isDefault;

  /// Профиль работающего агента («Current», D18).
  final bool isCurrent;

  /// Профиль, выбранный для следующего старта («Selected», «Use», D18).
  final bool isSelected;

  /// Имя собственного секрета профиля `codelab/profiles/<id>/token`, если
  /// профиль ссылается именно на него; иначе `null` (design.md change
  /// `add-provider-setup-ui`, D14). Страница по нему решает, предлагать ли
  /// флажок «Also delete the stored token»: чужой секрет («Use stored
  /// secret») удалять нельзя никогда.
  String? get ownTokenSecret {
    final profile = this.profile;
    if (profile is! WebSocketProfile) {
      return null;
    }
    final own = ownTokenSecretName(profile.id);
    return profile.tokenRef == 'secret:$own' ? own : null;
  }

  /// Профиль окна, которого нет в `profiles.json`.
  final bool isUnsaved;

  /// Состояние последней попытки подключения; только у строки профиля этой
  /// попытки (`WorkspaceState.profile`). У строки «Current» это `Connected`,
  /// у неудачной попытки — `Failed`, пока идёт попытка — `Connecting…`.
  final ConnectionRowStatus? status;

  String get id => profile.id;
  String get label => profile.label;
  bool get isBuiltIn => profile is EmbeddedProfile;

  /// У строки из файла есть «Rename» и «Remove».
  bool get hasFileActions => !isBuiltIn && !isUnsaved;

  /// «Remove» возможна для сохранённого профиля, не являющегося текущим и
  /// выбранным: встроенный агент не из файла, а текущий и выбранный связаны с
  /// окном (подсказка `Use another profile first.`, D18).
  bool get canRemove => hasFileActions && !isCurrent && !isSelected;

  /// «Use» не показывается у выбранного профиля (D18): метка «Selected»
  /// говорит, что он уже выбран. «Current» — профиль работающего агента, он
  /// может быть и не выбранным.
  bool get canUse => !isSelected;
}

/// Состояние страницы «Connection» — явный автомат (`state-management.md`,
/// design.md change `add-app-settings-shell`, D4).
///
/// Три вида данных разведены: сохранённые настройки (файл и
/// `shared_preferences`), действующее подключение (`WorkspaceState`) и
/// черновик формы (появится с диалогом «Add connection profile»).
sealed class ConnectionSettingsState {
  const ConnectionSettingsState();
}

/// Файл ещё читается.
final class ConnectionSettingsLoading extends ConnectionSettingsState {
  const ConnectionSettingsLoading();
}

/// Разовое сообщение о сбое действия страницы «Connection».
///
/// Почему закрытая иерархия, а не строка: сообщение — исход события, которое
/// не повторится, поэтому строку из входов не пересобрать. Состояние хранит
/// тип с аргументами, а текст собирает presentation по `context.l10n` и тем
/// самым пересобирает его при смене языка (`add-desktop-localization`, D5,
/// вид «разовое сообщение»). Значений токена и текста исключений здесь нет.
sealed class ConnectionSettingsFailure {
  const ConnectionSettingsFailure();
}

/// Запись изменения не удалась (переименование, удаление, выбор профиля).
final class ProfileSaveFailure extends ConnectionSettingsFailure {
  const ProfileSaveFailure();

  @override
  bool operator ==(Object other) => other is ProfileSaveFailure;

  @override
  int get hashCode => (ProfileSaveFailure).hashCode;
}

/// Профиль удалён, но собственный секрет токена [secretName] остался: страница
/// называет команду `codelab secret delete` (D13, D18).
final class TokenNotDeleted extends ConnectionSettingsFailure {
  const TokenNotDeleted(this.secretName);

  final String secretName;

  @override
  bool operator ==(Object other) =>
      other is TokenNotDeleted && other.secretName == secretName;

  @override
  int get hashCode => Object.hash(TokenNotDeleted, secretName);
}

/// Почему `profiles.json` не прочитан ([ConnectionSettingsUnreadable.reason]).
///
/// Почему тип, а не строка: причина без текста исключения (оно может нести
/// содержимое файла). Фразу вокруг причины и сами причины приложения
/// переводит presentation; причина composition root (`unavailable`) — текст
/// без типа и показывается как есть (`add-desktop-localization`, D6, D7).
sealed class ProfilesUnreadableReason {
  const ProfilesUnreadableReason();
}

/// Неподдерживаемая версия или неверная структура файла.
final class ProfilesUnsupportedFile extends ProfilesUnreadableReason {
  const ProfilesUnsupportedFile();
}

/// Профили недоступны: причина названа composition root (недопустимый
/// `CODELAB_HOME`); показывается как есть.
final class ProfilesNotAvailable extends ProfilesUnreadableReason {
  const ProfilesNotAvailable(this.message);

  final String message;
}

/// Файл не читается по другой причине; [errorType] — только имя типа
/// исключения.
final class ProfilesCannotRead extends ProfilesUnreadableReason {
  const ProfilesCannotRead(this.errorType);

  final String errorType;
}

/// Общие поля состояний, в которых страница уже показывает строки и блок
/// «Behavior». «Behavior» не зависит от `profiles.json`, поэтому есть и у
/// [ConnectionSettingsUnreadable] (D4).
sealed class ConnectionSettingsLoaded extends ConnectionSettingsState {
  const ConnectionSettingsLoaded({
    required this.rows,
    required this.restartTarget,
    required this.currentProfile,
    required this.connection,
    required this.restartAvailable,
    required this.l10n,
    this.failure,
  });

  /// Каталог языка, на котором собран производный текст состояния (строки,
  /// «Restart agent»). Состояние — функция «(входы, язык)»: при смене языка
  /// Cubit публикует новое с новым каталогом (`add-desktop-localization`, D5).
  final AppLocalizations l10n;

  /// Встроенный агент первым, затем профили файла в его порядке, затем при
  /// необходимости строка «not saved».
  final List<ConnectionProfileRow> rows;

  /// Цель «Restart agent» (`ConnectionCommands.restartTarget`): профиль
  /// последнего принятого подключения, а до первого принятого — последний
  /// выбранный; `null` — окно ещё ни к чему не подключалось. Это не
  /// `WorkspaceState.profile`: workspace публикует профиль уже в начале
  /// попытки, и после неудачи он указывал бы на профиль, который не
  /// подключился.
  final ConnectionProfile? restartTarget;

  /// Профиль с живым соединением («Current»): цель перезапуска, к которой
  /// workspace сейчас подключён или переподключается; иначе `null` — метки
  /// нет ни у кого (решение пользователя 2026-11-05).
  final ConnectionProfile? currentProfile;
  final ConnectionView connection;

  /// Есть корень процесса для перезапуска: проект, сессия в фокусе или прежний
  /// корень (D18). Без него «Restart agent» недоступна: `Starts when you open
  /// a project.`
  final bool restartAvailable;

  /// Последний сбой действия страницы; `null` — сбоя нет. Типизированное
  /// разовое сообщение: текст строит presentation (D5).
  final ConnectionSettingsFailure? failure;

  String? get currentProfileId => currentProfile?.id;

  /// «Restart agent» доступна при корне процесса (D18) и во время старта
  /// (вытесняет попытку, Q25).
  bool get canRestart => restartTarget != null && restartAvailable;

  /// Подсказка недоступной «Restart agent» (D18).
  String? get restartHint =>
      restartAvailable ? null : l10n.connectionRestartHint;

  /// Живое соединение — с удалённым агентом (WebSocket).
  bool get isRemote => currentProfile is WebSocketProfile;

  /// `scheme://host:port` удалённого агента; `null`, если текущий профиль не
  /// WebSocket.
  String? get remoteOrigin => switch (currentProfile) {
    WebSocketProfile(:final uri) => profileOrigin(uri),
    _ => null,
  };

  /// InfoBar «Read-only»: пока окно подключено к удалённому агенту (D10).
  bool get showsReadOnlyNotice => isRemote && connection is Connected;

  /// Заголовок строки «Restart agent»: для WebSocket процесс чужой, поэтому
  /// «Reconnect» (D9).
  /// Подпись зависит от цели перезапуска, а не от живого соединения.
  bool get restartsRemote => restartTarget is WebSocketProfile;

  String get restartTitle =>
      restartsRemote ? l10n.connectionReconnect : l10n.commonRestartAgent;

  String get restartButtonLabel =>
      restartsRemote ? l10n.connectionReconnect : l10n.connectionRestartButton;

  /// Описание строки «Restart agent»: называет цель и не обещает
  /// `session/cancel` (D9).
  String get restartDescription {
    final target = restartTarget;
    final subject = target == null
        ? l10n.connectionRestartSubjectWindow
        : localizedProfileTitle(target, l10n);
    final running = currentProfile;
    if (target != null && running != null && running.id != target.id) {
      return l10n.connectionRestartToUse(subject);
    }
    return l10n.connectionRestartDescription(subject);
  }
}

/// Файл прочитан.
final class ConnectionSettingsReady extends ConnectionSettingsLoaded {
  const ConnectionSettingsReady({
    required super.rows,
    required super.restartTarget,
    required super.currentProfile,
    required super.connection,
    required super.restartAvailable,
    required super.l10n,
    required this.defaultProfileId,
    required this.ignoredDefaultEntry,
    super.failure,
  });

  /// Id профиля по умолчанию; `embedded` — встроенный агент.
  final String defaultProfileId;

  /// В файле осталась запись `default` от прежней версии: она игнорируется, а
  /// страница предлагает её удалить (D5, D21).
  final bool ignoredDefaultEntry;
}

/// Профили недоступны: `profiles.json` не разбирается, имеет неизвестную
/// версию или `CODELAB_HOME` недопустим (D4, D7).
///
/// Файл пользователя не перезаписывается (AGENTS.md §2, п. 3): страница
/// показывает [rows] из одного встроенного агента и ошибку, а «Add profile»,
/// «Rename» и «Remove» недоступны. «Behavior» работает.
final class ConnectionSettingsUnreadable extends ConnectionSettingsLoaded {
  const ConnectionSettingsUnreadable({
    required super.rows,
    required super.restartTarget,
    required super.currentProfile,
    required super.connection,
    required super.restartAvailable,
    required super.l10n,
    required this.path,
    required this.reason,
    super.failure,
  });

  /// Путь к файлу для сообщения на экране; `null` — пути нет, потому что
  /// `CODELAB_HOME` недопустим. В журнал не пишется.
  final String? path;

  /// Причина без текста исключения: оно может нести содержимое файла. Текст
  /// фразы собирает presentation (`ProfilesUnreadableReason`).
  final ProfilesUnreadableReason reason;
}
