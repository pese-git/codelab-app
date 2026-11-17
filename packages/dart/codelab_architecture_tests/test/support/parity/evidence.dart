/// Доказательства строк матрицы целей и проверка их существования.
///
/// Почему: строка Must матрицы `agent-parity-goals.md` считается закрытой, только
/// когда названные в ней фикстуры, e2e-сценарии и тесты реально есть и
/// проходят (`switch-default-agent-to-dart`, D3–D4). Переименование фикстуры
/// без правки матрицы должно ловиться на каждом pull request, а не ночью.
///
/// Для чего: извлекает доказательства из ячейки «Критерий приёмки» и отвечает
/// на вопрос «существует ли доказательство» без отчётов прогонов. Те же
/// сведения (где лежит тест, какие фикстуры с ролью `agent`) использует
/// `verdict.dart` при расчёте статуса.
///
/// Как использовать: `extractEvidence(ячейка)` даёт список доказательств;
/// `checkEvidenceExists(...)` сверяет их с деревом репозитория: любое
/// отсутствующее доказательство роняет проверку (D4; список известных пробелов
/// убран, когда change `add-agent-builtin-slash-commands` закрыл K-02 и R-08).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'matrix_parser.dart';

/// Вид доказательства строки матрицы (D3).
enum EvidenceKind {
  /// `acp/<id>` — golden-фикстура корпуса.
  acp,

  /// `cli/<id>` — e2e-сценарий `codelab_cli`.
  cli,

  /// `core/<id>` — тест ядра агента.
  core,

  /// `app:<файл>` — интеграционный тест десктопа.
  app,

  /// Путь файла теста (`packages/…_test.dart`, `apps/…_test.dart`).
  testFile,

  /// Шаблон `acp/*` — все фикстуры с ролью `agent`.
  allAcp,

  /// Шаблон `app:*` — все файлы `integration_test/*_test.dart`.
  allApp,
}

/// Доказательство, извлечённое из ячейки «Критерий приёмки».
class Evidence {
  const Evidence(this.kind, this.label);

  /// Вид доказательства.
  final EvidenceKind kind;

  /// Текст в том виде, как он печатается в сообщениях: `acp/x`, `app:f_test.dart`,
  /// путь файла, `acp/*`.
  final String label;

  /// Идентификатор без префикса вида: `x` для `acp/x`, `f_test.dart` для
  /// `app:f_test.dart`, путь для файла теста.
  String get id => switch (kind) {
    EvidenceKind.acp ||
    EvidenceKind.cli ||
    EvidenceKind.core => label.substring(label.indexOf('/') + 1),
    EvidenceKind.app => label.substring('app:'.length),
    _ => label,
  };

  @override
  String toString() => label;
}

/// Итог проверки существования.
class ExistenceReport {
  const ExistenceReport({required this.failures});

  /// Строки, роняющие тест: `<строка> <доказательство> missing`.
  final List<String> failures;
}

/// Каталог золотых фикстур ACP от корня репозитория.
const acpFixturesDir = 'packages/dart/codelab_acp_testing/fixtures/acp';

/// Каталог интеграционных тестов десктопа.
const appTestsDir = 'apps/codelab_desktop/integration_test';

/// Каталоги тестов, где ищется `cli/<id>` (D3).
const cliTestDirs = ['apps/codelab_cli/test/e2e'];

/// Каталоги тестов, где ищется `core/<id>` (D3).
const coreTestDirs = [
  'packages/dart/codelab_agent_core/test',
  'packages/dart/codelab_agent_io/test',
  'packages/dart/codelab_agent_acp/test',
  'packages/dart/codelab_agent_mcp/test',
  'packages/dart/codelab_embedded/test',
  'apps/codelab_agent/test',
];

final _fragment = RegExp(r'`([^`]+)`');
final _idChars = r'[A-Za-z0-9][A-Za-z0-9_.\-]*';

/// Извлекает доказательства из ячейки «Критерий приёмки» (D3); повтор — один раз.
///
/// Берутся только фрагменты в обратных кавычках, которые целиком совпадают с
/// одним из видов [EvidenceKind]; всё остальное (флаги, имена типов, пометки
/// «закрыто change …») доказательством не является.
List<Evidence> extractEvidence(String criterion) {
  final seen = <String>{};
  final result = <Evidence>[];
  for (final match in _fragment.allMatches(criterion)) {
    final text = match[1]!.trim();
    final kind = _classify(text);
    if (kind == null || !seen.add(text)) continue;
    result.add(Evidence(kind, text));
  }
  return result;
}

