import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../features/settings/application/contrast_checks.dart';
import 'built_in_themes.dart';

/// Контраст с запасом над порогом 4,5:1: округления не опускают цвет ниже
/// требования (как в `CodeLabCodeTheme`).
const _targetContrast = 4.7;

Color _rgbColor(Rgb value) => Color(0xFF000000 | value.value);

/// Сдвигает яркость [color] от фона [background], пока контраст не достигнет
/// [_targetContrast] (подгонка D8 для цветов, которые app выводит сам).
Color _fit(Color color, Color background) {
  final towardLight = background.computeLuminance() < 0.5;
  var hsl = HSLColor.fromColor(Color.alphaBlend(color, background));
  for (
    var i = 0;
    i < 40 && contrastRatio(hsl.toColor(), background) < _targetContrast;
    i++
  ) {
    hsl = hsl.withLightness(
      (hsl.lightness + (towardLight ? 0.025 : -0.025)).clamp(0.0, 1.0),
    );
  }
  return hsl.toColor();
}

/// Подгоняет [color] под фоны, которые вернёт [backgroundsFor] для
/// очередного кандидата: сдвигает яркость в сторону [towardLight], пока худший
/// контраст не достигнет [_targetContrast].
///
/// Почему фоны зависят от кандидата: тег рисует текст тона на заливке того же
/// цвета (альфа 22 %), и чем светлее тон, тем светлее его заливка; без этого
/// тег `Approval` выходил на 4,1:1 при 10:1 к фону страницы.
Color _fitAll(
  Color color,
  List<Color> Function(Color) backgroundsFor, {
  required bool towardLight,
}) {
  double worst(Color c) => backgroundsFor(
    c,
  ).map((b) => contrastRatio(c, b)).reduce((a, b) => a < b ? a : b);
  var hsl = HSLColor.fromColor(color);
  for (var i = 0; i < 40 && worst(hsl.toColor()) < _targetContrast; i++) {
    hsl = hsl.withLightness(
      (hsl.lightness + (towardLight ? 0.025 : -0.025)).clamp(0.0, 1.0),
    );
  }
  return hsl.toColor();
}

