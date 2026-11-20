// «Тёмная проверка» (задача 4.11 change `add-app-appearance-page`; design.md
// «Риски: Тёмный режим впервые для всего app», Q3 (а)).
//
// Экраны рисовались и проверялись только в светлой теме, а «Match system» по
// умолчанию делает тёмным app каждого пользователя с тёмной системой. Один
// тест на тему проходит ВСЕ экраны одного приложения — рабочее место с лентой,
// вызовом инструмента, диалогом одобрения и доками, затем каждую видимую
// страницу настроек из `defaultSettingsPages` — в `dark` и `high-contrast`:
//   - нет исключений рендера;
//   - у ключевых ролей цвета (основной и вторичный текст, тоны `success`,
//     `warning`, `danger`, ссылки `info`) контраст к фону страницы и к фону
//     карточки не ниже 4,5:1 (WCAG AA).
//
// Как устроен: настоящий граф app (`LiveScene`) с оформлением из шва
// `AppAppearanceStart`; страница выбирается тем же `NavigationCubit`, что и
// пользователь. Новая страница в `defaultSettingsPages` попадает в прогон
// сама. Красный по причине зашитых цветов вне ролей темы; реализация 4.12
// заменяет их ролями (только места, на которые указал тест).

import 'package:codelab_desktop/app/appearance/app_appearance_start.dart';
import 'package:codelab_desktop/app/default_settings_pages.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/core/platform/app_appearance_preferences.dart';
import 'package:codelab_desktop/features/settings/application/contrast_checks.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_provider_settings.dart';
import '../support/live_scene.dart';

/// Роль цвета текста и её значение в теме экрана.
typedef _Role = ({String name, Color color});

Color _flat(Color over, Color under) =>
    Color.alphaBlend(over, under).withValues(alpha: 1);

/// Тема, действующая внутри `FluentApp`: композер рабочего места остаётся в
/// дереве и под настройками (`Offstage`), поэтому ищется со `skipOffstage:
/// false`.
FluentThemeData _themeOf(WidgetTester tester) => FluentTheme.of(
  tester.element(find.byType(CodeLabPromptComposer, skipOffstage: false)),
);

/// Проверяет контраст ключевых ролей темы, действующей на экране [screen].
void _expectKeyRoles(WidgetTester tester, String screen) {
  final theme = _themeOf(tester);
  final page = theme.resources.solidBackgroundFillColorBase;
  final card = _flat(theme.resources.cardBackgroundFillColorDefault, page);
  final palette = CodeLabPalette.of(theme);
  final link = palette.info is AccentColor
      ? (palette.info as AccentColor).defaultBrushFor(theme.brightness)
      : palette.info;
  final roles = <_Role>[
    (name: 'text', color: theme.resources.textFillColorPrimary),
    (name: 'muted', color: theme.resources.textFillColorSecondary),
    (name: 'success', color: palette.success),
    (name: 'warning', color: palette.warning),
    (name: 'danger', color: palette.danger),
    (name: 'info (ссылка)', color: link),
  ];
  for (final role in roles) {
    for (final (fill, background) in [('страница', page), ('карточка', card)]) {
      expect(
        contrastRatio(_flat(role.color, background), background),
        greaterThanOrEqualTo(kMinTextContrast),
        reason: '$screen: ${role.name} на фоне «$fill»',
      );
    }
  }
}

/// Тег кита читаем на своей заливке: цвет текста `CodeLabBadge` к фону страницы
/// с заливкой тега не ниже 4,5:1. Находка 4.12: нейтральный тег (`http`,
/// `user`, `app`) рисовался зашитым `Colors.grey` (#323130) — 1,3:1 на тёмном.
void _expectBadgesReadable(WidgetTester tester, String screen) {
  final page = _themeOf(tester).resources.solidBackgroundFillColorBase;
  for (final badge in tester.elementList(find.byType(CodeLabBadge))) {
    final fill = find
        .descendant(
          of: find.byWidget(badge.widget),
          matching: find.byType(DecoratedBox),
        )
        .evaluate()
        .map((e) => (e.widget as DecoratedBox).decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color)
        .whereType<Color>()
        .first;
    final text = tester
        .widget<Text>(
          find.descendant(
            of: find.byWidget(badge.widget),
            matching: find.byType(Text),
          ),
        )
        .style
        ?.color;
    final background = _flat(fill, page);
    expect(
      contrastRatio(_flat(text!, background), background),
      greaterThanOrEqualTo(kMinTextContrast),
      reason: '$screen: тег «${(badge.widget as CodeLabBadge).label}»',
    );
  }
}

void main() {
  const themes = {
    'dark': AppAppearanceSettings(mode: AppearanceMode.dark),
    'high-contrast': AppAppearanceSettings(
      mode: AppearanceMode.dark,
      darkTheme: 'high-contrast',
    ),
  };

  for (final entry in themes.entries) {
    testWidgets('${entry.key}: рабочее место, доки, диалог одобрения и все '
        'страницы настроек без исключений, ключевые роли ≥ 4,5:1', (
      tester,
    ) async {
      final store = FakeAgentConfigStore(
        user: {
          'agent': {'default_model': 'anthropic/m'},
          'providers': {
            'anthropic': providerMap(
              kind: 'anthropic',
              baseUrl: null,
              secret: 'codelab/anthropic',
            ),
          },
          'mcp': {
            'servers': [
              {
                'name': 'github',
                'type': 'http',
                'url': 'https://api.example.test/mcp/',
              },
            ],
          },
        },
      );
      final session = FakeProviderSettingsSession(store);
      final scene = await LiveScene.open(
        tester,
        appearance: AppAppearanceStart(settings: entry.value),
        providerSettingsOpener: (access, env) async => session,
      );
      await scene.newSession('s1');
      final turn = await scene.prompt('explain the repo');
      await scene.agentText('s1', 'Done. 3 files changed.');
      await scene.endTurn(turn, stopReason: 'max_tokens');
      await scene.prompt('run the tests');
      await scene.toolCall('s1', toolCallId: 'c1', title: 'Run echo hi');
      await scene.requestPermission(id: 100, sessionId: 's1', toolCallId: 'c2');
      await scene.flush();

      expect(
        _themeOf(tester).brightness,
        Brightness.dark,
        reason: 'тест идёт в тёмной теме',
      );
      expect(tester.takeException(), isNull, reason: 'рабочее место');
      _expectKeyRoles(tester, 'рабочее место (${entry.key})');
      _expectBadgesReadable(tester, 'рабочее место (${entry.key})');

      final navigation = scene.binding.scope.resolve<NavigationCubit>();
      await navigation.openSettings(
        page: defaultSettingsPages.visible.first,
        source: SettingsOpenSource.sidebar,
      );
      await scene.flush();
      for (final page in defaultSettingsPages.visible) {
        await navigation.selectSettingsPage(page);
        // Не `pumpAndSettle`: идущий вызов держит бесконечную анимацию.
        await scene.flush();
        expect(
          tester.takeException(),
          isNull,
          reason: 'настройки: ${page.slug}',
        );
        _expectKeyRoles(tester, 'настройки: ${page.slug} (${entry.key})');
        _expectBadgesReadable(tester, 'настройки: ${page.slug} (${entry.key})');
      }

      await scene.close();
    });
  }
}
