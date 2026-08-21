import 'package:freezed_annotation/freezed_annotation.dart';

import '../json_rpc/json_value.dart';
import '../json_rpc/protocol_error.dart';
import 'acp_validation.dart';
import 'session.dart';

part 'prompt.freezed.dart';

enum Role {
  assistant('assistant'),
  user('user');

  const Role(this.wireName);

  final String wireName;

  static Role fromJson(Object? value) {
    if (value is String) {
      for (final role in Role.values) {
        if (role.wireName == value) {
          return role;
        }
      }
    }

    throw JsonRpcProtocolException.invalidShape(
      'role must be "assistant" or "user".',
    );
  }

  String toJson() => wireName;
}

enum StopReason {
  endTurn('end_turn'),
  maxTokens('max_tokens'),
  maxTurnRequests('max_turn_requests'),
  refusal('refusal'),
  cancelled('cancelled');

  const StopReason(this.wireName);

  final String wireName;

  static StopReason fromJson(Object? value) {
    if (value is String) {
      for (final reason in StopReason.values) {
        if (reason.wireName == value) {
          return reason;
        }
      }
    }

    throw JsonRpcProtocolException.invalidShape(
      'stopReason has an unsupported value.',
    );
  }

  String toJson() => wireName;
}

@freezed
sealed class Annotations with _$Annotations {
  const Annotations._();