/// Собирает `FluentThemeData` из темы [theme] (design.md change
/// `add-app-appearance-page`, D4, D6, D7).
///
/// Почему: Fluent не имеет ресурсов «успех текста» и цветов diff, поэтому app
/// кладёт в `FluentThemeData.extensions` палитру `CodeLabPalette` и палитру
/// кода `CodeLabCodeTheme` — виджеты кита читают цвета из них (D4).
///
/// Для чего: база — `FluentThemeData(brightness)` режима темы; поверх неё роли
/// встроенной темы базы (`extends`) и роли самой темы, в этом порядке. Не
/// заданные ролью цвета выводит кит из той же темы Fluent, поэтому для `light` и
/// `dark` без системного акцента значения равны выведенным китом (сценарий
/// «Стандартная тема не меняет вид»). Роли, которые не выражаются цветом
/// (`default`, ANSI, индексные), заменяются ролями базы. Пользовательская роль
/// применяется как задана — даже при низком контрасте (D8); подгоняются только
/// цвета, которые app выводит сам (запасные цвета кода под заменённый фон,
/// ссылка под системный акцент).
///
/// Как использовать: [systemAccent] — включённый системный акцент, он
/// заменяет роль `accent` любой темы (Q4); `null` — акцент темы. Функция
/// чистая, исключений не бросает.
FluentThemeData buildFluentTheme(ThemeFile theme, {Color? systemAccent}) {
  final base = builtInThemeFile(theme.base.jsonName);
  final roles = <ThemeRole, Color>{
    for (final file in [base, theme])
      for (final entry in file.roles.entries)
        if (entry.value is Rgb) entry.key: _rgbColor(entry.value as Rgb),
  };
  final brightness = theme.base == ThemeBase.light
      ? Brightness.light
      : Brightness.dark;
  final accent = systemAccent ?? roles[ThemeRole.accent];

  final defaults = brightness == Brightness.light
      ? const ResourceDictionary.light()
      : const ResourceDictionary.dark();
  final resources = brightness == Brightness.light
      ? ResourceDictionary.light(
          textFillColorPrimary:
              roles[ThemeRole.text] ?? defaults.textFillColorPrimary,
          textFillColorSecondary:
              roles[ThemeRole.muted] ?? defaults.textFillColorSecondary,
          systemFillColorSuccess:
              roles[ThemeRole.success] ?? defaults.systemFillColorSuccess,
          systemFillColorCaution:
              roles[ThemeRole.warning] ?? defaults.systemFillColorCaution,
          systemFillColorCritical:
              roles[ThemeRole.error] ?? defaults.systemFillColorCritical,
        )
      : ResourceDictionary.dark(
          textFillColorPrimary:
              roles[ThemeRole.text] ?? defaults.textFillColorPrimary,
          textFillColorSecondary:
              roles[ThemeRole.muted] ?? defaults.textFillColorSecondary,
          systemFillColorSuccess:
              roles[ThemeRole.success] ?? defaults.systemFillColorSuccess,
          systemFillColorCaution:
              roles[ThemeRole.warning] ?? defaults.systemFillColorCaution,
          systemFillColorCritical:
              roles[ThemeRole.error] ?? defaults.systemFillColorCritical,
        );

  FluentThemeData make([List<ThemeExtension<dynamic>> extensions = const []]) =>
      FluentThemeData(
        brightness: brightness,
        accentColor: accent?.toAccentColor(),
        selectionColor: roles[ThemeRole.selection],
        resources: resources,
        extensions: extensions,
      );

  // Тема без расширений: кит выводит из неё палитры по ролям Fluent и
  // акценту, и они следуют за системным акцентом.
  final themed = make();
  final derivedCode = CodeLabCodeTheme.of(themed);
  final background = roles[ThemeRole.codeBackground] ?? derivedCode.background;
  final backgroundReplaced = roles.containsKey(ThemeRole.codeBackground);

  Color codeColor(ThemeRole role, Color derived) =>
      roles[role] ?? (backgroundReplaced ? _fit(derived, background) : derived);

  final code = CodeLabCodeTheme(
    background: background,
    plain: codeColor(ThemeRole.text, derivedCode.plain),
    colors: {
      CodeLabTokenClass.keyword: codeColor(
        ThemeRole.codeKeyword,
        derivedCode.colorOf(CodeLabTokenClass.keyword),
      ),
      CodeLabTokenClass.string: codeColor(
        ThemeRole.codeString,
        derivedCode.colorOf(CodeLabTokenClass.string),
      ),
      CodeLabTokenClass.comment: codeColor(
        ThemeRole.codeComment,
        derivedCode.colorOf(CodeLabTokenClass.comment),
      ),
      CodeLabTokenClass.number: codeColor(
        ThemeRole.codeNumber,
        derivedCode.colorOf(CodeLabTokenClass.number),
      ),
      CodeLabTokenClass.type: codeColor(
        ThemeRole.codeType,
        derivedCode.colorOf(CodeLabTokenClass.type),
      ),
      CodeLabTokenClass.function: codeColor(
        ThemeRole.codeFunction,
        derivedCode.colorOf(CodeLabTokenClass.function),
      ),
      CodeLabTokenClass.variable: codeColor(
        ThemeRole.codeVariable,
        derivedCode.colorOf(CodeLabTokenClass.variable),
      ),
      CodeLabTokenClass.operator: codeColor(
        ThemeRole.codeOperator,
        derivedCode.colorOf(CodeLabTokenClass.operator),
      ),
      CodeLabTokenClass.attribute: codeColor(
        ThemeRole.codeAttribute,
        derivedCode.colorOf(CodeLabTokenClass.attribute),
      ),
    },
  );

  final derived = CodeLabPalette.of(themed);
  // Тоны, которые app выводит сам (роль не задана), подгоняются под фон
  // страницы, карточки и кода: в тёмной теме зашитые `Colors.green` и
  // `Colors.red` нечитаемы (риск «Тёмный режим впервые», задача 4.11), а
  // `Colors.red` на светлом фоне кода даёт 4,23:1, что ниже порога D8. Остальные
  // тоны светлой темы остаются прежними (сценарий «Стандартная тема не
  // меняет вид»).
  final page = resources.solidBackgroundFillColorBase;
  final card = Color.alphaBlend(
    resources.cardBackgroundFillColorDefault,
    page,
  ).withValues(alpha: 1);
  final backgrounds = [page, card, background];
  final dark = brightness == Brightness.dark;
  Color tone(ThemeRole role, Color derivedTone, {bool onlyDark = true}) {
    final given = roles[role];
    if (given != null) return given;
    if (onlyDark && !dark) return derivedTone;
    return _fitAll(
      derivedTone,
      (c) => [
        ...backgrounds,
        // Заливка тега под текстом тона (`CodeLabBadge`, альфа 56).
        Color.alphaBlend(c.withAlpha(56), page),
        Color.alphaBlend(c.withAlpha(56), card),
      ],
      towardLight: dark,
    );
  }

  final palette = derived.copyWith(
    success: tone(ThemeRole.success, derived.success),
    warning: tone(ThemeRole.warning, derived.warning),
    danger: tone(ThemeRole.error, derived.danger, onlyDark: false),
    accent: accent ?? tone(ThemeRole.accent, derived.accent),
    // В Fluent-темах ссылка — акцент (D4): без роли она следует за системным
    // акцентом, подогнанным под фон кода; без акцента остаётся выведенной.
    info:
        roles[ThemeRole.info] ??
        (systemAccent == null ? null : _fit(systemAccent, background)),
    diffAddBackground: roles[ThemeRole.diffAddBg],
    diffRemoveBackground: roles[ThemeRole.diffRemoveBg],
    selection: roles[ThemeRole.selection],
  );
  return make([palette, code]);
}
