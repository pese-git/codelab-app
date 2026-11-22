// Панель Protocol в собранном приложении (задача 5.3 change
// `redesign-protocol-pane`; spec agent-workbench-ui «Панель Protocol: виды
// Frames и Log», «Таблица кадров», «Выбранный кадр», «Вид Log панели
// Protocol», «Pause, Clear и Export панели Protocol», «Режим Trace панели
// Protocol», «Полноэкранный log viewer — master-detail»; approval-safety
// «Секрет скрыт и в режиме Trace»; testing-quality «Рендерится панель
// Protocol»; design.md D1, D6, D7, D8, D10, D12, D17).
//
// Красный до задач 5.2 и 5.4: у `CodeLabTestBinding` и
// `createCodeLabRootScope` нет швов `debugBuild:` и `protocolExportSaver:`, в
// `CodeLabShell` нет ветки `ToolPane.protocol` с виджетом панели, а
// `/logs` не выбирает вид Log. Кадры идут из настоящего ядра клиента:
// сценарный агент (`FakeAcpTransport`) отвечает на `initialize` и
// `session/new`, а секретные поля добавляет исходящее с агента уведомление.
//
// Идентификаторы, которых нет в design.md и которые задаёт этот тест (для
// 5.4): `ValueKey('protocol-trace')` — переключатель Trace (`ToggleButton`),
// `protocol-search` — поле поиска, `protocol-log-expand` — иконка `Expand`,
// `protocol-export-confirm` и `protocol-export-cancel` — кнопки подтверждения
// экспорта. Тексты — из spec, на английском. Остальное ищется по тексту и по
// ключам кита (`protocol-table`, `protocol-detail`, `protocol-row-<id>`).
//
// Тесты на Dart VM, без плагинов Flutter (§21): диалог сохранения подменён
// портом `FakeProtocolExportSaver`, буфер обмена — каналом платформы.

import 'dart:async';
import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show ProtocolPayloadOmitted;
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/core/platform/protocol_export_saver.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_pane_cubit.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_pane_state.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_pane_view.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart'
    show FluentLogViewerPage;
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;
import 'package:structured_log/structured_log.dart' show LogLevel;

import '../../../support/fake_protocol_export_saver.dart';
import '../../../support/start_agent.dart';
import '../../../support/test_app_scope.dart';

const _secret = 'ghp_abc';
const _masked = '••••••• (masked)';

Finder _key(String key) => find.byKey(ValueKey(key));
final _protocolPane = find.byKey(CodeLabToolDock.paneKey(ToolPane.protocol));
final _protocolToggle = find.byKey(CodeLabAppBar.toggleKey(ToolPane.protocol));
Finder _inPane(Finder matching) =>
    find.descendant(of: _protocolPane, matching: matching);

/// Окружение теста: приложение, сценарный агент и порты.
final class _Env {
  _Env({required this.debug, FakeProtocolExportSaver? saver})
    : saver = saver ?? FakeProtocolExportSaver();

  final bool debug;
  final FakeProtocolExportSaver saver;
  final FakeAcpTransport agent = FakeAcpTransport();
  late final CodeLabTestBinding binding;
  late final CodeLabShellCubit shell;

  ProtocolPaneCubit get cubit => binding.scope.resolve<ProtocolPaneCubit>();
  LogBuffer get logBuffer => binding.scope.resolve<LogBuffer>();