  const factory Annotations({
    List<Role>? audience,
    String? lastModified,
    num? priority,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _Annotations;

  factory Annotations.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'annotations',
      allowedKeys: {'audience', 'lastModified', 'priority', '_meta'},
    );

    return Annotations(
      audience: _optionalObjectList(source, 'audience', Role.fromJson),
      lastModified: _optionalString(source, 'lastModified'),
      priority: _optionalNumber(source, 'priority'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      if (audience != null)
        'audience': audience?.map((role) => role.toJson()).toList(),
      if (lastModified != null) 'lastModified': lastModified,
      if (priority != null) 'priority': priority,
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class ContentBlock with _$ContentBlock {
  const ContentBlock._();

  const factory ContentBlock.text({
    required String text,
    Annotations? annotations,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = TextContent;

  const factory ContentBlock.image({
    required String data,
    required String mimeType,
    String? uri,
    Annotations? annotations,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = ImageContent;

  const factory ContentBlock.audio({
    required String data,
    required String mimeType,
    Annotations? annotations,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = AudioContent;

  const factory ContentBlock.resourceLink({
    required String uri,
    required String name,
    String? title,
    String? description,
    String? mimeType,
    int? size,
    Annotations? annotations,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = ResourceLink;

  const factory ContentBlock.resource({
    required EmbeddedResourceContents resource,
    Annotations? annotations,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = EmbeddedResource;

  factory ContentBlock.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'contentBlock',
      allowedKeys: {
        'type',
        'text',
        'data',
        'mimeType',
        'uri',
        'name',
        'title',
        'description',
        'size',
        'resource',
        'annotations',
        '_meta',
      },
    );

    return switch (_requiredString(source, 'type')) {
      'text' => ContentBlock.text(
        text: _requiredString(source, 'text'),
        annotations: _optionalAnnotations(source),
        meta: _optionalObject(source, '_meta'),
      ),
      'image' => ContentBlock.image(
        data: _requiredString(source, 'data'),
        mimeType: _requiredString(source, 'mimeType'),
        uri: _optionalString(source, 'uri'),
        annotations: _optionalAnnotations(source),
        meta: _optionalObject(source, '_meta'),
      ),
      'audio' => ContentBlock.audio(
        data: _requiredString(source, 'data'),
        mimeType: _requiredString(source, 'mimeType'),
        annotations: _optionalAnnotations(source),
        meta: _optionalObject(source, '_meta'),
      ),
      'resource_link' => ContentBlock.resourceLink(
        uri: _requiredString(source, 'uri'),
        name: _requiredString(source, 'name'),
        title: _optionalString(source, 'title'),
        description: _optionalString(source, 'description'),
        mimeType: _optionalString(source, 'mimeType'),
        size: _optionalInt(source, 'size'),
        annotations: _optionalAnnotations(source),
        meta: _optionalObject(source, '_meta'),
      ),
      'resource' => ContentBlock.resource(
        resource: EmbeddedResourceContents.fromJson(source['resource']),
        annotations: _optionalAnnotations(source),
        meta: _optionalObject(source, '_meta'),
      ),
      final type => throw JsonRpcProtocolException.invalidShape(
        'contentBlock.type "$type" is not supported.',
      ),
    };
  }

  JsonObject toJson() {
    return switch (this) {
      TextContent(:final text, :final annotations, :final meta) => {
        'type': 'text',
        'text': text,
        if (annotations != null) 'annotations': annotations.toJson(),
        '_meta': ?meta,
      },
      ImageContent(
        :final data,
        :final mimeType,
        :final uri,
        :final annotations,
        :final meta,
      ) =>
        {
          'type': 'image',
          'data': data,
          'mimeType': mimeType,
          'uri': ?uri,
          if (annotations != null) 'annotations': annotations.toJson(),
          '_meta': ?meta,
        },
      AudioContent(
        :final data,
        :final mimeType,
        :final annotations,
        :final meta,
      ) =>
        {
          'type': 'audio',
          'data': data,
          'mimeType': mimeType,
          if (annotations != null) 'annotations': annotations.toJson(),
          '_meta': ?meta,
        },
      ResourceLink(
        :final uri,
        :final name,
        :final title,
        :final description,
        :final mimeType,
        :final size,
        :final annotations,
        :final meta,
      ) =>
        {
          'type': 'resource_link',
          'uri': uri,
          'name': name,
          'title': ?title,
          'description': ?description,
          'mimeType': ?mimeType,
          'size': ?size,
          if (annotations != null) 'annotations': annotations.toJson(),
          '_meta': ?meta,
        },
      EmbeddedResource(:final resource, :final annotations, :final meta) => {
        'type': 'resource',
        'resource': resource.toJson(),
        if (annotations != null) 'annotations': annotations.toJson(),
        '_meta': ?meta,
      },
    };
  }
}

@freezed
sealed class EmbeddedResourceContents with _$EmbeddedResourceContents {
  const EmbeddedResourceContents._();

  const factory EmbeddedResourceContents.text({
    required String uri,
    required String text,
    String? mimeType,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = TextResourceContents;

  const factory EmbeddedResourceContents.blob({
    required String uri,
    required String blob,
    String? mimeType,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = BlobResourceContents;

  factory EmbeddedResourceContents.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'embeddedResourceContents',
      allowedKeys: {'uri', 'text', 'blob', 'mimeType', '_meta'},
    );

    if (source.containsKey('text')) {
      return EmbeddedResourceContents.text(
        uri: _requiredString(source, 'uri'),
        text: _requiredString(source, 'text'),
        mimeType: _optionalString(source, 'mimeType'),
        meta: _optionalObject(source, '_meta'),
      );
    }

    if (source.containsKey('blob')) {
      return EmbeddedResourceContents.blob(
        uri: _requiredString(source, 'uri'),
        blob: _requiredString(source, 'blob'),
        mimeType: _optionalString(source, 'mimeType'),
        meta: _optionalObject(source, '_meta'),
      );
    }

    throw JsonRpcProtocolException.invalidShape(
      'embeddedResourceContents must include text or blob.',
    );
  }

  JsonObject toJson() {
    return switch (this) {
      TextResourceContents(
        :final uri,
        :final text,
        :final mimeType,
        :final meta,
      ) =>
        {'uri': uri, 'text': text, 'mimeType': ?mimeType, '_meta': ?meta},
      BlobResourceContents(
        :final uri,
        :final blob,
        :final mimeType,
        :final meta,
      ) =>
        {'uri': uri, 'blob': blob, 'mimeType': ?mimeType, '_meta': ?meta},
    };
  }
}

@freezed
sealed class PromptRequest with _$PromptRequest {
  const PromptRequest._();

  const factory PromptRequest({
    required SessionId sessionId,
    required List<ContentBlock> prompt,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _PromptRequest;

  factory PromptRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'promptRequest',
      allowedKeys: {'sessionId', 'prompt', '_meta'},
    );

    return PromptRequest(
      sessionId: SessionId.fromJson(source['sessionId']),
      prompt: _objectList(source, 'prompt', ContentBlock.fromJson),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'prompt': prompt.map((block) => block.toJson()).toList(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class PromptResponse with _$PromptResponse {
  const PromptResponse._();

  const factory PromptResponse({
    required StopReason stopReason,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _PromptResponse;

  factory PromptResponse.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'promptResponse',
      allowedKeys: {'stopReason', '_meta'},
    );

    return PromptResponse(
      stopReason: StopReason.fromJson(source['stopReason']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {'stopReason': stopReason.toJson(), if (meta != null) '_meta': meta};
  }
}

@freezed
sealed class CancelNotification with _$CancelNotification {
  const CancelNotification._();

  const factory CancelNotification({
    required SessionId sessionId,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _CancelNotification;

  factory CancelNotification.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'cancelNotification',
      allowedKeys: {'sessionId', '_meta'},
    );

    return CancelNotification(
      sessionId: SessionId.fromJson(source['sessionId']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {'sessionId': sessionId.toJson(), if (meta != null) '_meta': meta};
  }
}

JsonObject? _optionalObject(JsonObject source, String field) {
  if (!source.containsKey(field) || source[field] == null) {
    return null;
  }

  return requireJsonObject(source[field], path: field);
}

Annotations? _optionalAnnotations(JsonObject source) {
  return source['annotations'] == null
      ? null
      : Annotations.fromJson(source['annotations']);
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

num? _optionalNumber(JsonObject source, String field) {
  if (!source.containsKey(field) || source[field] == null) {
    return null;
  }

  final value = source[field];
  if (value is num) {
    return value;
  }

  throw JsonRpcProtocolException.invalidShape('$field must be a number.');
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
