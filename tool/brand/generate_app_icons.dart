/// Генератор иконок приложения CodeLab для всех платформ Flutter.
///
/// Почему: десктоп-клиент собирается под macOS, Linux, Windows, Android, iOS
/// и Web, а у каждой платформы свои размеры, маски и правила прозрачности.
/// Рисовать варианты вручную — значит рано или поздно получить расхождение
/// знака между платформами.
///
/// Для чего: единственный путь от исходника знака
/// (`docs/design/brand/codelab-glyph.svg`, `codelab-glyph-mono.svg`) к
/// платформенным ресурсам по путям шаблона `flutter create`, а также к
/// эталонным SVG бренда: варианты иконки в `docs/design/brand/launcher/` и
/// логотип из знака и `codelab-wordmark.svg`. Скрипт только
/// раскладывает файлы: подключение иконки в нативном коде (`roundIcon` в
/// манифесте Android, иконка окна GTK в Linux) остаётся платформенной
/// настройкой, см. `docs/design/brand/README.md`.
///
/// Как использовать: из корня репозитория
/// `fvm dart run tool/brand/generate_app_icons.dart [--out <каталог>]
/// [--platforms macos,ios,...]`. По умолчанию пишет в `apps/codelab_desktop`
/// и только в платформы, каталог которых уже есть (после
/// `fvm flutter create --platforms=<p> .`). С `--out` пишет все выбранные
/// платформы в указанный каталог — для предпросмотра. Нужны `rsvg-convert`
/// (librsvg) и `magick` (ImageMagick) в `PATH`.
library;

import 'dart:io';

const _brandDir = 'docs/design/brand';
const _defaultAppDir = 'apps/codelab_desktop';
const _allPlatforms = ['macos', 'ios', 'android', 'windows', 'linux', 'web'];

/// Центр знака в координатах исходника 1024×1024: колба ниже геометрического
/// центра из-за горлышка, поэтому масштаб считается от (512, 523).
const _glyphCenterY = 523;

/// Градиент плашки — акцент Fluent `#005FB8` из макетов `docs/design`,
/// растянутый в светлую и тёмную сторону.
const _backgroundDefs = '''
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#1A7FE0"/>
  <stop offset="1" stop-color="#003E8A"/>
</linearGradient>''';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final glyph = _svgBody(
    File('$_brandDir/codelab-glyph.svg').readAsStringSync(),
  );
  final mono = _svgBody(
    File('$_brandDir/codelab-glyph-mono.svg').readAsStringSync(),
  );
  final root = options.out ?? _defaultAppDir;

  final platforms = options.platforms.where((p) {
    // Без --out платформа, которой нет в приложении, пропускается: создавать
    // платформенный каталог — задача `flutter create`, а не генератора.
    if (options.out != null || Directory('$root/$p').existsSync()) return true;
    stdout.writeln('skip $p: $root/$p does not exist');
    return false;
  });

  final renderer = _Renderer(glyph: glyph, mono: mono);
  for (final platform in platforms) {
    await switch (platform) {
      'macos' => renderer.macos('$root/macos'),
      'ios' => renderer.ios('$root/ios'),
      'android' => renderer.android('$root/android'),
      'windows' => renderer.windows('$root/windows'),
      'linux' => renderer.linux('$root/linux'),
      'web' => renderer.web('$root/web'),
      _ => throw ArgumentError.value(platform, 'platform', 'unknown platform'),
    };
    stdout.writeln('ok $platform');
  }

  final wordmark = _svgBody(
    File('$_brandDir/codelab-wordmark.svg').readAsStringSync(),
  );
  await renderer.brand(
    options.out == null ? _brandDir : '${options.out}/brand',
    wordmark: wordmark,
  );
  stdout.writeln('ok brand');
}

/// Собирает SVG-варианты знака и растеризует их в файлы платформ.
///
/// Почему отдельный класс: варианты различаются только формой фона и
/// масштабом знака, а растеризация и запись файлов у всех общие.
class _Renderer {
  _Renderer({required this.glyph, required this.mono});

