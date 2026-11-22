import 'dart:convert';

import 'package:codelab_client_acp/codelab_client_acp.dart';

import 'protocol_pane_view.dart' show protocolMethodLabel;

/// Кадры сессии в фокусе и элементы соединения (design.md change
/// `redesign-protocol-pane`, D6).
///
/// Почему: панель показывает сессию в фокусе рабочего места, а кадры без
/// сессии (`initialize`, `session/list`, ошибки соединения) — общие для всех
/// сессий. Буфер один на соединение и области не знает, поэтому фильтрация
/// здесь, а не в kit.
///
/// Для чего: чистая функция; порядок записи сохраняется. Без фокуса
/// ([focusedSessionId] `null`) остаются только элементы соединения.
List<ProtocolFrame> framesInScope(
  Iterable<ProtocolFrame> frames, {
  String? focusedSessionId,
}) => [
  for (final frame in frames)
    if (frame.sessionId == null || frame.sessionId == focusedSessionId) frame,
];

/// Фильтры вида Frames: поиск и три переключателя (spec agent-workbench-ui
/// «Таблица кадров»).
///
/// Значение с равенством: Cubit хранит его в состоянии, а переход Log → Frames
/// сбрасывает фильтр к `const ProtocolFrameFilter()`.
final class ProtocolFrameFilter {
  const ProtocolFrameFilter({
    this.query = '',
    this.showRequests = true,
    this.showNotifications = true,
    this.errorsOnly = false,
  });

  final String query;

  /// Запросы и ответы на них (результаты и ошибки).
  final bool showRequests;
  final bool showNotifications;

  /// Только ошибки, независимо от `showRequests` и `showNotifications`.
  final bool errorsOnly;

  ProtocolFrameFilter copyWith({
    String? query,
    bool? showRequests,
    bool? showNotifications,
    bool? errorsOnly,
  }) => ProtocolFrameFilter(
    query: query ?? this.query,
    showRequests: showRequests ?? this.showRequests,
    showNotifications: showNotifications ?? this.showNotifications,
    errorsOnly: errorsOnly ?? this.errorsOnly,
  );

  @override
  bool operator ==(Object other) =>
      other is ProtocolFrameFilter &&
      other.query == query &&
      other.showRequests == showRequests &&
      other.showNotifications == showNotifications &&
      other.errorsOnly == errorsOnly;

  @override
  int get hashCode =>
      Object.hash(query, showRequests, showNotifications, errorsOnly);
}

/// Применяет [filter] к [frames].
///
/// Поиск — подстрока без учёта регистра в подписи метода, id или тексте
/// замаскированного payload (spec «Таблица кадров»).
List<ProtocolFrame> applyFrameFilter(
  List<ProtocolFrame> frames,
  ProtocolFrameFilter filter,
) {
  final query = filter.query.toLowerCase();
  bool matchesQuery(ProtocolFrame frame) {
    if (query.isEmpty) return true;
    if (protocolMethodLabel(frame).toLowerCase().contains(query)) return true;
    final id = frame.id?.toJsonValue();
    if (id != null && '$id'.toLowerCase().contains(query)) return true;
    final payload = frame.payload;
    return payload != null && jsonEncode(payload).toLowerCase().contains(query);
  }

  bool matchesKind(ProtocolFrame frame) {
    if (filter.errorsOnly) return frame.kind == ProtocolFrameKind.error;
    return frame.kind == ProtocolFrameKind.notification
        ? filter.showNotifications
        : filter.showRequests;
  }

  return [
    for (final frame in frames)
      if (matchesKind(frame) && matchesQuery(frame)) frame,
  ];
}
