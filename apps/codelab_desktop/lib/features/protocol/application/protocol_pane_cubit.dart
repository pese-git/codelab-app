import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log/structured_log.dart' show LogLevel;

import '../../../core/platform/protocol_export_saver.dart';
import 'log_record_filter.dart';
import 'log_record_source.dart';
import 'protocol_export.dart';
import 'protocol_frame_filter.dart';
import 'protocol_pane_state.dart';

/// Состояние и действия панели Protocol (design.md change
/// `redesign-protocol-pane`, D6, D7, D10, D17).
///
/// Почему Cubit в root scope: кадры, пришедшие до первого открытия панели,
/// должны быть видны, а вид, фильтры, выбор и доля разделителя переживают
/// закрытие вкладки (spec agent-workbench-ui «Панель Protocol»). Источник
/// кадров — буфер `ProtocolFrameLog` рабочего пространства (его владелец —
/// `ClientWorkspace`), источник записей — порт [LogRecordSource]; политику
/// «что хранить» держит kit, Cubit только отображает и выбирает область.
///
/// Для чего: область (сессия в фокусе и элементы соединения), фильтры, пауза
/// со снимком, выбор копией объекта, Trace, `Clear`, переход Log → Frames,
/// навигация Alt и экспорт JSON Lines. Публикация изменений буфера — не чаще
/// одного раза за [publishInterval] (`streaming.md` §15): первое изменение
/// публикуется сразу, дальнейшие склеиваются таймером. Действия пользователя
/// публикуются сразу.
///
/// Почему состояние читается лениво: Cubit живёт в root scope и получает
/// события буфера кадров и журнала, даже когда панель закрыта, а таймер,
/// запущенный без зрителя, остался бы «зависшим» в любом тесте приложения.
/// Поэтому, пока на [stream] никто не подписан, таймеров нет: геттер [state]
/// пересчитывает снимок при чтении, если буфер менялся, а публикация в поток
/// с ограничением частоты идёт только при наличии подписчика.
///
/// Как использовать: создаёт composition root; виджет читает состояние через
/// `BlocBuilder` и вызывает методы. Подписки на буфер кадров, источник записей
/// и фокус отменяются в [close], таймер склейки — тоже.
final class ProtocolPaneCubit extends Cubit<ProtocolPaneState> {
  ProtocolPaneCubit({
    required ClientWorkspace workspace,
    required LogRecordSource logRecords,
    required ProtocolExportSaver exportSaver,
    required ProtocolPayloadPolicy basePolicy,
    required Logger logger,
    this.publishInterval = const Duration(milliseconds: 100),
    this.appVersion = '',
    this.platform = '',
    DateTime Function() clock = DateTime.now,
  }) : _workspace = workspace,
       _logRecords = logRecords,
       _exportSaver = exportSaver,
       _basePolicy = basePolicy,
       _logger = logger,
       _clock = clock,
       super(const ProtocolPaneState()) {
    final active = workspace.current.activeSessionId;
    _focus = active?.value;
    _live = _compute(const ProtocolPaneState());
    _frameSub = workspace.protocolFrames.changes.listen((_) => _dirty());
    _recordSub = logRecords.changes.listen((_) => _dirty());
    _focusSub = workspace.state.listen((next) {
      final focus = next.activeSessionId?.value;
      if (focus != _focus) _changeFocus(focus);
    });
  }

  /// Минимальный интервал между публикациями изменений буфера (D7).
  final Duration publishInterval;

  /// Базовая политика payload хоста: по ней виджет выбирает InfoBar (D3).
  ProtocolPayloadPolicy get basePolicy => _basePolicy;

  /// Версия app и платформа — для заголовка экспорта (D10).
  final String appVersion;
  final String platform;

  final ClientWorkspace _workspace;
  final LogRecordSource _logRecords;
  final ProtocolExportSaver _exportSaver;
  final ProtocolPayloadPolicy _basePolicy;
  final Logger _logger;
  final DateTime Function() _clock;