  final String glyph;
  final String mono;

  /// Все варианты иконки по имени: и для PNG платформ, и для эталонных SVG
  /// в `docs/design/brand/launcher/`, поэтому эталон и сборка не расходятся.
  /// Параметры каждого варианта объяснены у метода его платформы.
  late final Map<String, String> variants = {
    'macos': _plate(margin: 100, radius: 185, scale: 1),
    'ios': _fullBleed(scale: 1.15),
    'android-foreground': _layer(glyph, scale: 0.85),
    'android-background': _fullBleed(scale: 0, withGlyph: false),
    'android-monochrome': _layer(mono, scale: 0.85),
    'android-legacy': _plate(margin: 85, radius: 180, scale: 0.95),
    'android-round': _circle(margin: 85, scale: 0.95),
    'android-play-store': _fullBleed(scale: 1.15),
    'windows': _plate(margin: 32, radius: 200, scale: 1.1),
    'linux': _plate(margin: 64, radius: 190, scale: 1.05),
    'web-favicon': _plate(margin: 0, radius: 200, scale: 1.15),
    'web-icon': _plate(margin: 32, radius: 200, scale: 1.1),
    'web-maskable': _fullBleed(scale: 1),
  };

  /// Эталонные SVG бренда: варианты иконки в `launcher/`, горизонтальный
  /// логотип для светлого и тёмного фона и PNG-превью логотипа.
  ///
  /// Почему генерируются, а не рисуются: знак и надпись живут в своих
  /// исходниках (`codelab-glyph.svg`, `codelab-wordmark.svg`), а копия в
  /// логотипе устаревала бы при каждой правке знака.
  Future<void> brand(String dir, {required String wordmark}) async {
    for (final MapEntry(key: name, value: svg) in variants.entries) {
      _write('$dir/launcher/$name.svg', svg);
    }
    final light = _logo(wordmark, code: '#1A1A1A', lab: '#005FB8');
    // Акцент Fluent для тёмной темы: #005FB8 на тёмном фоне теряет контраст.
    final dark = _logo(wordmark, code: '#FFFFFF', lab: '#4CC2FF');
    _write('$dir/codelab-logo.svg', light);
    _write('$dir/codelab-logo-dark.svg', dark);
    await _pngWidth(light, 1600, '$dir/codelab-logo.png');
    await _pngWidth(dark, 1600, '$dir/codelab-logo-dark.png');
    await _png(variants['macos']!, 1024, '$dir/codelab-icon-1024.png');
  }

  /// Знак на плашке слева и надпись справа. Плашка 320 по высоте, прописные
  /// надписи — 200: так знак заметно крупнее строки, но не давит её. Поле
  /// 24 по краям, чтобы скруглённые концы букв не упирались в границу.
  String _logo(String wordmark, {required String code, required String lab}) {
    final body = wordmark
        .replaceFirst('.code{stroke:#1A1A1A}', '.code{stroke:$code}')
        .replaceFirst('.lab{stroke:#005FB8}', '.lab{stroke:$lab}');
    final mark = _svgBody(variants['web-favicon']!);
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-24 -24 1728 368">'
        '<g transform="scale(${320 / 1024})">$mark</g>'
        '<g transform="translate(405 -40)">$body</g></svg>\n';
  }

