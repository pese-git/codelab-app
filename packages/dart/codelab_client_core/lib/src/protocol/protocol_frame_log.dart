import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';

import '../backend/agent_backend.dart';

/// Буфер кадров ACP одного соединения.
///
/// Почему: история кадров — клиентское состояние (политика «что хранить и
/// сколько»), а владелец такого состояния — kit, а не Cubit app
/// (`AGENTS.md` пакета §1; design.md change `redesign-protocol-pane`, D5).
/// Кадры не входят в `WorkspaceState`: при стриминге их сотни в секунду, а
/// `WorkspaceState` перестраивает рабочее место.
///
/// Для чего: хранит неизменяемый снимок кадров по порядку записи с лимитами
/// 2000 кадров и 8 MiB суммарного payload (вытесняются самые старые);
/// переподключение буфер не очищает — кадры несут номер поколения (Q6).
/// Привязывает запрос `session/new` к сессии из результата (D6: запрос ещё не
/// знает id сессии). Держит режим Trace (D17): включение переводит ядро на
/// `full` для кадров, выключение снимает payload со всех кадров.
///
/// Как использовать: создаёт и закрывает только `ClientWorkspace`; хост
/// читает `ClientWorkspace.protocolFrames`: подписывается на [changes],
/// по [revision] понимает, что снимок [frames] устарел, и берёт его.
/// Область (сессия в фокусе) буфер не знает — это дело хоста.
final class ProtocolFrameLog {
  /// Подписывается на `backend.protocolFrames`; [dispose] отписывает.
  ProtocolFrameLog({required AgentBackend backend, Logger? logger})
    : _backend = backend,
      _logger = logger,
      traceAvailable = backend.traceAvailable {
    _subscription = backend.protocolFrames.listen(_add);
  }

  /// Предел числа кадров (D5).
  static const maxFrames = 2000;

  /// Предел суммарного размера payload в UTF-8 (D5).
  static const maxPayloadBytes = 8 * 1024 * 1024;

  final AgentBackend _backend;
  final Logger? _logger;
  late final StreamSubscription<ProtocolFrame> _subscription;
  final _entries = ListQueue<_Entry>();
  final _changes = StreamController<void>.broadcast(sync: true);
  var _payloadBytes = 0;
  var _revision = 0;
  var _traceEnabled = false;
  var _closed = false;
  List<ProtocolFrame>? _snapshot;

  /// Режим Trace возможен: базовая политика ядра — `metadataOnly`. При
  /// базовой `full` payload и так полные, и Trace не нужен.
  final bool traceAvailable;

  /// Режим Trace включён; при каждом запуске выключен и не сохраняется.
  bool get traceEnabled => _traceEnabled;

  /// Неизменяемый снимок кадров, старые сначала.
  List<ProtocolFrame> get frames => _snapshot ??= List.unmodifiable([
    for (final entry in _entries) entry.frame,
  ]);

  /// Растёт при каждом изменении буфера: по нему хост видит устаревший снимок.
  int get revision => _revision;

  /// Сигнал «буфер изменился» без копии списка; закрывается в [dispose].
  Stream<void> get changes => _changes.stream;

  /// Удаляет все кадры; запись продолжается как обычно.
  void clear() {
    if (_closed) return;
    _entries.clear();
    _payloadBytes = 0;
    _changed();
  }

  /// Включает или выключает режим Trace (D17).
  ///
  /// Без эффекта при `traceAvailable == false` и при повторном значении:
  /// бэкенд не вызывается, ревизия не растёт. Выключение возвращает ядро к
  /// `metadataOnly` и снимает payload со всех кадров (копии с
  /// `payloadOmitted = policy`), обнуляет учёт объёма и увеличивает ревизию.
  void setTrace(bool enabled) {
    if (_closed || !traceAvailable || _traceEnabled == enabled) return;
    _traceEnabled = enabled;
    _backend.setFrameTrace(enabled);
    if (enabled) return;
    var dropped = 0;
    var changed = false;
    final stripped = <_Entry>[];
    for (final entry in _entries) {
      if (!_needsStrip(entry.frame)) {
        stripped.add(entry);
        continue;
      }
      if (entry.frame.payload != null) dropped++;
      final frame = entry.frame.withoutPayload();
      // Ошибка без payload уже могла быть без текста: ревизия растёт только
      // при настоящем изменении кадра.
      if (frame != entry.frame) changed = true;
      stripped.add(_Entry(frame, 0));
    }
    _entries
      ..clear()
      ..addAll(stripped);
    _payloadBytes = 0;
    _logger?.debug(
      'protocol_frames.payloads_dropped',
      context: {'count': dropped},
    );
    if (dropped > 0 || changed) _changed();
  }

  /// Закрывает буфер: отписывается от бэкенда и закрывает [changes]. Вызывает
  /// только владелец — `ClientWorkspace.dispose` (AGENTS.md §9).
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await _changes.close();
  }

  void _add(ProtocolFrame incoming) {
    if (_closed) return;
    // Пока Trace выключен при базовой `metadataOnly`, payload в буфер не
    // попадает: кадр, построенный ядром до выключения, но доставленный после
    // (поток `sync: false`), не вернёт payload обратно (D5, D17).
    final frame = traceAvailable && !_traceEnabled && _needsStrip(incoming)
        ? incoming.withoutPayload()
        : incoming;
    _bindSessionNew(frame);
    final bytes = frame.payload == null
        ? 0
        : utf8.encode(jsonEncode(frame.payload)).length;
    _entries.addLast(_Entry(frame, bytes));
    _payloadBytes += bytes;
    while (_entries.length > maxFrames || _payloadBytes > maxPayloadBytes) {
      _payloadBytes -= _entries.removeFirst().payloadBytes;
    }
    _changed();
  }

  /// Результат `session/new` с `sessionId` подставляет сессию в кадр запроса
  /// с тем же id и поколением: место и `seq` кадра сохраняются (D6).
  void _bindSessionNew(ProtocolFrame result) {
    final sessionId = result.sessionId;
    if (result.kind != ProtocolFrameKind.result ||
        result.method != sessionNewMethod ||
        sessionId == null ||
        result.id == null) {
      return;
    }
    final items = _entries.toList();
    for (var i = items.length - 1; i >= 0; i--) {
      final candidate = items[i].frame;
      if (candidate.kind == ProtocolFrameKind.request &&
          candidate.direction != result.direction &&
          candidate.method == sessionNewMethod &&
          candidate.id == result.id &&
          candidate.connectionGeneration == result.connectionGeneration &&
          candidate.sessionId == null) {
        items[i] = _Entry(
          candidate.copyWith(sessionId: sessionId),
          items[i].payloadBytes,
        );
        _entries
          ..clear()
          ..addAll(items);
        return;
      }
    }
  }

  /// Кадру нужно снятие: у него есть payload либо это ошибка. Текст ошибки
  /// (`detail`) — замаскированный, но всё же текст агента, и у кадра `tooLarge`
  /// payload нет, а текст есть; `withoutPayload` идемпотентен (D3, D17).
  bool _needsStrip(ProtocolFrame frame) =>
      frame.payload != null || frame.kind == ProtocolFrameKind.error;

  void _changed() {
    _revision++;
    _snapshot = null;
    if (!_changes.isClosed) _changes.add(null);
  }
}

final class _Entry {
  const _Entry(this.frame, this.payloadBytes);

  final ProtocolFrame frame;
  final int payloadBytes;
}
