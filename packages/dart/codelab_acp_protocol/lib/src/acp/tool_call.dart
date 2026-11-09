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

/// Вид вызова инструмента (`ToolKind`, `17-Schema.md`).
///
/// Почему: вид в ACP — подсказка клиенту для отображения и оценки риска, а не
/// управляющее поле, и перечень может расти вперёд (design.md change
/// `tolerate-unknown-tool-kind`, D1). Строгий разбор терял бы вызов целиком и
/// отменял бы запрос разрешения из-за незнакомого значения.
///
/// Для чего: единый разбор вида для `tool_call`, `tool_call_update` и
/// `session/request_permission`.
///
/// Как использовать: `ToolKind.fromJson(raw)`; незнакомая строка даёт [other].
/// Исходное значение при `toJson` теряется (D3); узнать его до разбора можно
/// через [unrecognizedToolKind].
enum ToolKind {
  read('read'),
  edit('edit'),
  delete('delete'),
  move('move'),
  search('search'),
  execute('execute'),
  think('think'),
  fetch('fetch'),

  /// Смена режима сессии (`switch_mode`, `17-Schema.md`; D2). Например,
  /// выход из plan-режима (`12-Session Model.md`, «Exiting plan modes»).
  switchMode('switch_mode'),
  other('other');

  const ToolKind(this.wireName);

  /// Значение поля `kind` на wire.
  final String wireName;

  /// Разбирает вид вызова мягко (D1).
  ///
  /// Строка из перечисления даёт соответствующее значение; любая другая
  /// строка, включая пустую, — [other]: ACP трактует `other` как вид по
  /// умолчанию, а будущие виды схемы не должны ломать клиент. Не-строка
  /// нарушает форму схемы (вид — union строк), а не «будущее значение», поэтому
  /// остаётся ошибкой [JsonRpcProtocolException.invalidShape]. `null` сюда не
  /// передаётся: его обрабатывают вызывающие `parseToolCall*Json`.
  static ToolKind fromJson(Object? value) {
    if (value is! String) {
      throw JsonRpcProtocolException.invalidShape('toolKind must be a string.');
    }
    for (final kind in ToolKind.values) {
      if (kind.wireName == value) {
        return kind;
      }
    }
    return ToolKind.other;
  }

  String toJson() => wireName;
}

/// Исходное значение `kind` сырого объекта вызова, если его нет в [ToolKind].
///
/// Почему: после мягкого разбора (D1) незнакомый вид неотличим от явного
/// `other`, а протокольный слой не должен писать в журнал (`acp-boundary.md`),
/// поэтому правило «что считается известным видом» живёт здесь, рядом с
/// перечнем (D4).
///
/// Для чего: клиент по результату пишет WARN в журнал.
///
/// Как использовать: передайте сырой объект `update` или `toolCall`. Результат
/// `null`, если нет поля, оно `null`, вид известный, значение не строка или
/// аргумент не объект.
String? unrecognizedToolKind(Object? toolCall) {
  if (toolCall is! Map) {
    return null;
  }
  final kind = toolCall['kind'];
  if (kind is! String) {
    return null;
  }
  for (final known in ToolKind.values) {
    if (known.wireName == kind) {
      return null;
    }
  }
  return kind;
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