  late final StreamSubscription<void> _frameSub;
  late final StreamSubscription<void> _recordSub;
  late final StreamSubscription<WorkspaceState> _focusSub;
  String? _focus;

  /// Последнее вычисленное состояние; [state] пересчитывает его, если после
  /// вычисления буфер менялся ([_stale]).
  late ProtocolPaneState _live;
  bool _stale = false;

  /// Есть ли подписчики [stream]: таймер склейки нужен, только если они есть.
  /// Последний подписчик ушёл — отложенная публикация отменяется.
  bool _observed = false;
  late final StreamController<ProtocolPaneState> _out =
      StreamController<ProtocolPaneState>.broadcast(
        onListen: () => _observed = true,
        onCancel: () {
          _observed = false;
          _cooldown?.cancel();
          _cooldown = null;
          _pending = false;
        },
      );
  late final StreamSubscription<ProtocolPaneState> _bridge = super.stream
      .listen(_out.add);

  @override
  Stream<ProtocolPaneState> get stream {
    // Мост от потока Bloc подписывается при первом обращении к `stream`.
    _bridge;
    return _out.stream;
  }

  @override
  ProtocolPaneState get state {
    if (_stale && !isClosed) {
      _stale = false;
      _live = _compute(_live);
    }
    return _live;
  }

  /// Снимки буфера на момент паузы вида (D7).
  List<ProtocolFrame>? _frozenFrames;
  List<Map<String, Object?>>? _frozenRecords;

  /// Идёт интервал «остывания» после публикации; `_pending` — за это время
  /// пришли изменения буфера.
  Timer? _cooldown;
  bool _pending = false;

  ProtocolFrameLog get _log => _workspace.protocolFrames;

  // -------------------------------------------------------------------------
  // Публикация.

  /// Пересчитывает область, фильтры и счётчики поверх [base].
  ProtocolPaneState _compute(ProtocolPaneState base) {
    final frameSource = base.framesPaused
        ? (_frozenFrames ?? _log.frames)
        : _log.frames;
    final recordSource = base.logPaused
        ? (_frozenRecords ?? _logRecords.records)
        : _logRecords.records;
    final logScope = recordsInScope(
      _logRecords.records,
      focusedSessionId: _focus,
    );
    return base.copyWith(
      focusedSessionId: _focus,
      visibleFrames: applyFrameFilter(
        framesInScope(frameSource, focusedSessionId: _focus),
        base.frameFilter,
      ),
      visibleRecords: applyRecordFilter(
        recordsInScope(recordSource, focusedSessionId: _focus),
        base.logFilter,
      ),
      framesCount: framesInScope(_log.frames, focusedSessionId: _focus).length,
      logCount: logScope.length,
      logCategories: <String>{
        for (final record in logScope)
          if (record['category'] is String) record['category']! as String,
      }.toList()..sort(),
      selectedRecordHasFrame:
          base.selectedRecord != null &&
          frameOfRecord(base.selectedRecord!) != null,
      traceAvailable: _log.traceAvailable,
      traceEnabled: _log.traceEnabled,
    );
  }

  /// Публикует состояние [next] сразу: путь действий пользователя.
  void _publish(ProtocolPaneState next) {
    if (isClosed) return;
    final computed = _compute(next);
    _stale = false;
    // `emit` сравнивает с прежним `state`, поэтому `_live` обновляется после.
    emit(computed);
    _live = computed;
  }

  /// Изменение буфера: первое публикуется сразу, остальные склеиваются.
  void _dirty() {
    if (isClosed) return;
    _stale = true;
    if (!_observed) return;
    if (_cooldown != null) {
      _pending = true;
      return;
    }
    _publish(_live);
    _startCooldown();
  }

  void _startCooldown() {
    _cooldown = Timer(publishInterval, () {
      _cooldown = null;
      if (isClosed) return;
      if (_pending) {
        _pending = false;
        _publish(_live);
        _startCooldown();
      }
    });
  }

  /// Действие пользователя: сбрасывает заметку сбоя экспорта (D10) и
  /// публикует [next] сразу.
  void _act(ProtocolPaneState next) =>
      _publish(next.copyWith(saveFailed: false));

