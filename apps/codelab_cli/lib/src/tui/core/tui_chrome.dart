/// Готовые строки компонентов `dart_tui` для кадра.
///
/// Почему: значок хода и строку подсказок рисуют компоненты пакета
/// (`SpinnerModel`, `HelpModel`), а ядро экрана пакет не импортирует (TUI-5).
/// Адаптер передаёт их `view()` в `render` строками: раскладка, ширина и
/// сброс атрибутов остаются за ядром (design.md change `add-cli-tui`, D12).
///
/// Как использовать: `TuiApp` собирает chrome на каждом кадре; тесты ядра
/// подставляют свои строки. [now] — время кадра для времени хода.
final class TuiChrome {
  const TuiChrome({this.spinner, this.hints, required this.now});

  final String? spinner;
  final String? hints;
  final DateTime now;
}
