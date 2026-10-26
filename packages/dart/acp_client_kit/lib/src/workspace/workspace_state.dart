import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../connection/connection_profile.dart';
import '../connection/connection_view.dart';
import '../transcript/transcript_item.dart';

part 'workspace_state.freezed.dart';

/// Снимок рабочего пространства: соединение, профиль, проект и сессии.
///
/// Почему: UI и CLI читают одно неизменяемое значение вместо нескольких
/// потоков ядра клиента (`09-10`, «Публичный API `acp_client_kit`»).
///
/// Для чего: публикуется `ClientWorkspace.state` при каждом изменении
/// соединения, списка сессий, статуса сессии или активной сессии.
///
/// Как использовать: подписаться на `ClientWorkspace.state` или прочитать
/// `ClientWorkspace.current`; [sessions] — от новой к старой.
@freezed
abstract class WorkspaceState with _$WorkspaceState {
  const factory WorkspaceState({
    @Default(ConnectionView.disconnected()) ConnectionView connection,
    ConnectionProfile? profile,
    String? projectDirectory,
    @Default([]) List<SessionSummaryView> sessions,
    SessionId? activeSessionId,
  }) = _WorkspaceState;
}

/// Строка списка сессий: id, рабочая папка и статус.
@freezed
abstract class SessionSummaryView with _$SessionSummaryView {
  const factory SessionSummaryView({
    required SessionId id,
    required String cwd,
    required SessionStatusView status,
  }) = _SessionSummaryView;
}

/// Представление одной сессии для отображения.
///
/// Почему: UI сравнивает представления дёшево по [revision], а не обходом
/// полей (`09-10`, «Публичный API»).
///
/// Для чего: `SessionHandle.current` и поток `SessionHandle.view`. Поля
/// очереди и опций добавляют следующие итерации change вместе с переносом
/// своей логики (design D12).
@freezed
abstract class SessionView with _$SessionView {
  const factory SessionView({
    required int revision,
    required SessionStatusView status,

    /// Транскрипт сессии; строит `TranscriptProjector` (design D5).
    @Default([]) List<TranscriptItem> transcript,
  }) = _SessionView;
}

/// Статус сессии для UI и CLI.
///
/// Почему: `SessionLifecycleStatus` ядра различает ожидание одобрения и
/// ход, а для «занята ли сессия» это одно состояние (design D4).
///
/// Для чего: [running] — идёт ход, в том числе с ожидающими одобрениями;
/// [cancelling] — отмена отправлена, ход ждёт ответа агента; обе значат
/// «сессия занята».
enum SessionStatusView {
  idle,
  running,
  cancelling,
  failed;

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
