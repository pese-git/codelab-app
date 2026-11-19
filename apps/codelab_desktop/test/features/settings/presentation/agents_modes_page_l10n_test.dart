// Тесты задач 5.1c и 5.2 change `add-desktop-localization`: страница
// «Agents & modes» на русском и английском, смена языка на странице (spec
// app-settings «Режим и баннер записи на русском», «Таблица определений
// агентов на русском», «Источник конфигурации на русском», «Страницы
// настроек II пересобираются при смене языка»; design.md D5 «Уточнение
// итерации 5», D6, D7, D9).
//
// Состояние страницы задаёт Cubit-двойник (`FakeAgentsModesCubit`): запись и
// источники проверяет `agents_modes_cubit_test.dart`, а здесь — как страница
// показывает типизированное состояние на двух языках: режим с переведённой
// пометкой, источник по `ConfigSourceKind`, целые фразы баннера записи (три
// вида × три «когда применится»), таблица определений по `AgentRowStatus` и
// `AgentRowScope`, InfoBar по типу причины.
//
// Ожидания `en` — прежние строки. Ожидания `ru` — по глоссарию §4:
// «Агенты и режимы», «Источник», «Действует», «Только этот проект», «Все
// проекты», «Доступен в», статусы определений, «сессия и субагент»,
// «Использовать bypass». Фразы вне глоссария проверяются без выдуманного
// перевода: английской основы и хвоста на экране нет, значения (id режимов,
// пути, команды, тексты ядра) сохранены.

import 'package:codelab_desktop/features/settings/application/agents_modes_cubit.dart';
import 'package:codelab_desktop/features/settings/presentation/agents_modes_page.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_setup/codelab_setup.dart'
    show AgentRowScope, AgentRowStatus, ConfigLayer, ConfigSourceKind;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

// В вызовах `expectNoStaleLanguage` ниже указан `ignore`: имя определения `default` — данные, а не подпись источника (итерация 5, D7).

import '../../../support/fake_agents_modes_cubit.dart';
import '../../../support/l10n_mix.dart';
import '../../../support/l10n_page_harness.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _text(String key, String text) => find.descendant(
  of: _key(key),
  matching: find.textContaining(text),
  matchRoot: true,
);

AgentsModesReady _ready({
  String mode = 'standard',
  bool blocks = false,
  ConfigSourceKind? modeSource,
  bool narrowed = false,
  String effort = 'medium',
  ConfigSourceKind? effortSource,
  AgentsModesBanner? banner,
  AgentsDefinitionsView? definitions,
}) => AgentsModesReady(
  mode: mode,
  blocksWriteAndExec: blocks,
  modeSourceKind: modeSource,
  narrowedByProject: narrowed,
  effort: effort,
  effortSourceKind: effortSource,
  target: ConfigLayer.user,
  canTargetProject: true,
  banner: banner,
  definitions: definitions,
);

AgentsDefinitionRow _row(
  String name, {
  String? sourcePath,
  AgentRowScope? scope,
  AgentRowStatus status = AgentRowStatus.available,
  int? line,
  String? overriddenBy,
  bool loaded = true,
  AgentsStatusTone tone = AgentsStatusTone.success,
}) => AgentsDefinitionRow(
  name: name,
  descriptionText: 'Описание $name',
  sourcePath: sourcePath,
  scope: scope,
  rowStatus: status,
  errorLine: line,
  overriddenBy: overriddenBy,
  loaded: loaded,
  tone: tone,
);