  // -------------------------------------------------------------------------
  // Фокус.

  void _changeFocus(String? focus) {
    _focus = focus;
    var next = state;
    // Выбор снимается, если элемент не входит в новую область; элемент
    // соединения остаётся (D6).
    final frame = next.selectedFrame;
    if (frame != null && frame.sessionId != null && frame.sessionId != focus) {
      next = next.copyWith(selectedFrame: null);
    }
    final record = next.selectedRecord;
    if (record != null &&
        record['session_id'] != null &&
        '${record['session_id']}' != focus) {
      next = next.copyWith(selectedRecord: null);
    }
    _publish(next);
  }

  // -------------------------------------------------------------------------
  // Вид, фильтры, выбор.

  /// Выбирает активный вид; смена пишет debug-событие `protocol_pane.view`.
  void selectView(ProtocolView view) {
    if (view == state.view) return;
    _logger.debug('protocol_pane.view', context: {'view': view.name});
    _act(state.copyWith(view: view));
  }

  /// `/logs` в палитре: открывает вид Log.
  void openLog() => selectView(ProtocolView.log);

  void setFrameQuery(String query) => _act(
    state.copyWith(frameFilter: state.frameFilter.copyWith(query: query)),
  );

  void setShowRequests(bool value) => _act(
    state.copyWith(
      frameFilter: state.frameFilter.copyWith(showRequests: value),
    ),
  );

  void setShowNotifications(bool value) => _act(
    state.copyWith(
      frameFilter: state.frameFilter.copyWith(showNotifications: value),
    ),
  );

  void setErrorsOnly(bool value) => _act(
    state.copyWith(frameFilter: state.frameFilter.copyWith(errorsOnly: value)),
  );

  void setLogQuery(String query) =>
      _act(state.copyWith(logFilter: state.logFilter.copyWith(query: query)));

  void setLogCategory(String? category) => _act(
    state.copyWith(logFilter: state.logFilter.copyWith(category: category)),
  );

  void setLogMinLevel(LogLevel? level) => _act(
    state.copyWith(logFilter: state.logFilter.copyWith(minLevel: level)),
  );

  void selectFrame(ProtocolFrame? frame) =>
      _act(state.copyWith(selectedFrame: frame));

  void selectRecord(Map<String, Object?>? record) =>
      _act(state.copyWith(selectedRecord: record));

  /// Сохраняет долю таблицы активного вида (D7, D12).
  void setSplit(double fraction) => _act(
    state.view == ProtocolView.frames
        ? state.copyWith(framesSplit: fraction)
        : state.copyWith(logSplit: fraction),
  );

  /// Alt+→ / Alt+↓: следующий видимый элемент; без выбора — первый; на краю
  /// выбор не меняется (spec «Клавиатура панели Protocol»).
  void selectNext() => _move(1);

  /// Alt+← / Alt+↑: предыдущий видимый элемент; без выбора — последний.
  void selectPrevious() => _move(-1);

  void _move(int step) {
    if (state.view == ProtocolView.frames) {
      final items = state.visibleFrames;
      if (items.isEmpty) return;
      final selected = state.selectedFrame;
      final index = selected == null
          ? -1
          : items.indexWhere((frame) => frame.seq == selected.seq);
      final target = _target(index, items.length, step);
      if (target != null) {
        selectFrame(items[target]);
      }
    } else {
      final items = state.visibleRecords;
      if (items.isEmpty) return;
      final selected = state.selectedRecord;
      final index = selected == null
          ? -1
          : items.indexWhere((record) => identical(record, selected));
      final target = _target(index, items.length, step);
      if (target != null) {
        selectRecord(items[target]);
      }
    }
  }

  /// Индекс цели шага или `null` на краю. [index] `-1` — выбора (в области)
  /// нет: вперёд — первый, назад — последний.
  int? _target(int index, int length, int step) {
    if (index < 0) return step > 0 ? 0 : length - 1;
    final next = index + step;
    return next < 0 || next >= length ? null : next;
  }

