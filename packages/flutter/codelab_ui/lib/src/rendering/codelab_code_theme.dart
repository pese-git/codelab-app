import 'package:fluent_ui/fluent_ui.dart';

import 'codelab_code_highlighter.dart' show CodeLabTokenClass;

/// Палитра подсветки кода в теме Fluent.
///
/// Почему: встроенные темы `val_highlight` светлые и берут цвета из чужих
/// схем, а в тёмной теме Fluent блок кода с ними нечитаем (прототип
/// `add-desktop-markdown`, факт 6); палитру из чужой темы копировать нельзя
/// (решение Q4, D4). Цвета обязаны быть различимыми на фоне блока: контраст не
/// ниже 4,5:1 (DSK-19).
///
/// Для чего: даёт фон блока ([background]), цвет обычного текста кода
/// ([plain]) и цвет каждого класса токена ([colorOf]). Палитра строится из
/// ролей `FluentTheme`: фон — карточка поверх фона страницы, обычный и
/// приглушённый текст — `textFillColor*`, остальные классы — оттенки
/// акцентных цветов Fluent (`Colors.*`) под яркость темы, а затем лёгкость
/// каждого цвета подбирается шагами, пока контраст к фону не дойдёт до
/// [_targetContrast] — это гарантирует требование, а не надежда на оттенок.
///
/// Как использовать: `CodeLabCodeTheme.of(FluentTheme.of(context))` в блоке
/// кода. Приложение МОЖЕТ положить свою палитру в
/// `FluentThemeData.extensions` — она победит расчётную.
class CodeLabCodeTheme extends ThemeExtension<CodeLabCodeTheme> {
  const CodeLabCodeTheme({
    required this.background,
    required this.plain,
    required Map<CodeLabTokenClass, Color> colors,
  }) : _colors = colors;

  /// Непрозрачный фон блока кода: на нём проверяется контраст.
  final Color background;

  /// Цвет кода без подсветки и участков между токенами.
  final Color plain;

  final Map<CodeLabTokenClass, Color> _colors;

  /// Контраст с запасом над порогом 4,5:1 (DSK-19): округления яркости не
  /// должны опускать цвет ниже требования.
  static const double _targetContrast = 4.7;

  static final Expando<CodeLabCodeTheme> _derived = Expando(
    'derived code palettes',
  );

  /// Палитра темы [theme]: из `extensions`, если приложение её задало, иначе
  /// рассчитанная по ролям Fluent (кешируется на объект темы).
  static CodeLabCodeTheme of(FluentThemeData theme) {
    final registered = theme.extensions[CodeLabCodeTheme];
    if (registered is CodeLabCodeTheme) return registered;
    return _derived[theme] ??= CodeLabCodeTheme._derive(theme);
  }

  /// Цвет класса токена.
  Color colorOf(CodeLabTokenClass tokenClass) => _colors[tokenClass] ?? plain;

  factory CodeLabCodeTheme._derive(FluentThemeData theme) {
    final resources = theme.resources;
    final dark = theme.brightness == Brightness.dark;
    final base = resources.solidBackgroundFillColorBase;
    final background = _opaque(
      resources.cardBackgroundFillColorSecondary,
      base,
    );

    Color fit(Color color) =>
        _withContrast(_opaque(color, background), background);

    // Оттенки акцентов: тёмные для светлого фона, светлые для тёмного.
    Color shade(AccentColor accent) => dark ? accent.lighter : accent.darker;

    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    return CodeLabCodeTheme(
      background: background,
      plain: fit(resources.textFillColorPrimary),
      colors: {
        CodeLabTokenClass.keyword: fit(accent),
        CodeLabTokenClass.string: fit(shade(Colors.green)),
        CodeLabTokenClass.comment: fit(resources.textFillColorSecondary),
        CodeLabTokenClass.number: fit(shade(Colors.orange)),
        CodeLabTokenClass.type: fit(shade(Colors.teal)),
        CodeLabTokenClass.function: fit(shade(Colors.blue)),
        CodeLabTokenClass.variable: fit(shade(Colors.magenta)),
        CodeLabTokenClass.operator: fit(resources.textFillColorTertiary),
        CodeLabTokenClass.attribute: fit(shade(Colors.purple)),
      },
    );
  }

  /// [color] поверх [under] без прозрачности.
  static Color _opaque(Color color, Color under) =>
      Color.alphaBlend(color, under).withValues(alpha: 1);

  /// Сдвигает яркость [color] от фона, пока контраст не достигнет
  /// [_targetContrast]; без сдвига возвращает цвет, который уже проходит.
  static Color _withContrast(Color color, Color background) {
    final towardLight = background.computeLuminance() < 0.5;
    var hsl = HSLColor.fromColor(color);
    for (
      var i = 0;
      i < 40 && _contrast(hsl.toColor(), background) < _targetContrast;
      i++
    ) {
      final next = hsl.lightness + (towardLight ? 0.025 : -0.025);
      hsl = hsl.withLightness(next.clamp(0.0, 1.0));
    }
    return hsl.toColor();
  }

  static double _contrast(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final hi = l1 > l2 ? l1 : l2;
    final lo = l1 > l2 ? l2 : l1;
    return (hi + 0.05) / (lo + 0.05);
  }

  @override
  CodeLabCodeTheme copyWith({
    Color? background,
    Color? plain,
    Map<CodeLabTokenClass, Color>? colors,
  }) => CodeLabCodeTheme(
    background: background ?? this.background,
    plain: plain ?? this.plain,
    colors: colors ?? _colors,
  );

  @override
  CodeLabCodeTheme lerp(ThemeExtension<CodeLabCodeTheme>? other, double t) {
    if (other is! CodeLabCodeTheme) return this;
    return CodeLabCodeTheme(
      background: Color.lerp(background, other.background, t)!,
      plain: Color.lerp(plain, other.plain, t)!,
      colors: {
        for (final c in CodeLabTokenClass.values)
          c: Color.lerp(colorOf(c), other.colorOf(c), t)!,
      },
    );
  }
}
