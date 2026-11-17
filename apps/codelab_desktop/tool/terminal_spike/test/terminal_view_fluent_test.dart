// Спайк 1.1: пункты 3 и 6 — `TerminalView` в `FluentApp` без Material и
// запрет буфера обмена на уровне виджета (D3, Q13).
import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_spike/terminal_policy.dart';
import 'package:xterm2/xterm.dart';

String _b64(String s) => base64.encode(utf8.encode(s));

void main() {
  late List<String> channelCalls;

  setUp(() {
    channelCalls = [];
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            channelCalls.add('setData(${(call.arguments as Map)['text']})');
          }
          if (call.method == 'Clipboard.getData') {
            channelCalls.add('getData');
            return <String, dynamic>{'text': 'CLIPBOARD-CONTENT'};
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<FocusNode> pump(WidgetTester tester, Terminal terminal) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          padding: EdgeInsets.zero,
          content: Builder(
            builder: (context) {
              final t = FluentTheme.of(context);
              return TerminalView(
                terminal,
                focusNode: focus,
                autofocus: true,
                theme: TerminalTheme(
                  cursor: t.accentColor,
                  selection: t.accentColor.withValues(alpha: .3),
                  foreground: t.typography.body!.color!,
                  background: t.scaffoldBackgroundColor,
                  black: const Color(0xFF000000),
                  red: const Color(0xFFCD3131),
                  green: const Color(0xFF0DBC79),
                  yellow: const Color(0xFFE5E510),
                  blue: const Color(0xFF2472C8),
                  magenta: const Color(0xFFBC3FBC),
                  cyan: const Color(0xFF11A8CD),
                  white: const Color(0xFFE5E5E5),
                  brightBlack: const Color(0xFF666666),
                  brightRed: const Color(0xFFF14C4C),
                  brightGreen: const Color(0xFF23D18B),
                  brightYellow: const Color(0xFFF5F543),
                  brightBlue: const Color(0xFF3B8EEA),
                  brightMagenta: const Color(0xFFD670D6),
                  brightCyan: const Color(0xFF29B8DB),
                  brightWhite: const Color(0xFFE5E5E5),
                  searchHitBackground: const Color(0xFFFFFF2B),
                  searchHitBackgroundCurrent: const Color(0xFF31FF26),
                  searchHitForeground: const Color(0xFF000000),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return focus;
  }

  testWidgets('TerminalView работает внутри FluentApp без Material', (
    tester,
  ) async {
    final terminal = buildPolicyTerminal(onOutput: (_) {});
    await pump(tester, terminal);
    terminal.write('hello \x1b[31mred\x1b[0m\r\n');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(TerminalView), findsOneWidget);
    expect(find.byType(MaterialApp), findsNothing);
    expect(
      find.byType(Material),
      findsNothing,
      reason: 'Material-виджеты не создаются',
    );
  });

  testWidgets('политика D3/Q13: OSC 52/1337/5522 не пишут и не читают буфер', (
    tester,
  ) async {
    final out = <String>[];
    final attempts = <String>[];
    final terminal = buildPolicyTerminal(
      onOutput: out.add,
      onClipboardAttempt: attempts.add,
    );
    final focus = await pump(tester, terminal);
    expect(
      focus.hasFocus,
      isTrue,
      reason: 'фокус нужен: TerminalView пишет в буфер только в фокусе',
    );

    terminal.write('\x1b]52;c;${_b64('SECRET')}\x07');
    terminal.write('\x1b]52;c;?\x07');
    terminal.write(
      '\x1b]1337;CopyToClipboard=\x07SECRET\n\x1b]1337;EndCopy\x07',
    );
    terminal.write('\x1b]5522;type=write;${_b64('SECRET')}\x07');
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      channelCalls,
      isEmpty,
      reason: 'в системный буфер не писали и не читали',
    );
    expect(
      out.where((s) => s.contains(']52;')),
      isEmpty,
      reason: 'ответа на OSC 52 query нет',
    );
    // ignore: avoid_print
    print(
      'policy: channelCalls=$channelCalls, onOutput=$out, handler attempts=$attempts',
    );
  });

  testWidgets(
    'контроль: без явных обработчиков TerminalView пишет и читает буфер',
    (tester) async {
      final out = <String>[];
      final terminal = Terminal(onOutput: out.add);
      await pump(tester, terminal);

      terminal.write('\x1b]52;c;${_b64('SECRET')}\x07');
      terminal.write('\x1b]52;c;?\x07');
      await tester.pump(const Duration(milliseconds: 50));

      // ignore: avoid_print
      print(
        'control (default Terminal): channelCalls=$channelCalls, onOutput=$out',
      );
      expect(channelCalls, contains('setData(SECRET)'));
      expect(channelCalls, contains('getData'));
    },
  );
}
