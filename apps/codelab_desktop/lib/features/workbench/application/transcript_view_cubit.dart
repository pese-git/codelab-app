import 'shell_part.dart';

/// Ручное раскрытие строк ленты по сессиям.
final class TranscriptViewState {
  const TranscriptViewState({this.expansionBySession = const {}});

  /// id сессии → (id строки → раскрыта ли строка по выбору пользователя).
  final Map<String, Map<String, bool>> expansionBySession;

  /// Выбор пользователя в ленте сессии [sessionId]; пусто — строк не трогали.
  Map<String, bool> overridesFor(String? sessionId) =>
      sessionId == null ? const {} : expansionBySession[sessionId] ?? const {};
}

/// UI-состояние ленты: какие блоки мыслей и строки вызовов пользователь
/// раскрыл или свернул вручную.
///
/// Почему: строки ленты виртуализированы и уничтожаются при уходе с экрана,
/// поэтому выбор пользователя в `State` виджета терялся бы (§12.3.2;
/// design D3 change `redesign-transcript-rows`). Это не состояние сессии:
/// оно не попадает в kit и не сохраняется между запусками.
///
/// Для чего: хранит выбор по сессиям — переключение сессии не смешивает их
/// ленты. Раскрытие по умолчанию вычисляет сама лента.
///
/// Как использовать: создаётся вместе с остальными частями
/// (`CodeLabShellParts`); фасад вызывает [setExpanded] из
/// `CodeLabTranscriptPanel.onExpansionChanged` и отдаёт ленте
/// [TranscriptViewState.overridesFor] активной сессии.
final class TranscriptViewCubit extends ShellPartCubit<TranscriptViewState> {
  TranscriptViewCubit({required super.changes})
    : super(const TranscriptViewState());

  void setExpanded({
    required String sessionId,
    required String rowId,
    required bool expanded,
  }) {
    final session = {...state.overridesFor(sessionId), rowId: expanded};
    emit(
      TranscriptViewState(
        expansionBySession: {
          ...state.expansionBySession,
          sessionId: Map.unmodifiable(session),
        },
      ),
    );
  }
}