EvidenceKind? _classify(String text) {
  if (text == 'acp/*') return EvidenceKind.allAcp;
  if (text == 'app:*') return EvidenceKind.allApp;
  if (RegExp('^acp/$_idChars\$').hasMatch(text)) return EvidenceKind.acp;
  if (RegExp('^cli/$_idChars\$').hasMatch(text)) return EvidenceKind.cli;
  if (RegExp('^core/$_idChars\$').hasMatch(text)) return EvidenceKind.core;
  if (RegExp(r'^app:[\w.\-]+_test\.dart$').hasMatch(text)) {
    return EvidenceKind.app;
  }
  if (RegExp(r'^(packages|apps)/\S+_test\.dart$').hasMatch(text)) {
    return EvidenceKind.testFile;
  }
  return null;
}

/// Тест принадлежит [id], если его полное имя начинается с [id], а за id идёт
/// конец имени, `:` или пробел (D3, D5).
bool nameBelongsToId(String testName, String id) {
  if (!testName.startsWith(id)) return false;
  if (testName.length == id.length) return true;
  final next = testName[id.length];
  return next == ':' || next == ' ';
}

/// Идентификаторы фикстур корпуса (имена файлов без `.json`), у которых в
/// `roles` есть `agent`; служебные файлы с `_` пропускаются. Отсортированы.
List<String> agentFixtureIds(String repoRoot) {
  final dir = Directory(p.join(repoRoot, acpFixturesDir));
  if (!dir.existsSync()) return const [];
  final ids = <String>[];
  for (final entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final name = p.basenameWithoutExtension(entity.path);
    if (name.startsWith('_')) continue;
    if (fixtureRoles(entity).contains('agent')) ids.add(name);
  }
  return ids..sort();
}

/// Роли фикстуры; отсутствие поля `roles` означает обе роли.
///
/// Почему: так читает фикстуры сам корпус (`codelab_acp_testing`,
/// `fixture.dart`, разбор `roles`: `null` → `FixtureRole.values`), и в корпусе
/// большинство фикстур поля не имеют. Сторож не зависит от
/// `codelab_acp_testing` (новая зависимость пакета-сторожа не нужна для одного
/// правила), поэтому правило продублировано здесь; расхождение ловит тест
/// `edge_cases_test.dart` и реальный корпус в `parity_evidence_test.dart`.
///
/// Файл, который не разобрать, даёт пустой список: корректность фикстур
/// проверяет сам корпус.
List<String> fixtureRoles(File fixture) {
  try {
    final json = jsonDecode(fixture.readAsStringSync());
    if (json is Map) {
      final roles = json['roles'];
      if (roles == null) return const ['agent', 'client'];
      if (roles is List) return [for (final r in roles) r.toString()];
    }
  } on FormatException {
    // Не JSON — ролей нет.
  }
  return const [];
}

/// Файлы интеграционных тестов app: имена `*_test.dart`, отсортированы.
List<String> appTestFiles(String repoRoot) {
  final dir = Directory(p.join(repoRoot, appTestsDir));
  if (!dir.existsSync()) return const [];
  return [
    for (final entity in dir.listSync())
      if (entity is File && entity.path.endsWith('_test.dart'))
        p.basename(entity.path),
  ]..sort();
}

