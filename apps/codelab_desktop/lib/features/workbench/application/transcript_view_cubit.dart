import 'agents_pane_data.dart' show AgentsShowTarget;
import 'shell_part.dart';

/// Разовый запрос показа строки ленты (панель Agents, D49 Т7): прокрутить
/// ленту сессии [sessionId] к строке [rowId] и цели [targetId] внутри неё.
///
/// [serial] растёт с каждым запросом: повтор того же действия получает новый
/// номер, и лента прокручивает снова.
final class TranscriptShowRequest {
  const TranscriptShowRequest({
    required this.sessionId,
    required this.rowId,
    required this.targetId,
    required this.serial,
    this.focusApproval = false,
  });

  final String sessionId;
  final String rowId;
  final String targetId;
  final int serial;

  /// После показа поставить фокус на полосу решения цели (change
  /// `fix-approval-focus`, D4). ЗАГЛУШКА задачи 2.3: поле есть, но
  /// `requestShow` его не заполняет — поведение добавляет задача 2.4.
  final bool focusApproval;
}

/// Ручное раскрытие строк ленты, показанные изображения, выбранная строка
/// панели Agents и запрос показа по сессиям.
final class TranscriptViewState {
  const TranscriptViewState({
    this.expansionBySession = const {},
    this.selectedAgentBySession = const {},
    this.showRequest,
    this.showSerial = 0,
  });

  /// id сессии → (id строки → раскрыта ли строка по выбору пользователя).
  final Map<String, Map<String, bool>> expansionBySession;

  /// id сессии → `toolCallId` выбранной строки панели Agents (D33, D49 Т8).
  final Map<String, String> selectedAgentBySession;

  /// Последний запрос показа; `null` — запросов не было.
  final TranscriptShowRequest? showRequest;

  /// Номер последнего выданного запроса. Не обнуляется вместе с [showRequest]:
  /// лента исполняет только запрос с номером больше прежнего, и номер,
  /// начатый заново, был бы проигнорирован.
  final int showSerial;

  /// Выбранная строка панели Agents сессии [sessionId]; `null` — не выбрана.
  String? selectedAgentFor(String? sessionId) =>
      sessionId == null ? null : selectedAgentBySession[sessionId];

  /// Запрос показа для сессии [sessionId]: чужой сессии он не принадлежит.
  TranscriptShowRequest? showRequestFor(String? sessionId) =>
      showRequest != null && showRequest!.sessionId == sessionId
      ? showRequest
      : null;

  TranscriptViewState _copyWith({
    Map<String, Map<String, bool>>? expansionBySession,
    Map<String, String>? selectedAgentBySession,
    Object? showRequest = _keep,
    int? showSerial,
  }) => TranscriptViewState(
    expansionBySession: expansionBySession ?? this.expansionBySession,
    selectedAgentBySession:
        selectedAgentBySession ?? this.selectedAgentBySession,
    showRequest: identical(showRequest, _keep)
        ? this.showRequest
        : showRequest as TranscriptShowRequest?,
    showSerial: showSerial ?? this.showSerial,
  );

  /// Маркер «поле не менять»: `null` в [_copyWith] означает «обнулить».
  static const _keep = Object();

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
/// Панель Agents (change `add-subagents-and-tasks`, D33, D49 Т7, Т8): здесь же
/// выбранная строка по сессиям и разовый запрос показа. Раскрытие пути и
/// прокрутка ленты — одно действие над лентой, поэтому [requestShow] меняет
/// раскрытие и запрос одним `emit`, а отдельной части не нужно. Выбор не
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
      state._copyWith(
        expansionBySession: {
          ...state.expansionBySession,
          sessionId: Map.unmodifiable(session),
        },
      ),
    );
  }

  /// Выбирает строку [agentId] панели Agents сессии [sessionId].
  void selectAgent({required String sessionId, required String agentId}) {
    if (state.selectedAgentFor(sessionId) == agentId) {
      return;
    }
    emit(
      state._copyWith(
        selectedAgentBySession: {
          ...state.selectedAgentBySession,
          sessionId: agentId,
        },
      ),
    );
  }

  /// «Show in transcript» и «Go to approval»: раскрывает строки пути
  /// ([AgentsShowTarget.expand]) и запрашивает показ одним `emit`.
  ///
  /// Раскрытие — явное действие пользователя, поэтому оно остаётся выбором
  /// пользователя в ленте, как ручной клик (D33).
  void requestShow({
    required String sessionId,
    required AgentsShowTarget target,
    // ЗАГЛУШКА задачи 2.3 (`fix-approval-focus`, D4): параметр принят, но
    // в запрос пока не попадает; поведение добавляет задача 2.4.
    bool focusApproval = false,
  }) {
    final session = {
      ...state.overridesFor(sessionId),
      for (final id in target.expand) id: true,
    };
    emit(
      state._copyWith(
        expansionBySession: {
          ...state.expansionBySession,
          sessionId: Map.unmodifiable(session),
        },
        showRequest: TranscriptShowRequest(
          sessionId: sessionId,
          rowId: target.rowId,
          targetId: target.targetId,
          serial: state.showSerial + 1,
        ),
        showSerial: state.showSerial + 1,
      ),
    );
  }

  /// Гасит запрос показа, если фокус ушёл из его сессии ([focusedSessionId] —
  /// сессия в фокусе сейчас).
  ///
  /// Почему: запрос разовый (D49 Т7). Лента помнит исполненный номер только
  /// пока жива; пришедший заново старый запрос при возврате в сессию или при
  /// перемонтировании ленты повторил бы прокрутку и выключил следование за
  /// хвостом. Фасад вызывает метод при смене сессии в фокусе. Раскрытие и
  /// выбор строки остаются: это выбор пользователя, а не событие.
  void dropShowRequestOutside(String? focusedSessionId) {
    final request = state.showRequest;
    if (request == null || request.sessionId == focusedSessionId) {
      return;
    }
    emit(state._copyWith(showRequest: null));
  }

  /// Лента закончила показ запроса [serial] (`onShowRequestDone`): запрос
  /// гасится, чтобы перемонтированная лента (новый `State`, `initState`) не
  /// исполнила его снова. Номер другого, более нового запроса не гасится;
  /// [TranscriptViewState.showSerial] не откатывается.
  void finishShowRequest(int serial) {
    if (state.showRequest?.serial != serial) {
      return;
    }
    emit(state._copyWith(showRequest: null));
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
