import 'package:freezed_annotation/freezed_annotation.dart';

import '../json_rpc/json_value.dart';
import '../json_rpc/protocol_error.dart';
import 'acp_validation.dart';
import 'prompt.dart';
import 'session.dart';
import 'tool_call.dart';

part 'session_update.freezed.dart';

@freezed
sealed class AvailableCommandInput with _$AvailableCommandInput {
  const AvailableCommandInput._();

  const factory AvailableCommandInput({
    required String hint,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _AvailableCommandInput;

  factory AvailableCommandInput.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'availableCommandInput',
      allowedKeys: {'hint', '_meta'},
    );

    return AvailableCommandInput(
      hint: _requiredString(source, 'hint'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {'hint': hint, if (meta != null) '_meta': meta};
  }
}

@freezed
sealed class AvailableCommand with _$AvailableCommand {
  const AvailableCommand._();

  const factory AvailableCommand({
    required String name,
    required String description,
    AvailableCommandInput? input,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _AvailableCommand;

  factory AvailableCommand.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'availableCommand',
      allowedKeys: {'name', 'description', 'input', '_meta'},
    );

    return AvailableCommand(
      name: _requiredString(source, 'name'),
      description: _requiredString(source, 'description'),
      input: source['input'] == null
          ? null
          : AvailableCommandInput.fromJson(source['input']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'name': name,
      'description': description,
      if (input != null) 'input': input?.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

enum PlanEntryPriority {
  high('high'),
  medium('medium'),
  low('low');

  const PlanEntryPriority(this.wireName);

  final String wireName;

  static PlanEntryPriority fromJson(Object? value) {
    if (value is String) {
      for (final priority in PlanEntryPriority.values) {
        if (priority.wireName == value) {
          return priority;
        }
      }
    }

    throw JsonRpcProtocolException.invalidShape(
      'planEntry.priority has an unsupported value.',
    );
  }

  String toJson() => wireName;
}

enum PlanEntryStatus {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed');

  const PlanEntryStatus(this.wireName);

  final String wireName;

  static PlanEntryStatus fromJson(Object? value) {
    if (value is String) {
      for (final status in PlanEntryStatus.values) {
        if (status.wireName == value) {
          return status;
        }
      }
    }

    throw JsonRpcProtocolException.invalidShape(
      'planEntry.status has an unsupported value.',
    );
  }

  String toJson() => wireName;
}

@freezed
sealed class PlanEntry with _$PlanEntry {
  const PlanEntry._();

  const factory PlanEntry({
    required String content,
    required PlanEntryPriority priority,
    required PlanEntryStatus status,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _PlanEntry;

  factory PlanEntry.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'planEntry',
      allowedKeys: {'content', 'priority', 'status', '_meta'},
    );

    return PlanEntry(
      content: _requiredString(source, 'content'),
      priority: PlanEntryPriority.fromJson(source['priority']),
      status: PlanEntryStatus.fromJson(source['status']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'content': content,
      'priority': priority.toJson(),
      'status': status.toJson(),
      if (meta != null) '_meta': meta,
    };
  }
}

@freezed
sealed class SessionUpdate with _$SessionUpdate {
  const SessionUpdate._();

  const factory SessionUpdate.userMessageChunk({
    required ContentBlock content,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = UserMessageChunk;

  const factory SessionUpdate.agentMessageChunk({
    required ContentBlock content,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = AgentMessageChunk;

  const factory SessionUpdate.agentThoughtChunk({
    required ContentBlock content,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = AgentThoughtChunk;

  const factory SessionUpdate.toolCall({required ToolCall toolCall}) =
      ToolCallSessionUpdate;

  const factory SessionUpdate.toolCallUpdate({
    required ToolCallUpdate toolCallUpdate,
  }) = ToolCallUpdateSessionUpdate;

  const factory SessionUpdate.plan({
    required List<PlanEntry> entries,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = PlanUpdate;

  const factory SessionUpdate.availableCommandsUpdate({
    required List<AvailableCommand> availableCommands,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = AvailableCommandsUpdate;

  const factory SessionUpdate.currentModeUpdate({
    required SessionModeId currentModeId,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = CurrentModeUpdate;

  const factory SessionUpdate.configOptionUpdate({
    required List<SessionConfigOption> configOptions,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = ConfigOptionUpdate;

  const factory SessionUpdate.sessionInfoUpdate({
    String? title,
    String? updatedAt,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = SessionInfoUpdate;

  factory SessionUpdate.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'sessionUpdate',
      allowedKeys: {
        'sessionUpdate',
        'content',
        'toolCallId',
        'title',
        'kind',
        'status',
        'locations',
        'rawInput',
        'rawOutput',
        'entries',
        'availableCommands',
        'currentModeId',
        'configOptions',
        'updatedAt',
        '_meta',
      },
    );

    return switch (_requiredString(source, 'sessionUpdate')) {
      'user_message_chunk' => SessionUpdate.userMessageChunk(
        content: ContentBlock.fromJson(source['content']),
        meta: _optionalObject(source, '_meta'),
      ),
      'agent_message_chunk' => SessionUpdate.agentMessageChunk(
        content: ContentBlock.fromJson(source['content']),
        meta: _optionalObject(source, '_meta'),
      ),
      'agent_thought_chunk' => SessionUpdate.agentThoughtChunk(
        content: ContentBlock.fromJson(source['content']),
        meta: _optionalObject(source, '_meta'),
      ),
      'tool_call' => SessionUpdate.toolCall(
        toolCall: parseToolCallJson(
          source,
          allowedExtraRootKeys: {'sessionUpdate'},
        ),
      ),
      'tool_call_update' => SessionUpdate.toolCallUpdate(
        toolCallUpdate: parseToolCallUpdateJson(
          source,
          allowedExtraRootKeys: {'sessionUpdate'},
        ),
      ),
      'plan' => SessionUpdate.plan(
        entries: _objectList(source, 'entries', PlanEntry.fromJson),
        meta: _optionalObject(source, '_meta'),
      ),
      'available_commands_update' => SessionUpdate.availableCommandsUpdate(
        availableCommands: _objectList(
          source,
          'availableCommands',
          AvailableCommand.fromJson,
        ),
        meta: _optionalObject(source, '_meta'),
      ),
      'current_mode_update' => SessionUpdate.currentModeUpdate(
        currentModeId: SessionModeId.fromJson(source['currentModeId']),
        meta: _optionalObject(source, '_meta'),
      ),
      'config_option_update' => SessionUpdate.configOptionUpdate(
        configOptions: parseSessionConfigOptionList(source, 'configOptions'),
        meta: _optionalObject(source, '_meta'),
      ),
      'session_info_update' => SessionUpdate.sessionInfoUpdate(
        title: _optionalString(source, 'title'),
        updatedAt: _optionalString(source, 'updatedAt'),
        meta: _optionalObject(source, '_meta'),
      ),
      final update => throw JsonRpcProtocolException.invalidShape(
        'sessionUpdate "$update" is not supported.',
      ),
    };
  }

  JsonObject toJson() {
    return switch (this) {
      UserMessageChunk(:final content, :final meta) => {
        'sessionUpdate': 'user_message_chunk',
        'content': content.toJson(),
        '_meta': ?meta,
      },
      AgentMessageChunk(:final content, :final meta) => {
        'sessionUpdate': 'agent_message_chunk',
        'content': content.toJson(),
        '_meta': ?meta,
      },
      AgentThoughtChunk(:final content, :final meta) => {
        'sessionUpdate': 'agent_thought_chunk',
        'content': content.toJson(),
        '_meta': ?meta,
      },
      ToolCallSessionUpdate(:final toolCall) => {
        'sessionUpdate': 'tool_call',
        ...toolCall.toJson(),
      },
      ToolCallUpdateSessionUpdate(:final toolCallUpdate) => {
        'sessionUpdate': 'tool_call_update',
        ...toolCallUpdate.toJson(),
      },
      PlanUpdate(:final entries, :final meta) => {
        'sessionUpdate': 'plan',
        'entries': entries.map((entry) => entry.toJson()).toList(),
        '_meta': ?meta,
      },
      AvailableCommandsUpdate(:final availableCommands, :final meta) => {
        'sessionUpdate': 'available_commands_update',
        'availableCommands': availableCommands
            .map((command) => command.toJson())
            .toList(),
        '_meta': ?meta,
      },
      CurrentModeUpdate(:final currentModeId, :final meta) => {
        'sessionUpdate': 'current_mode_update',
        'currentModeId': currentModeId.toJson(),
        '_meta': ?meta,
      },
      ConfigOptionUpdate(:final configOptions, :final meta) => {
        'sessionUpdate': 'config_option_update',
        'configOptions': configOptions
            .map((option) => option.toJson())
            .toList(),
        '_meta': ?meta,
      },
      SessionInfoUpdate(:final title, :final updatedAt, :final meta) => {
        'sessionUpdate': 'session_info_update',
        'title': ?title,
        'updatedAt': ?updatedAt,
        '_meta': ?meta,
      },
    };
  }
}

@freezed
sealed class SessionNotification with _$SessionNotification {
  const SessionNotification._();

  const factory SessionNotification({
    required SessionId sessionId,
    required SessionUpdate update,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _SessionNotification;

  factory SessionNotification.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'sessionNotification',
      allowedKeys: {'sessionId', 'update', '_meta'},
    );

    return SessionNotification(
      sessionId: SessionId.fromJson(source['sessionId']),
      update: SessionUpdate.fromJson(source['update']),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'sessionId': sessionId.toJson(),
      'update': update.toJson(),
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