  Future<void> pump(WidgetTester tester, {bool connect = true}) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    binding = CodeLabTestBinding(
      project: '/workspace',
      transport: FakeAcpTransport(),
      stdioTransportFactory: (_) => agent,
      debugBuild: debug,
      protocolExportSaver: saver,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    shell = binding.scope.resolve<CodeLabShellCubit>();
    if (connect) {
      await tester.runAsync(() => shell.startWith());
      await tester.pump();
    }
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    // Публикация Cubit склеивается таймером 100 мс (D7).
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> createSession(WidgetTester tester, String id) async {
    agent.drainSentMessages();
    unawaited(shell.createSession());
    await settle(tester);
    final request = agent.sentMessages.whereType<JsonRpcRequest>().singleWhere(
      (r) => r.method == sessionNewMethod,
    );
    agent.emitInbound(
      JsonRpcMessage.response(id: request.id, result: {'sessionId': id}),
    );
    await settle(tester);
  }

  /// Уведомление агента с секретом в `_meta` (spec «Кадр с секретами»).
  void emitSecretUpdate(String sessionId) => agent.emitInbound(
    JsonRpcMessage.notification(
      method: sessionUpdateMethod,
      params: {
        'sessionId': sessionId,
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'hi'},
        },
        '_meta': {'apiKey': _secret},
      },
    ),
  );

  Future<void> openPane(WidgetTester tester) async {
    tester.widget<ToggleButton>(_protocolToggle).onChanged!(true);
    await settle(tester);
  }

  Future<void> closePane(WidgetTester tester) async {
    tester.widget<ToggleButton>(_protocolToggle).onChanged!(false);
    await settle(tester);
  }

  Future<void> tearDown(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }
}

/// Нажатие кнопки действий в строке вкладок дока. Строка действий в доке
/// 360 px прокручивается (в тестовом шрифте Ahem кнопки шире настоящих), поэтому
/// кнопка сначала прокручивается в видимую область, как сделал бы пользователь.
Future<void> _tapAction(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
}

/// Нажатие по строке таблицы по тексту ячейки метода.
Future<void> _tapRow(WidgetTester tester, String label) async {
  await tester.tap(_inPane(find.text(label)));
  await tester.pump();
}