/// Первые строковые литералы вызовов `test(` и `group(` в исходнике Dart.
///
/// Почему: упоминание id в комментарии тестом не считается, а в отчёте
/// `dart test` его не найти (D3). Поэтому нужен разбор, который знает про
/// комментарии и строки, а не `grep`.
///
/// Соседние литералы (`'cli/x: ' 'tail'`) склеиваются. Интерполяция не
/// вычисляется: имя, собранное из переменной, существование не найдёт — это
/// сознательное правило «первый литерал — id» (D3, «Risks»).
///
/// Вложенные вызовы не возвращаются (D3, уточнение 2026-11-10): полное имя
/// теста в отчёте начинается с имени внешней группы, поэтому `test('core/x')`
/// внутри `group('другое')` в отчёте `core/x` не найти. Возвращаются имена
/// вызовов вне любого `group(`: на верхнем уровне `main`, в цикле `for`, в
/// локальной функции. Вложенность считается по скобкам вызова `group(`.
///
/// Ограничения разбора: это лексер, а не парсер Dart. Интерполяция
/// `${…}` пропускается по балансу фигурных скобок вместе с вложенными
/// литералами (`'${f('x')}'`), но экзотика (комментарий с кавычкой внутри
/// интерполяции, многострочные литералы в ней) может сбить границы литерала
/// и баланс скобок. Чтобы такая ошибка не давала молча неверный результат,
/// при ненулевом балансе скобок в конце файла (или лишней `)`) бросается
/// [FormatException] с именем [file] — файл надо упростить, а не доверять
/// списку имён.
List<String> testNameLiterals(String source, {String file = '<source>'}) {
  final names = <String>[];
  final n = source.length;
  var i = 0;
  // Глубина круглых скобок и глубины, на которых открыты вызовы `group(`.
  var depth = 0;
  final groups = <int>[];

  bool isIdentChar(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5a) ||
      (c >= 0x61 && c <= 0x7a) ||
      c == 0x5f ||
      c == 0x24;

  // Читает строковый литерал, начинающийся в позиции [start]; возвращает
  // содержимое и позицию за литералом или `null`, если литерала нет.
  (String, int)? readString(int start) {
    var j = start;
    var raw = false;
    if (j < n &&
        source[j] == 'r' &&
        j + 1 < n &&
        '\'"'.contains(source[j + 1])) {
      raw = true;
      j++;
    }
    if (j >= n || !'\'"'.contains(source[j])) return null;
    final quote = source[j];
    final triple = source.startsWith(quote * 3, j);
    final open = triple ? 3 : 1;
    j += open;
    final content = StringBuffer();
    while (j < n) {
      final c = source[j];
      if (!raw && c == r'\' && j + 1 < n) {
        content.write(source[j + 1]);
        j += 2;
        continue;
      }
      // Интерполяция `${…}` может содержать свои строки с кавычками той же
      // породы (`'a ${f({'k': 1})}'`): её содержимое пропускается целиком по
      // балансу фигурных скобок, с рекурсивным чтением вложенных литералов.
      if (!raw && c == r'$' && j + 1 < n && source[j + 1] == '{') {
        var braces = 0;
        final from = j;
        while (j < n) {
          final d = source[j];
          if ('\'"'.contains(d)) {
            j = readString(j)?.$2 ?? j + 1;
            continue;
          }
          if (d == '{') braces++;
          if (d == '}') {
            braces--;
            if (braces == 0) {
              j++;
              break;
            }
          }
          j++;
        }
        content.write(source.substring(from, j));
        continue;
      }
      if (triple
          ? source.startsWith(quote * 3, j)
          : (c == quote || c == '\n')) {
        return (content.toString(), j + (c == quote ? open : 0));
      }
      content.write(c);
      j++;
    }
    return (content.toString(), j);
  }

  int skipSpace(int from) {
    var j = from;
    while (j < n) {
      if (' \t\r\n'.contains(source[j])) {
        j++;
      } else if (source.startsWith('//', j)) {
        while (j < n && source[j] != '\n') {
          j++;
        }
      } else if (source.startsWith('/*', j)) {
        final close = source.indexOf('*/', j + 2);
        j = close < 0 ? n : close + 2;
      } else {
        break;
      }
    }
    return j;
  }

  while (i < n) {
    final c = source[i];
    if (source.startsWith('//', i)) {
      while (i < n && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (source.startsWith('/*', i)) {
      final close = source.indexOf('*/', i + 2);
      i = close < 0 ? n : close + 2;
      continue;
    }
    if ('\'"'.contains(c) ||
        (c == 'r' &&
            i + 1 < n &&
            '\'"'.contains(source[i + 1]) &&
            (i == 0 || !isIdentChar(source.codeUnitAt(i - 1))))) {
      i = readString(i)?.$2 ?? i + 1;
      continue;
    }
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth < 0) {
        throw FormatException(
          'unbalanced parentheses in $file: extra ")" at offset $i',
        );
      }
      while (groups.isNotEmpty && groups.last > depth) {
        groups.removeLast();
      }
    }
    final word = RegExp(r'(test|group)\b').matchAsPrefix(source, i);
    if (word != null && (i == 0 || !isIdentChar(source.codeUnitAt(i - 1)))) {
      var j = skipSpace(word.end);
      if (j < n && source[j] == '(') {
        final nested = groups.isNotEmpty;
        depth++;
        if (word[1] == 'group') groups.add(depth);
        i = j + 1;
        j = skipSpace(j + 1);
        final first = readString(j);
        if (first != null) {
          final name = StringBuffer(first.$1);
          j = first.$2;
          // Соседние литералы склеиваются в одно имя.
          while (true) {
            final k = skipSpace(j);
            final next = readString(k);
            if (next == null) break;
            name.write(next.$1);
            j = next.$2;
          }
          if (!nested) names.add(name.toString());
          i = j;
        }
        continue;
      }
    }
    i++;
  }
  // Открытый `group(` без `)` оставляет глубину больше нуля, поэтому
  // отдельной проверки стека групп не нужно.
  if (depth != 0) {
    throw FormatException(
      'unbalanced parentheses in $file: depth $depth at the end of the file; '
      'the lexer of test names (evidence.dart) cannot read it',
    );
  }
  return names;
}

