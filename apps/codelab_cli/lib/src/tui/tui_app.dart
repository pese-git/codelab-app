import 'package:dart_tui/dart_tui.dart' as tea;

import 'core/frame.dart';
import 'core/tui_chrome.dart';
import 'core/tui_cmd.dart';
import 'core/tui_model.dart';
import 'core/tui_msg.dart';
import 'core/tui_update.dart' as core;
import 'core/tui_view.dart';
import 'registry_key_map.dart';
import 'tui_effects.dart';
import 'tui_input.dart';

/// Функция ядра экрана, которую вызывает [TuiApp]; тесты подставляют свою.
typedef TuiReduce = (TuiModel, List<TuiCmd>) Function(TuiModel, TuiMsg);

/// Метка тика значка хода среди `TickMsg` пакета.
const _spinnerTick = #codelabSpinner;

/// Модель `dart_tui` полноэкранного режима — единственный тип, который
/// видит `Program`.
///
/// Почему: ядро экрана — чистые `reduce` и `render` без пакета (TUI-5), а
/// значок хода и строку подсказок рисуют компоненты пакета (`SpinnerModel`,
/// `HelpModel`, решение владельца проекта). Компоненты живут здесь, рядом с
/// моделью ядра, и попадают в кадр строками `TuiChrome` (design.md change
/// `add-cli-tui`, D7, D12).
///
/// Для чего: [update] переводит сообщение пакета (`TuiInput`) или берёт
/// `DomainMsg`, вызывает `reduce` и переводит команды (`TuiEffects`); пока
/// идёт ход, тикает значок хода раз в 100 мс. Исключение `reduce` оставляет
/// модель прежней, третье подряд — выход с кодом `1` ([lastError] — для
/// печати после восстановления терминала). [view] собирает кадр; ошибка
/// `render` оставляет прошлый кадр (§12.2.7, шаг 7).
///
/// Как использовать: `TuiRunner` создаёт начальную модель и отдаёт её
/// `Program.run`.
final class TuiApp implements tea.Model {
  TuiApp({
    required this.model,
    required this.input,
    required this.effects,
    TuiReduce reduce = core.reduce,
    bool unicode = true,
    DateTime Function()? clock,
  }) : _reduce = reduce,
       _clock = clock ?? DateTime.now,
       _spinner = tea.SpinnerModel(
         frames: unicode
             ? const ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
             : const ['|', '/', '-', r'\'],
         styles: const tea.SpinnerStyles(),
       ),
       _help = tea.HelpModel.fromKeyMap(
         RegistryKeyMap(),
         title: '',
         styles: const tea.HelpStyles(),
       ),
       _shared = _Shared(),
       lastError = null,
       _errorStreak = 0,
       _ticking = false;

  TuiApp._next(
    TuiApp from, {
    required this.model,
    tea.SpinnerModel? spinner,
    int? errorStreak,
    this.lastError,
    bool? ticking,
  }) : input = from.input,
       effects = from.effects,
       _reduce = from._reduce,
       _clock = from._clock,
       _spinner = spinner ?? from._spinner,
       _help = from._help,
       _shared = from._shared,
       _errorStreak = errorStreak ?? from._errorStreak,
       _ticking = ticking ?? from._ticking;

  final TuiModel model;
  final TuiInput input;
  final TuiEffects effects;

  /// Последняя ошибка ядра экрана; `null` — ошибок не было.
  final Object? lastError;

  final TuiReduce _reduce;
  final DateTime Function() _clock;
  final tea.SpinnerModel _spinner;
  final tea.HelpModel _help;
  final _Shared _shared;
  final int _errorStreak;

  /// Тик значка хода уже запланирован.
  final bool _ticking;

  @override
  tea.Cmd? init() => null;

  @override
  (tea.Model, tea.Cmd?) update(tea.Msg msg) {
    if (msg is tea.TickMsg && msg.id == _spinnerTick) {
      final (spinner, _) = _spinner.update(msg);
      final running = model.running;
      return (
        TuiApp._next(
          this,
          model: model,
          spinner: spinner as tea.SpinnerModel,
          ticking: running,
          lastError: lastError,
        ),
        running ? _tick() : null,
      );
    }
    final translated = msg is DomainMsg
        ? msg.msg
        : input.translate(msg, now: _clock());
    if (translated == null) {
      return (this, null);
    }
    final TuiModel next;
    final List<TuiCmd> cmds;
    try {
      (next, cmds) = _reduce(model, translated);
    } on Object catch (error) {
      final streak = _errorStreak + 1;
      return (
        TuiApp._next(this, model: model, errorStreak: streak, lastError: error),
        streak >= 3 ? effects.toDartTuiCmd(const [QuitCmd(1)]) : null,
      );
    }
    final startTick = next.running && !_ticking;
    final effect = effects.toDartTuiCmd(cmds);
    // Новый размер — полная перерисовка: построчный diff пакета не стирает
    // хвосты строк прошлого, более широкого кадра (§12.2.7, шаг 5;
    // design.md change `add-cli-tui`, D7).
    final cmd = translated is ResizeMsg
        ? tea.batch([effect, () => tea.clearScreen()])
        : effect;
    return (
      TuiApp._next(
        this,
        model: next,
        errorStreak: 0,
        lastError: lastError,
        ticking: _ticking || startTick,
      ),
      startTick ? tea.batch([cmd, _tick()]) : cmd,
    );
  }

  static tea.Cmd _tick() => tea.tick(
    const Duration(milliseconds: 100),
    (time) => tea.TickMsg(time, id: _spinnerTick),
  );

  @override
  tea.View view() {
    Frame frame;
    try {
      frame = render(
        model,
        TuiChrome(
          spinner: _spinner.view().content,
          hints: hintLine(_help),
          now: _clock(),
        ),
      );
      _shared.lastFrame = frame;
    } on Object catch (error) {
      _shared.lastRenderError = error;
      frame = _shared.lastFrame ?? const Frame([]);
    }
    final cursor = frame.cursor;
    return tea.View(
      content: frame.lines.join('\n'),
      altScreen: true,
      cursor: cursor == null ? null : tea.Cursor(x: cursor.$2, y: cursor.$1),
    );
  }
}

/// Общее для всех копий [TuiApp] одного запуска: прошлый кадр на случай
/// ошибки `render`.
final class _Shared {
  Frame? lastFrame;
  Object? lastRenderError;
}
