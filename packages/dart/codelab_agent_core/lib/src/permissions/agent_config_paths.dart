/// Пути конфигурации агента, которые хост передаёт политике разрешений
/// (PERM-11, `agent-core-architecture` §7.6.1; design.md change
/// `add-config-writer-and-reload`, D8, «Пути конфигурации агента для
/// PERM-11»).
///
/// Почему: агент перечитывает свою конфигурацию на лету (D7), поэтому то, что
/// он перечитывает, модель не правит без человека. Список §7.6.1 знает только
/// проектные `.codelab/**` относительно корня сессии; глобальный
/// `$CODELAB_HOME/config.yaml`, файл `--config` и конфиг корня запуска при
/// сессии с другим `cwd` ядро само узнать не может — у него нет ни
/// окружения, ни файловой системы (PKG-1).
///
/// Для чего: [AgentConfigPaths] — данные запуска от хоста; [AgentConfigScope]
/// — их пересчитанная при каждой проверке форма, по которой политика
/// сравнивает цели `write`/`edit` и пути команды `exec`.
///
/// Как использовать: хост строит [AgentConfigPaths] одной функцией
/// (`agentConfigPathsFor` пакета `codelab_agent_io`) и кладёт в
/// `AgentCoreServices.agentConfigPaths`; политику с этим значением создаёт
/// рантайм. Сопоставление живёт здесь, а не в `critical_patterns.dart`:
/// шаблоны §7.6 остаются чистой функцией от строки команды.
library;

import '../env/execution_env.dart';
import '../util/posix_path.dart';
import '../util/result.dart';

/// Пути конфигурации агента от хоста (PERM-11, D8).
///
/// Почему отдельный объект, а не поле `HostProfile`: пути — данные запуска
/// конкретного процесса, профиль описывает возможности платформы (D8).
///
/// Для чего: [paths] — абсолютные канонические пути (`~` раскрыт, ссылки
/// раскрыты по самому глубокому существующему предку, в том числе для ещё
/// не созданных файлов); путь защищает и своё поддерево, поэтому каталоги
/// `agents` и `prompts` перечисляются самим каталогом. [expansions] — значения
/// `HOME` и `CODELAB_HOME` окружения хоста для раскрытия `~`, `$HOME`,
/// `${HOME}`, `$CODELAB_HOME`, `${CODELAB_HOME}` в командах `exec` (у ядра
/// своего окружения нет); [caseInsensitive] — файловая система без учёта
/// регистра (macOS, Windows), его определяет хост.
///
/// Как использовать: значение неизменяемо; пересчёт канонической формы при
/// каждой проверке делает [AgentConfigScope.resolve].
final class AgentConfigPaths {
  /// Создаётся хостом; в тестах политики — напрямую.
  AgentConfigPaths({
    required Iterable<String> paths,
    Iterable<String> skillDirs = const [],
    Map<String, String> expansions = const {},
    this.caseInsensitive = false,
  }) : paths = List.unmodifiable(paths),
       skillDirs = List.unmodifiable(skillDirs),
       expansions = Map.unmodifiable(expansions);

  /// Копия с путями и каталогами навыков сессии (design.md change
  /// `add-agent-skills`, D9, D17, решение Q27).
  ///
  /// Почему: корни навыков, зависящие от `cwd` (уровни выше `cwd`,
  /// относительные `skills.extra_roots`), и каталоги загруженных навыков
  /// известны только при открытии сессии, а поле хоста действует на весь
  /// процесс и их не содержит.
  ///
  /// Как использовать: рантайм вызывает при открытии сессии на значении
  /// хоста; элементы исходного значения идут первыми, новые добавляются без
  /// повторов; [expansions] и [caseInsensitive] остаются своими; исходное
  /// значение не меняется.
  AgentConfigPaths withSession({
    Iterable<String> paths = const [],
    Iterable<String> skillDirs = const [],
  }) => AgentConfigPaths(
    paths: {...this.paths, ...paths},
    skillDirs: {...this.skillDirs, ...skillDirs},
    expansions: expansions,
    caseInsensitive: caseInsensitive,
  );

