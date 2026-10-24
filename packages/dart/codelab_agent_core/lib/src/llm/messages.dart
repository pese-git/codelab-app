import 'package:collection/collection.dart';

import 'errors.dart';
import 'model_ref.dart';
import 'usage.dart';

/// Messages of a transcript and their canonical JSON form — the journal
/// format (`agent-core-architecture` §2.2). All types are immutable; lists
/// are unmodifiable copies. `null` fields are omitted on write; on read a
/// missing field is `null` or its default, and unknown fields are ignored.
///
/// The JSON of an assistant message keeps only the provider and id of its
/// model, so reading needs [ModelResolver] to restore the [ModelRef]
/// (design.md, D2).
typedef ModelResolver = ModelRef Function(String provider, String id);

const _deep = DeepCollectionEquality();

sealed class ContentBlock {
  const ContentBlock();

  factory ContentBlock.fromJson(Map<String, Object?> json) =>
      switch (json['type']) {
        'text' => TextContent(_string(json, 'text')),
        'thinking' => ThinkingContent(
          _string(json, 'thinking'),
          signature: json['signature'] as String?,
          redacted: json['redacted'] == true,
          api: _enumOrNull(ProviderApi.values, json['api']),
        ),
        'toolCall' => ToolCall(
          id: _string(json, 'id'),
          name: _string(json, 'name'),
          arguments: json['arguments'] is Map<String, Object?>
              ? json['arguments']! as Map<String, Object?>
              : const {},
          signature: json['signature'] as String?,
        ),
        'image' => ImageContent(
          base64: _string(json, 'data'),
          mimeType: _string(json, 'mimeType'),
        ),
        final type => throw FormatException('unknown content block "$type"'),
      };

  Map<String, Object?> toJson();
}

final class TextContent extends ContentBlock {
  const TextContent(this.text);

  final String text;

  @override
  Map<String, Object?> toJson() => {'type': 'text', 'text': text};

  @override
  bool operator ==(Object other) => other is TextContent && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'TextContent($text)';
}

final class ThinkingContent extends ContentBlock {
  const ThinkingContent(
    this.thinking, {
    this.signature,
    this.redacted = false,
    this.api,
  });

  /// With [redacted] — opaque provider data.
  final String thinking;

  /// Sent back only to its own [api].
  final String? signature;
  final bool redacted;

  /// Dialect that produced the block and the signature.
  final ProviderApi? api;

  @override
  Map<String, Object?> toJson() => {
    'type': 'thinking',
    'thinking': thinking,
    'signature': ?signature,
    if (redacted) 'redacted': true,
    'api': ?api?.name,
  };

  @override
  bool operator ==(Object other) =>
      other is ThinkingContent &&
      other.thinking == thinking &&
      other.signature == signature &&
      other.redacted == redacted &&
      other.api == api;

  @override
  int get hashCode => Object.hash(thinking, signature, redacted, api);

  @override
  String toString() => 'ThinkingContent($thinking)';
}

final class ToolCall extends ContentBlock {
  ToolCall({
    required this.id,
    required this.name,
    required Map<String, Object?> arguments,
    this.signature,
  }) : arguments = Map.unmodifiable(arguments);

  /// Unique within the whole transcript (LOOP-11).
  final String id;
  final String name;

  /// Always a parsed JSON object (LLM-6).
  final Map<String, Object?> arguments;

  /// Reasoning signature of the call; only for its own api (§17.10.3).
  final String? signature;

  @override
  Map<String, Object?> toJson() => {
    'type': 'toolCall',
    'id': id,
    'name': name,
    'arguments': arguments,
    'signature': ?signature,
  };

  @override
  bool operator ==(Object other) =>
      other is ToolCall &&
      other.id == id &&
      other.name == name &&
      _deep.equals(other.arguments, arguments) &&
      other.signature == signature;

  @override
  int get hashCode => Object.hash(id, name, _deep.hash(arguments), signature);

  @override
  String toString() => 'ToolCall($id, $name, $arguments)';
}

final class ImageContent extends ContentBlock {
  const ImageContent({required this.base64, required this.mimeType});

  /// Without the `data:` prefix.
  final String base64;

  /// `image/png` | `image/jpeg` | `image/gif` | `image/webp`.
  final String mimeType;

  @override
  Map<String, Object?> toJson() => {
    'type': 'image',
    'data': base64,
    'mimeType': mimeType,
  };

  @override
  bool operator ==(Object other) =>
      other is ImageContent &&
      other.base64 == base64 &&
      other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash(base64, mimeType);
}

enum StopReason { stop, length, toolUse, error, aborted }

sealed class Message {
  const Message();

  factory Message.fromJson(
    Map<String, Object?> json, {
    required ModelResolver resolveModel,
  }) {
    final timestamp = DateTime.parse(_string(json, 'timestamp'));
    final content = [
      for (final block in json['content'] as List<Object?>? ?? const [])
        ContentBlock.fromJson(block! as Map<String, Object?>),
    ];
    return switch (json['role']) {
      'user' => UserMessage(content, timestamp: timestamp),
      'assistant' => AssistantMessage(
        content: content,
        model: () {
          final model = json['model']! as Map<String, Object?>;
          return resolveModel(_string(model, 'provider'), _string(model, 'id'));
        }(),
        usage: json['usage'] is Map<String, Object?>
            ? Usage.fromJson(json['usage']! as Map<String, Object?>)
            : Usage.zero,
        stopReason: _enum(StopReason.values, json['stopReason'], 'stopReason'),
        rawStopReason: json['rawStopReason'] as String?,
        errorMessage: json['errorMessage'] as String?,
        errorClass: _enumOrNull(LlmErrorClass.values, json['errorClass']),
        timestamp: timestamp,
      ),
      'toolResult' => ToolResultMessage(
        toolCallId: _string(json, 'toolCallId'),
        toolName: _string(json, 'toolName'),
        content: content,
        isError: json['isError'] == true,
        timestamp: timestamp,
      ),
      final role => throw FormatException('unknown message role "$role"'),
    };
  }

