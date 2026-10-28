/// Готовые строки компонентов `dart_tui` для кадра.
///
/// Почему: значок хода, пикер и строку подсказок рисуют компоненты пакета
/// (`SpinnerModel`, `ListModel`, `HelpModel`), а ядро экрана пакет не
/// импортирует (TUI-5).
/// Адаптер передаёт их `view()` в `render` строками: раскладка, ширина и
/// сброс атрибутов остаются за ядром (design.md change `add-cli-tui`, D12).
///
/// Как использовать: `TuiApp` собирает chrome на каждом кадре; тесты ядра
/// подставляют свои строки. [now] — время кадра для времени хода;
/// [picker] — строки `ListModel` открытого пикера.
final class TuiChrome {
  const TuiChrome({this.spinner, this.hints, this.picker, required this.now});

  final String? spinner;
  final String? hints;
  final List<String>? picker;
  final DateTime now;
}
