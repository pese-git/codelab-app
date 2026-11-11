import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:val_highlight/languages/all.dart';
import 'package:val_highlight/val_highlight.dart';

import 'codelab_markdown_stats.dart';

/// Класс токена подсветки: что означает фрагмент кода.
///
/// Почему: движок `val_highlight` отдаёт вложенные области в стиле TextMate
/// (`keyword`, `string.escape`, `type.builtin`…), а палитре нужен небольшой
/// закрытый набор (D4). Сопоставление — в [CodeLabCodeHighlighter].
enum CodeLabTokenClass {
  keyword,
  string,
  comment,
  number,
  type,
  function,
  variable,
  operator,
  attribute,
}

/// Подсвеченный фрагмент кода: смещения `[start, end)` во всём коде.
///
/// Почему простые данные: список токенов возвращается из фонового isolate
/// (D4, A4) — в нём нет объектов Flutter и движка.
///
/// Для чего: тот же вид у синхронного и фонового результата. Токены
/// упорядочены, не пересекаются и лежат внутри кода; участки между токенами —
/// обычный текст.
class CodeLabCodeToken {
  const CodeLabCodeToken(this.start, this.end, this.tokenClass);

  final int start;
  final int end;
  final CodeLabTokenClass tokenClass;
}

/// Как подсвечивать код такого размера и языка (A4, DSK-5).
enum CodeLabHighlightMode {
  /// Не подсвечивать: язык неизвестен или код слишком большой.
  none,

  /// Токенизировать синхронно в кадре построения.
  sync,

  /// Токенизировать в фоновом isolate; до результата код без цвета.
  background,
}

/// Токенизатор: код на языке [language] в токены. Подменяется в тестах.
typedef CodeLabTokenizer =
    List<CodeLabCodeToken> Function(String language, String code);

/// Фоновый токенизатор. Подменяется в тестах; по умолчанию — отдельный isolate
/// (`Isolate.spawn` с `kill` по таймауту).
typedef CodeLabBackgroundTokenizer =
    Future<List<CodeLabCodeToken>> Function(String language, String code);

/// Подсветка кода на `val_highlight` с порогами и кешем.
///
/// Почему: токенизация большого блока в кадре построения блокирует UI isolate
/// (§12 `AGENTS.md`, DSK-5), а повторное построение строки после прокрутки
/// не должно токенизировать заново. Автоопределение языка у `val_highlight`
/// дорогое и часто ошибается — не используется (A4).
///
/// Для чего: единственная точка подсветки в ките. Пороги A4: до 300 строк,
/// 16 К code units и строк не длиннее 150 — синхронно; до 5000 строк, 256 К и
/// строк не длиннее 1000 — в фоновом isolate (`Isolate.spawn`, в него уходят
/// только язык и код, назад — простые токены; по таймауту 5 с isolate
/// убивается); больше — без подсветки. Порог по длине строки нужен потому, что
/// `RegExp` движка квадратичен по ней (swift `'#' * 16000` — 4,6 с). Язык
/// берётся из info-строки ограды; неизвестный, пустой и `text` — без токенов.
/// Результат кешируется в LRU на 256 записей и в бюджете 8 Mi единиц (code
/// units кода + 20 на токен). Сбой движка или таймаут не роняют ленту: пустой
/// список, `FlutterError` без текста кода, и тот же код дальше не пробуется
/// (результат «без подсветки» кешируется). Одинаковые фоновые запросы в полёте
/// делят один запуск.
///
/// Как использовать: блок кода берёт [shared] (общий кеш всей ленты) или
/// экземпляр из `CodeLabMarkdownConfig.highlighter`. Сначала [modeFor], затем
/// [cached] / [highlightSync] / [highlightInBackground].
class CodeLabCodeHighlighter {
  CodeLabCodeHighlighter({
    CodeLabTokenizer? tokenizer,
    CodeLabBackgroundTokenizer? background,
    this.backgroundTimeout = const Duration(seconds: 5),
  }) : _tokenizer = tokenizer ?? tokenizeWithEngine,
       _background =
           background ??
           ((language, code) =>
               _tokenizeInIsolate(language, code, backgroundTimeout));

  /// Общий экземпляр ленты: один LRU на все ответы.
  static final CodeLabCodeHighlighter shared = CodeLabCodeHighlighter();

