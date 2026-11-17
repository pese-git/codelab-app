// Спайк 1.1 add-integrated-terminal (D14, D15): приложение для ручной проверки.
//
// Запуск: `fvm flutter run -d macos` из каталога спайка (или собранный бинарь,
// чтобы stdout шёл в терминал). Каталог удаляется в задаче 3.9.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pty2/pty2.dart';
import 'package:terminal_spike/terminal_policy.dart';
import 'package:xterm2/xterm.dart';

void spikeLog(String message) {
  final line =
      '[spike ${DateTime.now().toIso8601String().substring(11, 23)}] $message';
  stdout.writeln(line);
  _logLines.value = [..._logLines.value.take(40), line].toList();
}

final ValueNotifier<List<String>> _logLines = ValueNotifier(const []);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Все клавиши до дерева фокуса: видно, что приходит от системы
  // (Cmd+`, Ctrl+`, раскладка).
  HardwareKeyboard.instance.addHandler((event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final k = HardwareKeyboard.instance;
    spikeLog(
      '${event.runtimeType} logical="${event.logicalKey.keyLabel}" '
      'id=0x${event.logicalKey.keyId.toRadixString(16)} '
      'physical=${event.physicalKey.debugName} char=${_show(event.character)} '
      'ctrl=${k.isControlPressed} shift=${k.isShiftPressed} '
      'meta=${k.isMetaPressed} alt=${k.isAltPressed} '
      'isBackquote=${event.logicalKey == LogicalKeyboardKey.backquote} '
      'physBackquote=${event.physicalKey == PhysicalKeyboardKey.backquote}',
    );
    return false;
  });
  runApp(const SpikeApp());
}

String _show(String? s) => s == null
    ? 'null'
    : s.runes.map((r) => 'U+${r.toRadixString(16)}').join(',');

/// Без `MaterialApp`: проверка пункта 6 спайка (`TerminalView` внутри `FluentApp`).
class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) =>
      FluentApp(title: 'terminal spike', home: const SpikePage());
}

