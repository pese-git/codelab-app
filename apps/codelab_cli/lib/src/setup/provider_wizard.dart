import 'dart:async';

import 'package:codelab_setup/codelab_setup.dart';

import '../input/key_decoder.dart';
import '../input/terminal.dart';
import '../render/sanitize.dart';
import 'prompt_line.dart';
import 'wizard_steps.dart';

/// Итог построчного мастера провайдера.
///
/// Почему закрытая иерархия: вызывающему (`codelab provider add`, первый
/// запуск, `/provider add`) нужно по-разному ответить на запись, отмену и
/// отказ записи, а набор булевых флагов позволил бы невозможные сочетания
/// (AGENTS.md §8).
sealed class ProviderWizardResult {
  const ProviderWizardResult();
}

/// Провайдер записан в конфиг; [providerId] — id, под которым он сохранён.
final class ProviderWizardSaved extends ProviderWizardResult {
  const ProviderWizardSaved(this.providerId);

  final String providerId;
}

/// Пользователь отменил мастер (Ctrl+C, Esc, `n`, конец ввода): файлы не
/// изменены.
final class ProviderWizardCancelled extends ProviderWizardResult {
  const ProviderWizardCancelled();
}

/// Мастер не открылся: [message] — причина (идёт ход, нет терминала).
final class ProviderWizardRefused extends ProviderWizardResult {
  const ProviderWizardRefused(this.message);

  final String message;
}

/// Запись не удалась: [message] — строка для человека без значений секретов.
final class ProviderWizardFailed extends ProviderWizardResult {
  const ProviderWizardFailed(this.message);

  final String message;
}

/// Запускает построчный мастер на терминале и ждёт его итога.
///
/// Почему отдельная функция: подкоманда `codelab provider add` и первый
/// запуск (D16) владеют вводом сами, а `/provider add` в REPL подаёт клавиши
/// из подписки `Repl` (см. [LineWizard]); общая логика шагов — одна.
///
/// Как использовать: [flow] строит `run.dart` (`entry: cli`/`firstRun`);
/// [providerId] — позиционный id подкоманды, применяется на «Review» событием
/// `ReviewEdited(providerId:)`; [pathOf] даёт путь файла слоя для сводки.
/// Функция включает raw-режим, подписывается на `Terminal.input`, на любом
/// выходе отменяет подписку, восстанавливает терминал и освобождает [flow]
/// (значение ключа не переживает мастер, SETUP-1).
Future<ProviderWizardResult> runProviderWizard({
  required ProviderSetupFlow flow,
  required Terminal terminal,
  String? providerId,
  ConfigTarget? target,
  String Function(ConfigTarget target)? pathOf,
}) async {
  final wizard = LineWizard(
    flow: flow,
    output: terminal.output,
    providerId: providerId,
    target: target,
    pathOf: pathOf,
    columns: terminal.columns,
  );
  final decoder = KeyDecoder(wizard.onKey);
  final input = terminal.input.listen(
    decoder.add,
    onDone: () {
      decoder.close();
      wizard.inputClosed();
    },
  );
  // Raw-режим — после успешной подписки: иначе при сбое `listen` терминал
  // остался бы без эха.
  if (terminal.hasTerminal) {
    terminal.enableRawMode();
  }
  wizard.start();
  try {
    return await wizard.result;
  } finally {
    await input.cancel();
    decoder.close();
    terminal.restore();
    await wizard.dispose();
  }
}

/// Построчный мастер провайдера (артборд `CliSetup`, design.md D15, D17).
///
/// Почему отдельный класс с [onKey]: в REPL клавиши приходят из единственной
/// подписки `Repl` на `Terminal.input`, а вторая подписка на stdin запрещена
/// (D15, D16, D17); подкоманда и первый запуск подают те же события из своей
/// подписки.
///
/// Для чего: превращает состояния `ProviderSetupFlow` в вопросы и ответы
/// пользователя в события автомата. Состояния не хранит — источник правды
/// автомат; здесь только вид ввода текущего шага ([_mode]).
///
/// Как использовать: `start()`, затем `onKey` на каждую клавишу; [result]
/// завершается записью, отменой или отказом записи. Ключ вводится в скрытое
/// поле: на экране `*` по числу рун, Ctrl+R показывает и прячет, Ctrl+U
/// очищает (U-17); буфер не попадает в историю и сбрасывается при отправке.
final class LineWizard {
  LineWizard({
    required ProviderSetupFlow flow,
    required StringSink output,
    String? providerId,
    ConfigTarget? target,
    String Function(ConfigTarget target)? pathOf,
    int columns = 80,
  }) : _flow = flow,
       _out = output,
       _columns = columns,
       _pendingId = providerId,
       _pendingTarget = target,
       _pathOf = pathOf;