  /// Пороги A4: синхронно до этих значений включительно. Размер считается в
  /// code units строки Dart (не в байтах UTF-8).
  static const int syncMaxLines = 300;
  static const int syncMaxChars = 16 * 1024;

  /// Самая длинная строка: `RegExp` движка квадратичен по длине строки
  /// (swift `'#' * 16000` — 4,6 с), поэтому синхронно — только строки до 150
  /// code units (замер AOT: блок 16 К строками по 300 — 73 мс), в фоне — до
  /// 1000 (256 К строками по 2000 — 7,8 с, дольше таймаута), длиннее — без
  /// подсветки (ревью итерации 3).
  static const int syncMaxLineChars = 150;
  static const int maxLineChars = 1000;

  /// Больше этих значений код не подсвечивается (DSK-5).
  static const int maxLines = 5000;
  static const int maxChars = 256 * 1024;

  /// Число записей LRU (D4).
  static const int cacheSize = 256;

  /// Суммарный бюджет кеша: code units кода плюс [tokenWeight] на каждый
  /// токен. Без него 256 блоков по 256 КиБ с токенами держали бы сотни
  /// мегабайт.
  static const int cacheBudget = 8 * 1024 * 1024;

  /// Вес одного токена в бюджете: объект с тремя полями дороже code unit.
  static const int tokenWeight = 20;

  /// Сколько ждать фоновую токенизацию; по истечении — код без подсветки.
  final Duration backgroundTimeout;

  final CodeLabTokenizer _tokenizer;
  final CodeLabBackgroundTokenizer _background;

  /// Запись кеша хранит и сам код: хеш в ключе — не доказательство
  /// совпадения, а токены чужого кода дали бы смещения за границей строки.
  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();
  int _cacheCost = 0;

  /// Фоновые запуски в полёте по `(язык, код)`: второй запрос не запускает
  /// второй isolate.
  final Map<String, Future<List<CodeLabCodeToken>>> _inFlight = {};

  /// Очищает кеш (для тестов: общий экземпляр иначе переносит состояние
  /// между тестами).
  @visibleForTesting
  void clear() {
    _cache.clear();
    _cacheCost = 0;
    _inFlight.clear();
  }

  /// Язык поддержан движком и не является «простым текстом» (D11: `text`
  /// не подсвечивается).
  bool supports(String language) => _supportedGrammar(language) != null;

  /// Режим подсветки для кода (A4, DSK-5): по языку, числу строк, размеру и
  /// самой длинной строке — один линейный проход.
  CodeLabHighlightMode modeFor(String language, String code) {
    if (!supports(language)) return CodeLabHighlightMode.none;
    final chars = code.length;
    if (chars > maxChars) return CodeLabHighlightMode.none;
    var lines = 1;
    var longest = 0;
    var current = 0;
    for (var i = 0; i < chars; i++) {
      if (code.codeUnitAt(i) == 0x0A) {
        lines++;
        if (current > longest) longest = current;
        current = 0;
      } else {
        current++;
      }
    }
    if (current > longest) longest = current;
    if (lines > maxLines || longest > maxLineChars) {
      return CodeLabHighlightMode.none;
    }
    if (lines <= syncMaxLines &&
        chars <= syncMaxChars &&
        longest <= syncMaxLineChars) {
      return CodeLabHighlightMode.sync;
    }
    return CodeLabHighlightMode.background;
  }

  /// Токены из кеша без токенизации; `null`, если записи нет.
  List<CodeLabCodeToken>? cached(String language, String code) {
    final key = _keyOf(language, code);
    final entry = _cache.remove(key);
    if (entry == null) return null;
    if (entry.code != code) {
      _cacheCost -= entry.cost;
      return null;
    }
    _cache[key] = entry; // «свежая» запись в конце LRU
    return entry.tokens;
  }

  /// Токенизирует в UI isolate (для кода в пределах синхронного порога).
  ///
  /// Неподдержанный язык даёт пустой список без вызова движка. Сбой движка —
  /// пустой список и один отчёт без текста кода; исход «без подсветки»
  /// запоминается, повтор того же кода движок не вызывает.
  List<CodeLabCodeToken> highlightSync(String language, String code) {
    if (!supports(language)) return const [];
    final hit = cached(language, code);
    if (hit != null) return hit;
    assert(CodeLabMarkdownStats.noteHighlightRun(sync: true));
    try {
      return _store(language, code, _tokenizer(language, code));
    } on Object catch (error, stack) {
      _report(language, error, stack);
      return _store(language, code, const []);
    }
  }