class _Tab {
  _Tab(this.id) {
    pty = PseudoTerminal.start(
      Platform.environment['SHELL'] ?? '/bin/zsh',
      ['-l'],
      workingDirectory: Platform.environment['HOME'],
      environment: {
        // D5/Q9: окружение app целиком + TERM/COLORTERM (pty2 сам берёт лишь узкий набор).
        ...Platform.environment,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
    );
    terminal = buildPolicyTerminal(
      onOutput: pty.write,
      onResize: pty.resize,
      onClipboardAttempt: (what) =>
          spikeLog('CLIPBOARD ATTEMPT tab $id: $what (отклонено)'),
    );
    pty.exitCode.then((code) {
      exited = true;
      terminal.write('\r\n[Process exited with code $code]\r\n');
      spikeLog('tab $id exited code=$code');
    });
  }

  final int id;
  late final PseudoTerminal pty;
  late final Terminal terminal;
  bool exited = false;
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final _tabs = <_Tab>[];
  final _subs = <int, StreamSubscription<String>>{};
  final _pending = StringBuffer();
  _Tab? _active;
  int _nextId = 1;
  bool _batch = true;
  bool _flushScheduled = false;
  final _termFocus = FocusNode(debugLabel: 'terminal');
  final _composerFocus = FocusNode(debugLabel: 'composer');
  late final AppLifecycleListener _lifecycle;
  final _frames = _FrameStats();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: _onExitRequested,
      onStateChange: (s) => spikeLog('lifecycle state=$s'),
      onDetach: () => spikeLog('lifecycle detach'),
    );
    SchedulerBinding.instance.addTimingsCallback(_frames.onTimings);
    _newTab();
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_frames.onTimings);
    _lifecycle.dispose();
    for (final s in _subs.values) {
      s.cancel();
    }
    _termFocus.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  /// D4: hangUp всем, ждать до 3 с, затем kill оставшимся.
  Future<AppExitResponse> _onExitRequested() async {
    final sw = Stopwatch()..start();
    spikeLog('onExitRequested: вкладок ${_tabs.length}');
    _closing = true;
    final live = _tabs.where((t) => !t.exited).toList();
    for (final t in live) {
      t.pty.kill(ProcessSignal.sighup);
    }
    await Future.wait(
      live.map(
        (t) => t.pty.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            spikeLog('tab ${t.id}: не вышел за 3 с, SIGKILL');
            t.pty.kill(ProcessSignal.sigkill);
            return -1;
          },
        ),
      ),
    );
    spikeLog('onExitRequested: готово за ${sw.elapsedMilliseconds} мс -> exit');
    return AppExitResponse.exit;
  }

  void _newTab() {
    if (_closing) return;
    final tab = _Tab(_nextId++);
    _subs[tab.id] = tab.pty.out.listen((chunk) {
      if (!_batch) {
        tab.terminal.write(chunk);
        return;
      }
      // Порции не чаще кадра (риск «нагрузка на UI isolate», design.md).
      _pending.write(chunk);
      _scheduleFlush(tab);
    });
    setState(() {
      _tabs.add(tab);
      _active = tab;
    });
    spikeLog('tab ${tab.id} opened');
  }

  void _scheduleFlush(_Tab tab) {
    if (_flushScheduled) return;
    _flushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _flushScheduled = false;
      if (_pending.isEmpty) return;
      final s = _pending.toString();
      _pending.clear();
      tab.terminal.write(s);
    });
  }

  void _closeTab() {
    final tab = _active;
    if (tab == null) return;
    tab.pty.kill(ProcessSignal.sighup);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!tab.exited) tab.pty.kill(ProcessSignal.sigkill);
    });
    setState(() {
      _tabs.remove(tab);
      _active = _tabs.isEmpty ? null : _tabs.last;
    });
    spikeLog('tab ${tab.id} closed (SIGHUP, затем SIGKILL через 2 с)');
  }

  void _send(String text) {
    _active?.pty.write(text);
    _termFocus.requestFocus();
  }

  /// Ctrl+` вне терминала — в терминал, внутри — в композер (D6).
  void _toggleFocus() {
    final toTerminal = !_termFocus.hasFocus;
    spikeLog('Ctrl+` : фокус -> ${toTerminal ? 'terminal' : 'composer'}');
    (toTerminal ? _termFocus : _composerFocus).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.backquote, control: true):
            _toggleFocus,
        const SingleActivator(
          LogicalKeyboardKey.backquote,
          control: true,
          shift: true,
          includeRepeats: false,
        ): () {
          spikeLog('Ctrl+Shift+` : новая вкладка');
          _newTab();
        },
        const SingleActivator(LogicalKeyboardKey.backquote, meta: true): () =>
            spikeLog('Cmd+` дошёл до app'),
      },
      child: ScaffoldPage(
        padding: EdgeInsets.zero,
        content: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Button(onPressed: _newTab, child: const Text('New tab')),
                  Button(onPressed: _closeTab, child: const Text('Close tab')),
                  for (final t in _tabs)
                    ToggleButton(
                      checked: t == _active,
                      onChanged: (_) => setState(() => _active = t),
                      child: Text('tab ${t.id}${t.exited ? ' (exited)' : ''}'),
                    ),
                  const Text('Batch per frame:'),
                  ToggleSwitch(
                    checked: _batch,
                    onChanged: (v) => setState(() => _batch = v),
                  ),
                  Button(
                    onPressed: () {
                      _frames.reset();
                      _send('yes | head -n 200000\n');
                    },
                    child: const Text('Flood yes|head'),
                  ),
                  Button(
                    onPressed: () => _send('sleep 7777\n'),
                    child: const Text('sleep 7777'),
                  ),
                  Button(
                    onPressed: () => _send("trap '' HUP; sleep 7778\n"),
                    child: const Text('trap HUP; sleep 7778'),
                  ),
                  Button(
                    onPressed: () => _send(
                      "printf '\\033]52;c;%s\\a' \$(printf SECRET-FROM-OSC52 | base64); echo OSC52-sent\n",
                    ),
                    child: const Text('Send OSC 52'),
                  ),
                  Button(
                    onPressed: _frames.reset,
                    child: const Text('Reset frame stats'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 400,
                child: TextBox(
                  focusNode: _composerFocus,
                  placeholder: 'composer (проверка возврата фокуса по Ctrl+`)',
                ),
              ),
            ),
            ValueListenableBuilder<String>(
              valueListenable: _frames.summary,
              builder: (_, s, _) =>
                  Padding(padding: const EdgeInsets.all(8), child: Text(s)),
            ),
            Expanded(
              child: _active == null
                  ? const Center(child: Text('Нет вкладок'))
                  : TerminalView(
                      _active!.terminal,
                      key: ValueKey(_active!.id),
                      focusNode: _termFocus,
                      autofocus: true,
                      theme: _fluentTerminalTheme(theme),
                      textStyle: const TerminalStyle(
                        fontSize: 13,
                        fontFamily: 'Menlo',
                      ),
                      // D6: два сочетания рабочего места перехватываются раньше эмулятора.
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.backquote &&
                            HardwareKeyboard.instance.isControlPressed) {
                          if (HardwareKeyboard.instance.isShiftPressed) {
                            _newTab();
                          } else {
                            _toggleFocus();
                          }
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                    ),
            ),
            SizedBox(
              height: 140,
              child: ValueListenableBuilder<List<String>>(
                valueListenable: _logLines,
                builder: (_, lines, _) => ListView(
                  reverse: true,
                  children: [
                    for (final l in lines.reversed)
                      Text(l, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Тема терминала из `FluentTheme` (пункт 6 спайка): цвета фона/текста/курсора/
/// выделения берутся из темы Fluent, ANSI-палитра — по умолчанию xterm2.
TerminalTheme _fluentTerminalTheme(FluentThemeData t) {
  const d = TerminalThemes.defaultTheme;
  return TerminalTheme(
    cursor: t.accentColor.defaultBrushFor(t.brightness),
    selection: t.accentColor
        .defaultBrushFor(t.brightness)
        .withValues(alpha: 0.35),
    foreground: t.typography.body?.color ?? d.foreground,
    background: t.scaffoldBackgroundColor,
    black: d.black,
    red: d.red,
    green: d.green,
    yellow: d.yellow,
    blue: d.blue,
    magenta: d.magenta,
    cyan: d.cyan,
    white: d.white,
    brightBlack: d.brightBlack,
    brightRed: d.brightRed,
    brightGreen: d.brightGreen,
    brightYellow: d.brightYellow,
    brightBlue: d.brightBlue,
    brightMagenta: d.brightMagenta,
    brightCyan: d.brightCyan,
    brightWhite: d.brightWhite,
    searchHitBackground: d.searchHitBackground,
    searchHitBackgroundCurrent: d.searchHitBackgroundCurrent,
    searchHitForeground: d.searchHitForeground,
  );
}

/// Статистика кадров: на «рывки» указывают кадры дольше 16/33/100 мс.
class _FrameStats {
  final summary = ValueNotifier<String>('frames: 0');
  int _n = 0, _over16 = 0, _over33 = 0, _over100 = 0;
  Duration _worst = Duration.zero;

  void reset() {
    _n = _over16 = _over33 = _over100 = 0;
    _worst = Duration.zero;
    summary.value = 'frames: 0';
  }

  void onTimings(List<FrameTiming> timings) {
    for (final f in timings) {
      _n++;
      final d = f.totalSpan;
      if (d > _worst) _worst = d;
      if (d.inMilliseconds > 16) _over16++;
      if (d.inMilliseconds > 33) _over33++;
      if (d.inMilliseconds > 100) _over100++;
    }
    summary.value =
        'frames: $_n, >16ms: $_over16, >33ms: $_over33, >100ms: $_over100, worst: ${_worst.inMilliseconds} ms';
  }
}