  final ProviderSetupFlow _flow;
  final StringSink _out;
  final String Function(ConfigTarget target)? _pathOf;
  final int _columns;
  Timer? _closeTimer;
  String? _pendingId;
  ConfigTarget? _pendingTarget;

  final _result = Completer<ProviderWizardResult>();
  StreamSubscription<ProviderSetupState>? _states;

  /// Вид ввода текущего шага; меняется только в [_render].
  _Mode _mode = const _Idle();

  /// Высота блока выбора на экране (для перерисовки стрелками).
  var _blockLines = 0;

  /// Хранилище, о котором шаг ключа сообщил последним (для сводки).
  String _backend = '';

  Future<ProviderWizardResult> get result => _result.future;

  void start() {
    _states = _flow.states.listen(_render);
    _render(_flow.current);
  }

  Future<void> dispose() async {
    _closeTimer?.cancel();
    _wipe();
    await _states?.cancel();
    await _flow.dispose();
  }

  /// Конец ввода терминала — как отмена. Во время записи мастер ждёт её итога
  /// (не дольше 10 с), чтобы не бросить запись на середине (D21).
  void inputClosed() {
    if (_mode is _Saving) {
      _closeTimer ??= Timer(const Duration(seconds: 10), () {
        _finish(const ProviderWizardCancelled());
      });
      return;
    }
    _flow.dispatch(const Cancel());
    _finish(const ProviderWizardCancelled());
  }

  /// Сбрасывает буфер поля: значение не переживает мастер (D17, SETUP-1).
  void _wipe() {
    if (_mode case final _LineMode mode) {
      mode.line.clear();
    }
  }

  void _finish(ProviderWizardResult result) {
    _closeTimer?.cancel();
    _wipe();
    if (!_result.isCompleted) {
      _result.complete(result);
    }
  }

  // --- вывод шагов ---------------------------------------------------------

  void _render(ProviderSetupState state) {
    if (_result.isCompleted) {
      return;
    }
    if (state is Reviewing &&
        (_pendingId != null || _pendingTarget != null) &&
        state.error == null) {
      // Позиционный id и `--local` подкоманды применяются один раз (D15).
      final (id, target) = (_pendingId, _pendingTarget);
      _pendingId = _pendingTarget = null;
      _flow.dispatch(ReviewEdited(providerId: id, target: target));
      return;
    }
    final step = wizardStepOf(state, backend: _backend, pathOf: _pathOf);
    if (step.backend case final backend?) {
      _backend = backend;
    }
    if (step.cancelled) {
      _mode = const _Idle();
      _finish(const ProviderWizardCancelled());
      return;
    }
    if (step.savedProviderId case final id?) {
      _mode = const _Idle();
      _finish(ProviderWizardSaved(id));
      return;
    }
    step.notes.forEach(_say);
    if (step.failure case final failure?) {
      _finish(ProviderWizardFailed(failure));
      return;
    }
    if (step.saving) {
      _mode = const _Saving();
    } else if (step.waiting || step.progress != null) {
      _mode = const _Idle();
    }
    if (step.progress case final progress?) {
      _out.write(progress);
    } else if (step.options.isNotEmpty) {
      _mode = _Pick(
        title: step.title ?? '',
        labels: [for (final o in step.options) o.label],
        onPick: (i) => _perform(step.options[i].action),
      );
      _drawPick();
    } else if (step.models case final ids?) {
      _mode = _Filter(
        ids: ids,
        onModel: (id) => _flow.dispatch(ModelChosen(id)),
        onManual: () => _perform(const AskModelId()),
        selected: step.currentModel == null
            ? 0
            : ids.indexOf(step.currentModel!).clamp(0, ids.length - 1),
      );
      _drawFilter();
    } else if (step.field case final field?) {
      _openField(field);
    }
  }

