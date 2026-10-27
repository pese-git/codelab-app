import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

import '../cli_args.dart';
import '../render/sanitize.dart';
import '../render/terminal_renderer.dart';
import '../session_setup.dart';
import 'approval_policy.dart';
import 'outcome.dart';

/// Один ход без интерактива: `codelab -p`.
///
/// Почему: скрипты и CI запускают агента без терминала и читают ответ из
/// stdout, а исход — из кода выхода (H-01, H-02). Состояние сессии
/// принадлежит kit, раннер только выводит ревизии `SessionView`, решает
/// одобрения политикой `--approve` и превращает ответ `session/prompt` в
/// [HeadlessOutcome] (design.md change `add-codelab-cli`, D9).
///
/// Для чего: в [stdout] — только текст ответов агента байт в байт как
/// пришёл, с переводом строки в конце; строки инструментов, решения
/// политики, заметки и диагностика (`verbose`) — в [stderr] без управляющих
/// символов.
///
/// Как использовать: `HeadlessRunner(workspace: …, stdout: …, stderr: …)`,
/// затем `await runner.run(profile: …, cwd: …, prompt: …)`; сигнал процесса
/// — [interrupt]. Закрывает рабочее пространство вызывающий.
final class HeadlessRunner {
  HeadlessRunner({
    required ClientWorkspace workspace,
    required StringSink stdout,
    required StringSink stderr,
    bool verbose = false,
    ApprovePolicy approve = ApprovePolicy.reject,
    Duration? timeout,
    Duration cancelGrace = const Duration(seconds: 2),
  }) : _workspace = workspace,
       _stdout = stdout,
       _stderr = stderr,
       _verbose = verbose,
       _approve = approve,
       _timeout = timeout,
       _cancelGrace = cancelGrace;

  final ClientWorkspace _workspace;
  final StringSink _stdout;
  final StringSink _stderr;
  final bool _verbose;
  final ApprovePolicy _approve;

  /// Предел на ход `--timeout`; `null` — без предела.
  final Duration? _timeout;

  /// Сколько ждать ответа агента на `session/cancel` после сигнала, прежде
  /// чем выйти без него (design.md, D13).
  final Duration _cancelGrace;

  /// Элементы транскрипта до промпта (реплей загруженной сессии): их текст
  /// не выводится.
  final _before = <String>{};

  /// Длина уже выведенного текста по id элемента `AgentTextItem`.
  final _printed = <String, int>{};

  /// Вызовы инструментов и заметки, уже выведенные в stderr.
  final _reported = <String>{};

  /// Одобрения, на которые политика уже ответила.
  final _decided = <ApprovalRequestId>{};

  SessionHandle? _session;
  var _hadText = false;
  var _endsWithNewline = true;
  var _noticePrinted = false;
  var _timedOut = false;

  /// Сигнал прервал прогон; завершает ожидание хода без ответа агента.
  final _interrupted = Completer<int>();

  /// Прерывает прогон сигналом [code] (`130` или `143`): отменяет идущий ход
  /// и ждёт ответа агента не дольше `cancelGrace`.
  Future<void> interrupt(int code) async {
    if (_interrupted.isCompleted) {
      return;
    }
    _interrupted.complete(code);
    final session = _session;
    if (session != null) {
      await _cancel(session);
    }
  }

