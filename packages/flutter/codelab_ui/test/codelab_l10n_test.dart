// Красные тесты локализации кита (задача 2.1 change
// `add-desktop-localization`; design.md D4, D8, D9; spec app-settings
// «Тексты кита на русском», «Кит без делегата»).
//
// Что проверяется (поведение, не пиксели):
// * каждый фиксированный словарь кита — `CodeLabToolCallStatus`,
//   `CodeLabSessionStatus`, `CodeLabConnectionStatus`,
//   `CodeLabConnectionBannerStatus`, `CodeLabApprovalRisk`, подписи и тоны
//   решения об одобрении, `CodeLabPlanEntryPriority`, `CodeLabTurnState`,
//   `ToolPane` — показывает русский текст при `ru` с делегатом
//   `CodeLabLocalizations` и прежний английский без делегата (D4);
// * параметры с текстом по умолчанию (`placeholder`, `emptyLabel`,
//   `reconnectLabel`, `actionsLabel`) при отсутствии значения дают перевод
//   кита, а явная строка вызывающего показывается как есть;
// * русские подписи в узких местах не дают переполнения (D8, R4).
//
// Точные русские строки сверены с `docs/architecture/l10n-glossary.md` §3–§5.
// Для подписей, которых в глоссарии нет, тест требует только «перевод есть»
// (кириллица, английской подписи нет): точную формулировку выбирает задача 2.2
// и дописывает её в глоссарий.
//
// Заглушки красной фазы (без логики, их заменяет задача 2.2):
// `toolPaneTitleOf` в `codelab_tool_pane.dart` и экспорт `CodeLabLocalizations`
// из `codelab_ui.dart`. Остальное API (`codeLabStringsOf`) внутреннее и
// проверяется через виджеты.
//
// Красные причины: в ru-прогонах виджеты показывают английские литералы, а
// каталог кита пока содержит одно сообщение. Прогоны `en` без делегата и
// явные строки (`placeholder: 'X'`) сегодня зелёные и охраняют «как раньше».

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _ru = Locale('ru');
final _cyrillic = RegExp('[а-яА-ЯёЁ]');

/// Хост без делегата кита: так работают прежние тесты и превью (D4).
Widget _enHost(Widget child) => FluentApp(
  home: Align(alignment: Alignment.topLeft, child: child),
);

/// Хост с русским языком и делегатом кита.
Widget _ruHost(Widget child) => FluentApp(
  locale: _ru,
  localizationsDelegates: CodeLabLocalizations.localizationsDelegates,
  supportedLocales: CodeLabLocalizations.supportedLocales,
  home: Align(alignment: Alignment.topLeft, child: child),
);

/// Строки всех `Text` внутри [scope] (подписи кита рисуются через `Text`).
List<String> _textsIn(WidgetTester tester, Finder scope) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(of: scope, matching: find.byType(Text)),
  ))
    ?text.data,
];

/// Подпись словаря: [en] — английский эталон (спецификации), [ru] — точный
/// перевод из глоссария либо `null`, когда проверяется только наличие
/// перевода.
typedef _Label = ({String en, String? ru});

_Label _l(String en, [String? ru]) => (en: en, ru: ru);

/// Общая проверка словаря: [build] собирает виджет по значению, [scope] —
/// где искать подпись. Английский без делегата — как раньше; русский с
/// делегатом — перевод.
void _dictionaryTests<T>(
  String name,
  Map<T, _Label> labels,
  Widget Function(T value) build,
  Finder Function() scope,
) {
  group(name, () {
    for (final entry in labels.entries) {
      final value = entry.key;
      final label = entry.value;

      testWidgets('$value: en без делегата — «${label.en}»', (tester) async {
        await tester.pumpWidget(_enHost(build(value)));

        expect(_textsIn(tester, scope()), contains(label.en));
      });

      testWidgets('$value: ru с делегатом — перевод вместо «${label.en}»', (
        tester,
      ) async {
        await tester.pumpWidget(_ruHost(build(value)));

        final texts = _textsIn(tester, scope());
        expect(
          texts,
          isNot(contains(label.en)),
          reason: 'английская подпись осталась при ru: $texts',
        );
        final expected = label.ru;
        if (expected != null) {
          expect(texts, contains(expected));
        } else {
          expect(
            texts.any(_cyrillic.hasMatch),
            isTrue,
            reason: 'нет русской подписи: $texts',
          );
        }
      });
    }
  });
}