/// Индекс имён тестов репозитория: какие файлы `*_test.dart` содержат тест или
/// группу с нужным id (D3).
///
/// Почему: расчёт существования и статуса обращается к одним и тем же файлам
/// десятки раз; индекс читает каждый файл один раз.
class TestNameIndex {
  TestNameIndex(this.repoRoot);

  /// Корень репозитория.
  final String repoRoot;

  final _byDir = <String, Map<String, List<String>>>{};

  Map<String, List<String>> _scan(String dir) => _byDir.putIfAbsent(dir, () {
    final root = Directory(p.join(repoRoot, dir));
    if (!root.existsSync()) return const {};
    final files = <String, List<String>>{};
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
      final relative = p.relative(entity.path, from: repoRoot);
      files[relative] = testNameLiterals(
        entity.readAsStringSync(),
        file: relative,
      );
    }
    return files;
  });

  /// Файлы (пути от корня репозитория), где первый литерал `test(` или
  /// `group(` принадлежит [id]; для видов, кроме `cli` и `core`, пусто.
  List<String> filesWithId(EvidenceKind kind, String id) {
    final dirs = switch (kind) {
      EvidenceKind.cli => cliTestDirs,
      EvidenceKind.core => coreTestDirs,
      _ => const <String>[],
    };
    final prefix = kind == EvidenceKind.cli ? 'cli/' : 'core/';
    final found = <String>[];
    for (final dir in dirs) {
      for (final MapEntry(key: file, value: names) in _scan(dir).entries) {
        if (names.any((name) => nameBelongsToId(name, '$prefix$id'))) {
          found.add(file);
        }
      }
    }
    return found..sort();
  }
}

/// Существует ли доказательство [evidence] в дереве [repoRoot] (D3).
bool evidenceExists(
  Evidence evidence,
  String repoRoot, {
  TestNameIndex? index,
}) {
  bool file(String relative) => File(p.join(repoRoot, relative)).existsSync();
  return switch (evidence.kind) {
    EvidenceKind.acp => file('$acpFixturesDir/${evidence.id}.json'),
    EvidenceKind.app => file('$appTestsDir/${evidence.id}'),
    EvidenceKind.testFile => file(evidence.id),
    EvidenceKind.allAcp => agentFixtureIds(repoRoot).isNotEmpty,
    EvidenceKind.allApp => appTestFiles(repoRoot).isNotEmpty,
    EvidenceKind.cli || EvidenceKind.core =>
      (index ?? TestNameIndex(repoRoot))
          .filesWithId(evidence.kind, evidence.id)
          .isNotEmpty,
  };
}

/// Проверяет существование доказательств [rows] в дереве [repoRoot] (D3–D4).
///
/// Строка без единого доказательства — `<строка> (no evidence) missing`,
/// отсутствующее доказательство — `<строка> <доказательство> missing`.
/// Исключений нет: пробел существования не допускается (храповик `knownGaps`
/// удалён вместе с последними записями K-02 и R-08).
ExistenceReport checkEvidenceExists({
  required List<MatrixRow> rows,
  required String repoRoot,
}) {
  final index = TestNameIndex(repoRoot);
  final failures = <String>[];

  for (final row in rows) {
    final evidence = extractEvidence(row.criterion);
    if (evidence.isEmpty) {
      failures.add('${row.id} (no evidence) missing');
      continue;
    }
    for (final item in evidence) {
      if (!evidenceExists(item, repoRoot, index: index)) {
        failures.add('${row.id} ${item.label} missing');
      }
    }
  }
  return ExistenceReport(failures: failures);
}