  /// Канонические каталоги загруженных навыков сессии.
  ///
  /// Только для исключений E1–E3 (запуск скрипта навыка, D9): сами по себе
  /// каталоги ничего не защищают — защиту даёт [paths].
  final List<String> skillDirs;

  /// Абсолютные канонические пути (POSIX-вид ядра).
  final List<String> paths;

  /// `HOME` и `CODELAB_HOME` окружения хоста.
  final Map<String, String> expansions;

  /// Сравнивать пути без учёта регистра.
  final bool caseInsensitive;

  @override
  String toString() => 'AgentConfigPaths(${paths.length} paths)';
}

final _variable = RegExp(
  r'\$(?:\{(HOME|CODELAB_HOME)\}|(HOME|CODELAB_HOME)(?![A-Za-z0-9_]))',
);

/// Защищаемые пути на момент одной проверки (PERM-11, D8).
///
/// Почему не кэш на сессию: каталог-предок могли подменить ссылкой после
/// старта (`ln -s sub .codelab`), и тогда `write sub/config.yaml` правит
/// защищаемый `.codelab/config.yaml`. Каноническая форма защищаемых путей
/// поэтому пересчитывается на каждой проверке (§7.6.1); IO — через
/// [PathResolver] env хоста, которым `BoundedEnv` канонизирует цель для
/// containment.
///
/// Для чего: [covers] — цель совпадает с защищаемым путём или лежит внутри
/// него; [isAncestor] — цель совпадает с каталогом-предком защищаемого пути
/// (его нельзя создать, переименовать, удалить или подменить ссылкой).
/// Сравнение — по сегментам и без учёта регистра при
/// [AgentConfigPaths.caseInsensitive].
///
/// Как использовать: политика получает область через [resolve], прогоняет
/// сравнения (они запоминают проверенные пути), затем вызывает
/// [canonicalizeSeen] и сравнивает ещё раз — теперь с каноническими формами
/// целей: ссылка на защищаемый файл из другого места не выводит цель из-под
/// защиты. Объект не потокобезопасен и живёт в одном `decide`.
final class AgentConfigScope {
  AgentConfigScope._(this._config, this._forms, this._ancestors, this._parents)
    : _skillDirs = [
        for (final dir in _config.skillDirs)
          if (dir.startsWith('/')) ?normalizePath('/', dir),
      ];

  /// Пересчитывает каноническую форму защищаемых путей [config].
  ///
  /// Каждый путь даёт две формы — как передал хост и пересчитанную через
  /// [resolver]; без [resolver] (env без `PathResolver`) остаётся первая.
  /// Предки — все родительские каталоги всех форм, кроме корня.
  static Future<AgentConfigScope> resolve(
    AgentConfigPaths config,
    PathResolver? resolver,
  ) async {
    final forms = <String>{};
    for (final raw in config.paths) {
      final abs = raw.startsWith('/') ? normalizePath('/', raw) : null;
      if (abs == null) {
        continue;
      }
      forms.add(abs);
      forms.add(await canonicalForm(resolver, abs));
    }
    final ci = config.caseInsensitive;
    String key(String path) => ci ? path.toLowerCase() : path;
    return AgentConfigScope._(
      config,
      {for (final f in forms) key(f)},
      {
        // Все предки каждой формы, кроме корня (решение пользователя
        // 2026-11-03): `mv ~/proj x` уносит `~/proj/.codelab/config.yaml`.
        for (final f in forms)
          for (var a = parentOf(f); a != '/'; a = parentOf(a)) key(a),
      },
      {
        // Непосредственные родители: сам каталог конфигурации (`~/.codelab`).
        for (final f in forms)
          if (parentOf(f) != '/') key(parentOf(f)),
      },
    );
  }