  /// Токенизирует в фоновом isolate (для кода между порогами).
  ///
  /// Результат из кеша возвращается сразу. Сбой и таймаут — пустой список и
  /// отчёт без текста кода, исход запоминается как «без подсветки».
  Future<List<CodeLabCodeToken>> highlightInBackground(
    String language,
    String code,
  ) {
    if (!supports(language)) return Future.value(const []);
    final hit = cached(language, code);
    if (hit != null) return Future.value(hit);
    final key = '${language.trim().toLowerCase()}\u0000$code';
    return _inFlight[key] ??= _runInBackground(language, code, key);
  }

  Future<List<CodeLabCodeToken>> _runInBackground(
    String language,
    String code,
    String key,
  ) async {
    assert(CodeLabMarkdownStats.noteHighlightRun(sync: false));
    try {
      final tokens = await _background(
        language,
        code,
      ).timeout(backgroundTimeout);
      return _store(language, code, tokens);
    } on Object catch (error, stack) {
      _report(language, error, stack);
      // Тот же код даст тот же исход: повторный монтаж и прокрутка не должны
      // снова запускать isolate и слать отчёты.
      return _store(language, code, const []);
    } finally {
      _inFlight.remove(key);
    }
  }

  List<CodeLabCodeToken> _store(
    String language,
    String code,
    List<CodeLabCodeToken> tokens,
  ) {
    final key = _keyOf(language, code);
    final replaced = _cache.remove(key);
    if (replaced != null) _cacheCost -= replaced.cost;
    final entry = _CacheEntry(code, tokens);
    _cache[key] = entry;
    _cacheCost += entry.cost;
    while (_cache.length > cacheSize || _cacheCost > cacheBudget) {
      if (_cache.length <= 1) break;
      _cacheCost -= _cache.remove(_cache.keys.first)!.cost;
    }
    return tokens;
  }

  static String _keyOf(String language, String code) =>
      '${language.trim().toLowerCase()}\u0000${code.hashCode}';

  /// Отчёт о сбое без кода и без текста исходного исключения: оно может
  /// содержать фрагмент кода (§12, §16 `AGENTS.md`).
  static void _report(String language, Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(
          'Code highlighting failed for language "${language.trim()}": '
          '${error.runtimeType}',
        ),
        stack: stack,
        library: 'codelab_ui',
        context: ErrorDescription('while highlighting a code block'),
      ),
    );
  }
}

class _CacheEntry {
  const _CacheEntry(this.code, this.tokens);

  final String code;
  final List<CodeLabCodeToken> tokens;

  /// Условная стоимость: code units кода плюс вес токенов.
  int get cost =>
      code.length + tokens.length * CodeLabCodeHighlighter.tokenWeight;
}

// ---- Движок val_highlight (вызывается и в UI isolate, и в фоновом) ----

LanguageRegistry? _registry;

LanguageRegistry get _languages => _registry ??= LanguageRegistry(allLanguages);

/// Грамматика языка или `null`: неизвестный язык, пустая строка, а также
/// простой текст и общий запасной разбор (`plaintext`, `generic`) — они не
/// подсвечиваются (D11).
Grammar? _supportedGrammar(String language) {
  final name = language.trim();
  if (name.isEmpty) return null;
  final grammar = _languages.lookup(name);
  if (grammar == null) return null;
  if (grammar.name == 'plaintext' || grammar.name == 'generic') return null;
  return grammar;
}

