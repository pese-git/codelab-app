import 'package:freezed_annotation/freezed_annotation.dart';

import '../json_rpc/json_value.dart';
import '../json_rpc/protocol_error.dart';
import 'acp_validation.dart';
import 'session.dart';

part 'fs.freezed.dart';

@freezed
sealed class ReadTextFileRequest with _$ReadTextFileRequest {
  const ReadTextFileRequest._();

  const factory ReadTextFileRequest({
    required SessionId sessionId,
    required String path,
    int? line,
    int? limit,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _ReadTextFileRequest;

  factory ReadTextFileRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'readTextFileRequest',
      allowedKeys: {'sessionId', 'path', 'line', 'limit', '_meta'},
    );

    return ReadTextFileRequest(
      sessionId: SessionId.fromJson(source['sessionId']),
      path: _requiredAbsolutePath(source, 'path'),
      line: _optionalInt(source, 'line'),
      limit: _optionalInt(source, 'limit'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'path': path,
      if (line != null) 'line': line,
      if (limit != null) 'limit': limit,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class ReadTextFileResponse with _$ReadTextFileResponse {
  const ReadTextFileResponse._();

  const factory ReadTextFileResponse({
    required String content,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _ReadTextFileResponse;

  factory ReadTextFileResponse.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'readTextFileResponse',
      allowedKeys: {'content', '_meta'},
    );

    return ReadTextFileResponse(
      content: _requiredString(source, 'content'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {'content': content, if (meta != null) '_meta': meta};
  }
}

@freezed
sealed class WriteTextFileRequest with _$WriteTextFileRequest {
  const WriteTextFileRequest._();

  const factory WriteTextFileRequest({
    required SessionId sessionId,
    required String path,
    required String content,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _WriteTextFileRequest;

  factory WriteTextFileRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'writeTextFileRequest',
      allowedKeys: {'sessionId', 'path', 'content', '_meta'},
    );

    return WriteTextFileRequest(
      sessionId: SessionId.fromJson(source['sessionId']),
      path: _requiredAbsolutePath(source, 'path'),
      content: _requiredString(source, 'content'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'path': path,
      'content': content,
      if (meta != null) '_meta': meta,
    };
  }
}

/// The wire result for `fs/write_text_file` is an empty success payload
/// (ACP: `"result": null`) — this mirrors it as an empty object, consistent
/// with every other [AcpMethodDefinition] result in this package, which
/// always encodes/decodes a [JsonObject] rather than a bare JSON `null`.
@freezed
sealed class WriteTextFileResponse with _$WriteTextFileResponse {
  const WriteTextFileResponse._();

  const factory WriteTextFileResponse() = _WriteTextFileResponse;

  factory WriteTextFileResponse.fromJson(Object? value) {
    if (value != null) {
      requireAcpObject(value, path: 'writeTextFileResponse', allowedKeys: {});
    }

    return const WriteTextFileResponse();
  }

  JsonObject toJson() => const {};
}

String _requiredAbsolutePath(JsonObject source, String field) {
  final value = source[field];
  if (value is! String || value.isEmpty || !_isAbsolutePath(value)) {
    throw JsonRpcProtocolException.invalidShape(
      '$field must be a non-empty absolute path.',
    );
  }

  return value;
}

/// Recognizes POSIX absolute paths (`/...`), Windows drive-letter paths
/// (`C:\...`/`C:/...`), and Windows UNC paths (`\\server\share`) — this
/// package stays platform-agnostic (no `dart:io`/`Platform` checks), so it
/// cannot assume which OS produced the path.
bool _isAbsolutePath(String value) {
  if (value.startsWith('/')) {
    return true;
  }
  if (value.startsWith(r'\\')) {
    return true;
  }
  if (value.length >= 3 &&
      _isAsciiLetter(value.codeUnitAt(0)) &&
      value[1] == ':' &&
      (value[2] == '/' || value[2] == r'\')) {
    return true;
  }

  return false;
}

bool _isAsciiLetter(int codeUnit) {
  return (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A);
}

JsonObject? _optionalObject(JsonObject source, String field) {
  if (!source.containsKey(field) || source[field] == null) {
    return null;
  }

  return requireJsonObject(source[field], path: field);
}

String _requiredString(JsonObject source, String field) {
  final value = source[field];
  if (value is String) {
    return value;
  }

  throw JsonRpcProtocolException.invalidShape('$field must be a string.');
}

int? _optionalInt(JsonObject source, String field) {
  if (!source.containsKey(field) || source[field] == null) {
    return null;
  }

  final value = source[field];
  if (value is int) {
    return value;
  }

  throw JsonRpcProtocolException.invalidShape('$field must be an integer.');
}
