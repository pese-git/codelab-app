// Ссылки OSC 8 в выводе терминала собранного приложения (задача 2.9 change
// `add-integrated-terminal`; spec `integrated-terminal` «Ссылки в выводе
// терминала»; D3 «Ссылки OSC 8», D9, D11; Q14, Q16).
//
// Тест красный до задачи 2.10. Чего нет сейчас:
// * порта `ExternalLinkOpener` и `ExternalLinkOutcome`
//   (`lib/core/platform/external_link_opener.dart`);
// * шва `externalLinkOpener:` у `createCodeLabRootScope` и
//   `CodeLabTestBinding` (по образцу `userShellLauncher:`; в 2.10 параметр
//   добавляется в `test_app_scope.dart`, здесь он уже используется);
// * `onHyperlinkTap` у `TerminalView` панели, диалога `terminal-link-dialog`
//   и событий `terminal.link_opened` / `terminal.link_refused`.
//
// Контракт ключей диалога для 2.10: `terminal-link-dialog` (ContentDialog),
// `terminal-link-address` (полный адрес как есть), `terminal-link-open`
// (только для http/https), `terminal-link-cancel`; сообщение отказа —
// «Only http and https links can be opened.».
//
// Модификатор проверяет сам `TerminalView` (xterm2 5.4.0) по
// `defaultTargetPlatform`: Meta на macOS. Поэтому каждый тест идёт с
// `TargetPlatformVariant.only(macOS)` (платформа сбрасывается раннером).

import 'dart:convert';

import 'package:cherrypick/cherrypick.dart' show Scope;
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/terminal/application/terminal_tabs_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;
import 'package:xterm2/ui.dart' show TerminalView;

import '../../../support/fake_external_link_opener.dart';
import '../../../support/fake_user_shell_launcher.dart';
import '../../../support/test_app_scope.dart';

/// Приложение с fake-портами терминала и открытия адреса.
///
/// Почему локально: общий `_Env` в `terminal_pane_test.dart` приватный, а
/// выносить его до 2.10 значило бы трогать несвязанный тест (§19).
/// Как использовать: `_Env()`, затем `open(tester)` — подключение, сессия и
/// открытая панель Terminal с вкладкой `t1`.
final class _Env {
  _Env() {
    binding = CodeLabTestBinding(
      stdioTransportFactory: (_) => agent,
      userShellLauncher: launcher,
      externalLinkOpener: opener,
    );
    scope = binding.scope;
  }

  final FakeUserShellLauncher launcher = FakeUserShellLauncher()
    ..shellsExitOnHangUp = true;
  final FakeExternalLinkOpener opener = FakeExternalLinkOpener();
  final FakeAcpTransport agent = FakeAcpTransport();
  late final CodeLabTestBinding binding;
  late final Scope scope;

  CodeLabShellCubit get shell => scope.resolve<CodeLabShellCubit>();
  TerminalTabsCubit get terminals => scope.resolve<TerminalTabsCubit>();

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      CodeLabBootstrap(scope: scope, child: const CodeLabApp()),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await shell.selectProject('/work/a');
      await shell.connect();
      final sent = agent.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == sessionNewMethod,
      );
      final created = shell.createSession();
      final request = await sent as JsonRpcRequest;
      agent.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          result: {'sessionId': 'session-a'},
        ),
      );
      await created;
    });
    await tester.pump();
    await tester.pump();
    tester
        .widget<ToggleButton>(
          find.byKey(CodeLabAppBar.toggleKey(ToolPane.terminal)),
        )
        .onChanged!(true);
    await _frames(tester);
  }

  /// Выводит в терминал вкладки `t1` ссылку OSC 8: [text] — видимый текст в
  /// колонках с нулевой, [uri] — адрес. Сначала ссылка, поэтому клик в первую
  /// клетку области попадает на неё.
  Future<void> printLink(
    WidgetTester tester, {
    required String uri,
    required String text,
  }) async {
    launcher.shells.single.emit('\x1b]8;;$uri\x1b\\$text\x1b]8;;\x1b\\');
    await _frames(tester);
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  // Анимация закрытия диалога Fluent длится дольше двух кадров, а
  // `pumpAndSettle` не годится: курсор терминала мигает вечно (2.10).
  await tester.pump(const Duration(milliseconds: 500));
}

