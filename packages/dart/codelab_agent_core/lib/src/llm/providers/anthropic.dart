import 'dart:convert';
import 'dart:math';

import '../../cancel/cancel_token.dart';
import '../../util/logger.dart';
import '../errors.dart';
import '../events.dart';
import '../messages.dart';
import '../model_ref.dart';
import '../provider_config.dart';
import '../sse.dart';
import '../stream_function.dart';
import '../stream_state.dart';
import '../usage.dart';
import 'http_support.dart';

/// Adapter of the Anthropic Messages API with streaming
/// (`agent-core-architecture` §2.8).
StreamFunction anthropicStreamFunction(
  ProviderConfig config,
  CoreLlmServices services,
) =>
    (model, context, {cancel}) => runProvider(
      model,
      cancel,
      services.clock,
      (state) =>
          _AnthropicTurn(config, services, model, state).run(context, cancel),
      classify: classifyException,
    );

const _ephemeral = {'type': 'ephemeral'};

const _imageOmitted =
    '[image omitted: the current model does not accept images]';

/// Reasoning budgets of §2.8 and §2.12.3 for [ThinkingMode.budget].
const _thinkingBudget = {
  ReasoningEffort.low: 2048,
  ReasoningEffort.medium: 8192,
  ReasoningEffort.high: 16384,
};

final class _AnthropicTurn {
  _AnthropicTurn(this.config, this.services, this.model, this.state);

  final ProviderConfig config;
  final CoreLlmServices services;
  final ModelRef model;
  final ProviderStreamState state;

  /// Block index of the provider → our block index.
  final _blocks = <int, int>{};

  Future<void> run(LlmContext context, CancelToken? cancel) async {
    final response = await sendStreaming(
      services.httpClient,
      method: 'POST',
      url: endpointOf(config.baseUrl, 'v1/messages'),
      headers: {
        'content-type': 'application/json',
        'accept': 'text/event-stream',
        'anthropic-version': config.anthropicVersion,
        if (config.anthropicBeta.isNotEmpty)
          'anthropic-beta': config.anthropicBeta.join(','),
        if (config.apiKey case final key? when key.isNotEmpty)
          config.authHeader: config.authHeader.toLowerCase() == 'authorization'
              ? 'Bearer $key'
              : key,
        ...config.headers,
      },
      body: jsonEncode(buildAnthropicBody(model, context)),
      cancel: cancel,
      providerName: config.name,
    );
    if (!await acceptEventStream(response, state, config)) {
      return;
    }

    state.start();
    await for (final event in responseText(
      response,
      cancel,
    ).transform(const SseDecoder())) {
      final data = jsonDecode(event.data);
      if (data is! Map<String, Object?>) {
        continue;
      }
      if (!_handle(event.event ?? data['type'] as String? ?? '', data)) {
        return;
      }
    }
    state.fail(LlmErrorClass.network, 'stream ended before message_stop');
  }

