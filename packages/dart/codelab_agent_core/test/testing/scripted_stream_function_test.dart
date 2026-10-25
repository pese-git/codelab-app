import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import '../support/package_dir.dart';

final _time = DateTime.utc(2026);

LlmContext _context(List<Message> messages, {List<String> tools = const []}) =>
    LlmContext(
      systemPrompt: 'You are CodeLab.',
      messages: messages,
      tools: [
        for (final name in tools)
          ToolSchema(name: name, description: name, parameters: const {}),
      ],
      cacheKey: 'sess-1',
    );

UserMessage _user(String text) =>
    UserMessage([TextContent(text)], timestamp: _time);

Future<AssistantMessage> _ask(
  ScriptedStreamFunction model,
  LlmContext context, {
  CancelToken? cancel,
}) {
  final StreamFunction stream = model.call;
  return stream(testModel, context, cancel: cancel).result;
}

Map<String, Object?> _script(List<Map<String, Object?>> steps) => {
  'steps': steps,
};

void main() {
  test('steps are served strictly in order', () async {
    final model = ScriptedStreamFunction.fromJson(
      _script([
        {
          'reply': [
            {'text': 'first'},
          ],
          'stopReason': 'stop',
        },
        {
          'reply': [
            {'text': 'second'},
          ],
          'stopReason': 'stop',
        },
      ]),
    );

    final a = await _ask(model, _context([_user('anything')]));
    final b = await _ask(model, _context([_user('first again')]));

    expect(a.content, [const TextContent('first')]);
    expect(b.content, [const TextContent('second')]);
    model.verify();
  });

  test('expect mismatch fails with request diff', () async {
    final model = ScriptedStreamFunction.fromJson(
      _script([
        {
          'expect': {
            'lastMessage': {'role': 'user', r'$textContains': 'README'},
          },
          'reply': [
            {'text': 'ok'},
          ],
          'stopReason': 'stop',
        },
      ]),
    );

    final answer = await _ask(model, _context([_user('Fix main.dart')]));

    expect(answer.stopReason, StopReason.error);
    expect(answer.errorClass, LlmErrorClass.badRequest);
    expect(
      model.verify,
      throwsA(
        isA<ScriptedLlmFailure>().having(
          (f) => f.toString(),
          'diff',
          allOf(
            contains('step 1'),
            contains('expected'),
            contains('README'),
            contains('Fix main.dart'),
          ),
        ),
      ),
    );
  });

  test('an extra request fails verify and answers badRequest', () async {
    final model = ScriptedStreamFunction.fromJson(
      _script([
        {
          'reply': [
            {'text': 'only'},
          ],
          'stopReason': 'stop',
        },
      ]),
    );

    await _ask(model, _context([_user('a')]));
    final extra = await _ask(model, _context([_user('b')]));

    expect(extra.errorClass, LlmErrorClass.badRequest);
    expect(
      model.verify,
      throwsA(
        isA<ScriptedLlmFailure>().having(
          (f) => f.toString(),
          'message',
          contains('request 2'),
        ),
      ),
    );
  });

  test('an unused step fails verify', () async {
    final model = ScriptedStreamFunction.fromJson(
      _script([
        {
          'reply': [
            {'text': 'a'},
          ],
          'stopReason': 'stop',
        },
        {
          'reply': [
            {'text': 'b'},
          ],
          'stopReason': 'stop',
        },
      ]),
    );

    await _ask(model, _context([_user('x')]));

    expect(
      model.verify,
      throwsA(
        isA<ScriptedLlmFailure>().having(
          (f) => f.toString(),
          'message',
          contains('step 2 was not used'),
        ),
      ),
    );
  });

  test('text is split into deltas of 16 characters', () async {
    final model = ScriptedStreamFunction.fromJson(
      _script([
        {
          'reply': [
            {'text': 'Готово: README.md обновлён.'},
          ],
          'stopReason': 'stop',
        },
      ]),
    );

    final events = await model(testModel, _context([_user('x')])).toList();

    final deltas = events.whereType<BlockDeltaEvent>().map((e) => e.delta);
    expect(deltas, ['Готово: README.m', 'd обновлён.']);
    expect(events.first, isA<StartEvent>());
  });

  test('thinking, text and a tool call with usage', () async {
    final model = ScriptedStreamFunction.fromJson(
      _script([
        {
          'reply': [
            {'thinking': 'Read first.'},
            {'text': 'Reading.'},
            {
              'toolCall': {
                'id': 'call_1',
                'name': 'read',
                'arguments': {'path': 'a.txt'},
              },
            },
          ],
          'stopReason': 'toolUse',
          'usage': {'input': 900, 'output': 40},
        },
      ]),
    );

    final answer = await _ask(model, _context([_user('x')]));

    expect(answer.stopReason, StopReason.toolUse);
    expect(answer.content, [
      const ThinkingContent('Read first.'),
      const TextContent('Reading.'),
      ToolCall(id: 'call_1', name: 'read', arguments: const {'path': 'a.txt'}),
    ]);
    expect(answer.usage, const Usage(input: 900, output: 40));
    expect(answer.model, testModel);
  });

  test('error step ends with ErrorEvent of its class', () async {
    final model = ScriptedStreamFunction.fromJson(
      _script([
        {
          'error': {'class': 'auth', 'message': '401'},
          'stopReason': 'error',
        },
      ]),
    );

    final answer = await _ask(model, _context([_user('x')]));

    expect(answer.stopReason, StopReason.error);
    expect(answer.errorClass, LlmErrorClass.auth);
    expect(answer.errorMessage, '401');
    model.verify();
  });

  test('delayMs waits on the FakeClock', () async {
    final clock = FakeClock();
    final model = ScriptedStreamFunction.fromJson(
      _script([
        {
          'delayMs': 5000,
          'reply': [
            {'text': 'late'},
          ],
          'stopReason': 'stop',
        },
      ]),
      clock: clock,
    );

    AssistantMessage? answer;
    _ask(model, _context([_user('x')])).then((m) => answer = m);
    await clock.elapse(const Duration(seconds: 4));
    expect(answer, isNull);
    await clock.elapse(const Duration(seconds: 1));
    expect(answer?.content, [const TextContent('late')]);
  });

  test('waitForCancel answers only after cancel, with aborted', () async {
    final model = ScriptedStreamFunction.fromJson(
      _script([
        {'waitForCancel': true},
      ]),
    );
    final source = CancelTokenSource();

    AssistantMessage? answer;
    _ask(
      model,
      _context([_user('x')]),
      cancel: source.token,
    ).then((m) => answer = m);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(answer, isNull);

    source.cancel();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(answer?.stopReason, StopReason.aborted);
    expect(answer?.errorClass, LlmErrorClass.aborted);
    model.verify();
  });

  // Отмена посреди стрима (фикстура acp/prompt-cancel-mid-stream; design.md
  // change `add-dart-agent-acp-server`, D15): текст ответа уже ушёл, шаг
  // ждёт отмены и заканчивается aborted.
  test('waitForCancel with reply streams the reply, then waits', () async {
    final model = ScriptedStreamFunction.fromJson(
      _script([
        {
          'reply': [
            {'text': 'Starting'},
          ],
          'waitForCancel': true,
        },
      ]),
    );
    final source = CancelTokenSource();
    final deltas = <String>[];

    final stream = model.call(
      testModel,
      _context([_user('x')]),
      cancel: source.token,
    );
    final done = () async {
      await for (final event in stream) {
        if (event case BlockDeltaEvent(:final delta)) {
          deltas.add(delta);
        }
      }
      return stream.result;
    }();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(deltas, ['Starting']);

    source.cancel();
    final answer = await done;

    expect(answer.stopReason, StopReason.aborted);
    model.verify();
  });

  test(r'${cwd} and ${sessionId} are substituted in text', () async {
    final model = ScriptedStreamFunction.fromJson(
      _script([
        {
          'reply': [
            {'thinking': r'In ${cwd}.'},
            {'text': r'Session ${sessionId} in ${cwd}.'},
          ],
          'stopReason': 'stop',
        },
      ]),
      cwd: '/work/demo',
    );

    final answer = await _ask(model, _context([_user('x')]));

    expect(answer.content, [
      const ThinkingContent('In /work/demo.'),
      const TextContent('Session sess-1 in /work/demo.'),
    ]);
  });

  // Бинарь с --llm-script: шаги общие для сессий с разными cwd (design.md
  // change `add-codelab-agent-binary`, D3).
  test(r'cwdOf gives ${cwd} of the session of the request', () async {
    final model = ScriptedStreamFunction.fromJson(
      _script([
        for (var i = 0; i < 2; i++)
          {
            'reply': [
              {'text': r'cwd was: ${cwd}'},
            ],
            'stopReason': 'stop',
          },
      ]),
      cwdOf: (sessionId) =>
          {'sess-1': '/work/a', 'sess-2': '/work/b'}[sessionId],
    );

    final first = await _ask(model, _context([_user('x')]));
    final second = await _ask(
      model,
      LlmContext(
        systemPrompt: 'You are CodeLab.',
        messages: [_user('y')],
        tools: const [],
        cacheKey: 'sess-2',
      ),
    );

    expect(first.content, [const TextContent('cwd was: /work/a')]);
    expect(second.content, [const TextContent('cwd was: /work/b')]);
  });

  test('expect toolResult and tools', () async {
    final model = ScriptedStreamFunction.fromJson(
      _script([
        {
          'expect': {
            'toolResult': {'toolCallId': 'call_1', 'isError': false},
            'tools': ['read', 'edit'],
          },
          'reply': [
            {'text': 'done'},
          ],
          'stopReason': 'stop',
        },
      ]),
    );

    await _ask(
      model,
      _context(
        [
          _user('x'),
          AssistantMessage(
            content: [
              ToolCall(id: 'call_1', name: 'read', arguments: const {}),
            ],
            model: testModel,
            usage: Usage.zero,
            stopReason: StopReason.toolUse,
            timestamp: _time,
          ),
          ToolResultMessage(
            toolCallId: 'call_1',
            toolName: 'read',
            content: const [TextContent('1| x')],
            isError: false,
            timestamp: _time,
          ),
        ],
        tools: ['read', 'edit'],
      ),
    );

    model.verify();
  });

  test('an unknown step key is a format error', () {
    expect(
      () => ScriptedStreamFunction.fromJson(
        _script([
          {'answer': 'x'},
        ]),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('the llm block of acp/prompt-tool-permission-allow plays', () async {
    final fixture =
        jsonDecode(
              File(
                corePath(
                  '../acp_testing/fixtures/acp/prompt-tool-permission-allow.json',
                ),
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final model = ScriptedStreamFunction.fromJson(
      fixture['llm']! as Map<String, Object?>,
    );

    final first = await _ask(
      model,
      _context([_user('Замени в README.md слово foo на bar')]),
    );
    final second = await _ask(
      model,
      _context([
        _user('Замени в README.md слово foo на bar'),
        first,
        ToolResultMessage(
          toolCallId: 'call_1',
          toolName: 'edit',
          content: const [TextContent('Edited README.md')],
          isError: false,
          timestamp: _time,
        ),
      ]),
    );

    expect(first.toolCalls.single.name, 'edit');
    expect(second.content, [const TextContent('Готово: README.md обновлён.')]);
    model.verify();
  });
}
