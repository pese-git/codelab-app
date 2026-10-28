import 'package:codelab_client_core/codelab_client_core.dart';

import '../../input/key_bindings.dart';
import '../../input/key_decoder.dart';
import '../../repl/approval_prompt.dart';
import '../../repl/command_router.dart';
import '../../repl/picker_spec.dart';
import '../../strings.dart';
import 'composer.dart';
import 'transcript_lines.dart';
import 'tui_cmd.dart';
import 'tui_model.dart';
import 'tui_msg.dart';

/// Окно повторного Ctrl+C для выхода (U-07), как в REPL.
const exitWindow = Duration(seconds: 1);

/// Следующее состояние экрана и команды для адаптера.
///
/// Почему: вся логика экрана — чистая функция над моделью: клавиши,
/// вставка, ревизии kit и прокрутка проверяются без терминала и без
/// `dart_tui` (TUI-5; §12.2.7; design.md change `add-cli-tui`, D5, D6, D8).
///
/// Для чего: клавиши — по таблице [KeyBindings.tui]; Enter отправляет
/// промпт (во время хода kit ставит его в очередь) или строку с `/` как
/// команду; ревизия старее последней отбрасывается; начало хода берётся из
/// времени сообщения. Пока ход ждёт одобрения, клавиши идут в зону
/// одобрения (D9); выбор в пикере исполняет строку пункта или подставляет
/// её в композер (D10).
///
/// Как использовать: адаптер вызывает на каждое сообщение и исполняет
/// команды по порядку. Функция не бросает на корректных данных; адаптер всё
/// равно ловит исключения (`reduceGuarded`, §12.2.7, шаг 7).
(TuiModel, List<TuiCmd>) reduce(TuiModel model, TuiMsg msg) => switch (msg) {
  KeyMsg(:final key, :final at) => _key(model, key, at),
  PasteMsg(:final text) => (
    model.copyWith(composer: model.composer.paste(text)),
    const [],
  ),
  ResizeMsg(:final size) => (model.copyWith(size: size), const []),
  SessionViewMsg(:final view, :final at) => (_view(model, view, at), const []),
  // Заметки и прокрутка относились к прошлой сессии.
  SessionAttachedMsg(:final view, :final at) => (
    _view(
      model.copyWith(
        notes: const [],
        scroll: const ScrollState(),
        detailsFor: () => null,
        turnStartedAt: () => null,
      ),
      view,
      at,
      attached: true,
    ),
    const [],
  ),
  NoteMsg(:final text) => (_note(model, text), const []),
  EffectFailedMsg(:final error) => (
    _note(model, 'codelab: ${describeFailure(error)}'),
    const [],
  ),
  OpenPickerMsg(:final spec) => (
    spec.items.isEmpty ? model : model.copyWith(overlay: () => spec),
    const [],
  ),
  PickerChosenMsg(:final index) => _chosen(model, index),
  PickerClosedMsg() => (model.copyWith(overlay: () => null), const []),
  ThoughtsMsg(:final mode) => (model.copyWith(thoughts: mode), const []),
  ClearNotesMsg() => (model.copyWith(notes: const []), const []),
};

(TuiModel, List<TuiCmd>) _chosen(TuiModel model, int index) {
  final spec = model.overlay;
  final closed = model.copyWith(overlay: () => null);
  if (spec == null || index < 0 || index >= spec.items.length) {
    return (closed, const []);
  }
  final line = spec.items[index].line;
  return switch (spec.action) {
    PickerAction.insert => (
      closed.copyWith(composer: closed.composer.replace(line)),
      const [],
    ),
    // Выбор — та же команда с аргументом; строка остаётся в транскрипте,
    // как набранная (D10).
    PickerAction.run => (
      _note(closed.copyWith(scroll: const ScrollState()), '$inputPrompt$line'),
      [RunCommandCmd(line)],
    ),
  };
}

