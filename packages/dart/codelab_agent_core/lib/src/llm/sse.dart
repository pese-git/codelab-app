import 'dart:async';

/// Одно событие SSE (`agent-core-architecture` §2.6).
///
/// Почему отдельный тип: провайдеры LLM и транспорт MCP читают один и тот же
/// формат, второй реализации SSE нет.
///
/// Как использовать: значения выдаёт [SseDecoder]; руками создаются только в
/// тестах.
final class ServerSentEvent {
  const ServerSentEvent({this.event, required this.data, this.id, this.retry});

  /// Поле `event:`; `null` означает `message`.
  final String? event;

  /// Строки `data:`, склеенные через `\n`.
  final String data;
  final String? id;

  /// Последнее принятое поле `retry` (только цифры, миллисекунды) — пауза
  /// перед переподключением. Нужна MCP-клиенту для опроса legacy-потока
  /// (change `add-agent-mcp-client`, D10); провайдеры LLM его не читают.
  final Duration? retry;

  @override
  String toString() =>
      'ServerSentEvent(event: $event, id: $id, retry: $retry, data: $data)';
}

/// Предел `retry`: паузу длиннее суток поле не задаёт (сервер недоверенный).
const maxSseRetry = Duration(hours: 24);

final _digits = RegExp(r'^[0-9]+$');

/// Превращает поток текстовых кусков в [ServerSentEvent] по правилам §2.6.
///
/// Почему текст на входе: декодирование UTF-8 выполняется выше по потоку
/// (`Utf8Decoder(allowMalformed: true)`), оно же склеивает многобайтные
/// символы, разрезанные границей куска.
///
/// Правила:
/// * строки оканчиваются `\n`, `\r` или `\r\n`; `\r\n`, разрезанный границей
///   кусков, — один перевод строки;
/// * `U+FEFF` отбрасывается только как самый первый символ потока;
/// * строки с `:` в начале — комментарии (keep-alive провайдера);
/// * строка делится по первому `:`; без него вся строка — имя поля с пустым
///   значением; ровно один пробел в начале значения отбрасывается;
/// * `event` задаёт тип, `data` добавляет строку, `id` запоминается, если не
///   содержит `U+0000`; `retry` запоминается, если это только цифры, не
///   больше [maxSseRetry] (как `id`, живёт между событиями); остальные поля
///   игнорируются;
/// * пустая строка отправляет событие, если в нём есть данные, и сбрасывает
///   `event` и данные; `id` и `retry` остаются;
/// * незаконченная строка или событие в конце потока отбрасываются.
final class SseDecoder extends StreamTransformerBase<String, ServerSentEvent> {
  const SseDecoder();

  @override
  Stream<ServerSentEvent> bind(Stream<String> source) async* {
    final line = StringBuffer();
    final data = <String>[];
    String? event;
    String? id;
    Duration? retry;
    var skipLf = false;
    var atStart = true;

    ServerSentEvent? feed(String text) {
      if (text.isEmpty) {
        if (data.isEmpty) {
          event = null;
          return null;
        }
        final dispatched = ServerSentEvent(
          event: event,
          data: data.join('\n'),
          id: id,
          retry: retry,
        );
        data.clear();
        event = null;
        return dispatched;
      }
      if (text.startsWith(':')) {
        return null;
      }
      final colon = text.indexOf(':');
      final field = colon < 0 ? text : text.substring(0, colon);
      var value = colon < 0 ? '' : text.substring(colon + 1);
      if (value.startsWith(' ')) {
        value = value.substring(1);
      }
      switch (field) {
        case 'event':
          event = value;
        case 'data':
          data.add(value);
        case 'id':
          if (!value.contains('\u0000')) {
            id = value;
          }
        case 'retry':
          // Сверхбольшое число (`int.parse` бросил бы FormatException внутри
          // `async*` и уронил бы процесс) и всё выше предела игнорируются.
          final ms = _digits.hasMatch(value) ? int.tryParse(value) : null;
          if (ms != null && ms <= maxSseRetry.inMilliseconds) {
            retry = Duration(milliseconds: ms);
          }
      }
      return null;
    }

    await for (final chunk in source) {
      var start = 0;
      if (atStart && chunk.isNotEmpty) {
        atStart = false;
        if (chunk.codeUnitAt(0) == 0xFEFF) {
          start = 1;
        }
      }
      var segment = start;
      for (var i = start; i < chunk.length; i++) {
        final c = chunk.codeUnitAt(i);
        if (skipLf) {
          skipLf = false;
          if (c == 0x0A) {
            segment = i + 1;
            continue;
          }
        }
        if (c == 0x0A || c == 0x0D) {
          skipLf = c == 0x0D;
          line.write(chunk.substring(segment, i));
          segment = i + 1;
          final dispatched = feed(line.toString());
          line.clear();
          if (dispatched != null) {
            yield dispatched;
          }
        }
      }
      if (segment < chunk.length) {
        line.write(chunk.substring(segment));
      }
    }
  }
}
