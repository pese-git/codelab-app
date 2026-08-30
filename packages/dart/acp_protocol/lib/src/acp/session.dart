import 'package:freezed_annotation/freezed_annotation.dart';

import '../json_rpc/json_value.dart';
import '../json_rpc/protocol_error.dart';
import 'acp_validation.dart';

part 'session.freezed.dart';

@freezed
sealed class SessionId with _$SessionId {
  const SessionId._();

  const factory SessionId(String value) = _SessionId;

  factory SessionId.fromJson(Object? value) {
    if (value is String && value.isNotEmpty) {
      return SessionId(value);
    }

    throw JsonRpcProtocolException.invalidShape(
      'sessionId must be a non-empty string.',
    );
  }

  String toJson() => value;
}

@freezed
sealed class EnvVariable with _$EnvVariable {
  const EnvVariable._();

  const factory EnvVariable({
    required String name,
    required String value,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _EnvVariable;

  factory EnvVariable.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'envVariable',
      allowedKeys: {'name', 'value', '_meta'},
    );

    return EnvVariable(
      name: _requiredString(source, 'name'),
      value: _requiredString(source, 'value'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {'name': name, 'value': value, if (meta != null) '_meta': meta};
  }
}

@freezed
sealed class HttpHeader with _$HttpHeader {
  const HttpHeader._();

  const factory HttpHeader({
    required String name,
    required String value,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _HttpHeader;

  factory HttpHeader.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'httpHeader',
      allowedKeys: {'name', 'value', '_meta'},
    );

    return HttpHeader(
      name: _requiredString(source, 'name'),
      value: _requiredString(source, 'value'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {'name': name, 'value': value, if (meta != null) '_meta': meta};
  }
}

@freezed
sealed class McpServer with _$McpServer {
  const McpServer._();

  const factory McpServer.stdio({
    required String name,
    required String command,
    @Default([]) List<String> args,
    @Default([]) List<EnvVariable> env,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = McpServerStdio;

  const factory McpServer.http({
    required String name,
    required String url,
    @Default([]) List<HttpHeader> headers,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = McpServerHttp;

  const factory McpServer.sse({
    required String name,
    required String url,
    @Default([]) List<HttpHeader> headers,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = McpServerSse;

  factory McpServer.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'mcpServer',
      allowedKeys: {
        'type',
        'name',
        'command',
        'args',
        'env',
        'url',
        'headers',
        '_meta',
      },
    );

    return switch (_requiredString(source, 'type')) {
      'stdio' => McpServer.stdio(
        name: _requiredString(source, 'name'),
        command: _requiredString(source, 'command'),
        args: _stringList(source, 'args'),
        env: _objectList(source, 'env', EnvVariable.fromJson),
        meta: _optionalObject(source, '_meta'),
      ),
      'http' => McpServer.http(
        name: _requiredString(source, 'name'),
        url: _requiredString(source, 'url'),
        headers: _objectList(source, 'headers', HttpHeader.fromJson),
        meta: _optionalObject(source, '_meta'),
      ),
      'sse' => McpServer.sse(
        name: _requiredString(source, 'name'),
        url: _requiredString(source, 'url'),
        headers: _objectList(source, 'headers', HttpHeader.fromJson),
        meta: _optionalObject(source, '_meta'),
      ),
      final type => throw JsonRpcProtocolException.invalidShape(
        'mcpServer.type "$type" is not supported.',
      ),
    };
  }

  JsonObject toJson() {
    return switch (this) {
      McpServerStdio(
        :final name,
        :final command,
        :final args,
        :final env,
        :final meta,
      ) =>
        {
          'type': 'stdio',
          'name': name,
          'command': command,
          'args': args,
          'env': env.map((variable) => variable.toJson()).toList(),
          '_meta': ?meta,
        },
      McpServerHttp(:final name, :final url, :final headers, :final meta) => {
        'type': 'http',
        'name': name,
        'url': url,
        'headers': headers.map((header) => header.toJson()).toList(),
        '_meta': ?meta,
      },
      McpServerSse(:final name, :final url, :final headers, :final meta) => {
        'type': 'sse',
        'name': name,
        'url': url,
        'headers': headers.map((header) => header.toJson()).toList(),
        '_meta': ?meta,
      },
    };
  }
}

@freezed
sealed class SessionModeId with _$SessionModeId {
  const SessionModeId._();

  const factory SessionModeId(String value) = _SessionModeId;

  factory SessionModeId.fromJson(Object? value) {
    if (value is String && value.isNotEmpty) {
      return SessionModeId(value);
    }

    throw JsonRpcProtocolException.invalidShape(
      'sessionModeId must be a non-empty string.',
    );
  }

  String toJson() => value;
}

@freezed
sealed class SessionMode with _$SessionMode {
  const SessionMode._();

  const factory SessionMode({
    required SessionModeId id,
    required String name,
    String? description,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _SessionMode;

  factory SessionMode.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'sessionMode',
      allowedKeys: {'id', 'name', 'description', '_meta'},
    );

    return SessionMode(
      id: SessionModeId.fromJson(source['id']),
      name: _requiredString(source, 'name'),
      description: _optionalString(source, 'description'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'id': id.toJson(),
      'name': name,
      if (description != null) 'description': description,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class SessionModeState with _$SessionModeState {
  const SessionModeState._();

  const factory SessionModeState({
    required List<SessionMode> availableModes,
    required SessionModeId currentModeId,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _SessionModeState;

  factory SessionModeState.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'sessionModeState',
      allowedKeys: {'availableModes', 'currentModeId', '_meta'},
    );

    return SessionModeState(
      availableModes: _objectList(
        source,
        'availableModes',
        SessionMode.fromJson,
      ),
      currentModeId: SessionModeId.fromJson(source['currentModeId']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'availableModes': availableModes.map((mode) => mode.toJson()).toList(),
      'currentModeId': currentModeId.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class SessionConfigId with _$SessionConfigId {
  const SessionConfigId._();

  const factory SessionConfigId(String value) = _SessionConfigId;

  factory SessionConfigId.fromJson(Object? value) {
    if (value is String && value.isNotEmpty) {
      return SessionConfigId(value);
    }

    throw JsonRpcProtocolException.invalidShape(
      'sessionConfigId must be a non-empty string.',
    );
  }

  String toJson() => value;
}

@freezed
sealed class SessionConfigValueId with _$SessionConfigValueId {
  const SessionConfigValueId._();

  const factory SessionConfigValueId(String value) = _SessionConfigValueId;

  factory SessionConfigValueId.fromJson(Object? value) {
    if (value is String && value.isNotEmpty) {
      return SessionConfigValueId(value);
    }

    throw JsonRpcProtocolException.invalidShape(
      'sessionConfigValueId must be a non-empty string.',
    );
  }

  String toJson() => value;
}

@freezed
sealed class SessionConfigSelectOption with _$SessionConfigSelectOption {
  const SessionConfigSelectOption._();

  const factory SessionConfigSelectOption({
    required SessionConfigValueId value,
    required String name,
    String? description,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _SessionConfigSelectOption;

  factory SessionConfigSelectOption.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'sessionConfigSelectOption',
      allowedKeys: {'value', 'name', 'description', '_meta'},
    );

    return SessionConfigSelectOption(
      value: SessionConfigValueId.fromJson(source['value']),
      name: _requiredString(source, 'name'),
      description: _optionalString(source, 'description'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'value': value.toJson(),
      'name': name,
      if (description != null) 'description': description,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class SessionConfigOption with _$SessionConfigOption {
  const SessionConfigOption._();

  const factory SessionConfigOption.select({
    required SessionConfigId id,
    required String name,
    required SessionConfigValueId currentValue,
    required List<SessionConfigSelectOption> options,
    String? category,
    String? description,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = SessionConfigSelect;

  factory SessionConfigOption.fromJson(Object? value) {
    final option = _tryParseSessionConfigOption(value);
    if (option == null) {
      throw JsonRpcProtocolException.invalidShape(
        'sessionConfigOption.type is not supported.',
      );
    }

    return option;
  }

  JsonObject toJson() {
    return switch (this) {
      SessionConfigSelect(
        :final id,
        :final name,
        :final currentValue,
        :final options,
        :final category,
        :final description,
        :final meta,
      ) =>
        {
          'type': 'select',
          'id': id.toJson(),
          'name': name,
          'currentValue': currentValue.toJson(),
          'options': options.map((option) => option.toJson()).toList(),
          'category': ?category,
          'description': ?description,
          '_meta': ?meta,
        },
    };
  }
}

SessionConfigOption? _tryParseSessionConfigOption(Object? value) {
  final source = requireAcpObject(
    value,
    path: 'sessionConfigOption',
    allowedKeys: {
      'type',
      'id',
      'name',
      'currentValue',
      'options',
      'category',
      'description',
      '_meta',
    },
  );
  final type = _requiredString(source, 'type');
  if (type != 'select') {
    // Per ACP ("Session Config Options" — Default Values and Graceful
    // Degradation): a client that receives an option with an unrecognized
    // `type` SHOULD ignore that option, not fail the whole configOptions
    // list. `select` is the only type ACP currently defines; anything else
    // is either a future type or a non-conformant agent.
    return null;
  }

  return SessionConfigOption.select(
    id: SessionConfigId.fromJson(source['id']),
    name: _requiredString(source, 'name'),
    currentValue: SessionConfigValueId.fromJson(source['currentValue']),
    options: _objectList(source, 'options', SessionConfigSelectOption.fromJson),
    category: _optionalString(source, 'category'),
    description: _optionalString(source, 'description'),
    meta: _optionalObject(source, '_meta'),
  );
}

/// Parses a `configOptions` JSON array, skipping any entry whose `type`
/// this client doesn't recognize instead of failing the whole list — see
/// [_tryParseSessionConfigOption].
List<SessionConfigOption> parseSessionConfigOptionList(
  JsonObject source,
  String field,
) {
  final value = source[field];
  if (value is! List<Object?>) {
    throw JsonRpcProtocolException.invalidShape('$field must be an array.');
  }

  return value
      .map(_tryParseSessionConfigOption)
      .whereType<SessionConfigOption>()
      .toList(growable: false);
}

/// Nullable-field variant of [parseSessionConfigOptionList] for responses
/// where `configOptions` itself is optional (e.g. `session/new`).
List<SessionConfigOption>? parseOptionalSessionConfigOptionList(
  JsonObject source,
  String field,
) {
  if (!source.containsKey(field) || source[field] == null) {
    return null;
  }

  return parseSessionConfigOptionList(source, field);
}

@freezed
sealed class NewSessionRequest with _$NewSessionRequest {
  const NewSessionRequest._();

  const factory NewSessionRequest({
    required String cwd,
    required List<McpServer> mcpServers,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _NewSessionRequest;

  factory NewSessionRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'newSessionRequest',
      allowedKeys: {'cwd', 'mcpServers', '_meta'},
    );

    return NewSessionRequest(
      cwd: _requiredString(source, 'cwd'),
      mcpServers: _objectList(source, 'mcpServers', McpServer.fromJson),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'cwd': cwd,
      'mcpServers': mcpServers.map((server) => server.toJson()).toList(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class NewSessionResponse with _$NewSessionResponse {
  const NewSessionResponse._();

  const factory NewSessionResponse({
    required SessionId sessionId,
    SessionModeState? modes,
    List<SessionConfigOption>? configOptions,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _NewSessionResponse;

  factory NewSessionResponse.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'newSessionResponse',
      allowedKeys: {'sessionId', 'modes', 'configOptions', '_meta'},
    );

    return NewSessionResponse(
      sessionId: SessionId.fromJson(source['sessionId']),
      modes: source['modes'] == null
          ? null
          : SessionModeState.fromJson(source['modes']),
      configOptions: parseOptionalSessionConfigOptionList(
        source,
        'configOptions',
      ),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      if (modes != null) 'modes': modes?.toJson(),
      if (configOptions != null)
        'configOptions': configOptions
            ?.map((option) => option.toJson())
            .toList(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class LoadSessionRequest with _$LoadSessionRequest {
  const LoadSessionRequest._();

  const factory LoadSessionRequest({
    required SessionId sessionId,
    required String cwd,
    required List<McpServer> mcpServers,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _LoadSessionRequest;

  factory LoadSessionRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'loadSessionRequest',
      allowedKeys: {'sessionId', 'cwd', 'mcpServers', '_meta'},
    );

    return LoadSessionRequest(
      sessionId: SessionId.fromJson(source['sessionId']),
      cwd: _requiredString(source, 'cwd'),
      mcpServers: _objectList(source, 'mcpServers', McpServer.fromJson),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'cwd': cwd,
      'mcpServers': mcpServers.map((server) => server.toJson()).toList(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class LoadSessionResponse with _$LoadSessionResponse {
  const LoadSessionResponse._();

  const factory LoadSessionResponse({
    SessionModeState? modes,
    List<SessionConfigOption>? configOptions,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _LoadSessionResponse;

  factory LoadSessionResponse.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'loadSessionResponse',
      allowedKeys: {'modes', 'configOptions', '_meta'},
    );

    return LoadSessionResponse(
      modes: source['modes'] == null
          ? null
          : SessionModeState.fromJson(source['modes']),
      configOptions: parseOptionalSessionConfigOptionList(
        source,
        'configOptions',
      ),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      if (modes != null) 'modes': modes?.toJson(),
      if (configOptions != null)
        'configOptions': configOptions
            ?.map((option) => option.toJson())
            .toList(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class SetSessionConfigOptionRequest
    with _$SetSessionConfigOptionRequest {
  const SetSessionConfigOptionRequest._();

  const factory SetSessionConfigOptionRequest({
    required SessionId sessionId,
    required SessionConfigId configId,
    required SessionConfigValueId value,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _SetSessionConfigOptionRequest;

  factory SetSessionConfigOptionRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'setSessionConfigOptionRequest',
      allowedKeys: {'sessionId', 'configId', 'value', '_meta'},
    );

    return SetSessionConfigOptionRequest(
      sessionId: SessionId.fromJson(source['sessionId']),
      configId: SessionConfigId.fromJson(source['configId']),
      value: SessionConfigValueId.fromJson(source['value']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'configId': configId.toJson(),
      'value': value.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class SetSessionConfigOptionResponse
    with _$SetSessionConfigOptionResponse {
  const SetSessionConfigOptionResponse._();

  const factory SetSessionConfigOptionResponse({
    required List<SessionConfigOption> configOptions,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _SetSessionConfigOptionResponse;

  factory SetSessionConfigOptionResponse.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'setSessionConfigOptionResponse',
      allowedKeys: {'configOptions', '_meta'},
    );

    return SetSessionConfigOptionResponse(
      configOptions: parseSessionConfigOptionList(source, 'configOptions'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'configOptions': configOptions.map((option) => option.toJson()).toList(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class ListSessionsRequest with _$ListSessionsRequest {
  const ListSessionsRequest._();

  const factory ListSessionsRequest({
    String? cwd,
    String? cursor,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _ListSessionsRequest;

  factory ListSessionsRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'listSessionsRequest',
      allowedKeys: {'cwd', 'cursor', '_meta'},
    );

    return ListSessionsRequest(
      cwd: _optionalString(source, 'cwd'),
      cursor: _optionalString(source, 'cursor'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      if (cwd != null) 'cwd': cwd,
      if (cursor != null) 'cursor': cursor,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class SessionInfo with _$SessionInfo {
  const SessionInfo._();

  const factory SessionInfo({
    required SessionId sessionId,
    required String cwd,
    String? title,
    String? updatedAt,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _SessionInfo;

  factory SessionInfo.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'sessionInfo',
      allowedKeys: {'sessionId', 'cwd', 'title', 'updatedAt', '_meta'},
    );

    return SessionInfo(
      sessionId: SessionId.fromJson(source['sessionId']),
      cwd: _requiredString(source, 'cwd'),
      title: _optionalString(source, 'title'),
      updatedAt: _optionalString(source, 'updatedAt'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'cwd': cwd,
      if (title != null) 'title': title,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class ListSessionsResponse with _$ListSessionsResponse {
  const ListSessionsResponse._();

  const factory ListSessionsResponse({
    required List<SessionInfo> sessions,
    String? nextCursor,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _ListSessionsResponse;

  factory ListSessionsResponse.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'listSessionsResponse',
      allowedKeys: {'sessions', 'nextCursor', '_meta'},
    );

    return ListSessionsResponse(
      sessions: _objectList(source, 'sessions', SessionInfo.fromJson),
      nextCursor: _optionalString(source, 'nextCursor'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessions': sessions.map((session) => session.toJson()).toList(),
      if (nextCursor != null) 'nextCursor': nextCursor,
      if (meta != null) '_meta': meta,
    };
  }
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

List<String> _stringList(JsonObject source, String field) {
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
  final value = source[field];
  if (value is! List<Object?>) {
    throw JsonRpcProtocolException.invalidShape('$field must be an array.');
  }

  return value.map(parse).toList(growable: false);
}
