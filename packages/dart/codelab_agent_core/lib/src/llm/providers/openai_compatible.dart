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

/// Adapter of `POST {baseUrl}/chat/completions` with SSE streaming:
/// OpenAI, OpenRouter, Ollama, LM Studio, llama.cpp server, LiteLLM Proxy
/// and any compatible server (`agent-core-architecture` §2.7).
StreamFunction openAiCompatibleStreamFunction(
  ProviderConfig config,
  CoreLlmServices services,
) =>
    (model, context, {cancel}) => runProvider(
      model,
      cancel,
      services.clock,
      (state) =>
          _OpenAiTurn(config, services, model, state).run(context, cancel),
      classify: classifyException,
    );

/// Finish reasons of §2.7.
const _stopReasons = {'stop', 'eos', 'end_turn', 'stop_sequence'};
const _lengthReasons = {'length', 'max_tokens'};
const _toolReasons = {'tool_calls', 'function_call'};
const _refusalReasons = {'content_filter', 'refusal', 'safety'};

const _imageOmitted =
    '[image omitted: the current model does not accept images]';

final class _OpenAiTurn {
  _OpenAiTurn(this.config, this.services, this.model, this.state);

  final ProviderConfig config;
  final CoreLlmServices services;
  final ModelRef model;
  final ProviderStreamState state;

  /// The open text or thinking block that receives the next fragment.
  int? _current;
  BlockKind? _currentKind;
  final _byIndex = <int, int>{};
  final _byId = <String, int>{};
  final _calls = <int>[];
  var _sawEvent = false;

  Future<void> run(LlmContext context, CancelToken? cancel) async {
    final response = await sendStreaming(
      services.httpClient,
      method: 'POST',
      url: endpointOf(config.baseUrl, 'chat/completions'),
      headers: {
        'content-type': 'application/json',
        'accept': 'text/event-stream',
        if (config.apiKey case final key? when key.isNotEmpty)
          config.authHeader: config.authHeader.toLowerCase() == 'authorization'
              ? 'Bearer $key'
              : key,
        ...config.headers,
      },
      body: jsonEncode(buildOpenAiBody(config, model, context)),
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
      _sawEvent = true;
      if (event.data.trim() == '[DONE]') {
        break;
      }
      final chunk = jsonDecode(event.data);
      if (chunk is! Map<String, Object?>) {
        continue;
      }
      if (!_handle(chunk)) {
        return;
      }
    }
    _complete();
  }

  /// `false` when the chunk ended the stream.
  bool _handle(Map<String, Object?> chunk) {
    if (chunk['error'] case final Map<String, Object?> error) {
      state.fail(classifyStreamError(error), streamErrorText(config, error));
      return false;
    }
    if (chunk['usage'] case final Map<String, Object?> usage) {
      state.setUsage(_usage(usage));
    }
    final choices = chunk['choices'];
    if (choices is! List<Object?> || choices.isEmpty) {
      return true;
    }
    final choice = choices.first;
    if (choice is! Map<String, Object?>) {
      return true;
    }
    if (choice['delta'] case final Map<String, Object?> delta) {
      final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
      if (reasoning is String && reasoning.isNotEmpty) {
        state.append(_textLike(BlockKind.thinking), reasoning);
      }
      final content = delta['content'];
      if (content is String && content.isNotEmpty) {
        state.append(_textLike(BlockKind.text), content);
      }
      if (delta['tool_calls'] case final List<Object?> calls) {
        _toolCalls(calls);
      }
    }
    if (choice['finish_reason'] case final String reason) {
      state.setRawStopReason(reason);
    }
    return true;
  }

  int _textLike(BlockKind kind) {
    if (_current case final index? when _currentKind == kind) {
      return index;
    }
    _closeCurrent();
    final index = state.openBlock(
      kind,
      api: kind == BlockKind.thinking ? ProviderApi.openaiChat : null,
    );
    _current = index;
    _currentKind = kind;
    return index;
  }

  void _closeCurrent() {
    if (_current case final index?) {
      state.closeBlock(index);
    }
    _current = null;
    _currentKind = null;
  }

