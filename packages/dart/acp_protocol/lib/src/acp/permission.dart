import 'package:freezed_annotation/freezed_annotation.dart';

import '../json_rpc/json_value.dart';
import '../json_rpc/protocol_error.dart';
import 'session.dart';

part 'permission.freezed.dart';

@freezed
sealed class PermissionOptionId with _$PermissionOptionId {
  const PermissionOptionId._();

  const factory PermissionOptionId(String value) = _PermissionOptionId;

  factory PermissionOptionId.fromJson(Object? value) {
    if (value is String && value.isNotEmpty) {
      return PermissionOptionId(value);
    }

    throw JsonRpcProtocolException.invalidShape(
      'permissionOptionId must be a non-empty string.',
    );
  }

  String toJson() => value;
}

enum PermissionOptionKind {
  allowOnce('allow_once'),
  allowAlways('allow_always'),
  rejectOnce('reject_once'),
  rejectAlways('reject_always');

  const PermissionOptionKind(this.wireName);

  final String wireName;

  static PermissionOptionKind fromJson(Object? value) {
    if (value is String) {
      for (final kind in PermissionOptionKind.values) {
        if (kind.wireName == value) {
          return kind;
        }
      }
    }

    throw JsonRpcProtocolException.invalidShape(
      'permissionOption.kind has an unsupported value.',
    );
  }

  String toJson() => wireName;
}

@freezed
sealed class PermissionOption with _$PermissionOption {
  const PermissionOption._();

  const factory PermissionOption({
    required PermissionOptionId optionId,
    required String name,
    required PermissionOptionKind kind,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _PermissionOption;

  factory PermissionOption.fromJson(Object? value) {
    final source = requireJsonObject(value, path: 'permissionOption');

    return PermissionOption(
      optionId: PermissionOptionId.fromJson(source['optionId']),
      name: _requiredString(source, 'name'),
      kind: PermissionOptionKind.fromJson(source['kind']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'optionId': optionId.toJson(),
      'name': name,
      'kind': kind.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class ToolCallId with _$ToolCallId {
  const ToolCallId._();

  const factory ToolCallId(String value) = _ToolCallId;

  factory ToolCallId.fromJson(Object? value) {
    if (value is String && value.isNotEmpty) {
      return ToolCallId(value);
    }

    throw JsonRpcProtocolException.invalidShape(
      'toolCallId must be a non-empty string.',
    );
  }

  String toJson() => value;
}

enum ToolCallStatus {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed'),
  failed('failed');

  const ToolCallStatus(this.wireName);

  final String wireName;

  static ToolCallStatus fromJson(Object? value) {
    if (value is String) {
      for (final status in ToolCallStatus.values) {
        if (status.wireName == value) {
          return status;
        }
      }
    }

    throw JsonRpcProtocolException.invalidShape(
      'toolCall.status has an unsupported value.',
    );
  }

  String toJson() => wireName;
}

@freezed
sealed class ToolCallUpdate with _$ToolCallUpdate {
  const ToolCallUpdate._();

  const factory ToolCallUpdate({
    required ToolCallId toolCallId,
    String? title,
    String? kind,
    ToolCallStatus? status,
    JsonArray? content,
    JsonArray? locations,
    JsonObject? rawInput,
    JsonObject? rawOutput,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _ToolCallUpdate;

  factory ToolCallUpdate.fromJson(Object? value) {
    final source = requireJsonObject(value, path: 'toolCallUpdate');

    return ToolCallUpdate(
      toolCallId: ToolCallId.fromJson(source['toolCallId']),
      title: _optionalString(source, 'title'),
      kind: _optionalString(source, 'kind'),
      status: source['status'] == null
          ? null
          : ToolCallStatus.fromJson(source['status']),
      content: _optionalArray(source, 'content'),
      locations: _optionalArray(source, 'locations'),
      rawInput: _optionalObject(source, 'rawInput'),
      rawOutput: _optionalObject(source, 'rawOutput'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'toolCallId': toolCallId.toJson(),
      'title': ?title,
      'kind': ?kind,
      if (status case final ToolCallStatus status) 'status': status.toJson(),
      'content': ?content,
      'locations': ?locations,
      'rawInput': ?rawInput,
      'rawOutput': ?rawOutput,
      '_meta': ?meta,
    };
  }
}

@freezed
sealed class RequestPermissionRequest with _$RequestPermissionRequest {
  const RequestPermissionRequest._();

  const factory RequestPermissionRequest({
    required SessionId sessionId,
    required ToolCallUpdate toolCall,
    required List<PermissionOption> options,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _RequestPermissionRequest;

  factory RequestPermissionRequest.fromJson(Object? value) {
    final source = requireJsonObject(value, path: 'requestPermissionRequest');

    return RequestPermissionRequest(
      sessionId: SessionId.fromJson(source['sessionId']),
      toolCall: ToolCallUpdate.fromJson(source['toolCall']),
      options: _objectList(source, 'options', PermissionOption.fromJson),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'toolCall': toolCall.toJson(),
      'options': options.map((option) => option.toJson()).toList(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class RequestPermissionOutcome with _$RequestPermissionOutcome {
  const RequestPermissionOutcome._();

  const factory RequestPermissionOutcome.cancelled() =
      RequestPermissionCancelledOutcome;

  const factory RequestPermissionOutcome.selected({
    required PermissionOptionId optionId,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = SelectedPermissionOutcome;

  factory RequestPermissionOutcome.fromJson(Object? value) {
    final source = requireJsonObject(value, path: 'requestPermissionOutcome');

    return switch (_requiredString(source, 'outcome')) {
      'cancelled' => const RequestPermissionOutcome.cancelled(),
      'selected' => RequestPermissionOutcome.selected(
        optionId: PermissionOptionId.fromJson(source['optionId']),
        meta: _optionalObject(source, '_meta'),
      ),
      final outcome => throw JsonRpcProtocolException.invalidShape(
        'requestPermissionOutcome "$outcome" is not supported.',
      ),
    };
  }

  JsonObject toJson() {
    return switch (this) {
      RequestPermissionCancelledOutcome() => {'outcome': 'cancelled'},
      SelectedPermissionOutcome(:final optionId, :final meta) => {
        'outcome': 'selected',
        'optionId': optionId.toJson(),
        '_meta': ?meta,
      },
    };
  }
}

@freezed
sealed class RequestPermissionResponse with _$RequestPermissionResponse {
  const RequestPermissionResponse._();

  const factory RequestPermissionResponse({
    required RequestPermissionOutcome outcome,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _RequestPermissionResponse;

  factory RequestPermissionResponse.fromJson(Object? value) {
    final source = requireJsonObject(value, path: 'requestPermissionResponse');

    return RequestPermissionResponse(
      outcome: RequestPermissionOutcome.fromJson(source['outcome']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {'outcome': outcome.toJson(), if (meta != null) '_meta': meta};
  }
}

JsonObject? _optionalObject(JsonObject source, String field) {
  if (!source.containsKey(field) || source[field] == null) {
    return null;
  }

  return requireJsonObject(source[field], path: field);
}

JsonArray? _optionalArray(JsonObject source, String field) {
  if (!source.containsKey(field) || source[field] == null) {
    return null;
  }

  final value = source[field];
  if (value is JsonArray && isJsonValue(value)) {
    return value;
  }

  throw JsonRpcProtocolException.invalidShape('$field must be a JSON array.');
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