  /// Исполняет действие шага: событие автомату или открытие поля.
  void _perform(WizardAction action) {
    switch (action) {
      case SendEvent(:final event):
        _flow.dispatch(event);
      case Reask(:final message):
        if (message != null) {
          _say(message);
        }
        if (_mode is _LineMode) {
          _drawLine();
        }
      case AskSecret() || AskEnvName() || AskModelId() || AskField():
        _openField(fieldOfAction(action)!);
    }
  }

  void _openField(WizardField field) {
    _mode = _LineMode(
      prompt: field.prompt,
      initial: field.initial,
      hidden: field.hidden,
      onSubmit: (text) => _perform(field.submit(text)),
      onReject: field.hidden
          ? () {
              _say(keyRejectedLine);
              _openField(field);
            }
          : null,
    );
    _drawLine();
  }

  // --- ввод ----------------------------------------------------------------

  /// Клавиша терминала. Ctrl+C и Esc отменяют мастер, кроме записи (D21).
  void onKey(KeyEvent event) {
    if (_result.isCompleted) {
      return;
    }
    final mode = _mode;
    if (mode is _Saving) {
      return;
    }
    if (mode is _LineMode && mode.submitting) {
      mode.trailing = true;
      return;
    }
    if (event case SpecialKey(key: Key.ctrlC || Key.escape)) {
      _flow.dispatch(const Cancel());
      return;
    }
    switch (mode) {
      case _Idle() || _Saving():
        return;
      case final _LineMode line:
        _onLineKey(line, event);
      case final _Pick pick:
        _onPickKey(pick, event);
      case final _Filter filter:
        _onFilterKey(filter, event);
    }
  }

  void _onLineKey(_LineMode mode, KeyEvent event) {
    final line = mode.line;
    switch (applyLineKey(line, event)) {
      case LineKey.edited:
        _drawLine(redraw: true);
      case LineKey.submit:
        final text = line.text;
        _out.write('\n');
        line.clear();
        if (!line.hidden) {
          mode.onSubmit(text);
          return;
        }
        // Остаток чтения после Enter — вставка нескольких строк: ключ не
        // принимается (D14). Решение — после разбора всего чтения.
        mode.submitting = true;
        scheduleMicrotask(() {
          mode.submitting = false;
          if (_result.isCompleted || !identical(_mode, mode)) {
            return;
          }
          if (mode.trailing) {
            mode.onReject?.call();
          } else {
            mode.onSubmit(text);
          }
        });
      case LineKey.multiline:
        _out.write('\n');
        line.clear();
        mode.onReject?.call();
      case LineKey.cancel:
        // Ctrl+C и Esc обработаны выше; сюда доходит Ctrl+D.
        _flow.dispatch(const Cancel());
      case LineKey.ignored:
        break;
    }
  }

  void _onPickKey(_Pick pick, KeyEvent event) {
    if (event case SpecialKey(:final key)) {
      switch (key) {
        case Key.up:
          pick.move(-1);
          _drawPick(redraw: true);
        case Key.down:
          pick.move(1);
          _drawPick(redraw: true);
        case Key.enter:
          pick.onPick(pick.selected);
        case _:
          break;
      }
    }
  }

  void _onFilterKey(_Filter filter, KeyEvent event) {
    switch (event) {
      case TextKey(:final text):
        filter.insert(text);
        _drawFilter(redraw: true);
      case SpecialKey(:final key):
        switch (key) {
          case Key.up:
            filter.move(-1);
            _drawFilter(redraw: true);
          case Key.down:
            filter.move(1);
            _drawFilter(redraw: true);
          case Key.backspace:
            filter.backspace();
            _drawFilter(redraw: true);
          case Key.ctrlU:
            filter.clear();
            _drawFilter(redraw: true);
          case Key.enter:
            _out.write('\n');
            filter.choose();
          case _:
            break;
        }
    }
  }

  // --- рисование -----------------------------------------------------------

  void _say(String text) => _out.write('${sanitizeTerminalText(text)}\n');

