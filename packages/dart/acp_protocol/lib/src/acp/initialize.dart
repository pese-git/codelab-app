import 'package:freezed_annotation/freezed_annotation.dart';

import '../json_rpc/json_value.dart';
import '../json_rpc/protocol_error.dart';
import 'acp_validation.dart';

part 'initialize.freezed.dart';

@freezed
sealed class ProtocolVersion with _$ProtocolVersion {
  const ProtocolVersion._();

  const factory ProtocolVersion(int value) = _ProtocolVersion;

  factory ProtocolVersion.fromJson(Object? value) {
    if (value is! int || value < 0 || value > 65535) {
      throw JsonRpcProtocolException.invalidShape(
        'protocolVersion must be an integer from 0 to 65535.',
      );
    }

    return ProtocolVersion(value);
  }

  int toJson() => value;
}

@freezed
sealed class Implementation with _$Implementation {
  const Implementation._();

  const factory Implementation({
    required String name,
    required String version,
    String? title,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _Implementation;

  factory Implementation.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'implementation',
      allowedKeys: {'name', 'version', 'title', '_meta'},
    );

    return Implementation(
      name: _requiredString(source, 'name'),
      version: _requiredString(source, 'version'),
      title: _optionalString(source, 'title'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'name': name,
      'version': version,
      if (title != null) 'title': title,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class FileSystemCapabilities with _$FileSystemCapabilities {
  const FileSystemCapabilities._();

  const factory FileSystemCapabilities({
    @Default(false) bool readTextFile,
    @Default(false) bool writeTextFile,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _FileSystemCapabilities;

  factory FileSystemCapabilities.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'fs',
      allowedKeys: {'readTextFile', 'writeTextFile', '_meta'},
    );

    return FileSystemCapabilities(
      readTextFile: _optionalBool(source, 'readTextFile'),
      writeTextFile: _optionalBool(source, 'writeTextFile'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'readTextFile': readTextFile,
      'writeTextFile': writeTextFile,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class ClientCapabilities with _$ClientCapabilities {
  const ClientCapabilities._();

  const factory ClientCapabilities({
    @Default(FileSystemCapabilities()) FileSystemCapabilities fs,
    @Default(false) bool terminal,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _ClientCapabilities;

  factory ClientCapabilities.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'clientCapabilities',
      allowedKeys: {'fs', 'terminal', '_meta'},
    );

    return ClientCapabilities(
      fs: source.containsKey('fs')
          ? FileSystemCapabilities.fromJson(source['fs'])
          : const FileSystemCapabilities(),
      terminal: _optionalBool(source, 'terminal'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'fs': fs.toJson(),
      'terminal': terminal,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class McpCapabilities with _$McpCapabilities {
  const McpCapabilities._();

  const factory McpCapabilities({
    @Default(false) bool http,
    @Default(false) bool sse,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _McpCapabilities;

  factory McpCapabilities.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'mcpCapabilities',
      allowedKeys: {'http', 'sse', '_meta'},
    );

    return McpCapabilities(
      http: _optionalBool(source, 'http'),
      sse: _optionalBool(source, 'sse'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {'http': http, 'sse': sse, if (meta != null) '_meta': meta};
  }
}

@freezed
sealed class PromptCapabilities with _$PromptCapabilities {
  const PromptCapabilities._();

  const factory PromptCapabilities({
    @Default(false) bool audio,
    @Default(false) bool embeddedContext,
    @Default(false) bool image,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _PromptCapabilities;

  factory PromptCapabilities.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'promptCapabilities',
      allowedKeys: {'audio', 'embeddedContext', 'image', '_meta'},
    );

    return PromptCapabilities(
      audio: _optionalBool(source, 'audio'),
      embeddedContext: _optionalBool(source, 'embeddedContext'),
      image: _optionalBool(source, 'image'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'audio': audio,
      'embeddedContext': embeddedContext,
      'image': image,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class SessionListCapabilities with _$SessionListCapabilities {
  const SessionListCapabilities._();

  const factory SessionListCapabilities({
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _SessionListCapabilities;

  factory SessionListCapabilities.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'sessionCapabilities.list',
      allowedKeys: {'_meta'},
    );

    return SessionListCapabilities(meta: _optionalObject(source, '_meta'));
  }

  JsonObject toJson() {
    return {if (meta != null) '_meta': meta};
  }
}

@freezed
sealed class SessionCapabilities with _$SessionCapabilities {
  const SessionCapabilities._();

  const factory SessionCapabilities({
    SessionListCapabilities? list,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _SessionCapabilities;

  factory SessionCapabilities.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'sessionCapabilities',
      allowedKeys: {'list', '_meta'},
    );

    return SessionCapabilities(
      list: source['list'] == null
          ? null
          : SessionListCapabilities.fromJson(source['list']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      if (list != null) 'list': list?.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class AgentCapabilities with _$AgentCapabilities {
  const AgentCapabilities._();

  const factory AgentCapabilities({
    @Default(false) bool loadSession,
    @Default(McpCapabilities()) McpCapabilities mcpCapabilities,
    @Default(PromptCapabilities()) PromptCapabilities promptCapabilities,
    @Default(SessionCapabilities()) SessionCapabilities sessionCapabilities,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _AgentCapabilities;

  factory AgentCapabilities.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'agentCapabilities',
      allowedKeys: {
        'loadSession',
        'mcpCapabilities',
        'promptCapabilities',
        'sessionCapabilities',
        '_meta',
      },
    );

    return AgentCapabilities(
      loadSession: _optionalBool(source, 'loadSession'),
      mcpCapabilities: source.containsKey('mcpCapabilities')
          ? McpCapabilities.fromJson(source['mcpCapabilities'])
          : const McpCapabilities(),
      promptCapabilities: source.containsKey('promptCapabilities')
          ? PromptCapabilities.fromJson(source['promptCapabilities'])
          : const PromptCapabilities(),
      sessionCapabilities: source.containsKey('sessionCapabilities')
          ? SessionCapabilities.fromJson(source['sessionCapabilities'])
          : const SessionCapabilities(),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'loadSession': loadSession,
      'mcpCapabilities': mcpCapabilities.toJson(),
      'promptCapabilities': promptCapabilities.toJson(),
      'sessionCapabilities': sessionCapabilities.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class AuthMethod with _$AuthMethod {
  const AuthMethod._();

  const factory AuthMethod({
    required String id,
    required String name,
    String? description,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _AuthMethod;

  factory AuthMethod.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'authMethod',
      allowedKeys: {'type', 'id', 'name', 'description', '_meta'},
    );
    final type = source['type'];

    if (type != null && type != 'agent') {
      throw JsonRpcProtocolException.invalidShape(
        'authMethod.type must be "agent" when present.',
      );
    }

    return AuthMethod(
      id: _requiredString(source, 'id'),
      name: _requiredString(source, 'name'),
      description: _optionalString(source, 'description'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class InitializeRequest with _$InitializeRequest {
  const InitializeRequest._();

  const factory InitializeRequest({
    required ProtocolVersion protocolVersion,
    @Default(ClientCapabilities()) ClientCapabilities clientCapabilities,
    Implementation? clientInfo,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _InitializeRequest;

  factory InitializeRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'initialize request',
      allowedKeys: {
        'protocolVersion',
        'clientCapabilities',
        'clientInfo',
        '_meta',
      },
    );

    return InitializeRequest(
      protocolVersion: ProtocolVersion.fromJson(source['protocolVersion']),
      clientCapabilities: source.containsKey('clientCapabilities')
          ? ClientCapabilities.fromJson(source['clientCapabilities'])
          : const ClientCapabilities(),
      clientInfo: source['clientInfo'] == null
          ? null
          : Implementation.fromJson(source['clientInfo']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'protocolVersion': protocolVersion.toJson(),
      'clientCapabilities': clientCapabilities.toJson(),
      if (clientInfo != null) 'clientInfo': clientInfo?.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class InitializeResponse with _$InitializeResponse {
  const InitializeResponse._();

  const factory InitializeResponse({
    required ProtocolVersion protocolVersion,
    @Default(AgentCapabilities()) AgentCapabilities agentCapabilities,
    Implementation? agentInfo,
    @Default([]) List<AuthMethod> authMethods,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _InitializeResponse;

  factory InitializeResponse.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'initialize response',
      allowedKeys: {
        'protocolVersion',
        'agentCapabilities',
        'agentInfo',
        'authMethods',
        '_meta',
      },
    );
    final authMethods = source['authMethods'];

    final List<Object?>? authMethodItems;
    if (authMethods == null) {
      authMethodItems = null;
    } else if (authMethods is List<Object?>) {
      authMethodItems = authMethods;
    } else {
      throw JsonRpcProtocolException.invalidShape(
        'authMethods must be an array when present.',
      );
    }

    return InitializeResponse(
      protocolVersion: ProtocolVersion.fromJson(source['protocolVersion']),
      agentCapabilities: source.containsKey('agentCapabilities')
          ? AgentCapabilities.fromJson(source['agentCapabilities'])
          : const AgentCapabilities(),
      agentInfo: source['agentInfo'] == null
          ? null
          : Implementation.fromJson(source['agentInfo']),
      authMethods: authMethodItems == null
          ? const []
          : authMethodItems.map(AuthMethod.fromJson).toList(growable: false),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'protocolVersion': protocolVersion.toJson(),
      'agentCapabilities': agentCapabilities.toJson(),
      if (agentInfo != null) 'agentInfo': agentInfo?.toJson(),
      'authMethods': authMethods.map((method) => method.toJson()).toList(),
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

bool _optionalBool(JsonObject source, String field) {
  if (!source.containsKey(field) || source[field] == null) {
    return false;
  }

  final value = source[field];
  if (value is bool) {
    return value;
  }

  throw JsonRpcProtocolException.invalidShape('$field must be a boolean.');
}
