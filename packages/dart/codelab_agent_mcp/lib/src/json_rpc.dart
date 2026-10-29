import 'dart:convert';

import 'protocol.dart';

/// Кодек JSON-RPC 2.0 для MCP (design.md change `add-agent-mcp-client`,
/// D4).
///
/// Почему свой: `codelab_agent_mcp` не может зависеть от ACP-кодека
/// (`freezed`, `fpdart` вне allowlist) и от `json_rpc_2` (второй фреймворк
/// JSON-RPC, корневой `AGENTS.md` §4). Нужно ~150 строк: четыре вида
/// сообщений, разбор без исключений наружу и исходящие id.
///
/// Как использовать: входящий текст транспорта разбирается
/// [decodeMcpMessages]; исходящие сообщения строит один [McpOutbound] на
/// соединение.
sealed class McpIncoming {
  const McpIncoming();
}

/// Запрос сервера клиенту (в MVP — только legacy-`ping`, остальное `-32601`).
final class McpRequest extends McpIncoming {
  const McpRequest(this.id, this.method, this.params);

  final Object id;
  final String method;
  final Map<String, Object?> params;
}

final class McpNotification extends McpIncoming {
  const McpNotification(this.method, this.params);

  final String method;
  final Map<String, Object?> params;
}

final class McpResponse extends McpIncoming {
  const McpResponse(this.id, this.result);

  final Object id;
  final Map<String, Object?> result;
}

final class McpErrorResponse extends McpIncoming {
  const McpErrorResponse(this.id, this.code, this.message, [this.data]);

  final Object id;
  final int code;
  final String message;
  final Object? data;

  /// `data.supported` ошибки `-32022` (`UnsupportedProtocolVersion`); пусто,
  /// если поля нет или оно не список строк.
  List<String> get supportedVersions {
    final d = data;
    if (d is Map && d['supported'] is List) {
      return [
        for (final v in d['supported'] as List)
          if (v is String) v,
      ];
    }
    return const [];
  }
}

/// Сообщение, которое не удалось разобрать: `mcp.message.ignored`
/// `parse_error`, соединение не рвётся (D4).
final class McpMalformed extends McpIncoming {
  const McpMalformed(this.reason);

  final String reason;
}

/// Разбирает текст транспорта: объект или массив (пакет `2025-03-26`).
///
/// Никогда не бросает: не-JSON, `id: null`, дробный `id` и неизвестная форма
/// дают [McpMalformed]. Идентификатор — `int` или `String`
/// (`basic/index.md`, «Requests»).
List<McpIncoming> decodeMcpMessages(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return const [McpMalformed('not JSON')];
  }
  if (json is List) {
    if (json.isEmpty) {
      return const [McpMalformed('empty batch')];
    }
    return [for (final item in json) _decodeOne(item)];
  }
  return [_decodeOne(json)];
}

McpIncoming _decodeOne(Object? json) {
  if (json is! Map) {
    return const McpMalformed('not a JSON object');
  }
  if (json['jsonrpc'] != '2.0') {
    return const McpMalformed('jsonrpc is not "2.0"');
  }
  final hasId = json.containsKey('id');
  final Object? id = json['id'];
  if (hasId && id != null && id is! int && id is! String) {
    return const McpMalformed('id is neither int nor string');
  }
  final method = json['method'];
  if (method is String) {
    final params = _object(json['params']);
    if (!hasId) {
      return McpNotification(method, params);
    }
    if (id == null) {
      return const McpMalformed('request id is null');
    }
    return McpRequest(id, method, params);
  }
  if (id == null) {
    return const McpMalformed('response id is null or missing');
  }
  final error = json['error'];
  if (error is Map) {
    final code = error['code'];
    final message = error['message'];
    if (code is! int || message is! String) {
      return const McpMalformed('error without integer code and message');
    }
    return McpErrorResponse(id, code, message, error['data']);
  }
  final result = json['result'];
  if (result is Map) {
    return McpResponse(id, Map<String, Object?>.from(result));
  }
  return const McpMalformed('neither result nor error');
}

Map<String, Object?> _object(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};

/// Исходящее сообщение: id и готовый текст.
final class McpEncoded {
  const McpEncoded(this.id, this.text);

  final int id;
  final String text;
}

/// Строит исходящие сообщения одного соединения (D2, D4).
///
/// Почему вместе с эпохой: modern-запрос несёт `_meta` с версией, `{}`
/// capabilities и `clientInfo` (D2), legacy — нет. Эпоха определяется пробой
/// уже после создания кодека, поэтому [era] меняется: пробный
/// `server/discover` идёт как modern, `initialize` — как legacy.
///
/// Как использовать: один экземпляр на соединение; [request] выдаёт
/// возрастающие целые id без повторов (`basic/index.md`, «Requests»).
final class McpOutbound {
  McpOutbound({
    required this.clientName,
    required this.clientVersion,
    this.era = McpEra.modern,
  });

  final String clientName;
  final String clientVersion;
  McpEra era;
  var _next = 1;

  McpEncoded request(String method, [Map<String, Object?> params = const {}]) {
    final id = _next++;
    final body = <String, Object?>{...params};
    if (era == McpEra.modern) {
      body['_meta'] = {
        ...?(params['_meta'] as Map<String, Object?>?),
        'io.modelcontextprotocol/protocolVersion': modernProtocolVersion,
        'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
        'io.modelcontextprotocol/clientInfo': {
          'name': clientName,
          'version': clientVersion,
        },
      };
    }
    return McpEncoded(
      id,
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (body.isNotEmpty) 'params': body,
      }),
    );
  }

  /// Уведомления `_meta` протокола не несут (`basic/index.md`: поля
  /// запроса относятся к запросам).
  String notification(String method, [Map<String, Object?>? params]) =>
      jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': ?params});

  String response(Object id, Map<String, Object?> result) =>
      jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result});

  String errorResponse(Object id, int code, String message) => jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  });
}

/// Коды ошибок JSON-RPC, которые клиент выдаёт сам.
const jsonRpcMethodNotFound = -32601;