  void _drawLine({bool redraw = false}) {
    (_mode as _LineMode).line.draw(_out, columns: _columns, redraw: redraw);
  }

  void _drawPick({bool redraw = false}) {
    final pick = _mode as _Pick;
    if (redraw) {
      _out.write('\x1b[${_blockLines}A\r\x1b[J');
    }
    _out.write('? ${sanitizeTerminalText(pick.title)}\n');
    for (final (i, label) in pick.labels.indexed) {
      _out.write(
        '${i == pick.selected ? '  › ' : '    '}${sanitizeTerminalText(label)}\n',
      );
    }
    _blockLines = pick.labels.length + 1;
  }

  void _drawFilter({bool redraw = false}) {
    final filter = _mode as _Filter;
    if (redraw) {
      _out.write('\x1b[${_blockLines}A\r\x1b[J');
    }
    _out.write(
      '? Model (type to filter) › ${sanitizeTerminalText(filter.text)}\n',
    );
    final (start, rows) = filter.visible;
    for (final (i, label) in rows.indexed) {
      _out.write(
        '${start + i == filter.cursor ? '  › ' : '    '}'
        '${sanitizeTerminalText(label)}\n',
      );
    }
    _blockLines = rows.length + 1;
  }
}

sealed class _Mode {
  const _Mode();
}

final class _Idle extends _Mode {
  const _Idle();
}

final class _Saving extends _Mode {
  const _Saving();
}

/// Поле ввода шага: [line] — буфер и маска, [onSubmit] получает строку.
final class _LineMode extends _Mode {
  _LineMode({
    required String prompt,
    required this.onSubmit,
    this.onReject,
    String initial = '',
    bool hidden = false,
  }) : line = PromptLine(prompt: prompt, initial: initial, hidden: hidden);

  final PromptLine line;
  final void Function(String text) onSubmit;

  /// Что делать с отклонённым значением (вставка нескольких строк, слишком
  /// длинный ключ); `null` — перерисовать поле.
  final void Function()? onReject;

  /// Enter принят, решение откладывается до конца разбора чтения.
  var submitting = false;
  var trailing = false;
}

/// Список со стрелками.
final class _Pick extends _Mode {
  _Pick({required this.title, required this.labels, required this.onPick});

  final String title;
  final List<String> labels;
  final void Function(int index) onPick;
  var selected = 0;

  void move(int delta) =>
      selected = (selected + delta).clamp(0, labels.length - 1);
}

/// Выбор модели: фильтр по подстроке и пункт ручного ввода.
final class _Filter extends _Mode {
  _Filter({
    required this.ids,
    required this.onModel,
    required this.onManual,
    required int selected,
  }) : cursor = selected;

  static const _window = 8;
  static const manualLabel = 'Enter model id manually';

  final List<String> ids;
  final void Function(String id) onModel;
  final void Function() onManual;
  var text = '';
  int cursor;

  List<String> get _matches => [
    for (final id in ids)
      if (id.toLowerCase().contains(text.toLowerCase())) id,
  ];

  /// Строки списка: найденные модели и в конце ручной ввод.
  List<String> get _rows => [..._matches, manualLabel];

  /// Окно списка: индекс первой видимой строки и сами строки.
  (int, List<String>) get visible {
    final rows = _rows;
    cursor = cursor.clamp(0, rows.length - 1);
    final start = (cursor - _window + 1).clamp(0, rows.length);
    return (
      start,
      rows.sublist(start, (start + _window).clamp(0, rows.length)),
    );
  }

  void insert(String value) {
    text += String.fromCharCodes(value.runes.where((r) => r >= 0x20));
    cursor = 0;
  }

  void backspace() {
    if (text.isNotEmpty) {
      text = String.fromCharCodes(text.runes.toList()..removeLast());
      cursor = 0;
    }
  }

  void clear() {
    text = '';
    cursor = 0;
  }

  void move(int delta) => cursor = (cursor + delta).clamp(0, _rows.length - 1);

  void choose() {
    final rows = _rows;
    final index = cursor.clamp(0, rows.length - 1);
    if (index == rows.length - 1) {
      onManual();
    } else {
      onModel(rows[index]);
    }
  }
}
