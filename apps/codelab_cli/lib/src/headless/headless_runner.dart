import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

import '../render/sanitize.dart';
import 'outcome.dart';

/// Один ход без интерактива: `codelab -p`.
///
/// Почему: скрипты и CI запускают агента без терминала и читают ответ из
/// stdout, а исход — из кода выхода (H-01, H-02). Состояние сессии
/// принадлежит kit, раннер только выводит ревизии `SessionView` и
/// превращает ответ `session/prompt` в [HeadlessOutcome] (design.md change
/// `add-codelab-cli`, D9).
///
/// Для чего: в [stdout] — только текст ответов агента байт в байт как
/// пришёл, с переводом строки в конце; строки инструментов, заметки и
/// диагностика (`verbose`) — в [stderr] без управляющих символов.
///
/// Как использовать: `HeadlessRunner(workspace: …, stdout: …, stderr: …)`,
/// затем `await runner.run(profile: …, cwd: …, prompt: …)`; закрывает
/// рабочее пространство вызывающий.
final class HeadlessRunner {
  HeadlessRunner({
    required ClientWorkspace workspace,
    required StringSink stdout,
    required StringSink stderr,
    bool verbose = false,
  }) : _workspace = workspace,
       _stdout = stdout,
       _stderr = stderr,
       _verbose = verbose;

  final ClientWorkspace _workspace;
  final StringSink _stdout;
  final StringSink _stderr;
  final bool _verbose;

  /// Элементы транскрипта до промпта (реплей загруженной сессии): их текст
  /// не выводится.
  final _before = <String>{};

  /// Длина уже выведенного текста по id элемента `AgentTextItem`.
  final _printed = <String, int>{};

  /// Вызовы инструментов и заметки, уже выведенные в stderr.
  final _reported = <String>{};

  var _hadText = false;
  var _endsWithNewline = true;
  var _noticePrinted = false;

  Future<HeadlessOutcome> run({
    required ConnectionProfile profile,
    required String cwd,
    required String prompt,
  }) async {
    final diagnostics = _verbose
        ? _workspace.diagnostics.listen(
            (d) => _stderr.writeln(
              sanitizeTerminalText(
                '[${d.severity.name}] ${d.source}: ${d.message}',
              ),
            ),
          )
        : null;
    StreamSubscription<SessionView>? views;
    try {
      final SessionHandle session;
      try {
        await _workspace.connect(profile, projectDirectory: cwd);
        session = await _workspace.newSession(cwd: cwd);
      } on Object catch (error) {
        final message = describeFailure(error);
        _stderr.writeln(
          sanitizeTerminalText(
            'codelab: cannot start the agent ${_describe(profile)}: '
            '$message',
          ),
        );
        return ConnectFailed(message);
      }

      _before.addAll(session.current.transcript.map((item) => item.id));
      views = session.view.listen(_onView);
      final outcome = await session.send(prompt);
      // Последняя ревизия могла прийти синхронно с ответом: выводим её до
      // итога, чтобы ответ не потерял хвост.
      _onView(session.current);
      if (!_endsWithNewline) {
        _stdout.writeln();
      }
      return _outcomeOf(outcome);
    } finally {
      await views?.cancel();
      await diagnostics?.cancel();
    }
  }

  HeadlessOutcome _outcomeOf(PromptOutcome outcome) {
    switch (outcome) {
      case PromptCompleted(:final turn):
        if (!_hadText && !_noticePrinted) {
          _stderr.writeln('codelab: empty response');
        }
        return TurnCompleted(turn.stopReason, hadText: _hadText);
      case PromptFailed(:final error):
        final message = describeFailure(error);
        // Заметку об ошибке хода kit уже вывел через транскрипт; без неё —
        // печатаем причину сами.
        if (!_noticePrinted) {
          _stderr.writeln(sanitizeTerminalText('codelab: $message'));
        }
        return TurnFailed(message);
      case PromptQueued():
        // Новая сессия свободна, и промпт не может встать в очередь; если это
        // случилось, ход не состоялся.
        _stderr.writeln('codelab: the prompt was queued and not sent');
        return const TurnFailed('the prompt was queued and not sent');
    }
  }

  void _onView(SessionView view) {
    for (final item in view.transcript) {
      if (_before.contains(item.id)) {
        continue;
      }
      switch (item) {
        case AgentTextItem(:final id, :final text):
          final printed = _printed[id] ?? 0;
          if (text.length > printed) {
            final delta = text.substring(printed);
            _stdout.write(delta);
            _printed[id] = text.length;
            _hadText = true;
            _endsWithNewline = delta.endsWith('\n');
          }
        case ToolCallItem(:final id, :final title, :final details):
          final status = details?.status;
          if (status == null || !_isFinal(status) || !_reported.add(id)) {
            continue;
          }
          final command = details?.command;
          _stderr.writeln(
            sanitizeTerminalText(
              '${_icon(status)} $title${command == null ? '' : ' $command'}',
            ),
          );
        case NoticeItem(:final id):
          if (_reported.add(id)) {
            _noticePrinted = true;
            _stderr.writeln(
              sanitizeTerminalText('codelab: ${noticeText(item)}'),
            );
          }
        case UserItem() || ThoughtItem():
          // Мысли модели в headless не выводятся (`09-11`, H-01).
          continue;
      }
    }
  }

  /// Текст заметки для человека: у сорвавшегося хода — причина агента из
  /// `PromptFailure`, а не общий текст ошибки запроса.
  static String noticeText(NoticeItem notice) => switch (notice.failure) {
    AgentPromptFailure(:final errorClass, :final message) =>
      errorClass == null ? message : '$message ($errorClass)',
    RequestPromptFailure(:final code, :final message) =>
      'agent error $code: $message',
    ConnectionLostPromptFailure() => 'the connection to the agent was lost',
    UnknownPromptFailure() || null => notice.text,
  };

  /// Какого агента не удалось запустить: команда или адрес, без токена.
  static String _describe(ConnectionProfile profile) => switch (profile) {
    StdioProfile(:final command, :final args) =>
      '"${[command, ...args].join(' ')}"',
    WebSocketProfile(:final uri) => '$uri',
  };

  static bool _isFinal(ToolCallStatusView status) =>
      status == ToolCallStatusView.succeeded ||
      status == ToolCallStatusView.failed ||
      status == ToolCallStatusView.cancelled;

  static String _icon(ToolCallStatusView status) => switch (status) {
    ToolCallStatusView.succeeded => '✓',
    ToolCallStatusView.failed => '✗',
    _ => '⊘',
  };
}