CodeLabToolCallRow _callRow(
  CodeLabToolCallStatus status, {
  CodeLabTranscriptApproval? approval,
  bool awaitsRootDecision = false,
}) => CodeLabToolCallRow(
  id: 'call-1',
  status: status,
  label: 'Run',
  detail: 'echo hi',
  approval: approval,
  awaitsRootDecision: awaitsRootDecision,
);

const _options = [
  CodeLabApprovalOption(
    id: 'a1',
    label: 'Allow once',
    kind: CodeLabApprovalOptionKind.allowOnce,
  ),
  CodeLabApprovalOption(
    id: 'a2',
    label: 'Always allow echo *',
    kind: CodeLabApprovalOptionKind.allowAlways,
  ),
  CodeLabApprovalOption(
    id: 'r1',
    label: 'Reject',
    kind: CodeLabApprovalOptionKind.rejectOnce,
  ),
  CodeLabApprovalOption(
    id: 'r2',
    label: 'Always reject echo *',
    kind: CodeLabApprovalOptionKind.rejectAlways,
  ),
];

Widget _tile(CodeLabToolCallRow row) => SizedBox(
  width: 740,
  child: CodeLabToolCallTile(row: row, expanded: true, onToggle: (_) {}),
);

Widget _pendingTile(CodeLabApprovalRisk risk) => _tile(
  _callRow(
    CodeLabToolCallStatus.queued,
    approval: CodeLabTranscriptApproval.pending(
      risk: risk,
      options: _options,
      onOptionSelected: (_) {},
      command: 'echo hi',
    ),
  ),
);

CodeLabBadge _statusTag(WidgetTester tester) =>
    tester.widget<CodeLabBadge>(find.byKey(CodeLabToolCallTile.statusTagKey));