  Future<HeadlessOutcome> run({
    required ConnectionProfile profile,
    required String cwd,
    required String prompt,
    String? resume,
    bool continueLast = false,
    String? model,
    String? mode,
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
    if (_approve == ApprovePolicy.allowAll) {
      _stderr.writeln(
        'codelab: warning: --approve allow-all allows every permission '
        'request except critical ones without asking',
      );
    }
    StreamSubscription<SessionView>? views;
    Timer? timer;
    try {
      final SessionHandle session;
      try {
        await _workspace.connect(profile, projectDirectory: cwd);
        session = await openCliSession(
          _workspace,
          cwd,
          resume: resume,
          last: continueLast,
        );
      } on Object catch (error) {
        final message = error is SessionSetupError
            ? error.message
            : describeFailure(error);
        _stderr.writeln(
          sanitizeTerminalText(
            error is SessionSetupError
                ? 'codelab: $message'
                : 'codelab: cannot start the agent ${describeProfile(profile)}: '
                      '$message',
          ),
        );
        return ConnectFailed(message);
      }
      _session = session;
      if (_interrupted.isCompleted) {
        return Signalled(await _interrupted.future);
      }
      try {
        await applyConfigFlag(session, 'model', model);
        await applyConfigFlag(session, 'mode', mode);
      } on SessionSetupError catch (error) {
        _stderr.writeln(sanitizeTerminalText('codelab: ${error.message}'));
        return ConnectFailed(error.message);
      }

      _before.addAll(session.current.transcript.map((item) => item.id));
      views = session.view.listen(_onView);
      if (_timeout case final limit?) {
        timer = Timer(limit, () {
          _timedOut = true;
          _stderr.writeln(
            'codelab: timeout after ${limit.inSeconds}s, cancelling the turn',
          );
          unawaited(_cancel(session));
        });
      }
      final sent = session.send(prompt);
      final signalled = _interrupted.future.then(
        // После сигнала ждём ответа на отмену, но не дольше `cancelGrace`:
        // агент может не ответить вовсе.
        (code) => sent
            .then<int?>((_) => code)
            .timeout(_cancelGrace, onTimeout: () => code),
      );
      final first = await Future.any<Object?>([sent, signalled]);
      // Последняя ревизия могла прийти синхронно с ответом: выводим её до
      // итога, чтобы ответ не потерял хвост.
      _onView(session.current);
      if (!_endsWithNewline) {
        _stdout.writeln();
      }
      if (_interrupted.isCompleted) {
        return Signalled(await _interrupted.future);
      }
      final outcome = _outcomeOf(first! as PromptOutcome);
      return _timedOut ? const TimedOut() : outcome;
    } finally {
      timer?.cancel();
      await views?.cancel();
      await diagnostics?.cancel();
    }
  }

  Future<void> _cancel(SessionHandle session) async {
    try {
      await session.cancel();
    } on Object catch (error) {
      // Ход мог уже закончиться: отменять нечего, это не ошибка прогона.
      if (_verbose) {
        _stderr.writeln(
          sanitizeTerminalText('codelab: cancel: ${describeFailure(error)}'),
        );
      }
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
    _decideApprovals(view);
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

  /// Отвечает на новые запросы одобрения политикой `--approve`: ровно одно
  /// решение и одна строка stderr на запрос (spec cli-headless «Политика
  /// одобрений headless»).
  void _decideApprovals(SessionView view) {
    final session = _session;
    if (session == null) {
      return;
    }
    for (final approval in view.pendingApprovals) {
      if (!_decided.add(approval.approvalId)) {
        continue;
      }
      final call = _callOf(view, approval.approvalId);
      final decision = decideApproval(
        approval,
        _approve,
        kind: call?.details?.kind,
      );
      _stderr.writeln(
        sanitizeTerminalText(
          describeApproval(call?.title ?? 'tool call', decision),
        ),
      );
      final option = decision.optionId;
      unawaited(
        option == null
            ? _cancel(session)
            : session
                  .respond(approval.approvalId, option)
                  .then<void>(
                    (_) {},
                    onError: (Object error) => _stderr.writeln(
                      sanitizeTerminalText(
                        'codelab: cannot answer the permission request: '
                        '${describeFailure(error)}',
                      ),
                    ),
                  ),
      );
    }
  }

  /// Вызов инструмента, которому принадлежит одобрение [id].
  static ToolCallItem? _callOf(SessionView view, ApprovalRequestId id) {
    for (final item in view.transcript) {
      if (item case ToolCallItem(
        approval: PendingApprovalView(:final approvalId),
      ) when approvalId == id) {
        return item;
      }
    }
    return null;
  }

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