/// Подмена буфера обмена: записанный текст собирается в [sink].
void _captureClipboard(WidgetTester tester, List<String> sink) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        sink.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void main() {
  group('debug-сборка (политика full)', () {
    testWidgets('виды и счётчики, действия шапки дока, переключателя Trace '
        'нет', (tester) async {
      final env = _Env(debug: true);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);

      expect(_protocolPane, findsOneWidget);
      expect(env.cubit.state.view, ProtocolView.frames);
      final frames = env.cubit.state.framesCount;
      expect(frames, greaterThan(0));
      expect(_inPane(find.text('Frames $frames')), findsOneWidget);
      expect(_inPane(find.textContaining('Log ')), findsOneWidget);
      // Действия — в строке вкладок дока, а не в теле панели.
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('Export…'), findsOneWidget);
      expect(_key('protocol-trace'), findsNothing);
      expect(find.text('Trace'), findsNothing);
      expect(find.text('Select a frame to see its details.'), findsOneWidget);
      await env.tearDown(tester);
    });

    testWidgets('кадр с секретами: значения замаскированы, исходного секрета '
        'нигде нет, Copy копирует показанное тело', (tester) async {
      final copied = <String>[];
      _captureClipboard(tester, copied);
      final env = _Env(debug: true);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      env.emitSecretUpdate('s_7f3a');
      await env.settle(tester);
      await env.openPane(tester);

      await _tapRow(tester, 'session/update · agent_message_chunk');

      expect(find.text('Debug build: full payloads.'), findsOneWidget);
      expect(
        find.textContaining(
          'Release builds keep metadata only.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.textContaining(_masked, findRichText: true), findsOneWidget);
      expect(find.textContaining(_secret, findRichText: true), findsNothing);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      final selected = env.cubit.state.selectedFrame!;
      expect(copied, [protocolFrameCopyText(selected)]);
      expect(copied.single, isNot(contains(_secret)));
      await env.tearDown(tester);
    });

    testWidgets('экспорт: подтверждение «Export full payloads?», отказ ничего '
        'не пишет, согласие записывает файл', (tester) async {
      final env = _Env(debug: true);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);

      await _tapAction(tester, 'Export…');
      await tester.pumpAndSettle();
      expect(find.text('Export full payloads?'), findsOneWidget);
      expect(
        find.text(
          'The file will contain prompts, file contents and tool output from '
          'these frames. Secrets are masked.',
        ),
        findsOneWidget,
      );
      await tester.tap(_key('protocol-export-cancel'));
      await tester.pumpAndSettle();
      expect(env.saver.saved, isEmpty);
      expect(find.text('Export full payloads?'), findsNothing);

      await _tapAction(tester, 'Export…');
      await tester.pumpAndSettle();
      await tester.tap(_key('protocol-export-confirm'));
      await tester.pumpAndSettle();

      expect(env.saver.saved, hasLength(1));
      expect(
        env.saver.saved.single.suggestedName,
        startsWith('codelab-protocol-frames-'),
      );
      final header = jsonDecode(
        const LineSplitter().convert(env.saver.saved.single.text).first,
      );
      expect((header as Map)['build'], 'debug');
      await env.tearDown(tester);
    });

    testWidgets('сбой записи: заметка «Couldn\'t save the file.»', (
      tester,
    ) async {
      final env = _Env(
        debug: true,
        saver: FakeProtocolExportSaver(
          result: const ProtocolExportFailed('FileSystemException'),
        ),
      );
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);

      await _tapAction(tester, 'Export…');
      await tester.pumpAndSettle();
      await tester.tap(_key('protocol-export-confirm'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't save the file."), findsOneWidget);
      expect(env.cubit.state.saveFailed, isTrue);
      await env.tearDown(tester);
    });
  });

  group('release-сборка (политика metadataOnly)', () {
    testWidgets('переключатель Trace стоит перед Pause, Clear и Export… и не '
        'нажат', (tester) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);

      final trace = _key('protocol-trace');
      expect(trace, findsOneWidget);
      expect(tester.widget<ToggleButton>(trace).checked, isFalse);
      final traceLeft = tester.getRect(trace).left;
      for (final label in ['Pause', 'Clear', 'Export…']) {
        expect(
          tester.getRect(find.text(label)).left,
          greaterThan(traceLeft),
          reason: label,
        );
      }
      await env.tearDown(tester);
    });

    testWidgets('кадр: InfoBar «Release build: metadata only.», тело — поля '
        'кадра, Copy копирует только поля', (tester) async {
      final copied = <String>[];
      _captureClipboard(tester, copied);
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);

      await _tapRow(tester, 'session/new');

      expect(find.text('Release build: metadata only.'), findsOneWidget);
      expect(
        find.text(
          'Payloads are not stored. Secrets are masked before a frame is '
          'stored.',
        ),
        findsOneWidget,
      );
      for (final field in ['direction', 'kind', 'method', 'size']) {
        expect(_inPane(find.text(field)), findsWidgets, reason: field);
      }
      expect(find.textContaining(_masked, findRichText: true), findsNothing);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      final decoded = jsonDecode(copied.single) as Map<String, Object?>;
      expect(decoded['method'], 'session/new');
      expect(decoded.containsKey('payload'), isFalse);
      await env.tearDown(tester);
    });

    testWidgets('Trace: включение даёт полные payload с маскированием, '
        'кадр до включения — поля и строка про метаданные', (tester) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);
      await _tapRow(tester, 'session/new');
      expect(find.text('Release build: metadata only.'), findsOneWidget);

      tester.widget<ToggleButton>(_key('protocol-trace')).onChanged!(true);
      await env.settle(tester);
      expect(env.cubit.state.traceEnabled, isTrue);
      expect(
        tester.widget<ToggleButton>(_key('protocol-trace')).checked,
        isTrue,
      );
      // Выбранный до включения кадр остаётся без payload.
      expect(find.text('Trace on: full payloads.'), findsOneWidget);
      expect(
        find.text('Recorded before Trace was turned on: metadata only.'),
        findsOneWidget,
      );

      env.emitSecretUpdate('s_7f3a');
      await env.settle(tester);
      await _tapRow(tester, 'session/update · agent_message_chunk');

      expect(find.text('Trace on: full payloads.'), findsOneWidget);
      expect(
        find.text(
          'Prompts, file contents and tool output are kept in memory until '
          'Trace is turned off. Secrets are masked.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining(_masked, findRichText: true), findsOneWidget);
      expect(find.textContaining(_secret, findRichText: true), findsNothing);
      await env.tearDown(tester);
    });

    testWidgets('выключение Trace снимает payload с выбранного кадра', (
      tester,
    ) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);
      tester.widget<ToggleButton>(_key('protocol-trace')).onChanged!(true);
      await env.settle(tester);
      env.emitSecretUpdate('s_7f3a');
      await env.settle(tester);
      await _tapRow(tester, 'session/update · agent_message_chunk');
      expect(find.textContaining(_masked, findRichText: true), findsOneWidget);

      tester.widget<ToggleButton>(_key('protocol-trace')).onChanged!(false);
      await env.settle(tester);

      expect(find.text('Release build: metadata only.'), findsOneWidget);
      expect(find.textContaining(_masked, findRichText: true), findsNothing);
      expect(env.cubit.state.selectedFrame!.payload, isNull);
      expect(
        env.cubit.state.selectedFrame!.payloadOmitted,
        ProtocolPayloadOmitted.policy,
      );
      await env.tearDown(tester);
    });

    testWidgets('экспорт без payload — без подтверждения; в режиме Trace — '
        'с подтверждением', (tester) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);

      await _tapAction(tester, 'Export…');
      await tester.pumpAndSettle();
      expect(find.text('Export full payloads?'), findsNothing);
      expect(env.saver.saved, hasLength(1));

      tester.widget<ToggleButton>(_key('protocol-trace')).onChanged!(true);
      await env.settle(tester);
      env.emitSecretUpdate('s_7f3a');
      await env.settle(tester);
      await _tapAction(tester, 'Export…');
      await tester.pumpAndSettle();

      expect(find.text('Export full payloads?'), findsOneWidget);
      await env.tearDown(tester);
    });
  });

  group('область, фокус, вид Log', () {
    testWidgets('нет сессии в фокусе: заметка и элементы соединения с тегом '
        'connection', (tester) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.openPane(tester);

      expect(
        find.text('No session in focus. Showing connection frames only.'),
        findsOneWidget,
      );
      expect(_inPane(find.text('initialize')), findsOneWidget);
      expect(_inPane(find.text('connection')), findsWidgets);
      await env.tearDown(tester);
    });

    testWidgets('с сессией в фокусе заметки нет, запрос session/new — в своей '
        'сессии без тега connection', (tester) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);

      expect(find.textContaining('No session in focus'), findsNothing);
      expect(_inPane(find.text('session/new')), findsOneWidget);
      expect(_inPane(find.text('session/new · result')), findsOneWidget);
      expect(env.cubit.state.focusedSessionId, 's_7f3a');
      await env.tearDown(tester);
    });

    testWidgets('панель следует за фокусом: кадры другой сессии не видны, '
        'таблице передан новый tailScope', (tester) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      env.agent.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: {
            'sessionId': 's_7f3a',
            'update': {
              'sessionUpdate': 'agent_thought_chunk',
              'content': {'type': 'text', 'text': 'x'},
            },
          },
        ),
      );
      await env.settle(tester);
      await env.createSession(tester, 's_91c0');
      await env.openPane(tester);

      expect(
        _inPane(find.text('session/update · agent_thought_chunk')),
        findsNothing,
      );
      expect(
        tester
            .widget<CodeLabProtocolPane>(
              _inPane(find.byType(CodeLabProtocolPane)),
            )
            .tailScope,
        's_91c0',
      );

      env.shell.selectSession('s_7f3a');
      await env.settle(tester);

      expect(
        _inPane(find.text('session/update · agent_thought_chunk')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CodeLabProtocolPane>(
              _inPane(find.byType(CodeLabProtocolPane)),
            )
            .tailScope,
        's_7f3a',
      );
      await env.tearDown(tester);
    });

    testWidgets('/logs открывает Protocol с видом Log, полноэкранный просмотр '
        'не открывается', (tester) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      expect(env.cubit.state.view, ProtocolView.frames);

      env.shell.openCommandPalette();
      await tester.pump();
      await tester.pump();
      env.shell.selectCommand(
        env.shell.state.paletteActions.firstWhere((a) => a.id == 'logs'),
      );
      await env.settle(tester);

      expect(_protocolPane, findsOneWidget);
      expect(env.cubit.state.view, ProtocolView.log);
      expect(find.byType(FluentLogViewerPage), findsNothing);
      for (final column in ['Time', 'Level', 'Category', 'Event']) {
        expect(_inPane(find.text(column)), findsWidgets, reason: column);
      }
      await env.tearDown(tester);
    });

    testWidgets('Expand открывает полноэкранный просмотр, Esc возвращает без '
        'изменений вида и фильтров', (tester) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.openPane(tester);
      env.cubit.openLog();
      env.cubit.setLogQuery('connection');
      await env.settle(tester);

      await tester.tap(_key('protocol-log-expand'));
      await tester.pumpAndSettle();
      expect(find.byType(FluentLogViewerPage), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(FluentLogViewerPage), findsNothing);
      expect(_protocolPane, findsOneWidget);
      expect(env.cubit.state.view, ProtocolView.log);
      expect(env.cubit.state.logFilter.query, 'connection');
      await env.tearDown(tester);
    });

    testWidgets(
      'Clear в Log очищает буфер журнала, который видит и полноэкранный '
      'просмотр; буфер кадров не меняется',
      (tester) async {
        final env = _Env(debug: false);
        await env.pump(tester);
        await env.openPane(tester);
        env.logBuffer.capture({
          'event': 'marker_before_clear',
          'level': 'info',
        }, LogLevel.info);
        env.cubit.openLog();
        await env.settle(tester);
        final frames = env.cubit.state.framesCount;

        await _tapAction(tester, 'Clear');
        await env.settle(tester);

        expect(
          env.logBuffer.entries.value.where(
            (e) => e['event'] == 'marker_before_clear',
          ),
          isEmpty,
        );
        expect(env.cubit.state.framesCount, frames);
        await tester.tap(_key('protocol-log-expand'));
        await tester.pumpAndSettle();
        expect(find.text('marker_before_clear'), findsNothing);
        await env.tearDown(tester);
      },
    );
  });

  group('действия и состояние панели', () {
    testWidgets('действия есть только у активной вкладки Protocol', (
      tester,
    ) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);
      env.shell.togglePane(ToolPane.plan);
      await env.settle(tester);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Export…'), findsNothing);

      await tester.tap(_key('tool-tab-protocol'));
      await env.settle(tester);

      expect(find.text('Pause'), findsOneWidget);
      await env.tearDown(tester);
    });

    testWidgets('Pause становится Resume, Frames на паузе не получает '
        'followTail', (tester) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);
      CodeLabProtocolPane pane() => tester.widget<CodeLabProtocolPane>(
        _inPane(find.byType(CodeLabProtocolPane)),
      );
      expect(pane().followTail, isTrue);

      await _tapAction(tester, 'Pause');
      await env.settle(tester);

      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      expect(env.cubit.state.framesPaused, isTrue);
      expect(pane().followTail, isFalse);

      await _tapAction(tester, 'Resume');
      await env.settle(tester);
      expect(find.text('Pause'), findsOneWidget);
      expect(pane().followTail, isTrue);
      await env.tearDown(tester);
    });

    testWidgets('Clear в Frames: таблица пуста, «No frames yet.»', (
      tester,
    ) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);

      await _tapAction(tester, 'Clear');
      await env.settle(tester);

      expect(env.cubit.state.framesCount, 0);
      expect(find.text('No frames yet.'), findsOneWidget);
      await env.tearDown(tester);
    });

    testWidgets('Export… недоступна при пустой таблице', (tester) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);
      await _tapAction(tester, 'Clear');
      await env.settle(tester);

      final export = find.ancestor(
        of: find.text('Export…'),
        matching: find.byWidgetPredicate(
          (w) => w is Button || w is FilledButton,
        ),
      );
      expect(
        tester
            .widgetList(export)
            .any(
              (w) =>
                  (w is Button && w.onPressed == null) ||
                  (w is FilledButton && w.onPressed == null),
            ),
        isTrue,
      );
      await env.tearDown(tester);
    });

    testWidgets('фильтры переживают закрытие вкладки', (tester) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);
      await tester.enterText(_key('protocol-search'), 'session/new');
      await env.settle(tester);
      expect(_inPane(find.text('initialize')), findsNothing);

      await env.closePane(tester);
      expect(_protocolPane, findsNothing);
      await env.openPane(tester);

      expect(
        tester.widget<TextBox>(_key('protocol-search')).controller!.text,
        'session/new',
      );
      expect(_inPane(find.text('initialize')), findsNothing);
      // Только таблица: тот же текст стоит и в самом поле поиска.
      expect(
        find.descendant(
          of: _key('protocol-table'),
          matching: find.text('session/new'),
        ),
        findsOneWidget,
      );
      await env.tearDown(tester);
    });

    testWidgets('повторное открытие вкладки показывает выбранный кадр', (
      tester,
    ) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);
      await _tapRow(tester, 'session/new');
      final selected = env.cubit.state.selectedFrame!;

      await env.closePane(tester);
      env.emitSecretUpdate('s_7f3a');
      await env.settle(tester);
      await env.openPane(tester);

      expect(env.cubit.state.selectedFrame, selected);
      expect(find.text(protocolFrameTitle(selected)), findsOneWidget);
      final table = tester.getRect(_key('protocol-table'));
      final row = tester.getRect(_key('protocol-row-${selected.seq}'));
      expect(row.top, greaterThanOrEqualTo(table.top));
      expect(row.bottom, lessThanOrEqualTo(table.bottom));
      await env.tearDown(tester);
    });

    testWidgets('доля разделителя хранится в состоянии и переживает закрытие '
        'вкладки', (tester) async {
      final env = _Env(debug: false);
      await env.pump(tester);
      await env.createSession(tester, 's_7f3a');
      await env.openPane(tester);
      await _tapRow(tester, 'session/new');

      await tester.drag(
        _inPane(find.byType(CodeLabResizeHandle)),
        const Offset(0, 60),
      );
      await env.settle(tester);
      final dragged = env.cubit.state.framesSplit;
      expect(dragged, isNotNull);

      await env.closePane(tester);
      await env.openPane(tester);

      expect(
        tester
            .widget<CodeLabProtocolPane>(
              _inPane(find.byType(CodeLabProtocolPane)),
            )
            .splitFraction,
        dragged,
      );
      await env.tearDown(tester);
    });

    testWidgets('рендерится панель Protocol: таблица, тон ошибки, InfoBar '
        'своей политики', (tester) async {
      // testing-quality «Рендерится панель Protocol»: запрос, уведомление и
      // ошибка в буфере; и для full, и для metadataOnly.
      for (final debug in [true, false]) {
        final env = _Env(debug: debug);
        await env.pump(tester);
        await env.createSession(tester, 's_7f3a');
        env.emitSecretUpdate('s_7f3a');
        env.agent.emitInbound(
          const JsonRpcMessage.response(
            id: JsonRpcId.integer(77),
            error: JsonRpcError(code: -32603, message: 'boom'),
          ),
        );
        await env.settle(tester);
        await env.openPane(tester);

        expect(_inPane(find.text('session/new')), findsOneWidget);
        expect(
          _inPane(find.text('session/update · agent_message_chunk')),
          findsOneWidget,
        );
        expect(_inPane(find.textContaining('error -32603')), findsWidgets);
        await _tapRow(tester, 'session/update · agent_message_chunk');
        expect(
          find.text(
            debug
                ? 'Debug build: full payloads.'
                : 'Release build: metadata only.',
          ),
          findsOneWidget,
        );
        await env.tearDown(tester);
      }
    });
  });
}