  /// macOS не скругляет иконку сам: плашка 824×824 с отступом 100 и
  /// радиусом ~185 повторяет сетку иконок Apple для macOS 11+.
  Future<void> macos(String dir) async {
    final svg = variants['macos']!;
    final out = '$dir/Runner/Assets.xcassets/AppIcon.appiconset';
    for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
      await _png(svg, size, '$out/app_icon_$size.png');
    }
  }

  /// iOS сам накладывает маску со скруглением, а App Store отклоняет
  /// иконки с альфа-каналом, поэтому фон на всю площадь и без прозрачности.
  Future<void> ios(String dir) async {
    final svg = variants['ios']!;
    final out = '$dir/Runner/Assets.xcassets/AppIcon.appiconset';
    final sizes = <num, List<int>>{
      20: [1, 2, 3],
      29: [1, 2, 3],
      40: [1, 2, 3],
      60: [2, 3],
      76: [1, 2],
      83.5: [2],
      1024: [1],
    };
    for (final MapEntry(key: points, value: scales) in sizes.entries) {
      final name = points == 83.5 ? '83.5' : '${points.toInt()}';
      for (final scale in scales) {
        await _png(
          svg,
          (points * scale).round(),
          '$out/Icon-App-${name}x$name@${scale}x.png',
          opaque: true,
        );
      }
    }
  }

  /// Android 8+ берёт adaptive icon из двух слоёв 108dp и сам режет их
  /// маской производителя; знак держится в безопасной зоне 66dp, отсюда
  /// масштаб 0.85. Растровые `ic_launcher` и `ic_launcher_round` остаются
  /// для Android 7 и ниже, `monochrome` — для тематических иконок 13+.
  Future<void> android(String dir) async {
    final res = '$dir/app/src/main/res';
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    final legacy = variants['android-legacy']!;
    final round = variants['android-round']!;
    final foreground = variants['android-foreground']!;
    final monochrome = variants['android-monochrome']!;
    final background = variants['android-background']!;
    for (final MapEntry(key: density, value: k) in densities.entries) {
      final mipmap = '$res/mipmap-$density';
      await _png(legacy, (48 * k).round(), '$mipmap/ic_launcher.png');
      await _png(round, (48 * k).round(), '$mipmap/ic_launcher_round.png');
      final layer = (108 * k).round();
      await _png(foreground, layer, '$mipmap/ic_launcher_foreground.png');
      await _png(monochrome, layer, '$mipmap/ic_launcher_monochrome.png');
      await _png(background, layer, '$mipmap/ic_launcher_background.png');
    }
    const adaptive = '''
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
''';
    _write('$res/mipmap-anydpi-v26/ic_launcher.xml', adaptive);
    _write('$res/mipmap-anydpi-v26/ic_launcher_round.xml', adaptive);
    // Иконка для страницы Google Play: квадрат 512 без прозрачности,
    // скругление Play накладывает сам.
    await _png(
      variants['android-play-store']!,
      512,
      '$dir/play_store_512.png',
      opaque: true,
    );
  }

  /// Windows показывает иконку без маски на панели задач и в проводнике,
  /// поэтому плашка почти во весь квадрат; в `.ico` все размеры оболочки.
  Future<void> windows(String dir) async {
    final svg = variants['windows']!;
    final tmp = Directory.systemTemp.createTempSync('codelab_ico');
    try {
      final frames = <String>[];
      for (final size in [16, 24, 32, 48, 64, 128, 256]) {
        final frame = '${tmp.path}/$size.png';
        await _png(svg, size, frame);
        frames.add(frame);
      }
      final ico = '$dir/runner/resources/app_icon.ico';
      Directory(File(ico).parent.path).createSync(recursive: true);
      await _run('magick', [...frames, ico]);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  /// У шаблона Flutter для Linux нет иконки: файлы раскладываются по схеме
  /// hicolor freedesktop, чтобы их ставил пакет (deb, flatpak, snap) и
  /// подхватывал `.desktop`-файл с `Icon=codelab`.
  Future<void> linux(String dir) async {
    final svg = variants['linux']!;
    for (final size in [16, 24, 32, 48, 64, 128, 256, 512]) {
      await _png(
        svg,
        size,
        '$dir/assets/icons/hicolor/${size}x$size/apps/codelab.png',
      );
    }
    _write('$dir/assets/icons/hicolor/scalable/apps/codelab.svg', svg);
  }

  /// Web: `favicon.png` и иконки PWA из шаблона `web/manifest.json`.
  /// Maskable-вариант на весь квадрат: браузер режет его по кругу с
  /// безопасной зоной 80%, знак в неё помещается.
  Future<void> web(String dir) async {
    await _png(variants['web-favicon']!, 32, '$dir/favicon.png');
    final icon = variants['web-icon']!;
    final maskable = variants['web-maskable']!;
    for (final size in [192, 512]) {
      await _png(icon, size, '$dir/icons/Icon-$size.png');
      await _png(maskable, size, '$dir/icons/Icon-maskable-$size.png');
    }
  }

  String _plate({
    required int margin,
    required int radius,
    required double scale,
  }) {
    final side = 1024 - 2 * margin;
    return _svg(
      '<rect x="$margin" y="$margin" width="$side" height="$side" '
      'rx="$radius" fill="url(#bg)"/>${_place(glyph, scale)}',
    );
  }

  String _circle({required int margin, required double scale}) => _svg(
    '<circle cx="512" cy="512" r="${512 - margin}" fill="url(#bg)"/>'
    '${_place(glyph, scale)}',
  );

  String _fullBleed({required double scale, bool withGlyph = true}) => _svg(
    '<rect width="1024" height="1024" fill="url(#bg)"/>'
    '${withGlyph ? _place(glyph, scale) : ''}',
  );

  String _layer(String body, {required double scale}) =>
      _svg(_place(body, scale));

  String _svg(String content) =>
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
      '<defs>$_backgroundDefs</defs>$content</svg>\n';

  String _place(String body, double scale) =>
      '<g transform="translate(512 512) scale($scale) '
      'translate(-512 -$_glyphCenterY)">$body</g>';

  /// Растеризация по ширине для логотипа: он не квадратный, высота
  /// следует из `viewBox`.
  Future<void> _pngWidth(String svg, int width, String path) async {
    final tmp = File('$path.svg')..writeAsStringSync(svg);
    try {
      await _run('rsvg-convert', ['-w', '$width', tmp.path, '-o', path]);
    } finally {
      tmp.deleteSync();
    }
  }

  Future<void> _png(
    String svg,
    int size,
    String path, {
    bool opaque = false,
  }) async {
    Directory(File(path).parent.path).createSync(recursive: true);
    final tmp = File('$path.svg')..writeAsStringSync(svg);
    try {
      await _run('rsvg-convert', [
        '-w',
        '$size',
        '-h',
        '$size',
        tmp.path,
        '-o',
        path,
      ]);
    } finally {
      tmp.deleteSync();
    }
    if (opaque) {
      // Фон и так непрозрачен, но rsvg пишет RGBA; App Store и Play
      // проверяют именно наличие альфа-канала.
      await _run('magick', [path, '-alpha', 'off', path]);
    }
  }
}

/// Содержимое корневого `<svg>` без самого тега: знак вставляется в
/// варианты как группа, а не как вложенный документ — так rsvg не теряет
/// `defs` и градиенты.
String _svgBody(String text) {
  final start = text.indexOf('>', text.indexOf('<svg')) + 1;
  return text.substring(start, text.lastIndexOf('</svg>'));
}

void _write(String path, String content) {
  Directory(File(path).parent.path).createSync(recursive: true);
  File(path).writeAsStringSync(content);
}

Future<void> _run(String executable, List<String> args) async {
  final result = await Process.run(executable, args);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      args,
      '${result.stderr}',
      result.exitCode,
    );
  }
}

typedef _Options = ({String? out, List<String> platforms});

_Options _parseArgs(List<String> args) {
  String? out;
  var platforms = _allPlatforms;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--out':
        out = args[++i];
      case '--platforms':
        platforms = args[++i].split(',');
      default:
        stderr.writeln(
          'usage: generate_app_icons.dart [--out <dir>] '
          '[--platforms ${_allPlatforms.join(',')}]',
        );
        exit(64);
    }
  }
  return (out: out, platforms: platforms);
}