  /// `false` when the event ended the stream.
  bool _handle(String type, Map<String, Object?> data) {
    switch (type) {
      case 'message_start':
        final message = data['message'];
        if (message is Map<String, Object?> &&
            message['usage'] is Map<String, Object?>) {
          final usage = message['usage']! as Map<String, Object?>;
          state.setUsage(
            Usage(
              input: _int(usage['input_tokens']),
              output: _int(usage['output_tokens']),
              cacheRead: _int(usage['cache_read_input_tokens']),
              cacheWrite: _int(usage['cache_creation_input_tokens']),
            ),
          );
        }
      case 'content_block_start':
        _blockStart(data);
      case 'content_block_delta':
        final index = _blocks[data['index']];
        final delta = data['delta'];
        if (index == null || delta is! Map<String, Object?>) {
          return true;
        }
        switch (delta['type']) {
          case 'text_delta':
            state.append(index, '${delta['text'] ?? ''}');
          case 'thinking_delta':
            state.append(index, '${delta['thinking'] ?? ''}');
          case 'signature_delta':
            state.setSignature(index, '${delta['signature'] ?? ''}');
          case 'input_json_delta':
            state.append(index, '${delta['partial_json'] ?? ''}');
        }
      case 'content_block_stop':
        if (_blocks[data['index']] case final index?) {
          state.closeBlock(index);
        }
      case 'message_delta':
        if (data['delta'] case {'stop_reason': final String reason}) {
          state.setRawStopReason(reason);
        }
        if (data['usage'] case {'output_tokens': final num output}) {
          final usage = state.usage;
          state.setUsage(
            Usage(
              input: usage.input,
              output: output.toInt(),
              cacheRead: usage.cacheRead,
              cacheWrite: usage.cacheWrite,
            ),
          );
        }
      case 'message_stop':
        _finish();
        return false;
      case 'ping':
        break;
      case 'error':
        final error = data['error'] is Map<String, Object?>
            ? data['error']! as Map<String, Object?>
            : const <String, Object?>{};
        state.fail(classifyStreamError(error), streamErrorText(config, error));
        return false;
      default:
        services.logger.log(
          LogLevel.debug,
          'llm.stream.event_ignored',
          fields: {'provider': config.name, 'event': type},
        );
    }
    return true;
  }

  void _blockStart(Map<String, Object?> data) {
    final providerIndex = data['index'];
    final block = data['content_block'];
    if (providerIndex is! int || block is! Map<String, Object?>) {
      return;
    }
    switch (block['type']) {
      case 'text':
        final index = state.openBlock(BlockKind.text);
        _blocks[providerIndex] = index;
        state.append(index, '${block['text'] ?? ''}');
      case 'thinking':
        final index = state.openBlock(
          BlockKind.thinking,
          api: ProviderApi.anthropicMessages,
        );
        _blocks[providerIndex] = index;
        state.append(index, '${block['thinking'] ?? ''}');
      case 'redacted_thinking':
        final index = state.openBlock(
          BlockKind.thinking,
          api: ProviderApi.anthropicMessages,
          redacted: true,
        );
        _blocks[providerIndex] = index;
        state.append(index, '${block['data'] ?? ''}');
      case 'tool_use':
        _blocks[providerIndex] = state.openBlock(
          BlockKind.toolCall,
          id: block['id'] as String?,
          name: block['name'] as String?,
        );
    }
  }

  void _finish() {
    final raw = state.rawStopReason;
    switch (raw) {
      case 'end_turn' || 'stop_sequence':
        state.finish(StopReason.stop);
      case 'tool_use':
        state.finish(StopReason.toolUse);
      case 'max_tokens':
        state.finish(StopReason.length);
      case 'model_context_window_exceeded':
        state.fail(LlmErrorClass.overflow, 'Provider stop_reason: $raw');
      case 'refusal':
        state.fail(LlmErrorClass.terminalFinish, 'Provider stop_reason: $raw');
      default:
        services.logger.log(
          LogLevel.warning,
          'llm.finish_reason.unknown',
          fields: {
            'provider': config.name,
            'model': model.id,
            'finish_reason': raw,
          },
        );
        state.fail(LlmErrorClass.unknown, 'Provider stop_reason: $raw');
    }
  }
}

int _int(Object? value) => value is num ? value.toInt() : 0;