AgentsDefinitionsView _definitions({
  bool untrusted = false,
  bool timedOut = false,
  String? openFailure,
}) => AgentsDefinitionsView(
  rows: [
    _row('default', scope: AgentRowScope.session),
    _row('general', scope: AgentRowScope.both),
    _row(
      'reviewer',
      sourcePath: '~/.codelab/agents/reviewer.md',
      scope: AgentRowScope.subagent,
    ),
    _row(
      'migrator',
      sourcePath: '~/.codelab/agents/migrator.md',
      status: AgentRowStatus.error,
      line: 4,
      loaded: false,
      tone: AgentsStatusTone.danger,
    ),
    _row(
      'dup',
      sourcePath: '~/.codelab/agents/dup.md',
      status: AgentRowStatus.duplicate,
      loaded: false,
      tone: AgentsStatusTone.danger,
    ),
  ],
  errors: const [
    AgentsDefinitionError(
      index: 0,
      path: '/home/u/.codelab/agents/migrator.md',
      pathLabel: '~/.codelab/agents/migrator.md',
      line: 4,
      message: 'tools must be a list',
    ),
  ],
  untrustedProject: untrusted,
  projectLabel: untrusted ? '~/work/app' : null,
  timedOut: timedOut,
  openFailure: openFailure,
  projectFolderAvailable: true,
  projectFolderExists: true,
);

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  late FakeAgentsModesCubit cubit;
  late PageLanguage language;

  Future<void> pumpPage(
    WidgetTester tester,
    AgentsModesState state, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    cubit = FakeAgentsModesCubit(state);
    addTearDown(cubit.close);
    language = PageLanguage(locale);
    addTearDown(language.dispose);
    await tester.pumpWidget(
      language.wrap(
        ScaffoldPage(
          content: SingleChildScrollView(
            child: BlocProvider<AgentsModesCubit>.value(
              value: cubit,
              child: const AgentsModesPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('режим и источники', () {
    testWidgets('en: подпись режима, источник и уровень — прежние строки', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _ready(
          mode: 'ask',
          blocks: true,
          modeSource: ConfigSourceKind.projectLocal,
          effortSource: ConfigSourceKind.user,
        ),
      );

      expect(
        find.text('Effective: ask (edits and commands blocked by plan)'),
        findsOneWidget,
      );
      expect(
        _text('agents-modes-mode-source', 'Source: local'),
        findsOneWidget,
      );
      expect(find.textContaining('Reasoning effort · user'), findsOneWidget);
    });

    testWidgets('ru: «ask» без перевода с переведённой пометкой, источник по '
        'ConfigSourceKind, значения радиогруппы как есть (сценарий «Режим и '
        'баннер записи на русском»)', (tester) async {
      await pumpPage(
        tester,
        _ready(
          mode: 'ask',
          blocks: true,
          modeSource: ConfigSourceKind.projectLocal,
          effortSource: ConfigSourceKind.user,
        ),
        locale: const Locale('ru'),
      );

      expect(
        find.textContaining('ask (правки и команды запрещены режимом plan)'),
        findsOneWidget,
      );
      expect(
        _text('agents-modes-mode-source', 'Источник: локально'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Уровень рассуждения · пользователь'),
        findsOneWidget,
      );
      for (final id in const [
        'plan',
        'ask',
        'standard',
        'accept-edits',
        'bypass',
        'autopilot',
      ]) {
        expect(find.text(id), findsWidgets, reason: id);
      }
      expect(find.text('Агенты и режимы'), findsWidgets);
      expect(find.text('Режим разрешений по умолчанию'), findsOneWidget);
      expect(find.text('Все проекты'), findsOneWidget);
      expect(find.text('Только этот проект'), findsOneWidget);
      expectNoEnglish(const [
        'Effective:',
        'Source:',
        'blocked by plan',
        'Reasoning effort',
        'Default permission mode',
        'All projects',
        'This project only',
      ]);
    });

    testWidgets('ru: источник по умолчанию (null) и «файл --config»', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _ready(modeSource: null, effortSource: ConfigSourceKind.extraFile),
        locale: const Locale('ru'),
      );

      expect(_text('agents-modes-mode-source', 'по умолчанию'), findsOneWidget);
      expect(find.textContaining('Уровень рассуждения · файл'), findsOneWidget);
    });

    testWidgets('ru: подсказка autopilot и сужение недоверенным проектом — '
        'команда и режим как есть, английского нет', (tester) async {
      await pumpPage(
        tester,
        _ready(mode: 'ask', narrowed: true, modeSource: ConfigSourceKind.user),
        locale: const Locale('ru'),
      );

      expect(
        find.textContaining('codelab-agent serve --permission-mode autopilot'),
        findsOneWidget,
      );
      expect(
        _text('agents-modes-mode-narrowed', 'ask'),
        findsOneWidget,
        reason: 'сужение называет действующий режим',
      );
      expectNoEnglish(const [
        'Only as a launch flag of the agent',
        'This project is not trusted',
        'can only make the mode stricter',
        'New sessions start in it after Restart agent',
      ]);
    });

    testWidgets('en: подсказки autopilot и сужения прежние', (tester) async {
      await pumpPage(
        tester,
        _ready(mode: 'ask', narrowed: true, modeSource: ConfigSourceKind.user),
      );

      expect(
        find.textContaining(
          'Only as a launch flag of the agent '
          '(codelab-agent serve --permission-mode autopilot); '
          'never saved in config.',
        ),
        findsOneWidget,
      );
      expect(
        _text(
          'agents-modes-mode-narrowed',
          'This project is not trusted, so its config can only make the mode '
              'stricter. New sessions here use ask.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('ru: диалог bypass — заголовок и кнопка по глоссарию, '
        'решение отдаёт Cubit', (tester) async {
      await pumpPage(tester, _ready(), locale: const Locale('ru'));

      await tester.tap(_key('agents-modes-mode-bypass'));
      await tester.pumpAndSettle();

      expect(_key('agents-modes-bypass-confirm'), findsOneWidget);
      expect(
        find.text('Использовать bypass для новых сессий?'),
        findsOneWidget,
      );
      expect(find.text('Использовать bypass'), findsOneWidget);
      // Диалог шире стандартных 368 pt, чтобы кнопка «Использовать bypass» не
      // переносилась (тестовый шрифт Ahem вдвое шире, высоту строки в нём не
      // проверить, поэтому проверяется ширина диалога).
      expect(
        tester
            .getSize(find.byKey(const ValueKey('agents-modes-bypass-confirm')))
            .width,
        greaterThanOrEqualTo(480),
      );
      expectNoEnglish(const [
        'Use bypass',
        'Only critical commands',
        'disposable checkout',
      ]);

      await tester.tap(find.text('Использовать bypass'));
      await tester.pumpAndSettle();
      expect(cubit.calls, contains('confirmBypass'));
    });
  });

  group('баннер записи: целые фразы', () {
    const kinds = [
      AgentsApplyWhen.now,
      AgentsApplyWhen.afterRestart,
      AgentsApplyWhen.whenAgentStarts,
    ];

    for (final when in kinds) {
      testWidgets('ru: «сохранено / перекрыто слоем / сужено проектом» при '
          '${when.name} — без английской основы и хвоста', (tester) async {
        final messages = <AgentsModesBannerKind, AgentsModesMessage>{
          AgentsModesBannerKind.saved: AgentsSavedMessage(
            setting: AgentsModesSetting.effort,
            value: 'high',
            when: when,
          ),
          AgentsModesBannerKind.warning: AgentsSavedOverriddenMessage(
            setting: AgentsModesSetting.mode,
            target: ConfigLayer.user,
            source: ConfigSourceKind.projectLocal,
            value: 'ask',
            when: when,
            blocksWriteAndExec: true,
          ),
        };
        final texts = <String>{};
        for (final MapEntry(:key, :value) in messages.entries) {
          await pumpPage(
            tester,
            _ready(banner: AgentsModesBanner(key, message: value)),
            locale: const Locale('ru'),
          );
          final shown = tester
              .widget<Text>(
                find.descendant(
                  of: _key('agents-modes-banner'),
                  matching: find.byType(Text),
                ),
              )
              .data;
          texts.add(shown ?? '');
          expectNoEnglish(const [
            'Saved',
            'New sessions',
            'new sessions',
            'Restart agent',
            'when the agent starts',
            'overrides it',
          ]);
        }
        expect(texts, hasLength(2));
        expect(texts.every((t) => t.isNotEmpty), isTrue);
      });
    }

    testWidgets('en: баннеры записи прежние, когда применится — после '
        'перезапуска', (tester) async {
      await pumpPage(
        tester,
        _ready(
          banner: const AgentsModesBanner(
            AgentsModesBannerKind.saved,
            message: AgentsSavedMessage(
              setting: AgentsModesSetting.mode,
              value: 'accept-edits',
              when: AgentsApplyWhen.afterRestart,
            ),
          ),
        ),
      );

      expect(
        _text(
          'agents-modes-banner',
          'Saved. New sessions use accept-edits after Restart agent.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('ru: баннер «сужено проектом» называет значение и пометку', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _ready(
          banner: const AgentsModesBanner(
            AgentsModesBannerKind.warning,
            message: AgentsSavedNarrowedMessage(
              target: ConfigLayer.user,
              value: 'ask',
              when: AgentsApplyWhen.afterRestart,
              blocksWriteAndExec: true,
            ),
          ),
        ),
        locale: const Locale('ru'),
      );

      expect(
        _text(
          'agents-modes-banner',
          'ask (правки и команды запрещены режимом plan)',
        ),
        findsOneWidget,
      );
      expectNoEnglish(const ['untrusted project', 'overrides it']);
    });
  });

  group('InfoBar «только чтение» и проблемы конфига', () {
    testWidgets('ru: удалённый агент — адрес без пути, команды как есть', (
      tester,
    ) async {
      await pumpPage(
        tester,
        const AgentsModesReadOnly(
          reason: RemoteAgentReadOnly('wss://devbox:7420'),
        ),
        locale: const Locale('ru'),
      );

      expect(
        _text('agents-modes-read-only', 'wss://devbox:7420'),
        findsOneWidget,
      );
      expect(
        _text('agents-modes-read-only', 'codelab config set'),
        findsOneWidget,
      );
      expectNoEnglish(const ['Read-only: this agent runs on', 'on that host']);
    });

    testWidgets('en: удалённый и сторонний агенты — прежние строки', (
      tester,
    ) async {
      await pumpPage(
        tester,
        const AgentsModesReadOnly(
          reason: RemoteAgentReadOnly('wss://devbox:7420'),
        ),
      );
      expect(
        _text(
          'agents-modes-read-only',
          'Read-only: this agent runs on '
              'wss://devbox:7420.',
        ),
        findsOneWidget,
      );
      expect(
        _text(
          'agents-modes-read-only',
          'Change its modes and agents on that '
              'host: codelab config set, .codelab/agents.',
        ),
        findsOneWidget,
      );
      cubit.show(
        const AgentsModesReadOnly(reason: ForeignAgentReadOnly('python')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Agent settings are managed by python.'),
        findsOneWidget,
      );
    });

    testWidgets('ru: сторонний агент называет агента', (tester) async {
      await pumpPage(
        tester,
        const AgentsModesReadOnly(reason: ForeignAgentReadOnly('python')),
        locale: const Locale('ru'),
      );

      expect(_text('agents-modes-read-only', 'python'), findsOneWidget);
      expectNoEnglish(const ['Agent settings are managed by']);
    });

    testWidgets('ru: нечитаемый конфиг — фраза app переведена, текст '
        'загрузчика как есть под переведённым заголовком', (tester) async {
      await pumpPage(
        tester,
        const AgentsModesUnreadable(
          issues: [
            AppSettingsProblem(AppSettingsProblemKind.cannotReadSettings),
            LoaderSettingsProblem(
              'config.yaml:11:3: permissions.mode: autopilot is allowed only '
              'as a launch flag',
            ),
          ],
        ),
        locale: const Locale('ru'),
      );

      expect(
        _text('agents-modes-unreadable', 'permissions.mode: autopilot'),
        findsOneWidget,
      );
      expectNoEnglish(const [
        'Cannot read the agent config',
        'Cannot read the agent settings.',
        'CodeLab will not overwrite it',
      ]);
    });
  });

  group('таблица определений агентов', () {
    testWidgets('en: статусы, области и источник встроенного — прежние', (
      tester,
    ) async {
      await pumpPage(tester, _ready(definitions: _definitions()));

      expect(find.text('Available'), findsNWidgets(3));
      expect(find.text('Error · line 4'), findsOneWidget);
      expect(find.text('Not loaded: duplicate name'), findsOneWidget);
      expect(find.text('built-in'), findsNWidgets(2));
      expect(find.text('subagent'), findsOneWidget);
      expect(find.text('both'), findsOneWidget);
    });

    testWidgets('ru: статусы, «Доступен в» и подпись ошибки (сценарий '
        '«Таблица определений агентов на русском»)', (tester) async {
      await pumpPage(
        tester,
        _ready(definitions: _definitions()),
        locale: const Locale('ru'),
      );

      expect(find.text('Определения агентов'), findsOneWidget);
      expect(find.text('Доступен в'), findsOneWidget);
      expect(find.text('Доступно'), findsNWidgets(3));
      expect(find.text('Ошибка · строка 4'), findsOneWidget);
      expect(find.text('Не загружено: повторяющееся имя'), findsOneWidget);
      expect(find.text('сессия'), findsOneWidget);
      expect(find.text('субагент'), findsOneWidget);
      expect(find.text('сессия и субагент'), findsOneWidget);
      // Имена и описания определений — как есть (D7).
      expect(find.text('reviewer'), findsOneWidget);
      expect(find.text('Описание reviewer'), findsOneWidget);
      // У отклонённого файла — прочерки вместо области, инструментов и модели.
      expect(
        find.descendant(
          of: _key('agents-definitions-row-migrator'),
          matching: find.text('—'),
        ),
        findsWidgets,
      );
      expectNoEnglish(const ['Not loaded', 'Available in', 'built-in']);
    });

    testWidgets('ru: InfoBar ошибки определения — заголовок «Не удалось '
        'загрузить определение · строка 4», текст ядра как есть, путь с «~»', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _ready(definitions: _definitions()),
        locale: const Locale('ru'),
      );

      final bar = _key('agents-definitions-error-0');
      expect(
        find.descendant(
          of: bar,
          matching: find.text('Не удалось загрузить определение · строка 4'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('tools must be a list')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: bar,
          matching: find.textContaining('~/.codelab/agents/migrator.md'),
        ),
        findsOneWidget,
      );
      expectNoEnglish(const ['Cannot load the definition', 'Open folder']);
    });

    testWidgets('ru: InfoBar недоверенного проекта, таймаута и сбоя открытия '
        '— без английского, путь как есть', (tester) async {
      await pumpPage(
        tester,
        _ready(
          definitions: _definitions(
            untrusted: true,
            timedOut: true,
            openFailure: '~/.codelab/agents',
          ),
        ),
        locale: const Locale('ru'),
      );

      expect(
        _text('agents-definitions-untrusted', '~/work/app'),
        findsOneWidget,
      );
      expect(
        _text('agents-definitions-open-failed', '~/.codelab/agents'),
        findsOneWidget,
      );
      expect(_key('agents-definitions-timeout'), findsOneWidget);
      expectNoEnglish(const [
        'Project definitions are not read',
        'are not read: the project is not trusted',
        'were not read within 5 s',
        'Cannot open the folder',
        'Could not open',
      ]);
    });

    testWidgets('ru: меню «Open folder» — пункты и подпись по-русски, путь '
        'как есть', (tester) async {
      await pumpPage(
        tester,
        _ready(definitions: _definitions()),
        locale: const Locale('ru'),
      );

      await tester.tap(_key('agents-definitions-open-folder'));
      await tester.pumpAndSettle();

      expect(find.textContaining('~/.codelab/agents'), findsWidgets);
      expectNoEnglish(const [
        'User definitions',
        'This project (.codelab/agents)',
        'Open folder',
      ]);
    });
  });

  group('смена языка (D5, D9)', () {
    testWidgets('рабочее состояние: en → ru → en, expectNoStaleLanguage', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _ready(
          mode: 'ask',
          blocks: true,
          modeSource: ConfigSourceKind.projectLocal,
          effortSource: ConfigSourceKind.user,
          definitions: _definitions(),
        ),
      );

      await language.select(tester, const Locale('ru'));
      await expectNoStaleLanguage(
        tester,
        from: en,
        to: ru,
        ignore: {'default'},
      );
      expect(find.text('Доступно'), findsNWidgets(3));

      await language.select(tester, const Locale('en'));
      await expectNoStaleLanguage(
        tester,
        from: ru,
        to: en,
        ignore: {'default'},
      );
      expect(find.text('Available'), findsNWidgets(3));
    });

    testWidgets('с баннером перекрытия, InfoBar сужения и InfoBar ошибок '
        'определений: пересобираются, без смеси языков', (tester) async {
      await pumpPage(
        tester,
        _ready(
          mode: 'ask',
          narrowed: true,
          modeSource: ConfigSourceKind.user,
          banner: const AgentsModesBanner(
            AgentsModesBannerKind.warning,
            message: AgentsSavedOverriddenMessage(
              setting: AgentsModesSetting.mode,
              target: ConfigLayer.user,
              source: ConfigSourceKind.projectLocal,
              value: 'plan',
              when: AgentsApplyWhen.afterRestart,
            ),
          ),
          definitions: _definitions(untrusted: true, openFailure: '~/x'),
        ),
      );

      await language.select(tester, const Locale('ru'));
      await expectNoStaleLanguage(
        tester,
        from: en,
        to: ru,
        ignore: {'default'},
      );
      expectNoEnglish(const [
        'Saved to',
        'after Restart agent',
        'Project definitions are not read',
      ]);

      await language.select(tester, const Locale('en'));
      await expectNoStaleLanguage(
        tester,
        from: ru,
        to: en,
        ignore: {'default'},
      );
      expect(
        find.textContaining(
          'Saved to All projects; local overrides it: new sessions use plan '
          'after Restart agent.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('read-only и unreadable пересобираются при смене языка', (
      tester,
    ) async {
      await pumpPage(
        tester,
        const AgentsModesReadOnly(
          reason: RemoteAgentReadOnly('wss://devbox:7420'),
        ),
      );
      await language.select(tester, const Locale('ru'));
      await expectNoStaleLanguage(
        tester,
        from: en,
        to: ru,
        ignore: {'default'},
      );
      expectNoEnglish(const ['Read-only: this agent runs on']);

      cubit.show(
        const AgentsModesUnreadable(
          issues: [AppSettingsProblem(AppSettingsProblemKind.homeUnavailable)],
        ),
      );
      await tester.pumpAndSettle();
      expectNoEnglish(const ['The CodeLab home folder is not available.']);
      await language.select(tester, const Locale('en'));
      expect(
        find.textContaining('The CodeLab home folder is not available.'),
        findsOneWidget,
      );
    });
  });
}
