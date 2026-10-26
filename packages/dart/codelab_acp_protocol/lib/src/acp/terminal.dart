import 'package:freezed_annotation/freezed_annotation.dart';

import '../json_rpc/json_value.dart';
import '../json_rpc/protocol_error.dart';
import 'acp_validation.dart';
import 'session.dart';

part 'terminal.freezed.dart';

@freezed
sealed class TerminalId with _$TerminalId {
  const TerminalId._();

  const factory TerminalId(String value) = _TerminalId;

  factory TerminalId.fromJson(Object? value) {
    if (value is String && value.isNotEmpty) {
      return TerminalId(value);
    }

    throw JsonRpcProtocolException.invalidShape(
      'terminalId must be a non-empty string.',
    );
  }

  String toJson() => value;
}

@freezed
sealed class TerminalExitStatus with _$TerminalExitStatus {
  const TerminalExitStatus._();

  const factory TerminalExitStatus({
    int? exitCode,
    String? signal,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _TerminalExitStatus;

  factory TerminalExitStatus.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'terminalExitStatus',
      allowedKeys: {'exitCode', 'signal', '_meta'},
    );

    return TerminalExitStatus(
      exitCode: _optionalInt(source, 'exitCode'),
      signal: _optionalString(source, 'signal'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      if (exitCode != null) 'exitCode': exitCode,
      if (signal != null) 'signal': signal,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class CreateTerminalRequest with _$CreateTerminalRequest {
  const CreateTerminalRequest._();

  const factory CreateTerminalRequest({
    required SessionId sessionId,
    required String command,
    @Default([]) List<String> args,
    @Default([]) List<EnvVariable> env,
    String? cwd,
    int? outputByteLimit,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _CreateTerminalRequest;

  factory CreateTerminalRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'createTerminalRequest',
      allowedKeys: {
        'sessionId',
        'command',
        'args',
        'env',
        'cwd',
        'outputByteLimit',
        '_meta',
      },
    );

    return CreateTerminalRequest(
      sessionId: SessionId.fromJson(source['sessionId']),
      command: _requiredString(source, 'command'),
      args: _optionalStringList(source, 'args'),
      env: _objectList(source, 'env', EnvVariable.fromJson),
      cwd: _optionalAbsolutePath(source, 'cwd'),
      outputByteLimit: _optionalInt(source, 'outputByteLimit'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'command': command,
      'args': args,
      'env': env.map((variable) => variable.toJson()).toList(),
      if (cwd != null) 'cwd': cwd,
      if (outputByteLimit != null) 'outputByteLimit': outputByteLimit,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class CreateTerminalResponse with _$CreateTerminalResponse {
  const CreateTerminalResponse._();

  const factory CreateTerminalResponse({
    required TerminalId terminalId,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _CreateTerminalResponse;

  factory CreateTerminalResponse.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'createTerminalResponse',
      allowedKeys: {'terminalId', '_meta'},
    );

    return CreateTerminalResponse(
      terminalId: TerminalId.fromJson(source['terminalId']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {'terminalId': terminalId.toJson(), if (meta != null) '_meta': meta};
  }
}

@freezed
sealed class TerminalOutputRequest with _$TerminalOutputRequest {
  const TerminalOutputRequest._();

  const factory TerminalOutputRequest({
    required SessionId sessionId,
    required TerminalId terminalId,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _TerminalOutputRequest;

  factory TerminalOutputRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'terminalOutputRequest',
      allowedKeys: {'sessionId', 'terminalId', '_meta'},
    );

    return TerminalOutputRequest(
      sessionId: SessionId.fromJson(source['sessionId']),
      terminalId: TerminalId.fromJson(source['terminalId']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'terminalId': terminalId.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class TerminalOutputResponse with _$TerminalOutputResponse {
  const TerminalOutputResponse._();

  const factory TerminalOutputResponse({
    required String output,
    required bool truncated,
    TerminalExitStatus? exitStatus,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _TerminalOutputResponse;

  factory TerminalOutputResponse.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'terminalOutputResponse',
      allowedKeys: {'output', 'truncated', 'exitStatus', '_meta'},
    );

    return TerminalOutputResponse(
      output: _requiredString(source, 'output'),
      truncated: _requiredBool(source, 'truncated'),
      exitStatus: source['exitStatus'] == null
          ? null
          : TerminalExitStatus.fromJson(source['exitStatus']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'output': output,
      'truncated': truncated,
      if (exitStatus != null) 'exitStatus': exitStatus?.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class WaitForTerminalExitRequest with _$WaitForTerminalExitRequest {
  const WaitForTerminalExitRequest._();

  const factory WaitForTerminalExitRequest({
    required SessionId sessionId,
    required TerminalId terminalId,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _WaitForTerminalExitRequest;

  factory WaitForTerminalExitRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'waitForTerminalExitRequest',
      allowedKeys: {'sessionId', 'terminalId', '_meta'},
    );

    return WaitForTerminalExitRequest(
      sessionId: SessionId.fromJson(source['sessionId']),
      terminalId: TerminalId.fromJson(source['terminalId']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'terminalId': terminalId.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

/// Wire result of `terminal/wait_for_exit` is flat (`exitCode`/`signal`
/// directly on the response), unlike `terminal/output`'s nested
/// `exitStatus` — mirrors the ACP schema exactly rather than reusing
/// [TerminalExitStatus] as the response shape itself.
@freezed
sealed class WaitForTerminalExitResponse with _$WaitForTerminalExitResponse {
  const WaitForTerminalExitResponse._();

  const factory WaitForTerminalExitResponse({
    int? exitCode,
    String? signal,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _WaitForTerminalExitResponse;

  factory WaitForTerminalExitResponse.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'waitForTerminalExitResponse',
      allowedKeys: {'exitCode', 'signal', '_meta'},
    );

    return WaitForTerminalExitResponse(
      exitCode: _optionalInt(source, 'exitCode'),
      signal: _optionalString(source, 'signal'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      if (exitCode != null) 'exitCode': exitCode,
      if (signal != null) 'signal': signal,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class KillTerminalCommandRequest with _$KillTerminalCommandRequest {
  const KillTerminalCommandRequest._();

  const factory KillTerminalCommandRequest({
    required SessionId sessionId,
    required TerminalId terminalId,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _KillTerminalCommandRequest;

  factory KillTerminalCommandRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'killTerminalCommandRequest',
      allowedKeys: {'sessionId', 'terminalId', '_meta'},
    );

    return KillTerminalCommandRequest(
      sessionId: SessionId.fromJson(source['sessionId']),
      terminalId: TerminalId.fromJson(source['terminalId']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'terminalId': terminalId.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

/// The wire result for `terminal/kill` is an empty success payload, like
/// `fs/write_text_file` — see [WriteTextFileResponse] in `fs.dart`.
@freezed
sealed class KillTerminalCommandResponse with _$KillTerminalCommandResponse {
  const KillTerminalCommandResponse._();

  const factory KillTerminalCommandResponse() = _KillTerminalCommandResponse;

  factory KillTerminalCommandResponse.fromJson(Object? value) {
    if (value != null) {
      requireAcpObject(
        value,
        path: 'killTerminalCommandResponse',
        allowedKeys: {},
      );
    }

    return const KillTerminalCommandResponse();
  }

  JsonObject toJson() => const {};
}

@freezed
sealed class ReleaseTerminalRequest with _$ReleaseTerminalRequest {
  const ReleaseTerminalRequest._();

  const factory ReleaseTerminalRequest({
    required SessionId sessionId,
    required TerminalId terminalId,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _ReleaseTerminalRequest;

  factory ReleaseTerminalRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'releaseTerminalRequest',
      allowedKeys: {'sessionId', 'terminalId', '_meta'},
    );

    return ReleaseTerminalRequest(
      sessionId: SessionId.fromJson(source['sessionId']),
      terminalId: TerminalId.fromJson(source['terminalId']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'terminalId': terminalId.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

/// The wire result for `terminal/release` is an empty success payload, like
/// [KillTerminalCommandResponse].
@freezed
sealed class ReleaseTerminalResponse with _$ReleaseTerminalResponse {
  const ReleaseTerminalResponse._();

  const factory ReleaseTerminalResponse() = _ReleaseTerminalResponse;

  factory ReleaseTerminalResponse.fromJson(Object? value) {
    if (value != null) {
      requireAcpObject(value, path: 'releaseTerminalResponse', allowedKeys: {});
    }

    return const ReleaseTerminalResponse();
  }

  JsonObject toJson() => const {};
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

String? _optionalString(JsonObject source, String field) {
  if (!source.containsKey(field) || source[field] == null) {
    return null;
  }

  return _requiredString(source, field);
}

bool _requiredBool(JsonObject source, String field) {
  final value = source[field];
  if (value is bool) {
    return value;
  }

  throw JsonRpcProtocolException.invalidShape('$field must be a boolean.');
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

List<String> _optionalStringList(JsonObject source, String field) {
  if (!source.containsKey(field) || source[field] == null) {
    return const [];
  }

  final value = source[field];
  if (value is List<Object?> && value.every((item) => item is String)) {
    return value.cast<String>().toList(growable: false);
  }

  throw JsonRpcProtocolException.invalidShape('$field must be a string array.');
}

List<T> _objectList<T>(
  JsonObject source,
  String field,
  T Function(Object? value) parse,
) {
  if (!source.containsKey(field) || source[field] == null) {
    return const [];
  }

  final value = source[field];
  if (value is! List<Object?>) {
    throw JsonRpcProtocolException.invalidShape('$field must be an array.');
  }

  return value.map(parse).toList(growable: false);
}

/// Same absolute-path recognition as `fs.dart`'s `_requiredAbsolutePath`
/// (POSIX, Windows drive-letter, and UNC paths) — nullable since ACP marks
/// `terminal/create`'s `cwd` optional, unlike `fs/*`'s `path`.
String? _optionalAbsolutePath(JsonObject source, String field) {
  if (!source.containsKey(field) || source[field] == null) {
    return null;
  }

  final value = source[field];
  if (value is String && value.isNotEmpty && _isAbsolutePath(value)) {
    return value;
  }

  throw JsonRpcProtocolException.invalidShape(
    '$field must be a non-empty absolute path.',
  );
}

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