  // -------------------------------------------------------------------------
  // Pause, Clear, Trace.

  /// `Pause` / `Resume` активного вида (D10): пауза делает снимок буфера.
  void togglePause() {
    if (state.view == ProtocolView.frames) {
      final paused = !state.framesPaused;
      _frozenFrames = paused ? _log.frames : null;
      _act(state.copyWith(framesPaused: paused));
    } else {
      final paused = !state.logPaused;
      _frozenRecords = paused ? _logRecords.records : null;
      _act(state.copyWith(logPaused: paused));
    }
  }

  /// `Clear` активного вида: очищает буфер целиком, включая элементы других
  /// сессий (буфер общий, D6, D10), снимает выбор и паузу.
  void clear() {
    final view = state.view;
    if (view == ProtocolView.frames) {
      final count = _log.frames.length;
      _log.clear();
      _frozenFrames = null;
      _logger.info(
        'protocol_pane.clear',
        context: {'view': view.name, 'count': count},
      );
      _act(state.copyWith(framesPaused: false, selectedFrame: null));
    } else {
      final count = _logRecords.records.length;
      _logRecords.clear();
      _frozenRecords = null;
      _logger.info(
        'protocol_pane.clear',
        context: {'view': view.name, 'count': count},
      );
      _act(state.copyWith(logPaused: false, selectedRecord: null));
    }
  }

  /// Включает или выключает Trace (D17). Без эффекта, если Trace недоступен
  /// (базовая политика `full`) или значение не меняется. Выключение снимает
  /// payload с выбранного кадра и со снимка паузы: буфер снимает его у своих
  /// кадров сам.
  void setTrace(bool enabled) {
    if (!_log.traceAvailable || _log.traceEnabled == enabled) return;
    _log.setTrace(enabled);
    _logger.info('protocol_pane.trace', context: {'enabled': enabled});
    var next = state;
    if (!enabled) {
      // Кадр без payload берётся из буфера: он сам снял payload (и всё, что
      // из него следует, например текст ошибки) по правилам ядра; копия,
      // собранная здесь, нужна только вытесненному из буфера кадру.
      final current = {for (final f in _log.frames) f.seq: f};
      final frozen = _frozenFrames;
      if (frozen != null) {
        _frozenFrames = [for (final f in frozen) _stripped(f, current)];
      }
      final selected = next.selectedFrame;
      if (selected != null) {
        next = next.copyWith(selectedFrame: _stripped(selected, current));
      }
    }
    _act(next);
  }

  ProtocolFrame _stripped(
    ProtocolFrame frame,
    Map<int, ProtocolFrame> current,
  ) {
    // Ошибка несёт текст агента в `detail` и без payload (например,
    // `tooLarge`), поэтому её снимают всегда; `withoutPayload` идемпотентен.
    if (frame.payload == null && frame.kind != ProtocolFrameKind.error) {
      return frame;
    }
    // Вытесненный из буфера кадр снимается тем же правилом ядра
    // (`withoutPayload`: payload долой, текст ошибки — стандартное имя кода).
    return current[frame.seq] ?? frame.withoutPayload();
  }

  // -------------------------------------------------------------------------
  // Переход Log → Frames.

  /// Кадр записи журнала в области: тот же `request_id` (строковая форма) и
  /// `connection_generation`, если он есть в записи, иначе — последний такой
  /// (D8). `null` — кадра в буфере нет.
  ProtocolFrame? frameOfRecord(Map<String, Object?> record) {
    final requestId = record['request_id'];
    if (requestId == null) return null;
    final generation = record['connection_generation'];
    ProtocolFrame? found;
    for (final frame in framesInScope(_log.frames, focusedSessionId: _focus)) {
      if ('${frame.id?.toJsonValue()}' != '$requestId') continue;
      if (generation != null && frame.connectionGeneration != generation) {
        continue;
      }
      found = frame;
    }
    return found;
  }

