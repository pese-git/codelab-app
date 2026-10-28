import 'package:codelab_client_core/codelab_client_core.dart';

import '../../input/key_bindings.dart';
import '../../input/key_decoder.dart';
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
/// времени сообщения.
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
  NoteMsg(:final text) => (_note(model, text), const []),
  EffectFailedMsg(:final error) => (
    _note(model, 'codelab: ${describeFailure(error)}'),
    const [],
  ),
};

TuiModel _view(TuiModel model, SessionView view, DateTime at) {
  final current = model.session;
  if (current != null && view.revision < current.revision) {
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
    // Дополнение команд и пикеры — итерация 2 (tasks 5.3); кадр и так
    // перерисовывается целиком.
    case KeyAction.complete || KeyAction.clearScreen:
      return (model, const []);
  }
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
