/// Чтение расширений агента с диска для страницы навыков (design.md change
/// `add-app-skills-page`, D3, D4, D7).
library;

import 'dart:async';
import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart'
    show loadProjectExtensions, toHostPath, userHomeOf;
import 'package:meta/meta.dart';

import '../config/agent_config_store.dart';
import '../extensions/agent_extensions_of.dart';
import '../extensions/agent_extensions_view.dart';
import '../extensions/skills_list_edit.dart';
import 'extensions_host_paths.dart';

/// Предел просмотра записей каталога-кандидата по умолчанию: каталог другого
/// агента не должен вешать страницу (как предел записей корня загрузчика
/// навыков).
const _defaultEntryLimit = 1000;

/// Предел времени сбора кандидатов по умолчанию: как таймаут фаз
/// `loadProjectExtensions`.
const _defaultConsentTimeout = Duration(seconds: 5);

/// Сканер каталога-кандидата: число подкаталогов с `SKILL.md` не более
/// [entryLimit] записей, `null` — каталога нет. Шов тестов: настоящий сканер
/// ходит по диску, а зависший том в тесте не воспроизвести.
typedef ConsentDirScanner = Future<int?> Function(String path, int entryLimit);

/// Читает файлы проекта и навыки папки снимка и строит вид страницы.
///
/// Почему в `io.dart`: нужны файлы, а чтение и правила корней, доверия и
/// таймаутов — одна функция `codelab_agent_io`, общая с `config check`, так
/// что вид совпадает с тем, что прочитает сессия агента (D3). Тела файлов
/// остаются внутри: наружу уходит только вид (SETUP-25).
///
/// Как использовать: [snapshot] — свежий снимок конфигурации папки с читаемым
/// конфигом (`loaded.config != null`, иначе `StateError`); [codelabHome] —
/// `$CODELAB_HOME` профиля (важнее переменной окружения, как у
/// `FileAgentConfigStore`); [environment] — окружение агента (`HOME`).
/// Исход фаз (таймаут, исключение) — значения вида, а не исключения (D7).
///
/// Ошибки: исключение построителя `agentExtensionsOf` (разбор навыков и
/// шаблонов ядром) не перехватывается и уходит вызывающему. Вызывающий (Cubit
/// страницы) логирует только `runtimeType` и показывает «не прочитано»: текст
/// исключения может содержать фрагменты файлов.
///
/// Сбор кандидатов согласия ограничен [consentTimeout] (общий для всех
/// каталогов, параллельно) и [consentEntryLimit] записей на каталог:
/// каталог, не ответивший в срок, остаётся кандидатом без числа
/// (`skillDirs == null`), сканер, бросивший исключение, — выпадает из списка.
/// [scanConsentDir] — шов тестов.
Future<AgentExtensionsView> readAgentExtensions(
  AgentConfigSnapshot snapshot, {
  required String? codelabHome,
  required Map<String, String> environment,
  Duration consentTimeout = _defaultConsentTimeout,
  int consentEntryLimit = _defaultEntryLimit,
  @visibleForTesting ConsentDirScanner? scanConsentDir,
}) async {
  final config = snapshot.loaded.config;
  if (config == null) {
    throw StateError('The config snapshot has no loaded configuration');
  }
  final env = {...environment, 'CODELAB_HOME': ?codelabHome};
  final extensions = await loadProjectExtensions(
    cwd: snapshot.cwd,
    config: config,
    environment: env,
  );
  final userHome = userHomeOf(env);
  final view = agentExtensionsOf(
    snapshot,
    extensions,
    userHome: userHome,
    consents: await _consentCandidates(
      snapshot: snapshot,
      cwd: extensions.cwd,
      trusted: extensions.trusted,
      userHome: userHome,
      granted: config.skills.extraRoots,
      timeout: consentTimeout,
      entryLimit: consentEntryLimit,
      scan: scanConsentDir ?? _scanDir,
    ),
  );
  // Один проход перевода путей вида в форму хоста (D8): построитель отдаёт
  // форму ядра, клиент открывает каталоги платформой.
  return extensionsInHostForm(view, windows: Platform.isWindows);
}

/// Каталоги навыков других агентов, на чтение которых можно согласиться
/// (решение Q3): `.claude/skills` в папке и `~/.claude/skills`; только
/// существующие. Порядок: проект, затем домашний.
Future<List<SkillConsentView>> _consentCandidates({
  required AgentConfigSnapshot snapshot,
  required String cwd,
  required bool trusted,
  required String? userHome,
  required List<String> granted,
  required Duration timeout,
  required int entryLimit,
  required ConsentDirScanner scan,
}) async {
  final candidates = [
    ('.claude/skills', '$cwd/.claude/skills', trusted),
    if (userHome != null && userHome.isNotEmpty)
      ('~/.claude/skills', '$userHome/.claude/skills', true),
  ];
  // Одна общая граница времени: каталоги сканируются параллельно.
  final results = await Future.wait([
    for (final (_, path, _) in candidates)
      _scanLimited(scan, path, entryLimit, timeout),
  ]);
  final views = <SkillConsentView>[];
  for (final (i, (entry, path, readable)) in candidates.indexed) {
    final result = results[i];
    if (result.failed || (!result.timedOut && result.count == null)) {
      continue;
    }
    views.add(
      SkillConsentView(
        entry: entry,
        path: path,
        skillDirs: result.count,
        // Относительный элемент недоверенного проекта загрузчик не читает.
        granted: granted.contains(entry) && readable,
        // Одно правило с записью (D5): переключатель согласия — результат
        // `skillsListEdit` для «выдать», если согласия нет, и «отозвать», если
        // оно действует. Запись в `extra_roots` — только по этому правилу.
        toggle: SkillToggle.of(
          skillsListEdit(
            snapshot,
            'skills.extra_roots',
            entry,
            present: !(granted.contains(entry) && readable),
          ),
        ),
      ),
    );
  }
  return views;
}

typedef _ScanResult = ({int? count, bool timedOut, bool failed});

Future<_ScanResult> _scanLimited(
  ConsentDirScanner scan,
  String path,
  int entryLimit,
  Duration timeout,
) async {
  try {
    final count = await scan(path, entryLimit).timeout(timeout);
    return (count: count, timedOut: false, failed: false);
  } on TimeoutException {
    return (count: null, timedOut: true, failed: false);
  } on Object {
    // Каталог не прочитан (права, сбой тома): кандидата нет, страница жива.
    return (count: null, timedOut: false, failed: true);
  }
}

/// Настоящий сканер: пути — в форме хоста (как у загрузчика, §11), ссылки не
/// раскрываются (`followLinks: false`: подкаталог-ссылка не считается и не
/// открывается), не больше [entryLimit] записей.
Future<int?> _scanDir(String path, int entryLimit) async {
  final dir = Directory(toHostPath(path, windows: Platform.isWindows));
  if (!await dir.exists()) {
    return null;
  }
  var count = 0;
  var seen = 0;
  await for (final item in dir.list(followLinks: false)) {
    if (++seen > entryLimit) {
      break;
    }
    if (item is Directory && await File('${item.path}/SKILL.md').exists()) {
      count++;
    }
  }
  return count;
}