  /// Переключает вид на Frames и выбирает кадр записи; фильтры, которые его
  /// скрывают, сбрасываются к умолчанию. Без кадра ничего не делает.
  void showFrameOfRecord(Map<String, Object?> record) {
    final frame = frameOfRecord(record);
    if (frame == null) return;
    var next = state;
    if (applyFrameFilter([frame], next.frameFilter).isEmpty) {
      next = next.copyWith(frameFilter: const ProtocolFrameFilter());
    }
    if (next.view != ProtocolView.frames) {
      _logger.debug(
        'protocol_pane.view',
        context: {'view': ProtocolView.frames.name},
      );
    }
    _act(next.copyWith(view: ProtocolView.frames, selectedFrame: frame));
  }

  // -------------------------------------------------------------------------
  // Экспорт (D10).

  /// В видимом наборе вида Frames есть кадр с payload: экспорт сначала
  /// спрашивает подтверждение.
  bool get exportNeedsConfirmation =>
      state.view == ProtocolView.frames &&
      exportHasPayload(state.visibleFrames);

  /// Экспортирует то, что видно в активном виде. [confirm] показывает
  /// подтверждение `Export full payloads?`; текст файла строится уже после
  /// него, поэтому выключение Trace во время диалога сохранения набор не
  /// меняет. Пустой вид — без действий и без событий.
  Future<void> exportActive({required Future<bool> Function() confirm}) async {
    final view = state.view;
    if (_visibleCount(view) == 0) return;
    if (exportNeedsConfirmation && !await confirm()) {
      _logExport(view, const ProtocolExportCancelled(), _visibleCount(view));
      return;
    }
    if (isClosed) return;
    final count = _visibleCount(view);
    final now = _clock();
    final debugBuild = _basePolicy == ProtocolPayloadPolicy.full;
    final text = view == ProtocolView.frames
        ? buildFramesExport(
            frames: state.visibleFrames,
            exportedAt: now,
            debugBuild: debugBuild,
            appVersion: appVersion,
            platform: platform,
            sessionId: _focus,
          )
        : buildRecordsExport(
            records: state.visibleRecords,
            exportedAt: now,
            debugBuild: debugBuild,
            appVersion: appVersion,
            platform: platform,
            sessionId: _focus,
          );
    final result = await _exportSaver.save(
      suggestedName: protocolExportFileName(view, now),
      text: text,
    );
    _logExport(view, result, count);
    if (isClosed) return;
    _publish(state.copyWith(saveFailed: result is ProtocolExportFailed));
  }

  int _visibleCount(ProtocolView view) => view == ProtocolView.frames
      ? state.visibleFrames.length
      : state.visibleRecords.length;

  void _logExport(
    ProtocolView view,
    ProtocolExportSaveResult result,
    int count,
  ) => _logger.info(
    'protocol_pane.export',
    context: {
      'view': view.name,
      'outcome': result.outcome,
      'count': count,
      if (result case ProtocolExportFailed(:final errorClass))
        'error_class': errorClass,
    },
  );

  /// Выполняет побочное действие панели (буфер обмена, экспорт), не теряя
  /// ошибку: она пишется событием `protocol_pane.action_failed` с именем
  /// действия и классом исключения, без текста, путей и payload (§12, §16).
  ///
  /// Почему здесь: виджет запускает такие действия «без ожидания», а
  /// необработанная ошибка (диалог после размонтирования, сбой буфера обмена)
  /// ушла бы в зону без следа. Как использовать:
  /// `unawaited(cubit.guarded('copy', () => Clipboard.setData(…)))`.
  Future<void> guarded(String action, Future<void> Function() body) async {
    try {
      await body();
    } on Object catch (error) {
      _logger.error(
        'protocol_pane.action_failed',
        context: {
          'action': action,
          'error_class': error.runtimeType.toString(),
        },
      );
    }
  }

  @override
  Future<void> close() async {
    _cooldown?.cancel();
    _cooldown = null;
    await _frameSub.cancel();
    await _recordSub.cancel();
    await _focusSub.cancel();
    await super.close();
    await _out.close();
  }
}