/// Точка внутри первой клетки области терминала (отступ `TerminalView` —
/// 8 × 4, клетка не меньше 5 px).
Offset _firstCell(WidgetTester tester) =>
    tester.getTopLeft(find.byType(TerminalView)) + const Offset(8 + 2, 4 + 2);

/// Cmd+клик по первой клетке.
Future<void> _cmdClick(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.tapAt(_firstCell(tester));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await _frames(tester);
}

/// Записи журнала приложения строками JSON.
List<String> _logged(_Env env) => [
  for (final entry in env.scope.resolve<LogBuffer>().entries.value)
    jsonEncode(entry, toEncodable: (o) => '$o'),
];

final _dialog = find.byKey(const ValueKey('terminal-link-dialog'));
final _open = find.byKey(const ValueKey('terminal-link-open'));
final _cancel = find.byKey(const ValueKey('terminal-link-cancel'));
const _refusal = 'Only http and https links can be opened.';
final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  group('Cmd+клик по ссылке OSC 8', () {
    testWidgets('https: диалог с полным адресом, а не текстом ссылки; '
        '«Open» вызывает порт ровно один раз', (tester) async {
      final env = _Env();
      await env.open(tester);
      await env.printLink(
        tester,
        uri: 'https://example.com/docs?q=1',
        text: 'docs',
      );

      await _cmdClick(tester);

      expect(_dialog, findsOneWidget);
      expect(
        find.descendant(
          of: _dialog,
          matching: find.text('https://example.com/docs?q=1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _dialog, matching: find.text('docs')),
        findsNothing,
      );
      expect(_open, findsOneWidget);
      expect(
        env.opener.opened,
        isEmpty,
        reason: 'до подтверждения не открывать',
      );

      await tester.tap(_open);
      await _frames(tester);

      expect(env.opener.opened, [Uri.parse('https://example.com/docs?q=1')]);
      expect(_dialog, findsNothing);
    }, variant: _macOS);

    testWidgets('текст ссылки не совпадает с адресом: диалог показывает '
        'адрес', (tester) async {
      final env = _Env();
      await env.open(tester);
      await env.printLink(
        tester,
        uri: 'https://evil.example/login',
        text: 'https://safe.example',
      );

      await _cmdClick(tester);

      expect(
        find.descendant(
          of: _dialog,
          matching: find.text('https://evil.example/login'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _dialog,
          matching: find.textContaining('safe.example'),
        ),
        findsNothing,
      );
    }, variant: _macOS);

    testWidgets('диалог показывает нормализованный адрес, и порт получает '
        'тот же Uri (Q21)', (tester) async {
      final env = _Env();
      await env.open(tester);
      await env.printLink(
        tester,
        uri: 'https://example.com/a b/é',
        text: 'docs',
      );

      await _cmdClick(tester);

      final shown = tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('terminal-link-address')),
          )
          .data;
      expect(shown, 'https://example.com/a%20b/%C3%A9');

      await tester.tap(_open);
      await _frames(tester);

      expect(env.opener.opened.map((u) => u.toString()), [shown]);
    }, variant: _macOS);

    testWidgets('адрес со скрытым символом bidi: в диалоге он закодирован, '
        '«Open» нет, порт не вызывается (Q21)', (tester) async {
      final env = _Env();
      await env.open(tester);
      await env.printLink(
        tester,
        uri: 'https://example.com/\u202Epath',
        text: 'docs',
      );

      await _cmdClick(tester);

      expect(_dialog, findsOneWidget);
      expect(
        find.descendant(
          of: _dialog,
          matching: find.text('https://example.com/%E2%80%AEpath'),
        ),
        findsOneWidget,
      );
      expect(_open, findsNothing);
      expect(env.opener.opened, isEmpty);
      expect(
        _logged(env).where((l) => l.contains('terminal.link_refused')),
        hasLength(1),
      );
    }, variant: _macOS);

    testWidgets('«Cancel» закрывает диалог и не вызывает порт', (tester) async {
      final env = _Env();
      await env.open(tester);
      await env.printLink(tester, uri: 'https://example.com', text: 'docs');
      await _cmdClick(tester);
      expect(_dialog, findsOneWidget);

      await tester.tap(_cancel);
      await _frames(tester);

      expect(_dialog, findsNothing);
      expect(env.opener.opened, isEmpty);
    }, variant: _macOS);

    testWidgets('Esc закрывает диалог и не вызывает порт', (tester) async {
      final env = _Env();
      await env.open(tester);
      await env.printLink(tester, uri: 'https://example.com', text: 'docs');
      await _cmdClick(tester);
      expect(_dialog, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _frames(tester);

      expect(_dialog, findsNothing);
      expect(env.opener.opened, isEmpty);
    }, variant: _macOS);

    testWidgets('file: диалог с адресом и сообщением, без «Open»; порт не '
        'вызывается', (tester) async {
      final env = _Env();
      await env.open(tester);
      await env.printLink(tester, uri: 'file:///etc/passwd', text: 'passwd');

      await _cmdClick(tester);

      expect(_dialog, findsOneWidget);
      expect(
        find.descendant(of: _dialog, matching: find.text('file:///etc/passwd')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _dialog, matching: find.text(_refusal)),
        findsOneWidget,
      );
      expect(_open, findsNothing);
      expect(
        find.descendant(of: _dialog, matching: find.text('Open')),
        findsNothing,
      );
      expect(env.opener.opened, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _frames(tester);
      expect(env.opener.opened, isEmpty);
    }, variant: _macOS);
  });

  group('без жеста и без подтверждения', () {
    testWidgets('обычный клик по ссылке не открывает диалог', (tester) async {
      final env = _Env();
      await env.open(tester);
      await env.printLink(tester, uri: 'https://example.com', text: 'docs');

      await tester.tapAt(_firstCell(tester));
      await _frames(tester);

      expect(_dialog, findsNothing);
      expect(env.opener.opened, isEmpty);
    }, variant: _macOS);

    testWidgets('OSC 1337 OpenURL в выводе не открывает адрес и диалог '
        '(`onOpenUrl` не задан)', (tester) async {
      final env = _Env();
      await env.open(tester);

      env.launcher.shells.single.emit(
        '\x1b]1337;OpenURL=https://example.com/silent\x1b\\',
      );
      await _frames(tester);

      expect(env.terminals.terminalOf('t1')!.onOpenUrl, isNull);
      expect(_dialog, findsNothing);
      expect(env.opener.opened, isEmpty);
    }, variant: _macOS);
  });

  group('журнал (D9)', () {
    testWidgets('адрес не попадает в журнал, события несут только схему', (
      tester,
    ) async {
      final env = _Env();
      await env.open(tester);
      const secretUri = 'https://example.com/LINK_SECRET_7c1d?token=abc';
      await env.printLink(tester, uri: secretUri, text: 'docs');
      await _cmdClick(tester);
      await tester.tap(_open);
      await _frames(tester);

      // Очистка экрана и курсор в начало: иначе первая клетка остаётся за
      // первой (https) ссылкой, а не за новой.
      env.launcher.shells.single.emit('\x1b[2J\x1b[H');
      await env.printLink(tester, uri: 'file:///etc/passwd', text: 'passwd');
      await _cmdClick(tester);

      final lines = _logged(env);
      expect(lines.where((l) => l.contains('LINK_SECRET_7c1d')), isEmpty);
      expect(lines.where((l) => l.contains('token=abc')), isEmpty);
      expect(lines.where((l) => l.contains('/etc/passwd')), isEmpty);
      final opened = lines.where((l) => l.contains('terminal.link_opened'));
      final refused = lines.where((l) => l.contains('terminal.link_refused'));
      expect(opened, hasLength(1));
      expect(opened.single, matches(RegExp(r'"scheme":\s*"https"')));
      expect(refused, hasLength(1));
      expect(refused.single, matches(RegExp(r'"scheme":\s*"file"')));
    }, variant: _macOS);
  });
}