  /// Каноническая форма [abs]: ссылки раскрыты по самому глубокому
  /// существующему предку, остаток пути добавлен как есть — так же, как
  /// `BoundedEnv` канонизирует цель, которой ещё нет (§4.4).
  // Известная граница: висячая ссылка (`ln -s sub .codelab` при отсутствующем
  // `sub`) не раскрывается — у `PathResolver` нет `readlink`, а `realpath`
  // такую ссылку не видит; порт не меняем (решение пользователя 2026-11-03,
  // описание границы допишет архитектор в design.md change
  // `add-config-writer-and-reload`).
  static Future<String> canonicalForm(
    PathResolver? resolver,
    String abs,
  ) async {
    if (resolver == null) {
      return abs;
    }
    var prefix = abs;
    final rest = <String>[];
    while (true) {
      if (await resolver.realpath(prefix) case Ok(:final value)) {
        final resolved = normalizePath('/', value);
        if (resolved == null) {
          return abs;
        }
        return rest.isEmpty
            ? resolved
            : normalizePath(resolved, rest.reversed.join('/')) ?? abs;
      }
      if (prefix == '/') {
        return abs;
      }
      rest.add(prefix.substring(prefix.lastIndexOf('/') + 1));
      prefix = parentOf(prefix);
    }
  }

  final AgentConfigPaths _config;
  final Set<String> _forms;
  final Set<String> _ancestors;
  final Set<String> _parents;

  /// Проверенные пути: их канонические формы считает [canonicalizeSeen].
  final _seen = <String>{};
  final _canonical = <String, String>{};

  /// Проверенные пути, которые существуют (известно после [canonicalizeSeen]).
  final _existing = <String>{};

  /// Проверенные пути, чья каноническая форма — обычный файл (`stat` резолвера,
  /// если он `FileSystem`); без этого исключения E1/E3 не действуют (D17).
  final _regular = <String>{};

  /// Нормализованные каталоги загруженных навыков (E1–E3, D9).
  final List<String> _skillDirs;

  /// Значения `HOME` и `CODELAB_HOME` хоста.
  Map<String, String> get expansions => _config.expansions;

  String _key(String path) =>
      _config.caseInsensitive ? path.toLowerCase() : path;

  /// Раскрывает `~`, `$HOME`, `${HOME}`, `$CODELAB_HOME`, `${CODELAB_HOME}`
  /// значениями хоста; неизвестное остаётся как есть (цель с переменной не
  /// защищена: её значение неизвестно, §7.6).
  String expand(String raw) {
    var path = raw;
    final home = expansions['HOME'];
    if (home != null && (path == '~' || path.startsWith('~/'))) {
      path = '$home${path.substring(1)}';
    }
    return path.replaceAllMapped(
      _variable,
      (m) => expansions[m[1] ?? m[2]] ?? m[0]!,
    );
  }

  /// Запоминает [abs] для второй фазы и возвращает его каноническую форму,
  /// если она уже посчитана ([canonicalizeSeen]); в первой фазе — `null`.
  ///
  /// Для чего: исключения E1–E3 решаются по каноническому пути (ссылка наружу
  /// исключения не получает), а канонизация асинхронна, поэтому первый проход
  /// только собирает кандидатов, второй решает по кэшу (D17).
  String? canonicalOf(String abs) {
    _seen.add(abs);
    return _canonical[abs];
  }

  /// Каноническая форма [abs] — существующий обычный файл. До [canonicalizeSeen]
  /// и без `FileSystem` у резолвера — `false` (fail closed, D17).
  bool isRegularFile(String abs) => _regular.contains(abs);

  /// Каталог загруженного навыка, внутри которого лежит каноническая форма
  /// [canonical] (самый глубокий), или `null`. Сравнение — по сегментам и без
  /// учёта регистра при [caseInsensitive].
  String? skillDirOf(String canonical) {
    String? best;
    for (final dir in _skillDirs) {
      if (_inside(dir, canonical) &&
          (best == null || dir.length > best.length)) {
        best = dir;
      }
    }
    return best;
  }

  /// [path] лежит внутри [dir] (или совпадает) по правилам регистра хоста.
  bool _inside(String dir, String path) {
    final d = _key(dir);
    final p = _key(path);
    return d == '/' || p == d || p.startsWith('$d/');
  }

  /// [_inside] для вызывающих правил E1–E3.
  bool isInsideDir(String dir, String path) => _inside(dir, path);

