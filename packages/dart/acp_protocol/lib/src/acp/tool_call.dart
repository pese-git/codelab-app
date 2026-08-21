import 'package:freezed_annotation/freezed_annotation.dart';

import '../json_rpc/json_value.dart';
import '../json_rpc/protocol_error.dart';
import 'acp_validation.dart';
import 'prompt.dart';

part 'tool_call.freezed.dart';

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

enum ToolKind {
  read('read'),
  edit('edit'),
  delete('delete'),
  move('move'),
  search('search'),
  execute('execute'),
  think('think'),
  fetch('fetch'),
  other('other');

  const ToolKind(this.wireName);

  final String wireName;

  static ToolKind fromJson(Object? value) {
    if (value is String) {
      for (final kind in ToolKind.values) {
        if (kind.wireName == value) {
          return kind;
        }
      }
    }

    throw JsonRpcProtocolException.invalidShape(
      'toolKind has an unsupported value.',
    );
  }

  String toJson() => wireName;
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
sealed class Diff with _$Diff {
  const Diff._();

  const factory Diff({
    required String path,
    String? oldText,
    required String newText,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _Diff;

  factory Diff.fromJson(Object? value) {
    return parseDiffJson(value);
  }

  JsonObject toJson() {
    return {
      'path': path,
      if (oldText != null) 'oldText': oldText,
      'newText': newText,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class ToolCallLocation with _$ToolCallLocation {
  const ToolCallLocation._();

  const factory ToolCallLocation({
    required String path,
    int? line,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _ToolCallLocation;

  factory ToolCallLocation.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'toolCallLocation',
      allowedKeys: {'path', 'line', '_meta'},
    );

    return ToolCallLocation(
      path: _requiredString(source, 'path'),
      line: _optionalNonNegativeInt(source, 'line'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'path': path,
      if (line != null) 'line': line,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class ToolCallContent with _$ToolCallContent {
  const ToolCallContent._();

  const factory ToolCallContent.content({
    required ContentBlock content,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = ToolCallContentBlock;

  const factory ToolCallContent.diff({required Diff diff}) = ToolCallDiff;

  const factory ToolCallContent.terminal({
    required String terminalId,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = ToolCallTerminal;

  factory ToolCallContent.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'toolCallContent',
      allowedKeys: {
        'type',
        'content',
        'path',
        'oldText',
        'newText',
        'terminalId',
        '_meta',
      },
    );

    return switch (_requiredString(source, 'type')) {
      'content' => ToolCallContent.content(
        content: ContentBlock.fromJson(source['content']),
        meta: _optionalObject(source, '_meta'),
      ),
      'diff' => ToolCallContent.diff(
        diff: parseDiffJson(source, allowedExtraRootKeys: {'type'}),
      ),
      'terminal' => ToolCallContent.terminal(
        terminalId: _requiredString(source, 'terminalId'),
        meta: _optionalObject(source, '_meta'),
      ),
      final type => throw JsonRpcProtocolException.invalidShape(
        'toolCallContent.type "$type" is not supported.',
      ),
    };
  }

  JsonObject toJson() {
    return switch (this) {
      ToolCallContentBlock(:final content, :final meta) => {
        'type': 'content',
        'content': content.toJson(),
        '_meta': ?meta,
      },
      ToolCallDiff(:final diff) => {'type': 'diff', ...diff.toJson()},
      ToolCallTerminal(:final terminalId, :final meta) => {
        'type': 'terminal',
        'terminalId': terminalId,
        '_meta': ?meta,
      },
    };
  }
}

Diff parseDiffJson(
  Object? value, {
  Set<String> allowedExtraRootKeys = const {},
}) {
  final source = requireAcpObject(
    value,
    path: 'diff',
    allowedKeys: {
      'path',
      'oldText',
      'newText',
      '_meta',
      ...allowedExtraRootKeys,
    },
  );

  return Diff(
    path: _requiredString(source, 'path'),
    oldText: _optionalString(source, 'oldText'),
    newText: _requiredString(source, 'newText'),
    meta: _optionalObject(source, '_meta'),
  );
}

@freezed
sealed class ToolCall with _$ToolCall {
  const ToolCall._();

  const factory ToolCall({
    required ToolCallId toolCallId,
    required String title,
    @Default(ToolKind.other) ToolKind kind,
    @Default(ToolCallStatus.pending) ToolCallStatus status,
    List<ToolCallContent>? content,
    List<ToolCallLocation>? locations,
    JsonObject? rawInput,
    JsonObject? rawOutput,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _ToolCall;

  factory ToolCall.fromJson(Object? value) {
    return parseToolCallJson(value);
  }

  JsonObject toJson() {
    return {
      'toolCallId': toolCallId.toJson(),
      'title': title,
      'kind': kind.toJson(),
      'status': status.toJson(),
      if (content != null)
        'content': content?.map((item) => item.toJson()).toList(),
      if (locations != null)
        'locations': locations?.map((location) => location.toJson()).toList(),
      if (rawInput != null) 'rawInput': rawInput,
      if (rawOutput != null) 'rawOutput': rawOutput,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class ToolCallUpdate with _$ToolCallUpdate {
  const ToolCallUpdate._();

  const factory ToolCallUpdate({
    required ToolCallId toolCallId,
    String? title,
    ToolKind? kind,
    ToolCallStatus? status,
    List<ToolCallContent>? content,
    List<ToolCallLocation>? locations,
    JsonObject? rawInput,
    JsonObject? rawOutput,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _ToolCallUpdate;

  factory ToolCallUpdate.fromJson(Object? value) {
    return parseToolCallUpdateJson(value);
  }

  JsonObject toJson() {
    return {
      'toolCallId': toolCallId.toJson(),
      if (title != null) 'title': title,
      if (kind != null) 'kind': kind?.toJson(),
      if (status != null) 'status': status?.toJson(),
      if (content != null)
        'content': content?.map((item) => item.toJson()).toList(),
      if (locations != null)
        'locations': locations?.map((location) => location.toJson()).toList(),
      if (rawInput != null) 'rawInput': rawInput,
      if (rawOutput != null) 'rawOutput': rawOutput,
      if (meta != null) '_meta': meta,
    };
  }
}

ToolCall parseToolCallJson(
  Object? value, {
  Set<String> allowedExtraRootKeys = const {},
}) {
  final source = requireAcpObject(
    value,
    path: 'toolCall',
    allowedKeys: {
      'toolCallId',
      'title',
      'kind',
      'status',
      'content',
      'locations',
      'rawInput',
      'rawOutput',
      '_meta',
      ...allowedExtraRootKeys,
    },
  );

  return ToolCall(
    toolCallId: ToolCallId.fromJson(source['toolCallId']),
    title: _requiredString(source, 'title'),
    kind: source['kind'] == null
        ? ToolKind.other
        : ToolKind.fromJson(source['kind']),
    status: source['status'] == null
        ? ToolCallStatus.pending
        : ToolCallStatus.fromJson(source['status']),
    content: _optionalObjectList(source, 'content', ToolCallContent.fromJson),
    locations: _optionalObjectList(
      source,
      'locations',
      ToolCallLocation.fromJson,
    ),
    rawInput: _optionalObject(source, 'rawInput'),
    rawOutput: _optionalObject(source, 'rawOutput'),
    meta: _optionalObject(source, '_meta'),
  );
}

ToolCallUpdate parseToolCallUpdateJson(
  Object? value, {
  Set<String> allowedExtraRootKeys = const {},
}) {
  final source = requireAcpObject(
    value,
    path: 'toolCallUpdate',
    allowedKeys: {
      'toolCallId',
      'title',
      'kind',
      'status',
      'content',
      'locations',
      'rawInput',
      'rawOutput',
      '_meta',
      ...allowedExtraRootKeys,
    },
  );

  return ToolCallUpdate(
    toolCallId: ToolCallId.fromJson(source['toolCallId']),
    title: _optionalString(source, 'title'),
    kind: source['kind'] == null ? null : ToolKind.fromJson(source['kind']),
    status: source['status'] == null
        ? null
        : ToolCallStatus.fromJson(source['status']),
    content: _optionalObjectList(source, 'content', ToolCallContent.fromJson),
    locations: _optionalObjectList(
      source,
      'locations',
      ToolCallLocation.fromJson,
    ),
    rawInput: _optionalObject(source, 'rawInput'),
    rawOutput: _optionalObject(source, 'rawOutput'),
    meta: _optionalObject(source, '_meta'),
  );
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

int? _optionalNonNegativeInt(JsonObject source, String field) {
  if (!source.containsKey(field) || source[field] == null) {
    return null;
  }

  final value = source[field];
  if (value is int && value >= 0) {
    return value;
  }

  throw JsonRpcProtocolException.invalidShape(
    '$field must be a non-negative integer.',
  );
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

List<T>? _optionalObjectList<T>(
  JsonObject source,
  String field,
  T Function(Object? value) parse,
) {
  if (!source.containsKey(field) || source[field] == null) {
    return null;
  }

  return _objectList(source, field, parse);
}