TuiModel _view(
  TuiModel model,
  SessionView view,
  DateTime at, {
  bool attached = false,
}) {
  final current = model.session;
  if (!attached && current != null && view.revision < current.revision) {
    return model;
  }
  final running = switch (view.status) {
    SessionStatusView.running || SessionStatusView.cancelling => true,
    _ => false,
  };
  return model.copyWith(
    session: view,
    turnStartedAt: () => running ? (model.turnStartedAt ?? at) : null,
  );
}

TuiModel _note(TuiModel model, String text) => model.copyWith(
  notes: [
    ...model.notes,
    TuiNote(after: model.session?.transcript.length ?? 0, text: text),
  ],
);

(TuiModel, List<TuiCmd>) _key(TuiModel model, KeyEvent key, DateTime at) {
  if (approvalOf(model) case final prompt?) {
    return _approvalKey(model, prompt, key);
  }
  final composer = model.composer;
  switch (key) {
    case TextKey(:final text):
      return (model.copyWith(composer: composer.insert(text)), const []);
    case SpecialKey(:final key):
      final action = KeyBindings.tui.actionFor(key, running: model.running);
      if (action == null) {
        return (model, const []);
      }
      return _action(model, action, at);
  }
}

(TuiModel, List<TuiCmd>) _action(
  TuiModel model,
  KeyAction action,
  DateTime at,
) {
  final composer = model.composer;
  TuiModel edit(ComposerState next) => model.copyWith(composer: next);
  switch (action) {
    case KeyAction.submit:
      return _submit(model);
    case KeyAction.newline:
      return (edit(composer.newline()), const []);
    case KeyAction.cancelTurn:
      return (model, const [CancelTurnCmd()]);
    case KeyAction.clearLine:
      return (edit(composer.clear()), const []);
    case KeyAction.interrupt:
      final last = model.lastInterrupt;
      if (last != null && at.difference(last) <= exitWindow) {
        return (model, const [QuitCmd(0)]);
      }
      final cleared = model.copyWith(
        composer: composer.clear(),
        lastInterrupt: () => at,
      );
      return (
        composer.isEmpty ? _note(cleared, pressCtrlCAgain) : cleared,
        const [],
      );
    case KeyAction.exit:
      return composer.isEmpty ? (model, const [QuitCmd(0)]) : (model, const []);
    case KeyAction.historyPrevious:
      return (edit(composer.up()), const []);
    case KeyAction.historyNext:
      return (edit(composer.down()), const []);
    case KeyAction.moveLeft:
      return (edit(composer.moveLeft()), const []);
    case KeyAction.moveRight:
      return (edit(composer.moveRight()), const []);
    case KeyAction.moveHome:
      return (edit(composer.moveHome()), const []);
    case KeyAction.moveEnd:
      return (edit(composer.moveEnd()), const []);
    case KeyAction.deleteBackward:
      return (edit(composer.deleteBackward()), const []);
    case KeyAction.deleteForward:
      return (edit(composer.deleteForward()), const []);
    case KeyAction.deleteToStart:
      return (edit(composer.deleteToStart()), const []);
    case KeyAction.scrollUp:
      return (_scrollUp(model), const []);
    case KeyAction.scrollDown:
      return (_scrollDown(model), const []);
    case KeyAction.follow:
      return (model.copyWith(scroll: const ScrollState()), const []);
    case KeyAction.complete:
      return (_complete(model), const []);
    // Кадр и так перерисовывается целиком.
    case KeyAction.clearScreen:
      return (model, const []);
  }
}