/// Токенизация движком `val_highlight` в простые токены.
///
/// Почему открыта: это точка входа и для UI isolate, и для фонового isolate —
/// чистая функция от `(язык, код)`.
///
/// Область токена — вложенный путь (`string > interpolation`); берётся
/// ближайшая к токену область, которая сопоставлена классу (внутренняя
/// важнее внешней). Соседние токены одного класса сливаются.
List<CodeLabCodeToken> tokenizeWithEngine(String language, String code) {
  final grammar = _supportedGrammar(language);
  if (grammar == null) return const [];
  final result = const Highlighter().highlight(code, language: grammar);
  final classOfStack = <int, CodeLabTokenClass?>{};
  final tokens = <CodeLabCodeToken>[];
  for (var i = 0; i < result.tokenCount; i++) {
    final stack = result.tokenStack(i);
    final tokenClass = classOfStack.putIfAbsent(
      stack,
      () => _classOfScopes(result.scopes.scopesOf(stack)),
    );
    if (tokenClass == null) continue;
    // Граница между половинами суррогатной пары сдвигается за пару: иначе
    // `Text` получил бы одинокий суррогат и упал при отрисовке.
    final start = snapToCodePoint(code, result.tokenStart(i));
    final end = snapToCodePoint(code, result.tokenEnd(i));
    if (end <= start) continue;
    if (tokens.isNotEmpty &&
        tokens.last.tokenClass == tokenClass &&
        tokens.last.end == start) {
      final last = tokens.removeLast();
      tokens.add(CodeLabCodeToken(last.start, end, tokenClass));
    } else {
      tokens.add(CodeLabCodeToken(start, end, tokenClass));
    }
  }
  return tokens;
}

/// Сопоставление областей `val_highlight` классам палитры (D4). Внутренняя
/// область важнее внешней; незамеченные (`punctuation`, `heading`, `link`,
/// `invalid`…) остаются обычным текстом.
CodeLabTokenClass? _classOfScopes(List<String> scopes) {
  for (var i = scopes.length - 1; i >= 0; i--) {
    final name = scopes[i];
    final root = name.contains('.')
        ? name.substring(0, name.indexOf('.'))
        : name;
    final mapped = switch (root) {
      'comment' => CodeLabTokenClass.comment,
      'string' || 'regexp' => CodeLabTokenClass.string,
      'number' => CodeLabTokenClass.number,
      'keyword' || 'literal' => CodeLabTokenClass.keyword,
      'type' => CodeLabTokenClass.type,
      'function' => CodeLabTokenClass.function,
      'variable' || 'property' => CodeLabTokenClass.variable,
      'operator' => CodeLabTokenClass.operator,
      'attribute' || 'tag' || 'meta' => CodeLabTokenClass.attribute,
      _ => null,
    };
    if (mapped != null) return mapped;
  }
  return null;
}

/// Граница [offset] в [code], не попадающая внутрь суррогатной пары: если
/// смещение стоит между старшей и младшей половиной, оно сдвигается за пару.
int snapToCodePoint(String code, int offset) {
  if (offset <= 0 || offset >= code.length) return offset;
  final before = code.codeUnitAt(offset - 1);
  final at = code.codeUnitAt(offset);
  final splits =
      before >= 0xD800 && before <= 0xDBFF && at >= 0xDC00 && at <= 0xDFFF;
  return splits ? offset + 1 : offset;
}

/// Фон: отдельный isolate, которому передаются только `(язык, код)`, а
/// возвращаются простые токены (A4). Его можно остановить (в отличие от
/// `compute`): по истечении [timeout] isolate убивается, чтобы зависшая
/// токенизация не копила работающие isolate (ревью итерации 3).
///
/// Один `RawReceivePort` принимает результат, ошибку и выход isolate, поэтому
/// исход не зависит от порядка доставки сообщений из двух портов: результат —
/// `_IsolateResult`, любое другое сообщение (ошибка или `null` при выходе без
/// результата) — сбой.
Future<List<CodeLabCodeToken>> _tokenizeInIsolate(
  String language,
  String code,
  Duration timeout,
) async {
  final done = Completer<List<CodeLabCodeToken>>();
  final port = RawReceivePort();
  port.handler = (Object? message) {
    if (done.isCompleted) return;
    if (message is _IsolateResult) {
      done.complete(message.tokens);
    } else {
      // Сообщение об ошибке isolate может содержать фрагмент кода — наружу
      // идёт только факт сбоя.
      done.completeError(StateError('isolate failed'));
    }
  };
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn<(SendPort, String, String)>(
      _isolateMain,
      (port.sendPort, language, code),
      onError: port.sendPort,
      onExit: port.sendPort,
      errorsAreFatal: true,
    );
    return await done.future.timeout(timeout);
  } finally {
    isolate?.kill(priority: Isolate.immediate);
    port.close();
  }
}

/// Успешный ответ фонового isolate.
class _IsolateResult {
  const _IsolateResult(this.tokens);

  final List<CodeLabCodeToken> tokens;
}

void _isolateMain((SendPort, String, String) request) {
  request.$1.send(_IsolateResult(tokenizeWithEngine(request.$2, request.$3)));
}