  /// Accumulation of tool calls by provider index and id (§2.7).
  void _toolCalls(List<Object?> items) {
    _closeCurrent();
    for (final (position, raw) in items.indexed) {
      if (raw is! Map<String, Object?>) {
        continue;
      }
      final key = raw['index'] is int ? raw['index']! as int : position;
      final id = raw['id'] is String ? raw['id']! as String : '';
      final function = raw['function'] is Map<String, Object?>
          ? raw['function']! as Map<String, Object?>
          : const <String, Object?>{};
      final name = function['name'] is String
          ? function['name']! as String
          : '';
      final arguments = function['arguments'] is String
          ? function['arguments']! as String
          : '';

      var block = _byIndex[key];
      final foundByIndex = block != null;
      block ??= id.isEmpty ? null : _byId[id];
      if (block != null &&
          foundByIndex &&
          id.isNotEmpty &&
          id != state.idOf(block) &&
          state.nameOf(block).isNotEmpty &&
          state.argumentsOf(block).isNotEmpty) {
        block = null;
      }
      if (block == null) {
        final index = state.openBlock(BlockKind.toolCall, name: name, id: id);
        block = index;
        if (id.isEmpty) {
          state.setId(index, 'call_$index');
        }
        _byIndex[key] = index;
        if (id.isNotEmpty) {
          _byId[id] = index;
        }
        _calls.add(index);
      } else if (name.isNotEmpty) {
        final current = state.nameOf(block);
        if (current.isEmpty) {
          state.setName(block, name);
        } else if (name != current) {
          state.setName(block, '$current$name');
        }
      }
      if (arguments.isNotEmpty) {
        final accumulated = state.argumentsOf(block);
        if (accumulated.isEmpty || arguments != accumulated) {
          state.append(block, arguments);
        }
      }
    }
  }

  void _complete() {
    final raw = state.rawStopReason;
    final hasCalls = _calls.isNotEmpty;
    if (!_sawEvent) {
      state.fail(
        LlmErrorClass.network,
        'provider returned an empty event stream; check baseUrl and model id',
      );
      return;
    }
    if (raw == null) {
      for (final index in state.openBlocks.toList()) {
        state.closeBlock(index);
      }
      if (state.blockCount == 0) {
        state.fail(
          LlmErrorClass.network,
          'stream ended without finish_reason and without content',
        );
        return;
      }
      final truncatedCall = _calls.any(state.argumentsInvalid);
      state.finish(
        truncatedCall
            ? StopReason.length
            : (hasCalls ? StopReason.toolUse : StopReason.stop),
        note:
            'stream ended without finish_reason; the response may be truncated',
      );
      return;
    }
    if (_stopReasons.contains(raw)) {
      state.finish(hasCalls ? StopReason.toolUse : StopReason.stop);
    } else if (_lengthReasons.contains(raw)) {
      state.finish(StopReason.length);
    } else if (_toolReasons.contains(raw)) {
      state.finish(StopReason.toolUse);
    } else if (_refusalReasons.contains(raw)) {
      state.fail(LlmErrorClass.terminalFinish, 'Provider finish_reason: $raw');
    } else {
      services.logger.log(
        LogLevel.warning,
        'llm.finish_reason.unknown',
        fields: {
          'provider': config.name,
          'model': model.id,
          'finish_reason': raw,
        },
      );
      state.fail(LlmErrorClass.unknown, 'Provider finish_reason: $raw');
    }
  }
}

/// Usage of an OpenAI-compatible answer: `input` without cached tokens.
Usage _usage(Map<String, Object?> json) {
  int value(Object? v) => v is num ? v.toInt() : 0;
  final prompt = value(json['prompt_tokens']);
  final details = json['prompt_tokens_details'] is Map<String, Object?>
      ? json['prompt_tokens_details']! as Map<String, Object?>
      : const <String, Object?>{};
  final cacheRead = details.containsKey('cached_tokens')
      ? value(details['cached_tokens'])
      : value(json['prompt_cache_hit_tokens']);
  final cacheWrite = value(details['cache_write_tokens']);
  final completionDetails =
      json['completion_tokens_details'] is Map<String, Object?>
      ? json['completion_tokens_details']! as Map<String, Object?>
      : const <String, Object?>{};
  final reasoning = completionDetails['reasoning_tokens'];
  return Usage(
    input: max(0, prompt - cacheRead - cacheWrite),
    output: value(json['completion_tokens']),
    cacheRead: cacheRead,
    cacheWrite: cacheWrite,
    reasoning: reasoning is num ? reasoning.toInt() : null,
  );
}