/// The request body of §2.8: three cache marks at most (system, the last
/// tool, the last block of the last user message of the transcript).
Map<String, Object?> buildAnthropicBody(ModelRef model, LlmContext context) {
  final effort = model.supportsReasoning ? model.reasoningEffort : null;
  final adaptive = model.thinkingMode == ThinkingMode.adaptive;
  final budget = effort == null || adaptive
      ? null
      : min(_thinkingBudget[effort]!, model.maxOutputTokens - 1024);
  return {
    'model': model.id,
    'max_tokens': model.maxOutputTokens,
    if (context.systemPrompt.isNotEmpty)
      'system': [
        {
          'type': 'text',
          'text': context.systemPrompt,
          'cache_control': _ephemeral,
        },
      ],
    'messages': _messages(model, context.messages),
    if (context.tools.isNotEmpty) ...{
      'tools': [
        for (final (i, tool) in context.tools.indexed)
          {
            'name': tool.name,
            'description': tool.description,
            'input_schema': tool.parameters,
            if (i == context.tools.length - 1) 'cache_control': _ephemeral,
          },
      ],
      'tool_choice': {'type': 'auto'},
    },
    'stream': true,
    if (effort != null && adaptive) ...{
      'thinking': {'type': 'adaptive', 'display': 'summarized'},
      'output_config': {'effort': effort.name},
    },
    if (budget != null && budget >= 1024)
      'thinking': {'type': 'enabled', 'budget_tokens': budget},
  };
}

List<Map<String, Object?>> _messages(ModelRef model, List<Message> messages) {
  final out = <(String, List<Map<String, Object?>>)>[];

  void add(String role, List<Map<String, Object?>> blocks) {
    if (blocks.isEmpty) {
      return;
    }
    if (out.isNotEmpty && out.last.$1 == role) {
      out.last.$2.addAll(blocks);
    } else {
      out.add((role, [...blocks]));
    }
  }

  for (final message in messages) {
    switch (message) {
      case UserMessage(:final content):
        add('user', [for (final block in content) ?_userBlock(block, model)]);
      case AssistantMessage(:final content):
        add('assistant', [
          for (final block in content) ?_assistantBlock(block),
        ]);
      case ToolResultMessage(:final toolCallId, :final content, :final isError):
        add('user', [
          {
            'type': 'tool_result',
            'tool_use_id': normalizeToolCallId(toolCallId),
            'content': [for (final block in content) ?_userBlock(block, model)],
            'is_error': isError,
          },
        ]);
    }
  }

  for (final (role, blocks) in out.reversed) {
    if (role == 'user') {
      blocks.last = {...blocks.last, 'cache_control': _ephemeral};
      break;
    }
  }
  return [
    for (final (role, blocks) in out) {'role': role, 'content': blocks},
  ];
}

Map<String, Object?>? _userBlock(ContentBlock block, ModelRef model) =>
    switch (block) {
      TextContent(:final text) when text.isEmpty => null,
      TextContent(:final text) => {'type': 'text', 'text': text},
      ImageContent(:final base64, :final mimeType) when model.supportsImages =>
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': mimeType, 'data': base64},
        },
      ImageContent() => {'type': 'text', 'text': _imageOmitted},
      _ => null,
    };

/// Reasoning of other dialects or without a signature is dropped; the
/// transcript keeps it (§2.8, general rules).
Map<String, Object?>? _assistantBlock(ContentBlock block) => switch (block) {
  TextContent(:final text) when text.isEmpty => null,
  TextContent(:final text) => {'type': 'text', 'text': text},
  ThinkingContent(api: ProviderApi.anthropicMessages, redacted: true) => {
    'type': 'redacted_thinking',
    'data': block.thinking,
  },
  ThinkingContent(
    api: ProviderApi.anthropicMessages,
    :final thinking,
    signature: final String signature,
  )
      when signature.isNotEmpty =>
    {'type': 'thinking', 'thinking': thinking, 'signature': signature},
  ThinkingContent() => null,
  ToolCall(:final id, :final name, :final arguments) => {
    'type': 'tool_use',
    'id': normalizeToolCallId(id),
    'name': name,
    'input': arguments,
  },
  ImageContent() => null,
};

/// Characters outside `[A-Za-z0-9_-]` become `_`, at most 64 characters;
/// the same function for `tool_use.id` and `tool_result.tool_use_id`.
String normalizeToolCallId(String id) {
  final normalized = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return normalized.length > 64 ? normalized.substring(0, 64) : normalized;
}
