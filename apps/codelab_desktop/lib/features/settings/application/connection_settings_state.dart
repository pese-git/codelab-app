import 'package:codelab_client_core/codelab_client_core.dart'
    show
        Connected,
        Connecting,
        ConnectionFailed,
        ConnectionLost,
        ConnectionProfile,
        ConnectionView,
        EmbeddedProfile,
        ProfileProbeOutcome,
        Reconnecting,
        StdioProfile,
        WebSocketProfile,
        ownTokenSecretName;

import 'probe_outcome_view.dart';
import 'profile_view.dart';

/// Состояние подключения окна для бейджа строки текущего профиля.
///
/// Почему отдельный enum: бейдж показывает три исхода без текста ошибки — её
/// показывает баннер соединения рабочего места (design.md change
/// `add-app-settings-shell`, D4, находка ручного прогона итерации 2).
enum ConnectionRowStatus {
  connecting('Connecting…'),
  connected('Connected'),
  failed('Failed');

  const ConnectionRowStatus(this.label);

  /// Подпись бейджа.
  final String label;

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
/// действия по [canRemove], [hasFileActions] и [showNotTested].
final class ConnectionProfileRow {
  const ConnectionProfileRow._({
    required this.profile,
    required this.summary,
    required this.token,
    required this.isDefault,
    required this.isCurrent,
    required this.isUnsaved,
    required this.status,
    this.isSelected = false,
    this.probe,
    this.isProbing = false,
  });

  /// Встроенный агент: не из файла, всегда первый.
  factory ConnectionProfileRow.embedded({
    required ConnectionProfile profile,
    required bool isDefault,
    required bool isCurrent,
    required ConnectionRowStatus? status,
    bool isSelected = false,
  }) => ConnectionProfileRow._(
    profile: profile,
    summary: profileSummary(profile),
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
    required ProfileTokenView? token,
    required bool isDefault,
    required bool isCurrent,
    required ConnectionRowStatus? status,
    bool isSelected = false,
    ProfileProbeOutcome? probe,
    bool isProbing = false,
  }) => ConnectionProfileRow._(
    profile: profile,
    summary: profileSummary(profile),
    token: token,
    isDefault: isDefault,
    isCurrent: isCurrent,
    isSelected: isSelected,
    isUnsaved: false,
    status: status,
    probe: probe,
    isProbing: isProbing,
  );

  /// Профиль текущего окна, которого нет в файле: «Current connection (not
  /// saved)» (D4). Он текущий по определению.
  factory ConnectionProfileRow.unsaved({
    required ConnectionProfile profile,
    required ProfileTokenView? token,
    required ConnectionRowStatus? status,
    bool isSelected = false,
  }) => ConnectionProfileRow._(
    profile: profile,
    summary: profileSummary(profile),
    token: token,
    isDefault: false,
    isCurrent: true,
    isSelected: isSelected,
    isUnsaved: true,
    status: status,
  );

  final ConnectionProfile profile;

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

  /// Последний исход «Test connection» за жизнь страницы (D14); `null` — в
  /// этом запуске строку не проверяли. В `profiles.json` исход не пишется.
  final ProfileProbeOutcome? probe;

  /// «Test connection» этой строки идёт сейчас.
  final bool isProbing;

  /// Текст [probe] для бейджа `connection-profile-probe-<id>` (D12): тот же,
  /// что в диалоге; из профиля берутся только команда и источник токена.
  String? get probeText {
    final outcome = probe;
    if (outcome == null) {
      return null;
    }
    return probeOutcomeText(
      outcome,
      command: switch (profile) {
        StdioProfile(:final command) => command,
        _ => null,
      },
      token: token ?? const NoTokenView(),
    );
  }

  /// Строку проверяли на этой странице (любым исходом).
  bool get isTested => probe != null;

  String get id => profile.id;
  String get label => profile.label;
  bool get isBuiltIn => profile is EmbeddedProfile;

  /// Заголовок строки: `label`, а при пустом `label` и при `label` из
  /// значения `--agent` (`stdio:…`, `ws://…`, `wss://…`; так CLI заполняет
  /// `label` встроенного в строку профиля) — `id`. Иначе вся команда
  /// повторялась бы в заголовке (D4).
  String get title => profileTitle(profile);

  /// У строки из файла есть «Test connection», «Rename» и «Remove».
  bool get hasFileActions => !isBuiltIn && !isUnsaved;

  /// Метка «Not tested» (D14): пока строку не проверяли.
  bool get showNotTested => hasFileActions && !isTested && !isProbing;

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
    this.lastProbes = const {},
    this.failure,
  });

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

  /// Исходы «Test connection» по id профиля за жизнь страницы (D4, D14).
  /// Это UI-состояние: в `profiles.json` оно не пишется.
  final Map<String, ProfileProbeOutcome> lastProbes;

  /// Текст последнего сбоя действия страницы; `null` — сбоя нет.
  final String? failure;

  String? get currentProfileId => currentProfile?.id;

  /// «Restart agent» доступна при корне процесса (D18) и во время старта
  /// (вытесняет попытку, Q25).
  bool get canRestart => restartTarget != null && restartAvailable;

  /// Подсказка недоступной «Restart agent» (D18).
  String? get restartHint =>
      restartAvailable ? null : 'Starts when you open a project.';

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

  String get restartTitle => restartsRemote ? 'Reconnect' : 'Restart agent';

  String get restartButtonLabel => restartsRemote ? 'Reconnect' : 'Restart';

  /// Описание строки «Restart agent»: называет цель и не обещает
  /// `session/cancel` (D9).
  String get restartDescription {
    final target = restartTarget;
    final subject = target == null
        ? 'the profile of this window'
        : profileTitle(target);
    final running = currentProfile;
    if (target != null && running != null && running.id != target.id) {
      return 'Restart $subject to use it.';
    }
    return 'Reconnects $subject and reloads open sessions. A running turn is '
        'interrupted; queued prompts stay.';
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
    required this.defaultProfileId,
    required this.ignoredDefaultEntry,
    super.lastProbes,
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
    required this.path,
    required this.reason,
    super.lastProbes,
    super.failure,
  });

  /// Путь к файлу для сообщения на экране; `null` — пути нет, потому что
  /// `CODELAB_HOME` недопустим. В журнал не пишется.
  final String? path;

  /// Причина без текста исключения: оно может нести содержимое файла.
  final String reason;
}