  /// Цель [abs] — защищаемый путь или лежит внутри него.
  bool covers(String abs) {
    _seen.add(abs);
    final canonical = _canonical[abs];
    return _inForms(_key(abs)) ||
        canonical != null && _inForms(_key(canonical));
  }

  /// Цель [abs] — каталог-предок защищаемого пути.
  bool isAncestor(String abs) {
    _seen.add(abs);
    final canonical = _canonical[abs];
    return _ancestors.contains(_key(abs)) ||
        canonical != null && _ancestors.contains(_key(canonical));
  }

  /// Цель [abs] — предок, которого ещё нет: перенос или ссылка на неё
  /// создаёт каталог конфигурации. Если каталог есть, `mv x DIR` и `ln -s x DIR`
  /// кладут `x` внутрь него, а это ловит сравнение путей (`DIR/x`). Без этого
  /// `mv a .` в корне проекта, который сам предок, был бы критическим.
  bool isMissingAncestor(String abs) =>
      isAncestor(abs) && !_existing.contains(abs);

  /// Сравнивать пути без учёта регистра (файловая система хоста).
  bool get caseInsensitive => _config.caseInsensitive;

  /// Цель [abs] — каталог конфигурации: непосредственный родитель
  /// защищаемого пути хоста (`~/.codelab` для `~/.codelab/config.yaml`).
  /// Команда вне белого списка чтения, которой он передан, пишет в него
  /// (`tar -C ~/.codelab`, `cp -r x/. ~/.codelab`; R5-4).
  ///
  /// Широкие предки не считаются: `HOME` (и всё выше него) и корень сессии
  /// [root] содержат защищаемые пути, но `cp -r src .` или `make` в корне —
  /// обычная работа; запись внутрь них ловится сравнением конкретных путей, а
  /// разрушение — правилом подмены предка (`isAncestor`).
  bool isConfigParent(String abs, {required String root}) {
    _seen.add(abs);
    final canonical = _canonical[abs];
    final home = expansions['HOME'];
    bool broad(String path) =>
        isInside(path, root) ||
        home != null && isInside(path, normalizePath('/', home) ?? home);
    bool hit(String path) => _parents.contains(_key(path)) && !broad(path);
    return hit(abs) || canonical != null && hit(canonical);
  }

  /// Имена прямых потомков [abs], ведущих к защищаемым путям хоста: на них
  /// проверяется маска (`rm ~/.codelab/*.yaml`, R5-4). Имена — в виде ключа
  /// сравнения (нижний регистр при [caseInsensitive]).
  Set<String> childNames(String abs) {
    _seen.add(abs);
    final names = <String>{};
    void collect(String dir) {
      final prefix = dir == '/' ? '/' : '${_key(dir)}/';
      for (final form in _forms) {
        if (form.startsWith(prefix) && form.length > prefix.length) {
          names.add(form.substring(prefix.length).split('/').first);
        }
      }
    }

    collect(abs);
    final canonical = _canonical[abs];
    if (canonical != null) {
      collect(canonical);
    }
    return names;
  }

  bool _inForms(String key) {
    for (final form in _forms) {
      if (key == form || key.startsWith('$form/')) {
        return true;
      }
    }
    return false;
  }

  /// Считает канонические формы всех проверенных путей через [resolver]
  /// (вторая фаза проверки: ссылка на защищаемое место не скрывает цель).
  Future<void> canonicalizeSeen(PathResolver? resolver) async {
    for (final path in _seen.toList()) {
      if (!_canonical.containsKey(path)) {
        _canonical[path] = await canonicalForm(resolver, path);
      }
      if (resolver != null && await resolver.realpath(path) is Ok) {
        _existing.add(path);
        // Признак «обычный файл» — по канонической форме, не по ссылке.
        final Object fs = resolver;
        if (fs is FileSystem) {
          final stat = await fs.stat(_canonical[path]!);
          if (stat case Ok(:final value) when value.type == FileType.file) {
            _regular.add(path);
          }
        }
      }
    }
  }
}
