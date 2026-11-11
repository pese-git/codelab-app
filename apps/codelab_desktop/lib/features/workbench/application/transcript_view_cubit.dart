import 'shell_part.dart';

/// Ручное раскрытие строк ленты и показанные изображения по сессиям.
final class TranscriptViewState {
  const TranscriptViewState({this.expansionBySession = const {}});

  /// id сессии → (id строки → раскрыта ли строка по выбору пользователя).
  final Map<String, Map<String, bool>> expansionBySession;

  /// Маркер ключа показанного изображения в таблице выбора.
  static const _imageMarker = '#image:';

  /// Ключ показанного изображения: строка и адрес вместе (D6) — тот же адрес в
  /// другом ответе снова требует клика.
  static String imageKey(String rowId, String url) => '$rowId$_imageMarker$url';

  /// Ключи изображений, которые пользователь показал в сессии [sessionId].
  Set<String> shownImagesFor(String? sessionId) => {
    for (final entry in overridesFor(sessionId).entries)
      if (entry.value && entry.key.contains(_imageMarker)) entry.key,
  };

  /// Показано ли изображение [url] в строке [rowId] сессии [sessionId].
  bool isImageShown(String? sessionId, String rowId, String url) =>
      overridesFor(sessionId)[imageKey(rowId, url)] ?? false;

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
/// Показанное изображение (D6, DSK-20) хранится в той же таблице выбора под
/// ключом `<rowId>#image:<url>` со значением `true`: один источник истины, не
/// сохраняется между запусками.
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

  /// Пользователь нажал «Show image» для [url] в строке [rowId] (D6).
  void setImageShown({
    required String sessionId,
    required String rowId,
    required String url,
  }) => setExpanded(
    sessionId: sessionId,
    rowId: TranscriptViewState.imageKey(rowId, url),
    expanded: true,
  );
}
