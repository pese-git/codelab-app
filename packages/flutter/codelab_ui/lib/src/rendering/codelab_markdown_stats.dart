import 'package:flutter/foundation.dart';

/// Debug-счётчики работы отрисовки markdown.
///
/// Почему: «закрытый блок строится не больше одного раза за стрим» (DSK-3,
/// D3) нельзя проверить по времени кадра — тест был бы хрупким. Счётчик
/// работы даёт точное число построений без замеров (D13,
/// `12-3-desktop-display.md` §12.3.7).
///
/// Для чего: наблюдаемость для тестов `acp_markdown_test.dart`. Значения
/// меняются только внутри `assert`, поэтому в release-сборке код счётчиков
/// выбрасывается и стоимости не имеет.
///
/// Ограничение: в debug-сборке карты растут на каждый новый ключ блока или
/// заголовка и не чистятся (при долгой сессии — килобайты); только `reset()`
/// в тестах. В release карты не заполняются.
///
/// Как использовать: тест вызывает [reset] в `setUp` и читает поля после
/// кадров. Ключ блока кода — `<id>-<n>`: `id` строки ленты и порядковый номер
/// блока кода в ответе; ключ заголовка — его текст.
abstract final class CodeLabMarkdownStats {
  /// Построения ЗАКРЫТЫХ блоков кода по ключу `<id>-<n>`. Построения
  /// незакрытого хвоста сюда не входят: он по определению перестраивается
  /// на каждой дельте.
  @visibleForTesting
  static final Map<String, int> codeBlockBuilds = {};

  /// Монтирования (`initState`) блоков кода по тому же ключу. Больше одного —
  /// блок потерял состояние (риск R1 change `add-desktop-markdown`).
  @visibleForTesting
  static final Map<String, int> codeBlockMounts = {};

  /// Построения заголовков по тексту заголовка.
  @visibleForTesting
  static final Map<String, int> headingBuilds = {};

  /// Запуски токенизации кода (подсветка появится в итерации 3).
  @visibleForTesting
  static int highlightRuns = 0;

  /// Запуски токенизации синхронно, в UI isolate (итерация 3).
  @visibleForTesting
  static int highlightSyncRuns = 0;

  /// Обнуляет все счётчики.
  @visibleForTesting
  static void reset() {
    codeBlockBuilds.clear();
    codeBlockMounts.clear();
    headingBuilds.clear();
    highlightRuns = 0;
    highlightSyncRuns = 0;
  }

  /// Учитывает монтирование блока кода; вызывается только из `assert`.
  static bool noteCodeBlockMount(String key) => _bump(codeBlockMounts, key);

  /// Учитывает построение закрытого блока кода; только из `assert`.
  static bool noteCodeBlockBuild(String key) => _bump(codeBlockBuilds, key);

  /// Учитывает построение заголовка; только из `assert`.
  static bool noteHeadingBuild(String text) => _bump(headingBuilds, text);

  static bool _bump(Map<String, int> counter, String key) {
    counter.update(key, (value) => value + 1, ifAbsent: () => 1);
    return true;
  }
}