  DateTime get timestamp;

  List<ContentBlock> get content;

  Map<String, Object?> toJson();
}

final class UserMessage extends Message {
  UserMessage(List<ContentBlock> content, {required this.timestamp})
    : content = List.unmodifiable(content);

  /// Only [TextContent] and [ImageContent].
  @override
  final List<ContentBlock> content;

  @override
  final DateTime timestamp;

  @override
  Map<String, Object?> toJson() => {
    'role': 'user',
    'content': [for (final block in content) block.toJson()],
    'timestamp': _timestamp(timestamp),
  };

  @override
  bool operator ==(Object other) =>
      other is UserMessage &&
      _deep.equals(other.content, content) &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(_deep.hash(content), timestamp);

  @override
  String toString() => 'UserMessage($content)';
}

final class AssistantMessage extends Message {
  AssistantMessage({
    required List<ContentBlock> content,
    required this.model,
    required this.usage,
    required this.stopReason,
    required this.timestamp,
    this.rawStopReason,
    this.errorMessage,
    this.errorClass,
  }) : content = List.unmodifiable(content);

  /// [TextContent], [ThinkingContent] and [ToolCall].
  @override
  final List<ContentBlock> content;

  /// Who actually answered (after fallback).
  final ModelRef model;
  final Usage usage;
  final StopReason stopReason;

  /// The provider finish or stop reason as is.
  final String? rawStopReason;

  /// For `error` and `aborted`, and for notes (truncation).
  final String? errorMessage;

  /// Only with [StopReason.error] and [StopReason.aborted].
  final LlmErrorClass? errorClass;

  @override
  final DateTime timestamp;

  Iterable<ToolCall> get toolCalls => content.whereType<ToolCall>();

  AssistantMessage copyWith({
    List<ContentBlock>? content,
    ModelRef? model,
    Usage? usage,
    StopReason? stopReason,
    String? rawStopReason,
    String? errorMessage,
    LlmErrorClass? errorClass,
  }) => AssistantMessage(
    content: content ?? this.content,
    model: model ?? this.model,
    usage: usage ?? this.usage,
    stopReason: stopReason ?? this.stopReason,
    rawStopReason: rawStopReason ?? this.rawStopReason,
    errorMessage: errorMessage ?? this.errorMessage,
    errorClass: errorClass ?? this.errorClass,
    timestamp: timestamp,
  );

  @override
  Map<String, Object?> toJson() => {
    'role': 'assistant',
    'content': [for (final block in content) block.toJson()],
    'model': {'provider': model.provider, 'id': model.id},
    'usage': usage.toJson(),
    'stopReason': stopReason.name,
    'rawStopReason': ?rawStopReason,
    'errorMessage': ?errorMessage,
    'errorClass': ?errorClass?.name,
    'timestamp': _timestamp(timestamp),
  };

  @override
  bool operator ==(Object other) =>
      other is AssistantMessage &&
      _deep.equals(other.content, content) &&
      other.model == model &&
      other.usage == usage &&
      other.stopReason == stopReason &&
      other.rawStopReason == rawStopReason &&
      other.errorMessage == errorMessage &&
      other.errorClass == errorClass &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(
    _deep.hash(content),
    model,
    usage,
    stopReason,
    rawStopReason,
    errorMessage,
    errorClass,
    timestamp,
  );

  @override
  String toString() =>
      'AssistantMessage(${stopReason.name}, $content'
      '${errorMessage == null ? '' : ', $errorMessage'})';
}

final class ToolResultMessage extends Message {
  ToolResultMessage({
    required this.toolCallId,
    required this.toolName,
    required List<ContentBlock> content,
    required this.isError,
    required this.timestamp,
  }) : content = List.unmodifiable(content);

  final String toolCallId, toolName;

  /// [TextContent] and [ImageContent].
  @override
  final List<ContentBlock> content;
  final bool isError;

  @override
  final DateTime timestamp;

  @override
  Map<String, Object?> toJson() => {
    'role': 'toolResult',
    'toolCallId': toolCallId,
    'toolName': toolName,
    'content': [for (final block in content) block.toJson()],
    'isError': isError,
    'timestamp': _timestamp(timestamp),
  };

  @override
  bool operator ==(Object other) =>
      other is ToolResultMessage &&
      other.toolCallId == toolCallId &&
      other.toolName == toolName &&
      _deep.equals(other.content, content) &&
      other.isError == isError &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(
    toolCallId,
    toolName,
    _deep.hash(content),
    isError,
    timestamp,
  );
}

String _timestamp(DateTime time) => time.toUtc().toIso8601String();

String _string(Map<String, Object?> json, String key) => switch (json[key]) {
  final String value => value,
  final value => throw FormatException('"$key" must be a string, got $value'),
};

T _enum<T extends Enum>(List<T> values, Object? name, String key) =>
    _enumOrNull(values, name) ??
    (throw FormatException('unknown $key "$name"'));

T? _enumOrNull<T extends Enum>(List<T> values, Object? name) =>
    name is String ? values.asNameMap()[name] : null;
