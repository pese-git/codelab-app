import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../connection/connection_profile.dart';
import '../connection/connection_view.dart';
import '../queue/prompt_queue.dart';
import '../session/session_views.dart';
import '../transcript/transcript_item.dart';

part 'workspace_state.freezed.dart';

/// Снимок рабочего пространства: соединение, профиль, проект и сессии.
///
/// Почему: UI и CLI читают одно неизменяемое значение вместо нескольких
/// потоков ядра клиента (`09-10`, «Публичный API `codelab_client_core`»).
///
/// Для чего: публикуется `ClientWorkspace.state` при каждом изменении
/// соединения, списка сессий, статуса сессии или активной сессии.
///
/// Как использовать: подписаться на `ClientWorkspace.state` или прочитать
/// `ClientWorkspace.current`. [sessions] — список сайдбара проекта: сначала
/// сессии, открытые в этом запуске, от новой к старой, затем ещё не
/// открытые сессии агента из `session/list` в его порядке ([SessionStatusView.notLoaded]);
/// [hasMoreSessions] — у агента есть следующая страница
/// (`ClientWorkspace.loadMoreSessions`, design D3 change
/// `add-session-list-and-reload`).
@freezed
abstract class WorkspaceState with _$WorkspaceState {
  const factory WorkspaceState({
    @Default(ConnectionView.disconnected()) ConnectionView connection,
    ConnectionProfile? profile,
    String? projectDirectory,
    @Default([]) List<SessionSummaryView> sessions,
    SessionId? activeSessionId,
    @Default(false) bool hasMoreSessions,
  }) = _WorkspaceState;
}

/// Строка списка сессий: id, рабочая папка, статус, заголовок и время
/// последнего изменения.
///
/// [title] — заголовок сессии в ядре клиента (`session_info_update`), а у
/// неоткрытой — из `session/list`; [updatedAt] — из `session/list`, если
/// агент его прислал.
@freezed
abstract class SessionSummaryView with _$SessionSummaryView {
  const factory SessionSummaryView({
    required SessionId id,
    required String cwd,
    required SessionStatusView status,
    String? title,
    DateTime? updatedAt,
  }) = _SessionSummaryView;
}

/// Представление одной сессии для отображения.
///
/// Почему: UI сравнивает представления дёшево по [revision], а не обходом
/// полей (`09-10`, «Публичный API»).
///
/// Для чего: `SessionHandle.current` и поток `SessionHandle.view`.
@freezed
abstract class SessionView with _$SessionView {
  const factory SessionView({
    required int revision,
    required SessionStatusView status,

    /// Транскрипт сессии; строит `TranscriptProjector` (design D5).
    @Default([]) List<TranscriptItem> transcript,

    /// Отложенные промпты сессии по порядку отправки (design D7).
    @Default([]) List<QueuedPrompt> queue,

    /// Опции конфигурации сессии; `configOptionInFlight` — `configId`
    /// запроса `session/set_config_option` в полёте (design D4).
    @Default([]) List<ConfigOptionView> configOptions,
    String? configOptionInFlight,

    /// Команды агента из последнего `available_commands_update`.
    @Default([]) List<AgentCommandView> agentCommands,

    /// Запросы `session/request_permission`, ждущие ответа пользователя.
    @Default([]) List<PendingApprovalView> pendingApprovals,
  }) = _SessionView;
}

/// Статус сессии для UI и CLI.
///
/// Почему: `SessionLifecycleStatus` ядра различает ожидание одобрения и
/// ход, а для «занята ли сессия» это одно состояние (design D4).
///
/// Для чего: [running] — идёт ход, в том числе с ожидающими одобрениями;
/// [cancelling] — отмена отправлена, ход ждёт ответа агента; обе значат
/// «сессия занята»; [notLoaded] — сессия есть у агента (`session/list`), но
/// в этом запуске не открыта: у неё нет `SessionHandle`, открывает её
/// `ClientWorkspace.loadSession` (design D3 change
/// `add-session-list-and-reload`).
enum SessionStatusView {
  idle,
  running,
  cancelling,
  failed,
  notLoaded;

  /// Статус представления для статуса жизненного цикла ядра клиента.
  static SessionStatusView of(SessionLifecycleStatus status) =>
      switch (status) {
        SessionLifecycleStatus.idle ||
        SessionLifecycleStatus.active => SessionStatusView.idle,
        SessionLifecycleStatus.runningTurn ||
        SessionLifecycleStatus.awaitingApproval => SessionStatusView.running,
        SessionLifecycleStatus.cancellingTurn => SessionStatusView.cancelling,
        SessionLifecycleStatus.failed => SessionStatusView.failed,
      };
}