/// The request body of §2.7. Keys keep their insertion order and
/// `jsonEncode` writes no spaces, so the same snapshot gives the same
/// bytes (LLM-11).
Map<String, Object?> buildOpenAiBody(
  ProviderConfig config,
  ModelRef model,
  LlmContext context,
) {
  final effort = model.supportsReasoning ? model.reasoningEffort : null;
  return {
    'model': model.id,
    'messages': _messages(config, model, context),
    if (context.tools.isNotEmpty) ...{
      'tools': [
        for (final tool in context.tools)
          {
            'type': 'function',
            'function': {
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.parameters,
            },
          },
      ],
      'tool_choice': 'auto',
    },
    'stream': true,
    if (config.includeUsage) 'stream_options': {'include_usage': true},
    ?config.maxTokensField: model.maxOutputTokens,
    if (effort != null)
      ...switch (config.reasoningFormat) {
        ReasoningFormat.openai => {'reasoning_effort': effort.name},
        ReasoningFormat.openrouter => {
          'reasoning': {'effort': effort.name},
        },
        ReasoningFormat.none => const <String, Object?>{},
      },
    if (config.promptCacheKey) 'prompt_cache_key': ?context.cacheKey,
  };
}

List<Map<String, Object?>> _messages(
  ProviderConfig config,
  ModelRef model,
  LlmContext context,
) {
  final out = <Map<String, Object?>>[
    if (context.systemPrompt.isNotEmpty)
      {'role': config.systemRole, 'content': context.systemPrompt},
  ];
  final pendingImages = <(String, List<ImageContent>)>[];

  void flushImages() {
    if (pendingImages.isEmpty) {
      return;
    }
    out.add({
      'role': 'user',
      'content': [
        for (final (id, images) in pendingImages) ...[
          {'type': 'text', 'text': 'Images returned by tool call $id:'},
          for (final image in images) _imagePart(image, model),
        ],
      ],
    });
    pendingImages.clear();
  }

  for (final message in context.messages) {
    if (message is! ToolResultMessage) {
      flushImages();
    }
    switch (message) {
      case UserMessage(:final content):
        out.add({'role': 'user', 'content': _userContent(content, model)});
      case AssistantMessage(:final content, :final stopReason):
        final text = content.whereType<TextContent>().map((b) => b.text).join();
        final calls = content.whereType<ToolCall>().toList();
        final failed =
            stopReason == StopReason.error || stopReason == StopReason.aborted;
        if (failed && text.isEmpty && calls.isEmpty) {
          continue;
        }
        out.add({
          'role': 'assistant',
          'content': text.isEmpty ? null : text,
          if (calls.isNotEmpty)
            'tool_calls': [
              for (final call in calls)
                {
                  'id': call.id,
                  'type': 'function',
                  'function': {
                    'name': call.name,
                    'arguments': jsonEncode(call.arguments),
                  },
                },
            ],
        });
      case ToolResultMessage(:final toolCallId, :final content):
        final images = content.whereType<ImageContent>().toList();
        final texts = [
          for (final block in content.whereType<TextContent>()) block.text,
          if (images.isNotEmpty) '[image attached in the next message]',
        ];
        out.add({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'content': texts.join('\n'),
        });
        if (images.isNotEmpty) {
          pendingImages.add((toolCallId, images));
        }
    }
  }
  flushImages();
  return out;
}

Object _userContent(List<ContentBlock> content, ModelRef model) {
  if (content.every((b) => b is TextContent)) {
    return content.cast<TextContent>().map((b) => b.text).join('\n\n');
  }
  return [
    for (final block in content)
      switch (block) {
        TextContent(:final text) => {'type': 'text', 'text': text},
        final ImageContent image => _imagePart(image, model),
        _ => {'type': 'text', 'text': ''},
      },
  ];
}

Map<String, Object?> _imagePart(ImageContent image, ModelRef model) =>
    model.supportsImages
    ? {
        'type': 'image_url',
        'image_url': {'url': 'data:${image.mimeType};base64,${image.base64}'},
      }
    : {'type': 'text', 'text': _imageOmitted};