/// Клавиши зоны одобрения: вариант, `?`, отмена хода и прокрутка;
/// остальное, включая Enter и клавиши непредложенных вариантов, ничего не
/// делает (D9, как в REPL).
(TuiModel, List<TuiCmd>) _approvalKey(
  TuiModel model,
  ApprovalPrompt prompt,
  KeyEvent key,
) {
  switch (key) {
    case TextKey(:final text):
      for (final char in text.split('')) {
        if (char == '?') {
          final id = prompt.approval.approvalId;
          return (
            model.copyWith(
              detailsFor: () => model.detailsFor == id ? null : id,
            ),
            const [],
          );
        }
        if (prompt.optionFor(char) case final option?) {
          return (
            model.copyWith(scroll: const ScrollState(), detailsFor: () => null),
            [RespondCmd(prompt.approval.approvalId, option)],
          );
        }
      }
      return (model, const []);
    case SpecialKey(:final key):
      return switch (KeyBindings.tui.actionFor(key, running: true)) {
        KeyAction.cancelTurn ||
        KeyAction.interrupt => (model, const [CancelTurnCmd()]),
        KeyAction.scrollUp => (_scrollUp(model), const []),
        KeyAction.scrollDown => (_scrollDown(model), const []),
        KeyAction.follow => (
          model.copyWith(scroll: const ScrollState()),
          const [],
        ),
        _ => (model, const []),
      };
  }
}

/// Tab: один кандидат подставляется, несколько — общий префикс и пикер,
/// выбор которого подставляет команду (D10; U-03).
TuiModel _complete(TuiModel model) {
  final result = CommandRouter(model.commands).complete(
    model.composer.text,
    agentCommands: model.session?.agentCommands ?? const [],
  );
  var next = model;
  if (result.replacement case final replacement?) {
    next = next.copyWith(composer: next.composer.replace(replacement));
  }
  if (result.candidates.length > 1) {
    next = next.copyWith(
      overlay: () => PickerSpec(
        items: [
          for (final candidate in result.candidates)
            PickerItem(
              label:
                  '${candidate.label}  ${candidate.description}'
                  '${candidate.fromAgent ? ' (agent)' : ''}',
              line: '${candidate.label} ',
            ),
        ],
        action: PickerAction.insert,
      ),
    );
  }
  return next;
}

(TuiModel, List<TuiCmd>) _submit(TuiModel model) {
  final (composer, text) = model.composer.submit();
  if (text == null) {
    return (model.copyWith(composer: composer), const []);
  }
  // Отправка возвращает к последней строке (§12.2.7).
  var next = model.copyWith(composer: composer, scroll: const ScrollState());
  final isCommand = text.startsWith('/');
  if (isCommand) {
    // Строка команды остаётся в транскрипте, как промпт: kit её не видит.
    next = _note(next, '$inputPrompt$text');
  }
  return (
    next,
    [
      SaveHistoryCmd(composer.history),
      isCommand ? RunCommandCmd(text) : SubmitCmd(text),
    ],
  );
}

TuiModel _scrollUp(TuiModel model) {
  final total = transcriptLines(model).length;
  final scroll = model.scroll;
  if (scroll.follow) {
    final holding = model.copyWith(
      scroll: ScrollState(follow: false, holdTotal: total),
    );
    final height = transcriptHeight(holding);
    if (total <= height) {
      return model;
    }
    final top = total - height - height;
    return holding.copyWith(
      scroll: ScrollState(
        follow: false,
        top: top < 0 ? 0 : top,
        holdTotal: total,
      ),
    );
  }
  final top = scroll.top - transcriptHeight(model);
  return model.copyWith(
    scroll: ScrollState(
      follow: false,
      top: top < 0 ? 0 : top,
      holdTotal: scroll.holdTotal,
    ),
  );
}

TuiModel _scrollDown(TuiModel model) {
  final scroll = model.scroll;
  if (scroll.follow) {
    return model;
  }
  final height = transcriptHeight(model);
  final top = scroll.top + height;
  if (top + height >= transcriptLines(model).length) {
    return model.copyWith(scroll: const ScrollState());
  }
  return model.copyWith(
    scroll: ScrollState(follow: false, top: top, holdTotal: scroll.holdTotal),
  );
}
