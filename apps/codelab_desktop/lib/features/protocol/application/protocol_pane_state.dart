import 'package:codelab_client_acp/codelab_client_acp.dart';

import 'log_record_filter.dart';
import 'protocol_frame_filter.dart';

/// Активный вид панели Protocol.
enum ProtocolView { frames, log }

/// Состояние панели Protocol (design.md change `redesign-protocol-pane`, D7).
///
/// Почему не в виджете: действия шапки дока и тело панели — разные поддеревья,
/// а `Pause`, `Clear`, `Export…` и переход Log → Frames меняют общее
/// состояние; фильтры и выбор переживают закрытие вкладки.
///
/// Для чего: неизменяемый снимок, который `ProtocolPaneCubit` публикует не
/// чаще раза в 100 мс. [visibleFrames] и [visibleRecords] — область, фильтры
/// и пауза уже применены; [framesCount] и [logCount] считают область без
/// фильтров и без паузы. Выбор хранится копией объекта: вытесненный из
/// буфера кадр остаётся в панели выбранного.
///
/// Как использовать: читать поля; менять только через методы Cubit.
final class ProtocolPaneState {
  const ProtocolPaneState({
    this.view = ProtocolView.frames,
    this.focusedSessionId,
    this.frameFilter = const ProtocolFrameFilter(),
    this.logFilter = const LogRecordFilter(),
    this.framesPaused = false,
    this.logPaused = false,
    this.visibleFrames = const [],
    this.visibleRecords = const [],
    this.framesCount = 0,
    this.logCount = 0,
    this.logCategories = const [],
    this.selectedRecordHasFrame = false,
    this.selectedFrame,
    this.selectedRecord,
    this.framesSplit,
    this.logSplit,
    this.traceAvailable = false,
    this.traceEnabled = false,
    this.saveFailed = false,
  });

  final ProtocolView view;

  /// Сессия в фокусе рабочего места (`WorkspaceState.activeSessionId`).
  final String? focusedSessionId;
  final ProtocolFrameFilter frameFilter;
  final LogRecordFilter logFilter;
  final bool framesPaused;
  final bool logPaused;
  final List<ProtocolFrame> visibleFrames;
  final List<Map<String, Object?>> visibleRecords;
  final int framesCount;
  final int logCount;

  /// Категории записей области без фильтров, по алфавиту: из них строится
  /// выпадающий выбор вида Log (выбор категории список не сужает).
  final List<String> logCategories;

  /// Для выбранной записи есть кадр в области: ссылка `Show frame in Frames`
  /// доступна. Считает Cubit, а не `build()` виджета.
  final bool selectedRecordHasFrame;
  final ProtocolFrame? selectedFrame;
  final Map<String, Object?>? selectedRecord;

  /// Доля таблицы вида; `null` — доля по умолчанию организма.
  final double? framesSplit;
  final double? logSplit;
  final bool traceAvailable;
  final bool traceEnabled;

  /// Последнее сохранение экспорта не удалось; сбрасывается следующим
  /// действием.
  final bool saveFailed;

  ProtocolPaneState copyWith({
    ProtocolView? view,
    Object? focusedSessionId = _keep,
    ProtocolFrameFilter? frameFilter,
    LogRecordFilter? logFilter,
    bool? framesPaused,
    bool? logPaused,
    List<ProtocolFrame>? visibleFrames,
    List<Map<String, Object?>>? visibleRecords,
    int? framesCount,
    int? logCount,
    List<String>? logCategories,
    bool? selectedRecordHasFrame,
    Object? selectedFrame = _keep,
    Object? selectedRecord = _keep,
    Object? framesSplit = _keep,
    Object? logSplit = _keep,
    bool? traceAvailable,
    bool? traceEnabled,
    bool? saveFailed,
  }) => ProtocolPaneState(
    view: view ?? this.view,
    focusedSessionId: identical(focusedSessionId, _keep)
        ? this.focusedSessionId
        : focusedSessionId as String?,
    frameFilter: frameFilter ?? this.frameFilter,
    logFilter: logFilter ?? this.logFilter,
    framesPaused: framesPaused ?? this.framesPaused,
    logPaused: logPaused ?? this.logPaused,
    visibleFrames: visibleFrames ?? this.visibleFrames,
    visibleRecords: visibleRecords ?? this.visibleRecords,
    framesCount: framesCount ?? this.framesCount,
    logCount: logCount ?? this.logCount,
    logCategories: logCategories ?? this.logCategories,
    selectedRecordHasFrame:
        selectedRecordHasFrame ?? this.selectedRecordHasFrame,
    selectedFrame: identical(selectedFrame, _keep)
        ? this.selectedFrame
        : selectedFrame as ProtocolFrame?,
    selectedRecord: identical(selectedRecord, _keep)
        ? this.selectedRecord
        : selectedRecord as Map<String, Object?>?,
    framesSplit: identical(framesSplit, _keep)
        ? this.framesSplit
        : framesSplit as double?,
    logSplit: identical(logSplit, _keep) ? this.logSplit : logSplit as double?,
    traceAvailable: traceAvailable ?? this.traceAvailable,
    traceEnabled: traceEnabled ?? this.traceEnabled,
    saveFailed: saveFailed ?? this.saveFailed,
  );

  // Списки сравниваются по ссылке: Cubit создаёт новый список при каждой
  // публикации, а сравнивать 2000 кадров поэлементно на каждом `emit` дороже
  // самой публикации.
  @override
  bool operator ==(Object other) =>
      other is ProtocolPaneState &&
      other.view == view &&
      other.focusedSessionId == focusedSessionId &&
      other.frameFilter == frameFilter &&
      other.logFilter == logFilter &&
      other.framesPaused == framesPaused &&
      other.logPaused == logPaused &&
      identical(other.visibleFrames, visibleFrames) &&
      identical(other.visibleRecords, visibleRecords) &&
      other.framesCount == framesCount &&
      other.logCount == logCount &&
      identical(other.logCategories, logCategories) &&
      other.selectedRecordHasFrame == selectedRecordHasFrame &&
      other.selectedFrame == selectedFrame &&
      identical(other.selectedRecord, selectedRecord) &&
      other.framesSplit == framesSplit &&
      other.logSplit == logSplit &&
      other.traceAvailable == traceAvailable &&
      other.traceEnabled == traceEnabled &&
      other.saveFailed == saveFailed;

  @override
  int get hashCode => Object.hashAll([
    view,
    focusedSessionId,
    frameFilter,
    logFilter,
    framesPaused,
    logPaused,
    identityHashCode(visibleFrames),
    identityHashCode(visibleRecords),
    framesCount,
    logCount,
    identityHashCode(logCategories),
    selectedRecordHasFrame,
    selectedFrame,
    selectedRecord == null ? null : identityHashCode(selectedRecord),
    framesSplit,
    logSplit,
    traceAvailable,
    traceEnabled,
    saveFailed,
  ]);
}

const Object _keep = Object();