void _setWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  // --- Фиксированные словари --------------------------------------------

  _dictionaryTests<CodeLabToolCallStatus>(
    'CodeLabToolCallStatus (сводка вызова)',
    {
      CodeLabToolCallStatus.queued: _l('Queued'),
      CodeLabToolCallStatus.running: _l('Running', 'Выполняется'),
      CodeLabToolCallStatus.succeeded: _l('Done', 'Готово'),
      CodeLabToolCallStatus.failed: _l('Failed', 'Сбой'),
      CodeLabToolCallStatus.cancelled: _l('Cancelled', 'Отменено'),
    },
    (status) => SizedBox(
      width: 600,
      child: CodeLabToolCallSummary(name: 'Run', status: status),
    ),
    () => find.byType(CodeLabToolCallSummary),
  );

  group(
    'CodeLabToolCallTile: тег статуса (сценарий «Тексты кита на русском»)',
    () {
      final cases = {
        CodeLabToolCallStatus.queued: (en: 'Queued', ru: null as String?),
        CodeLabToolCallStatus.running: (en: 'Running', ru: 'Выполняется'),
        CodeLabToolCallStatus.succeeded: (en: 'Done', ru: 'Готово'),
        CodeLabToolCallStatus.failed: (en: 'Failed', ru: 'Сбой'),
        CodeLabToolCallStatus.cancelled: (en: 'Cancelled', ru: 'Отменено'),
      };
      for (final entry in cases.entries) {
        testWidgets('${entry.key}: en без делегата', (tester) async {
          await tester.pumpWidget(_enHost(_tile(_callRow(entry.key))));

          expect(_statusTag(tester).label, entry.value.en);
        });

        testWidgets(
          '${entry.key}: ru, заголовок вызова от агента не меняется',
          (tester) async {
            await tester.pumpWidget(_ruHost(_tile(_callRow(entry.key))));

            final tag = _statusTag(tester);
            expect(tag.label, isNot(entry.value.en));
            expect(
              tag.label,
              entry.value.ru ?? matches(_cyrillic),
              reason: 'тег статуса вызова на ru',
            );
            // Строка агента не локализуется (D7).
            expect(find.textContaining('echo hi'), findsOneWidget);
          },
        );
      }

      testWidgets('тон тега не зависит от языка', (tester) async {
        await tester.pumpWidget(
          _ruHost(_tile(_callRow(CodeLabToolCallStatus.failed))),
        );

        expect(_statusTag(tester).tone, CodeLabTone.danger);
      });
    },
  );

  _dictionaryTests<CodeLabSessionStatus>(
    'CodeLabSessionStatus (бейдж в сайдбаре)',
    {
      CodeLabSessionStatus.running: _l('Running', 'Выполняется'),
      CodeLabSessionStatus.awaitingApproval: _l('Approval'),
      CodeLabSessionStatus.failed: _l('Failed', 'Сбой'),
      CodeLabSessionStatus.cancelled: _l('Cancelled', 'Отменено'),
      CodeLabSessionStatus.notLoaded: _l('Not loaded'),
      CodeLabSessionStatus.detached: _l('Detached'),
    },
    (status) => SizedBox(
      width: 320,
      height: 600,
      child: CodeLabSessionSidebar(
        projects: [
          CodeLabSidebarProject(
            path: '/work/app',
            name: 'app',
            current: true,
            sessions: [
              CodeLabSessionListItem(
                id: 's1',
                title: 'Fix bug',
                status: status,
              ),
            ],
          ),
        ],
        activeSessionId: 's1',
        onSessionSelected: (_) {},
      ),
    ),
    () => find.byKey(CodeLabSessionSidebar.sessionKey('s1')),
  );

  _dictionaryTests<CodeLabConnectionStatus>(
    'CodeLabConnectionStatus (строка соединения)',
    {
      CodeLabConnectionStatus.idle: _l('Idle'),
      CodeLabConnectionStatus.connecting: _l('Connecting', 'Подключение…'),
      CodeLabConnectionStatus.connected: _l('Connected', 'Подключено'),
      CodeLabConnectionStatus.reconnecting: _l('Reconnecting'),
      CodeLabConnectionStatus.disconnected: _l(
        'Disconnected',
        'Нет подключения',
      ),
      CodeLabConnectionStatus.lost: _l('Connection lost'),
      CodeLabConnectionStatus.failed: _l('Failed', 'Сбой'),
    },
    (status) => SizedBox(
      width: 600,
      child: CodeLabConnectionStatusRow(
        status: status,
        transportLabel: 'stdio',
        profileLabel: 'default',
      ),
    ),
    () => find.byType(CodeLabConnectionStatusRow),
  );

  _dictionaryTests<CodeLabConnectionBannerStatus>(
    'CodeLabConnectionBannerStatus (заголовок баннера)',
    {
      CodeLabConnectionBannerStatus.lost: _l('Connection to the agent lost'),
      CodeLabConnectionBannerStatus.failed: _l(
        'Could not connect to the agent',
      ),
      CodeLabConnectionBannerStatus.reconnecting: _l('Reconnecting…'),
    },
    (status) =>
        SizedBox(width: 700, child: CodeLabConnectionBanner(status: status)),
    () => find.byType(InfoBar),
  );

  group('CodeLabApprovalRisk (тег риска, метка security)', () {
    final cases = {
      CodeLabApprovalRisk.readOnly: (
        en: 'Read-only',
        ru: 'Только чтение',
        tone: CodeLabTone.success,
      ),
      CodeLabApprovalRisk.unknown: (
        en: 'Unknown risk',
        ru: 'Неизвестный риск',
        tone: CodeLabTone.warning,
      ),
      CodeLabApprovalRisk.localWrite: (
        en: 'Local write',
        ru: 'Локальная запись',
        tone: CodeLabTone.warning,
      ),
      CodeLabApprovalRisk.network: (
        en: 'Network',
        ru: 'Сеть',
        tone: CodeLabTone.warning,
      ),
      CodeLabApprovalRisk.shell: (
        en: 'Shell',
        ru: 'Оболочка',
        tone: CodeLabTone.danger,
      ),
      CodeLabApprovalRisk.destructive: (
        en: 'Destructive',
        ru: 'Разрушительное',
        tone: CodeLabTone.danger,
      ),
    };
    for (final entry in cases.entries) {
      testWidgets('${entry.key}: en без делегата', (tester) async {
        await tester.pumpWidget(_enHost(_pendingTile(entry.key)));

        expect(_statusTag(tester).label, entry.value.en);
        expect(_statusTag(tester).tone, entry.value.tone);
      });

      testWidgets('${entry.key}: ru, тон прежний', (tester) async {
        await tester.pumpWidget(_ruHost(_pendingTile(entry.key)));

        expect(_statusTag(tester).label, entry.value.ru);
        // Смысл риска не должен зависеть от языка (D14, §5 AGENTS кита).
        expect(_statusTag(tester).tone, entry.value.tone);
      });
    }
  });

  group('Полоса решения об одобрении (метка security)', () {
    Widget prompt({String? rawInput}) => SizedBox(
      width: 740,
      child: CodeLabApprovalPrompt(
        options: _options,
        rawInput: rawInput,
        onOptionSelected: (_) {},
      ),
    );

    testWidgets('en без делегата: Allow, Reject, Only this time', (
      tester,
    ) async {
      await tester.pumpWidget(_enHost(prompt()));

      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Only this time'), findsOneWidget);
    });

    testWidgets('ru: кнопки решения и охват переведены, ключи прежние', (
      tester,
    ) async {
      await tester.pumpWidget(_ruHost(prompt()));

      expect(
        find.descendant(
          of: find.byKey(CodeLabApprovalPrompt.allowKey),
          matching: find.text('Разрешить'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(CodeLabApprovalPrompt.rejectKey),
          matching: find.text('Отклонить'),
        ),
        findsOneWidget,
      );
      expect(find.text('Только сейчас'), findsOneWidget);
      expect(find.text('Allow'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('ru: подсказка «View raw input» переведена', (tester) async {
      await tester.pumpWidget(_ruHost(prompt(rawInput: '{"cmd":"ls"}')));

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(CodeLabApprovalPrompt.viewRawInputKey),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'Показать исходные параметры');
    });

    testWidgets('ru: варианты агента показываются без изменений', (
      tester,
    ) async {
      await tester.pumpWidget(_ruHost(prompt()));
      await tester.tap(find.byKey(CodeLabApprovalPrompt.scopeKey));
      await tester.pumpAndSettle();

      // Подписи вариантов — текст агента (D7), кит их не переводит.
      expect(find.text('Always allow echo *'), findsOneWidget);
      expect(find.text('Always reject echo *'), findsOneWidget);
      expect(find.text('Всегда'), findsOneWidget);
    });
  });

  group('Тег «Awaiting approval» (вложенный вызов ждёт корня)', () {
    final row = _callRow(
      CodeLabToolCallStatus.queued,
      awaitsRootDecision: true,
    );

    testWidgets('en без делегата', (tester) async {
      await tester.pumpWidget(_enHost(_tile(row)));

      expect(_statusTag(tester).label, 'Awaiting approval');
    });

    testWidgets('ru — «Ждёт одобрения»', (tester) async {
      await tester.pumpWidget(_ruHost(_tile(row)));

      expect(_statusTag(tester).label, 'Ждёт одобрения');
      expect(_statusTag(tester).tone, CodeLabTone.accent);
    });
  });

  group('Тоны исхода одобрения не зависят от языка', () {
    final tones = {
      CodeLabApprovalOutcome.allowed: CodeLabTone.success,
      CodeLabApprovalOutcome.rejected: CodeLabTone.danger,
      CodeLabApprovalOutcome.cancelled: CodeLabTone.warning,
      CodeLabApprovalOutcome.unknown: CodeLabTone.neutral,
    };
    for (final entry in tones.entries) {
      testWidgets('${entry.key}: ru, подпись варианта — от app', (
        tester,
      ) async {
        await tester.pumpWidget(
          _ruHost(
            _tile(
              _callRow(
                CodeLabToolCallStatus.succeeded,
                approval: CodeLabTranscriptApproval.resolved(
                  label: 'Allow once',
                  outcome: entry.key,
                ),
              ),
            ),
          ),
        );

        // Подпись решённого одобрения приходит от app готовой строкой; кит
        // меняет только тон по исходу, и перевод его не трогает.
        final badge = tester.widget<CodeLabBadge>(
          find.widgetWithText(CodeLabBadge, 'Allow once'),
        );
        expect(badge.tone, entry.value);
      });
    }
  });

  _dictionaryTests<CodeLabPlanEntryPriority>(
    'CodeLabPlanEntryPriority (приоритет в плане)',
    {
      CodeLabPlanEntryPriority.high: _l('High'),
      CodeLabPlanEntryPriority.medium: _l('Medium'),
      CodeLabPlanEntryPriority.low: _l('Low'),
    },
    (priority) => SizedBox(
      width: 600,
      height: 200,
      child: CodeLabProgressChecklist.list(
        key: const ValueKey('plan-list'),
        entries: [
          CodeLabPlanEntry(
            content: 'Write tests',
            status: CodeLabPlanEntryStatus.pending,
            priority: priority,
          ),
        ],
      ),
    ),
    () => find.byType(CodeLabBadge),
  );

  _dictionaryTests<CodeLabTurnState>(
    'CodeLabTurnState (чип хода в шапке сессии)',
    {
      CodeLabTurnState.running: _l('Turn running'),
      CodeLabTurnState.awaitingApproval: _l('Waiting for approval'),
      CodeLabTurnState.cancelling: _l('Cancelling…'),
    },
    (state) => SizedBox(
      width: 700,
      child: CodeLabSessionPaneHeader(title: 'Fix bug', turnState: state),
    ),
    () => find.byKey(CodeLabSessionPaneHeader.turnChipKey),
  );

  group('ToolPane (toolPaneTitleOf, D4)', () {
    // Точные русские названия вкладок — из глоссария §4; остальные — только
    // «перевод есть» (`Diff` как общеупотребительное слово не проверяется).
    final cases = {
      ToolPane.files: (en: 'Files', ru: 'Файлы'),
      ToolPane.diff: (en: 'Diff', ru: null as String?),
      ToolPane.terminal: (en: 'Terminal', ru: 'Терминал'),
      ToolPane.plan: (en: 'Plan', ru: 'План'),
      ToolPane.timeline: (en: 'Timeline', ru: null),
      ToolPane.agents: (en: 'Agents', ru: 'Агенты'),
      ToolPane.usage: (en: 'Usage', ru: 'Расход'),
      ToolPane.branches: (en: 'Branches', ru: null),
      ToolPane.protocol: (en: 'Protocol', ru: null),
    };

    for (final entry in cases.entries) {
      testWidgets('${entry.key}: en без делегата', (tester) async {
        late String title;
        await tester.pumpWidget(
          _enHost(
            Builder(
              builder: (context) {
                title = toolPaneTitleOf(context, entry.key);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(title, entry.value.en);
      });

      testWidgets('${entry.key}: ru с делегатом', (tester) async {
        late String title;
        await tester.pumpWidget(
          _ruHost(
            Builder(
              builder: (context) {
                title = toolPaneTitleOf(context, entry.key);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final expected = entry.value.ru;
        if (expected != null) {
          expect(title, expected);
        } else if (entry.key != ToolPane.diff) {
          expect(title, matches(_cyrillic));
        }
        if (entry.key != ToolPane.diff) {
          expect(title, isNot(entry.value.en));
        }
      });
    }
  });

  // --- Параметры по умолчанию (D4) --------------------------------------

  group('Параметры с текстом по умолчанию', () {
    group('placeholder композера', () {
      Widget composer({String? placeholder}) => SizedBox(
        width: 600,
        child: placeholder == null
            ? CodeLabPromptComposer(onSubmit: (_) {})
            : CodeLabPromptComposer(onSubmit: (_) {}, placeholder: placeholder),
      );

      testWidgets('без значения, en без делегата — «Message the agent»', (
        tester,
      ) async {
        await tester.pumpWidget(_enHost(composer()));

        expect(find.text('Message the agent'), findsOneWidget);
      });

      testWidgets('без значения, ru — перевод кита', (tester) async {
        await tester.pumpWidget(_ruHost(composer()));

        expect(find.text('Сообщение агенту'), findsOneWidget);
        expect(find.text('Message the agent'), findsNothing);
      });

      testWidgets('со значением X, ru — X', (tester) async {
        await tester.pumpWidget(_ruHost(composer(placeholder: 'X')));

        expect(find.text('X'), findsOneWidget);
        expect(find.text('Сообщение агенту'), findsNothing);
      });
    });

    group('emptyLabel', () {
      Widget transcript({String? emptyLabel}) => SizedBox(
        width: 600,
        height: 300,
        child: emptyLabel == null
            ? const CodeLabTranscriptPanel(rows: [])
            : CodeLabTranscriptPanel(rows: const [], emptyLabel: emptyLabel),
      );
      Widget sidebar({String? emptyLabel}) => SizedBox(
        width: 320,
        height: 500,
        child: CodeLabSessionSidebar(
          projects: const [
            CodeLabSidebarProject(path: '/w/app', name: 'app', current: true),
          ],
          onSessionSelected: (_) {},
          emptyLabel: emptyLabel ?? 'No sessions yet',
        ),
      );
      Widget palette({String? emptyLabel}) => SizedBox(
        width: 500,
        height: 300,
        child: emptyLabel == null
            ? const CodeLabCommandPaletteSurface(actions: [])
            : CodeLabCommandPaletteSurface(
                actions: const [],
                emptyLabel: emptyLabel,
              ),
      );

      testWidgets('лента: без значения, en — «No transcript yet»', (
        tester,
      ) async {
        await tester.pumpWidget(_enHost(transcript()));

        expect(find.text('No transcript yet'), findsOneWidget);
      });

      testWidgets('лента: без значения, ru — перевод; со значением — X', (
        tester,
      ) async {
        await tester.pumpWidget(_ruHost(transcript()));
        expect(find.text('No transcript yet'), findsNothing);
        expect(
          _textsIn(
            tester,
            find.byType(CodeLabTranscriptPanel),
          ).where(_cyrillic.hasMatch),
          isNotEmpty,
        );

        await tester.pumpWidget(_ruHost(transcript(emptyLabel: 'X')));
        expect(find.text('X'), findsOneWidget);
      });

      testWidgets('палитра: без значения, ru — перевод; со значением — X', (
        tester,
      ) async {
        await tester.pumpWidget(_enHost(palette()));
        expect(find.text('No matching commands'), findsOneWidget);

        await tester.pumpWidget(_ruHost(palette()));
        expect(find.text('No matching commands'), findsNothing);
        expect(
          _textsIn(
            tester,
            find.byKey(CodeLabCommandPaletteSurface.emptyKey),
          ).any(_cyrillic.hasMatch),
          isTrue,
        );

        await tester.pumpWidget(_ruHost(palette(emptyLabel: 'X')));
        expect(find.text('X'), findsOneWidget);
      });

      testWidgets('сайдбар: явная строка вызывающего показывается как есть', (
        tester,
      ) async {
        // Контракт «String? : null — текст кита» для сайдбара: хост app
        // передаёт свою строку, и она не заменяется переводом.
        await tester.pumpWidget(_ruHost(sidebar(emptyLabel: 'X')));

        expect(find.text('X'), findsOneWidget);
      });
    });

    group('reconnectLabel', () {
      Widget banner({String? reconnectLabel}) => SizedBox(
        width: 700,
        child: reconnectLabel == null
            ? CodeLabConnectionBanner(
                status: CodeLabConnectionBannerStatus.lost,
                onReconnect: () {},
              )
            : CodeLabConnectionBanner(
                status: CodeLabConnectionBannerStatus.lost,
                onReconnect: () {},
                reconnectLabel: reconnectLabel,
              ),
      );

      testWidgets('без значения: en — Reconnect, ru — «Переподключиться»', (
        tester,
      ) async {
        await tester.pumpWidget(_enHost(banner()));
        expect(find.text('Reconnect'), findsOneWidget);

        await tester.pumpWidget(_ruHost(banner()));
        expect(find.text('Переподключиться'), findsOneWidget);
        expect(find.text('Reconnect'), findsNothing);
      });

      testWidgets('со значением X, ru — X', (tester) async {
        await tester.pumpWidget(_ruHost(banner(reconnectLabel: 'X')));

        expect(find.text('X'), findsOneWidget);
        expect(find.text('Переподключиться'), findsNothing);
      });

      testWidgets('экран подключения: без значения, ru — перевод', (
        tester,
      ) async {
        Widget screen({String? reconnectLabel}) => SizedBox(
          width: 700,
          height: 400,
          child: reconnectLabel == null
              ? CodeLabConnectionScreen(
                  status: CodeLabConnectionStatus.failed,
                  transportLabel: 'stdio',
                  profileLabel: 'default',
                  onReconnect: () {},
                )
              : CodeLabConnectionScreen(
                  status: CodeLabConnectionStatus.failed,
                  transportLabel: 'stdio',
                  profileLabel: 'default',
                  onReconnect: () {},
                  reconnectLabel: reconnectLabel,
                ),
        );

        await tester.pumpWidget(_ruHost(screen()));
        expect(find.text('Переподключиться'), findsOneWidget);

        await tester.pumpWidget(_ruHost(screen(reconnectLabel: 'X')));
        expect(find.text('X'), findsOneWidget);
      });
    });

    group('actionsLabel таблицы состояния', () {
      Widget table({String? actionsLabel}) => SizedBox(
        width: 600,
        child: actionsLabel == null
            ? const CodeLabStatusTable(columns: ['A'], rows: [])
            : CodeLabStatusTable(
                columns: const ['A'],
                rows: const [],
                actionsLabel: actionsLabel,
              ),
      );

      testWidgets('без значения: en — Actions, ru — перевод', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(_enHost(table()));
        expect(find.bySemanticsLabel('Actions'), findsOneWidget);

        await tester.pumpWidget(_ruHost(table()));
        expect(find.bySemanticsLabel('Actions'), findsNothing);
        handle.dispose();
      });

      testWidgets('со значением X, ru — X', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(_ruHost(table(actionsLabel: 'X')));

        expect(find.bySemanticsLabel('X'), findsOneWidget);
        handle.dispose();
      });
    });
  });

  // --- Навигация настроек: подписи кита ---------------------------------

  group('Навигация настроек: собственные подписи кита', () {
    Widget nav({String query = ''}) => CodeLabSettingsNavigation(
      items: const [
        CodeLabSettingsNavItem(
          id: 'general',
          title: 'Общие',
          icon: FluentIcons.settings,
          group: 'Приложение',
        ),
      ],
      selectedId: 'general',
      onSelected: (_) {},
      onQueryChanged: (_) {},
      onBack: () {},
      child: const SizedBox.shrink(),
    );

    testWidgets('en без делегата: Settings, Find a setting', (tester) async {
      _setWindow(tester, const Size(1000, 700));
      await tester.pumpWidget(FluentApp(home: nav()));

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Find a setting'), findsOneWidget);
    });

    testWidgets(
      'ru: «Настройки», «Найти настройку»; заголовки пунктов — от app',
      (tester) async {
        _setWindow(tester, const Size(1000, 700));
        await tester.pumpWidget(
          FluentApp(
            locale: _ru,
            localizationsDelegates: CodeLabLocalizations.localizationsDelegates,
            supportedLocales: CodeLabLocalizations.supportedLocales,
            home: nav(),
          ),
        );

        expect(find.text('Настройки'), findsOneWidget);
        expect(find.text('Найти настройку'), findsOneWidget);
        expect(find.text('Общие'), findsOneWidget);
        expect(find.text('Settings'), findsNothing);
      },
    );

    testWidgets('ru: пустой результат поиска содержит запрос и перевод', (
      tester,
    ) async {
      _setWindow(tester, const Size(1000, 700));
      await tester.pumpWidget(
        FluentApp(
          locale: _ru,
          localizationsDelegates: CodeLabLocalizations.localizationsDelegates,
          supportedLocales: CodeLabLocalizations.supportedLocales,
          home: CodeLabSettingsNavigation(
            items: const [],
            selectedId: 'general',
            onSelected: (_) {},
            onQueryChanged: (_) {},
            onBack: () {},
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(CodeLabSettingsNavigation.searchKey),
        'zzz',
      );
      await tester.pump();

      expect(find.textContaining('No settings match'), findsNothing);
      expect(find.textContaining('zzz'), findsOneWidget);
    });
  });

  // --- Русские подписи без переполнения (D8, R4) ------------------------

  group('ru без переполнения при 760 px', () {
    testWidgets('строка статуса: готовые русские подписи и перевод кита', (
      tester,
    ) async {
      _setWindow(tester, const Size(760, 400));
      await tester.pumpWidget(
        _ruHost(
          const SizedBox(
            width: 760,
            child: CodeLabSessionStatusBar(
              data: CodeLabSessionStatusData(
                modelLabel: 'claude-sonnet-4-5-20250929',
                modeLabel: 'Режим принятия правок',
                usage: CodeLabStatusSegment(label: '94.0k → 12.3k'),
                cost: CodeLabStatusSegment(label: r'$0.0041 · сессия $1.20'),
                context: CodeLabStatusSegment(label: '79% контекста'),
                busy: true,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // Подпись индикатора занятого хода — текст кита.
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Turn in progress'), findsNothing);
      expect(find.bySemanticsLabel(_cyrillic), findsWidgets);
      handle.dispose();
    });

    testWidgets('теги вызовов всех статусов в узкой ленте', (tester) async {
      _setWindow(tester, const Size(760, 900));
      await tester.pumpWidget(
        _ruHost(
          SizedBox(
            width: 760,
            height: 900,
            child: CodeLabTranscriptPanel(
              rows: [
                for (final status in CodeLabToolCallStatus.values)
                  CodeLabToolCallRow(
                    id: 'call-${status.name}',
                    status: status,
                    label: 'Run',
                    detail: 'echo hi',
                  ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final tags = tester
          .widgetList<CodeLabBadge>(
            find.byKey(CodeLabToolCallTile.statusTagKey),
          )
          .map((badge) => badge.label)
          .toList();
      expect(tags, contains('Выполняется'));
      expect(tags, isNot(contains('Running')));
    });

    testWidgets('кнопки одобрения и тег самого длинного риска', (tester) async {
      _setWindow(tester, const Size(760, 600));
      await tester.pumpWidget(
        _ruHost(
          SizedBox(
            width: 760,
            child: CodeLabTranscriptPanel(
              rows: [
                CodeLabToolCallRow(
                  id: 'call-1',
                  status: CodeLabToolCallStatus.queued,
                  label: 'Run',
                  detail: 'rm -rf build',
                  approval: CodeLabTranscriptApproval.pending(
                    risk: CodeLabApprovalRisk.destructive,
                    options: _options,
                    onOptionSelected: (_) {},
                    command: 'rm -rf build',
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Разрешить'), findsOneWidget);
      expect(find.text('Отклонить'), findsOneWidget);
      expect(_statusTag(tester).label, 'Разрушительное');
    });

    testWidgets('навигация настроек слева, 760 px', (tester) async {
      _setWindow(tester, const Size(760, 700));
      await tester.pumpWidget(
        _ruHost(_settingsNav(CodeLabSettingsNavMode.left)),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Найти настройку'), findsOneWidget);
    });

    testWidgets('навигация настроек сверху, 759 px', (tester) async {
      _setWindow(tester, const Size(759, 700));
      await tester.pumpWidget(
        _ruHost(_settingsNav(CodeLabSettingsNavMode.top)),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Найти настройку'), findsOneWidget);
    });
  });
}

/// Навигация с русскими заголовками страниц и групп, как их даст app (D8).
Widget _settingsNav(CodeLabSettingsNavMode mode) => CodeLabSettingsNavigation(
  mode: mode,
  items: const [
    CodeLabSettingsNavItem(
      id: 'connection',
      title: 'Подключение',
      icon: FluentIcons.plug_connected,
      group: 'Агент',
    ),
    CodeLabSettingsNavItem(
      id: 'providers',
      title: 'Провайдеры',
      icon: FluentIcons.cloud,
      group: 'Агент',
    ),
    CodeLabSettingsNavItem(
      id: 'agents-modes',
      title: 'Агенты и режимы',
      icon: FluentIcons.robot,
      group: 'Агент',
    ),
    CodeLabSettingsNavItem(
      id: 'permissions',
      title: 'Разрешения и инструменты',
      icon: FluentIcons.permissions,
      group: 'Агент',
    ),
    CodeLabSettingsNavItem(
      id: 'skills',
      title: 'Навыки и расширения',
      icon: FluentIcons.lightbulb,
      group: 'Агент',
    ),
    CodeLabSettingsNavItem(
      id: 'general',
      title: 'Общие',
      icon: FluentIcons.settings,
      group: 'Приложение',
    ),
    CodeLabSettingsNavItem(
      id: 'keyboard',
      title: 'Клавиатура',
      icon: FluentIcons.keyboard_classic,
      group: 'Приложение',
    ),
  ],
  selectedId: 'connection',
  onSelected: (_) {},
  onQueryChanged: (_) {},
  onBack: () {},
  child: const SizedBox.shrink(),
);
