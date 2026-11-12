import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import '../config/config_loader.dart';
import '../config/config_writer.dart';
import '../util/silent_logger.dart';
import 'open_secret_store.dart';
import 'secret_admin.dart';
import 'secret_process_runner.dart';
import 'secret_value_checks.dart';

/// Параметры [SecretMigrator.run] (design.md change
/// `add-config-literal-secrets-and-migrate`, D7).
///
/// Почему типизированный вход, а не флаги строкой: разбор argv — дело
/// `package:args` каждого приложения, а кнопка codelab-app вызывает движок без
/// всякого argv (D8).
///
/// Как использовать: [cwd] — корень проекта (флаг `--cwd` или каталог
/// процесса), [environment] — окружение процесса (`CODELAB_HOME`,
/// `CODELAB_CONFIG`, `CODELAB_SECRET_*`; в `toString` не попадает), [layers] —
/// файлы, которые переносятся (`user`; `project`/`projectLocal` — слои
/// проекта [cwd]). [dryRun] — только план, [force] — заменить секрет с другим
/// значением (безвозвратно, L7).
@immutable
final class SecretMigrationOptions {
  const SecretMigrationOptions({
    required this.cwd,
    required this.environment,
    this.layers = const {ConfigLayer.user},
    this.dryRun = false,
    this.force = false,
    this.testStorePath,
  });

  /// Папка проекта: от неё ищутся проектные слои (`--cwd`).
  final String cwd;

  /// Окружение запуска: `CODELAB_HOME`, `CODELAB_CONFIG`, `HOME` — то же,
  /// что видит агент.
  final Map<String, String> environment;

  /// Слои для переноса: `user` по умолчанию, `--project`, `--local`, `--all`
  /// (D7); итог проверяется по слиянию всех слоёв (R8-10).
  final Set<ConfigLayer> layers;

  /// `--dry-run`: только план, без записи в хранилище и файлы.
  final bool dryRun;

  /// `--force`: заменить секрет с другим значением; безвозвратно (L7).
  final bool force;

  /// Путь к `secrets.yaml` тестового хранилища (`testSecretStorePath` от
  /// того же окружения, что у открывателя агента; `null` в рабочей сборке).
  ///
  /// Почему: в тестовой сборке (`CODELAB_ALLOW_TEST_SECRETS`) агент берёт
  /// ключи из файла по этому пути, и перенос обязан писать туда же, иначе
  /// агент и мигратор видят разные хранилища (change
  /// `add-config-literal-secrets-and-migrate`, D8). Задан — выбор
  /// `secrets.backend` игнорируется, бэкенд `file`, как у `openHostSecrets`.
  /// Не действует, если в [SecretMigrator] подставлен `openStore` (тесты).
  final String? testStorePath;

  @override
  String toString() =>
      'SecretMigrationOptions(cwd: $cwd, layers: $layers, dryRun: $dryRun, '
      'force: $force)';
}

/// Что делается с именем секрета в хранилище (D7, шаг 2).
enum SecretMigrationAction {
  /// Имени в хранилище нет — секрет создаётся.
  create('new'),

  /// В хранилище лежит то же значение — запись не нужна.
  reuse('reuse'),

  /// В хранилище другое значение, задан `--force` — замена безвозвратна.
  replace('replace');

  const SecretMigrationAction(this.label);

  /// Слово статуса в строке плана `--dry-run`.
  final String label;
}

/// Пункт отчёта [SecretMigrationReport]: одна строка вывода без значений.
///
/// Почему sealed-иерархия: кнопка codelab-app и CLI показывают те же пункты
/// (D8); исчерпывающий `switch` не даёт забыть вид пункта. [describe] — тот
/// же английский текст, что строка CLI.
sealed class SecretMigrationItem {
  const SecretMigrationItem();

  /// Строка вывода; значений секретов, их длин, префиксов и хешей в ней нет.
  String describe();

  @override
  String toString() => describe();
}

/// Строка плана `--dry-run`: `<path>: <ключ> -> <ссылка> (new|reuse|replace)`.
@immutable
final class SecretPlanItem extends SecretMigrationItem {
  const SecretPlanItem({
    required this.path,
    required this.key,
    required this.reference,
    required this.action,
  });

  /// Путь файла слоя — для вывода.
  final String path;

  /// Путь ключа с литералом (`providers.lm.api_key`).
  final String key;

  /// То, что встанет на место значения: `api_key_secret: <имя>` или
  /// значение со ссылкой `${secret:<имя>}`.
  final String reference;

  /// Что произойдёт с именем в хранилище.
  final SecretMigrationAction action;

  @override
  String describe() => '$path: $key -> $reference (${action.label})';
}

/// `Reused secret <name> for <ключ> in <path>`: в хранилище уже лежит то же
/// значение (повтор после сбоя записи конфига, L7).
@immutable
final class SecretReusedItem extends SecretMigrationItem {
  const SecretReusedItem({
    required this.name,
    required this.key,
    required this.path,
  });

  /// Имя секрета в хранилище.
  final String name;

  /// Путь ключа, значение которого перенесено.
  final String key;

  /// Путь файла слоя — для вывода.
  final String path;

  @override
  String describe() => 'Reused secret $name for $key in $path';
}

/// `Moved <ключ> in <path> to secret <name>`: файл переписан.
@immutable
final class SecretMovedItem extends SecretMigrationItem {
  const SecretMovedItem({
    required this.name,
    required this.key,
    required this.path,
  });

  /// Имя секрета в хранилище.
  final String name;

  /// Путь ключа, значение которого перенесено.
  final String key;

  /// Путь файла слоя — для вывода.
  final String path;

  @override
  String describe() => 'Moved $key in $path to secret $name';
}

/// `Moved providers.<id> (address and key) from <path> to <local path>`:
/// провайдер закоммиченного конфига доверенного проекта
/// переехал в локальный файл (design.md change `require-project-folder`, D26).
///
/// Почему отдельный пункт: ссылка на ключ из `config.yaml` не привязана к
/// адресу (D23, правило 3), и провайдер, оставшийся там, перестаёт работать.
/// Пункт говорит пользователю, что вместе с ключом переехал и адрес.
@immutable
final class SecretProviderMovedItem extends SecretMigrationItem {
  const SecretProviderMovedItem({
    required this.provider,
    required this.from,
    required this.to,
  });

  /// Путь ключа провайдера (`providers.<id>`).
  final String provider;

  /// Закоммиченный `config.yaml`, откуда поля группы удалены.
  final String from;

  /// `config.local.yaml`, куда они записаны.
  final String to;

  @override
  String describe() => 'Moved $provider (address and key) from $from to $to';
}

/// Предупреждение `--force`: секрет заменён, прежнее значение не восстановить
/// (L7).
@immutable
final class SecretReplacedItem extends SecretMigrationItem {
  const SecretReplacedItem({required this.name, this.referencedBy = const []});

  /// Имя заменённого секрета.
  final String name;

  /// Ключи всех слоёв загруженного конфига, ссылающиеся на [name]
  /// (`<ключ> (<слой>)`); пусто — хвоста в строке нет.
  final List<String> referencedBy;

  @override
  String describe() =>
      'warning: replaced the existing secret $name; the previous value '
      'cannot be restored'
      '${referencedBy.isEmpty ? '' : '; also referenced by: ${referencedBy.join(', ')}'}';
}

/// `action required: …`: ключ без места в схеме (`token`) удалён, ссылку на
/// секрет пользователь вписывает сам.
@immutable
final class SecretActionRequiredItem extends SecretMigrationItem {
  const SecretActionRequiredItem({required this.name, required this.place});

  /// Имя сохранённого секрета, на которое пользователь ставит ссылку.
  final String name;

  /// Где вписать ссылку: файл слоя и место ключа.
  final String place;

  @override
  String describe() => 'action required: reference \${secret:$name} in $place';
}

/// `not migrated: …`: находка, которую команда не трогает (код выхода не
/// меняется, R8-4: литерал загрузку не блокирует).
@immutable
final class SecretNotMigratedItem extends SecretMigrationItem {
  const SecretNotMigratedItem(this.reason);

  /// Причина без значения.
  final String reason;

  @override
  String describe() => 'not migrated: $reason';
}

/// Итог [SecretMigrator.run]: пункты и проблемы без значений секретов.
///
/// Почему данные, а не печать: CLI пишет строки в свои потоки, а codelab-app
/// строит из пунктов план и диалог (D8, `AGENTS.md` §6: виджеты IO не
/// делают). Ни одно поле и ни один `toString` не содержит значений, длин,
/// префиксов и хешей секретов.
///
/// Как использовать: напечатать [stdoutLines] и [stderrLines], завершиться с
/// [exitCode]. [showUsage] — ошибка использования (код `64`), приложение
/// добавляет справку `secret`.
@immutable
final class SecretMigrationReport {
  const SecretMigrationReport({
    required this.exitCode,
    this.items = const [],
    this.problems = const [],
    this.warnings = const [],
    this.dryRun = false,
    this.movedAny = false,
    this.readOnlyBackend = false,
    this.home,
    this.nameConflict = false,
    this.onlyExtraLayerFindings = false,
    this.showUsage = false,
    this.backendId,
  });

  /// `0`, `1` (хранилище, конфликт имени, писатель, кандидат, загрузка либо
  /// два источника ключа провайдера после переноса, R8-10) или `64`.
  final int exitCode;

  /// Пункты в порядке вывода: слои `user`, `project`, `local`, затем
  /// `CODELAB_CONFIG`.
  final List<SecretMigrationItem> items;

  /// Строки stderr: причина кода `1` или `64`.
  final List<String> problems;

  /// Строки stderr, не меняющие код (`warning: CODELAB_CONFIG ignored: …`).
  final List<String> warnings;

  /// Отчёт `--dry-run`: файлы и хранилище не изменены.
  final bool dryRun;

  /// Хотя бы один файл переписан (в `--dry-run` всегда `false`).
  final bool movedAny;

  /// Бэкенд только для чтения (`env`): подсказка в [problems].
  final bool readOnlyBackend;

  /// Путь `CODELAB_HOME`, вычисленный тем же `codelabHomeOf`, что и движок;
  /// `null`, если отказ случился до его вычисления (код `64`).
  ///
  /// Почему поле: подсказка бэкенда `env` в app называет `<home>/config.yaml`
  /// и не должна пересчитывать каталог сама (D8).
  final String? home;

  /// Отказ из-за конфликта имени: секрет с таким именем уже лежит в
  /// хранилище с другим значением, а `--force` не задан (`exitCode == 1`,
  /// ничего не записано, L7).
  ///
  /// Почему поле: codelab-app показывает для конфликта отдельный текст и
  /// только `Close` (D8) и не должна разбирать текст [problems].
  final bool nameConflict;

  /// Находки есть, но все — `not migrated` из-за слоя `CODELAB_CONFIG`,
  /// который команда не пишет (D7); переносить нечего, [canApply] `false`.
  ///
  /// Почему поле: app в этом случае показывает строки плана и только `Close`
  /// (D8). Находки записываемых слоёв (в том числе их `not migrated`) поле
  /// сбрасывают в `false`.
  final bool onlyExtraLayerFindings;

  final bool showUsage;

  /// `SecretBackendInfo.id` открытого хранилища; для `file` приложение
  /// добавляет предупреждение об открытом тексте. `null` — хранилище не
  /// открывалось.
  final String? backendId;

  /// Есть что применить: план `--dry-run` не пуст либо файлы переписаны.
  /// Кнопка app включает «Migrate» по этому признаку (D8).
  bool get canApply =>
      exitCode == 0 &&
      items.any((i) => i is SecretPlanItem || i is SecretMovedItem);

  /// Строки stdout; последняя — `restart the agent …` при переносе или
  /// `Nothing to migrate`, когда пунктов нет вовсе.
  List<String> get stdoutLines => [
    for (final item in items) item.describe(),
    if (movedAny)
      'restart the agent to use the moved secrets'
    else if (items.isEmpty && exitCode == 0)
      'Nothing to migrate',
  ];

  /// Строки stderr.
  List<String> get stderrLines => [...warnings, ...problems];

  @override
  String toString() =>
      'SecretMigrationReport(exitCode: $exitCode, items: ${items.length}, '
      'dryRun: $dryRun, movedAny: $movedAny)';
}

/// Переносит литеральные секреты из файлов конфига в хранилище и заменяет их
/// ссылками (design.md change `add-config-literal-secrets-and-migrate`, D7,
/// D3, R8-4; agent-secrets «Подкоманда secret migrate»).
///
/// Почему отдельный движок: `codelab secret migrate`, `codelab-agent secret
/// migrate` и кнопка codelab-app (D8) делают одно и то же и должны давать
/// одинаковые тексты; логика находок, имён и порядка записи живёт здесь, а
/// `SecretCommands.migrate` только форматирует отчёт.
///
/// Для чего: находки `findInlineSecrets` применяемых слоёв превращаются в
/// секреты хранилища (`SecretNames.suggestFor/forMcp`, суффикс `-2` при
/// разных значениях одного имени; имя, на которое уже ссылается тот же
/// провайдер или сервер с другим значением, пропускается) и правки файла
/// одной атомарной `ConfigWriter.apply`. Порядок (H4, №3, L7, R8-10):
/// проверки без записи — находки, доверие писателя, `secretValueProblem`,
/// имена, итог правок ВСЕХ выбранных файлов вместе через
/// `ConfigLoader.validateCandidate(pending:)` (до хранилища), затем
/// `SecretAdmin.checkStore` (только если есть что переносить), сравнение с
/// хранилищем и конфликты. Запись: сначала секреты всех файлов, потом
/// конфиги по одному. Конфликт источников ключа провайдера (R8-6) в уже
/// загруженном конфиге — следствие частичного сбоя либо исходной пары
/// «ссылка в одном слое, литерал в другом»: его снимает перенос, поэтому
/// загрузка его допускает, а итог обязан быть чистым. Недоверенный проект и
/// `CODELAB_CONFIG` значений в хранилище не отдают; элементы `args` не
/// трогаются. Значения живут только в памяти этого вызова: в отчёт, текст
/// исключения и лог они не попадают (CFG-2; писатель получает тихий логгер).
///
/// Провайдер закоммиченного `config.yaml` (D26, change `require-project-folder`):
/// ссылка из этого файла не привязана к адресу (D23, правило 3), поэтому
/// провайдер доверенного проекта с находкой в поле группы (`api_key`,
/// `api_key_env`, `api_key_secret`, `headers`) переезжает целиком — все поля
/// группы, которые задаёт `config.yaml`, — в `config.local.yaml` того же
/// проекта; литерал становится ссылкой, секрет уходит из репозитория. Файлы
/// пишутся в порядке `user`, `local`, `project`: сбой между записями оставляет
/// рабочий конфиг. `config.local.yaml` с иной группой этого провайдера —
/// `not migrated`, оба файла не меняются.
///
/// Как использовать: `await SecretMigrator().run(SecretMigrationOptions(…))`;
/// напечатать отчёт. Исключений для штатных отказов нет — они в
/// `exitCode`/`problems`. [processRunner], [clock], [random] и [platform] —
/// швы писателя и хранилища (`chmod`, Windows); [openStore] и [writeSeam] —
/// только для тестов.
final class SecretMigrator {
  SecretMigrator({
    SecretProcessRunner? processRunner,
    Clock? clock,
    Random? random,
    String? platform,
    @visibleForTesting SecretStoreOpener? openStore,
    @visibleForTesting Future<void> Function(ConfigWriteSeam point)? writeSeam,
  }) : _runner = processRunner ?? const IoSecretProcessRunner(),
       _clock = clock ?? const SystemClock(),
       _random = random ?? Random.secure(),
       _platform = platform ?? Platform.operatingSystem,
       _seam = writeSeam,
       _customOpener = openStore != null,
       _openStore =
           openStore ??
           (({required choice, required environment, required home}) =>
               openSecretStore(
                 choice: choice,
                 environment: environment,
                 home: home,
                 logger: const SilentLogger(),
                 runner: processRunner,
                 platform: platform,
               ));

  final SecretProcessRunner _runner;
  final Clock _clock;
  final Random _random;
  final String _platform;
  final Future<void> Function(ConfigWriteSeam point)? _seam;
  final SecretStoreOpener _openStore;

  /// Подставлен открыватель тестов: `testStorePath` ему не передаётся.
  final bool _customOpener;

  /// Выполняет перенос (или его план при `dryRun`).
  Future<SecretMigrationReport> run(SecretMigrationOptions options) =>
      _MigrationRun(this, options).execute();
}

// ---------------------------------------------------------------------------
// Внутренности запуска
// ---------------------------------------------------------------------------

final _ownerPattern = RegExp(r'^(providers\.[^.\[]+|mcp\.servers\[[^\]]*\])');

/// Неизменяемые части значения: один секрет внутри строки.
final class _Slot {
  _Slot({
    required this.value,
    required this.base,
    this.start,
    this.end,
    this.variableReference = false,
    this.secretReference = false,
  });

  /// Значение секрета. Живёт только в памяти запуска.
  final String value;

  /// Желаемое имя (`suggestedSecretName`).
  final String base;

  /// Участок значения в строке (`literalPart`, `referenceName`).
  final int? start, end;

  /// Участок — имя в `${LIT}` (переменная), а не в `${secret:LIT}`.
  final bool variableReference;
  final bool secretReference;

  /// Итоговое имя после разведения коллизий.
  late String name;
}

enum _UnitKind { providerKey, nameLiteral, otherInline, templated }

/// Одна правка файла: ключ с одним или несколькими секретами.
final class _Unit {
  _Unit(this.kind, this.key, this.slots, {this.original});

  final _UnitKind kind;
  final String key;
  final List<_Slot> slots;

  /// Исходная строка (`templated`).
  final String? original;

  /// Единица принадлежит переезжающему провайдеру (D26): в `config.yaml` она
  /// только удаляется, а ссылка пишется в `config.local.yaml`.
  _Move? move;

  /// Ключ ссылки в `config.local.yaml` при переезде провайдера.
  String get localKey => switch (kind) {
    _UnitKind.providerKey => '${_parent(key)}.api_key_secret',
    _UnitKind.nameLiteral =>
      key.endsWith('.api_key_env') ? '${_parent(key)}.api_key_secret' : key,
    _UnitKind.templated || _UnitKind.otherInline => key,
  };

  /// Значение ссылки в `config.local.yaml` при переезде (имя секрета либо
  /// строка со ссылками).
  String get localValue =>
      kind == _UnitKind.templated ? _templatedText() : slots.first.name;

  String _templatedText() {
    var text = original!;
    for (final slot in slots.reversed) {
      final replacement = slot.secretReference
          ? slot.name
          : slot.variableReference
          ? 'secret:${slot.name}'
          : '\${secret:${slot.name}}';
      text = text.replaceRange(slot.start!, slot.end!, replacement);
    }
    return text;
  }

  List<ConfigEdit> edits() {
    final name = slots.first.name;
    switch (kind) {
      case _UnitKind.providerKey:
        return [
          SetValue('${_parent(key)}.api_key_secret', name),
          UnsetValue(key),
        ];
      case _UnitKind.nameLiteral:
        return key.endsWith('.api_key_env')
            ? [
                SetValue('${_parent(key)}.api_key_secret', name),
                UnsetValue(key),
              ]
            : [SetValue(key, name)];
      case _UnitKind.otherInline:
        return [UnsetValue(key)];
      case _UnitKind.templated:
        return [SetValue(key, _templatedText())];
    }
  }

  /// Ссылка для строки плана.
  String reference(_Slot slot) =>
      kind == _UnitKind.providerKey || kind == _UnitKind.nameLiteral
      ? 'api_key_secret: ${slot.name}'
      : '\${secret:${slot.name}}';

  static String _parent(String key) => key.substring(0, key.lastIndexOf('.'));
}

/// Слой, который запуск просматривает.
final class _File {
  _File({required this.label, required this.path, this.target, this.snapshot});

  /// `user`, `project`, `local` или `CODELAB_CONFIG`.
  final String label;
  final String path;

  /// `null` — слой не записываемый (`CODELAB_CONFIG`).
  final ConfigTarget? target;
  ConfigSnapshot? snapshot;

  List<_Unit> units = [];

  /// Находки, которых команда не переносит (без значений).
  List<String> notes = [];

  /// Слой проекта вне `trusted_projects` (H4): значения не читаются.
  bool untrusted = false;

  /// Провайдеры, уезжающие из этого файла (`config.yaml`) в `config.local.yaml`
  /// (D26).
  final moves = <_Move>[];

  /// Провайдеры, приезжающие в этот файл (`config.local.yaml`, D26).
  final incoming = <_Move>[];
}

const _groupFields = [
  'kind',
  'base_url',
  'auth_header',
  'api_key_env',
  'api_key_secret',
  'api_key',
];

/// Переезд провайдера закоммиченного `config.yaml` доверенного проекта в
/// `config.local.yaml` (design.md change `require-project-folder`, D26).
///
/// Почему: ссылка на ключ из `config.yaml` не привязана к адресу (D23,
/// правило 3), поэтому провайдер, у которого мигратор заменил литерал ссылкой
/// в том же файле, перестал бы работать (`key_unbound`) при коде выхода `0`.
/// `config.local.yaml` — верхний слой группы (Q17 (a)), его ссылка
/// разрешается по условию (a). Секрет при этом уходит из репозитория.
///
/// Что переезжает: все поля группы D23, которые задаёт `config.yaml`
/// (`kind`, `base_url`, `headers`, `api_key*`, `auth_header`), с литералами,
/// превращёнными в ссылки. Остальное (`models`, сроки) остаётся.
final class _Move {
  _Move(this.id, this.source, this.target);

  final String id;
  final _File source;
  final _File target;

  /// Единицы правки `source`, относящиеся к полям группы.
  final units = <_Unit>[];

  /// Поля группы без находок: ключ → значение, копируются как есть.
  final copied = <String, Object>{};

  /// `config.local.yaml` уже задаёт ту же группу (повтор после сбоя): в него
  /// ничего не пишется, из `config.yaml` поля только удаляются.
  var resume = false;

  List<ConfigEdit> localEdits() => resume
      ? const []
      : [
          for (final MapEntry(:key, :value) in copied.entries)
            SetValue(key, value),
          for (final unit in units) SetValue(unit.localKey, unit.localValue),
        ];

  List<ConfigEdit> sourceEdits() => [
    for (final key in copied.keys) UnsetValue(key),
    for (final unit in units) UnsetValue(unit.key),
  ];
}

/// Решение по имени секрета в хранилище.
final class _Resolution {
  _Resolution(this.value, this.action);
  final String value;
  SecretMigrationAction action;
}

/// Короткое замыкание шага: готовый отчёт.
final class _Stop implements Exception {
  _Stop(this.report);
  final SecretMigrationReport report;
}

final class _MigrationRun {
  _MigrationRun(this._m, this._o);

  final SecretMigrator _m;
  final SecretMigrationOptions _o;

  late final Map<String, String> _env;
  late final String _home;

  /// `_home` вычислен: отчёт отказа до этого момента несёт `home: null`.
  var _homeKnown = false;
  late final String _cwd;
  late final ConfigWriter _writer;
  late final DescribedSecretStore _store;
  late final SecretAdmin _admin;
  late final List<ConfigTree> _layers;
  final _warnings = <String>[];
  final _files = <_File>[];
  var _active = const <_File>[];

  /// Итоговый текст каждого выбранного файла (R8-10).
  final _previews = <_File, PendingConfigText>{};

  /// Имя → значение в пределах запуска (D7, шаг 2).
  final _assigned = <String, String>{};
  final _resolved = <String, _Resolution>{};

  /// Имена, уже сохранённые этим запуском.
  final _stored = <String>{};

  Future<SecretMigrationReport> execute() async {
    try {
      return await _execute();
    } on _Stop catch (stop) {
      return stop.report;
    }
  }

  /// Завершает запуск штатным отказом. Прогресс подставляется сам: пункты
  /// уже записанных файлов, `movedAny` и имена секретов, уже сохранённых этим
  /// запуском (без значений), — повтор переиспользует их (L7).
  Never _fail(
    int code,
    List<String> problems, {
    bool usage = false,
    bool readOnly = false,
    bool conflict = false,
  }) => throw _Stop(
    SecretMigrationReport(
      exitCode: code,
      items: _done.isEmpty ? const [] : _items(planned: false, files: _done),
      problems: [
        ...problems,
        if (code == 1 && _stored.isNotEmpty)
          'secrets already stored (rerun the command to reuse them): '
              '${_stored.join(', ')}',
        // D26: сбой между двумя записями — назван файл, который остался
        // прежним.
        if (code == 1 && _done.isNotEmpty && _remainingPaths().isNotEmpty)
          'config not rewritten (rerun the command): '
              '${_remainingPaths().join(', ')}',
      ],
      warnings: _warnings,
      dryRun: _o.dryRun,
      movedAny: _done.isNotEmpty,
      readOnlyBackend: readOnly,
      home: _homeKnown ? _home : null,
      nameConflict: conflict,
      showUsage: usage,
      backendId: _backendId,
    ),
  );

  /// Файлы, конфиг которых уже переписан этим запуском.
  final _done = <_File>[];

  List<String> _remainingPaths() => [
    for (final f in _active)
      if (!_done.contains(f)) f.path,
  ];

  /// Проблемы загрузки, которые могут снять правки выбранных слоёв (R8-6).
  var _deferred = const <ConfigIssue>[];

  String? _backendId;

  Future<SecretMigrationReport> _execute() async {
    _prepareEnvironment();
    _load();
    _openStore();
    await _collect();

    var active = _activeFiles();
    _active = active;
    if (active.isEmpty && _deferred.isNotEmpty) {
      _fail(1, [for (final issue in _deferred) '$issue']);
    }
    if (active.isNotEmpty) {
      // Предварительные имена — без обращения к хранилищу: на итог R8-6 они
      // не влияют, а отказ R8-10 обязан случиться ДО хранилища.
      _allocateAll(active);
      // Итог всех файлов сразу — до хранилища и до любой записи (R8-10).
      await _checkCandidates(active);
      // Окончательные имена учитывают ссылки владельцев (читает хранилище).
      await _assignNames(active);
      // D26: переезд, чьи ссылки в `config.local.yaml` не совпали с тем, что
      // записал бы перенос, отменяется; имена и итог считаются заново.
      var refused = false;
      while (_verifyResumes()) {
        refused = true;
        active = _activeFiles();
        _active = active;
        if (active.isEmpty) {
          break;
        }
        await _assignNames(active);
      }
      if (active.isEmpty && _deferred.isNotEmpty) {
        _fail(1, [for (final issue in _deferred) '$issue']);
      }
      if (active.isNotEmpty) {
        if (refused) {
          await _checkCandidates(active);
        }
        await _refreshPreviews(active);
        await _checkStore();
        await _resolveNames(_assigned.keys);
        _failOnConflicts();
      }
    }
    if (_o.dryRun) {
      return _report(planned: true);
    }
    // Секреты ВСЕХ файлов — до первой записи конфига: после этого возможны
    // только сбои записи файлов, а повтор переиспользует сохранённое (L7).
    for (final file in active) {
      await _storeSecrets(file);
    }
    // Порядок записи (D26): `user`, `local`, `project`. `config.local.yaml` с
    // группой и ссылкой пишется раньше, чем группа удаляется из
    // `config.yaml`: сбой между записями оставляет рабочий конфиг (группу
    // берёт верхний слой — `config.local.yaml`), обратный порядок оставил бы
    // провайдера без адреса и ключа.
    const order = {'user': 0, 'local': 1, 'project': 2};
    final writeOrder = [...active]
      ..sort((a, b) => (order[a.label] ?? 3).compareTo(order[b.label] ?? 3));
    for (final file in writeOrder) {
      await _writeFile(file);
      _done.add(file);
    }
    return _report(planned: false);
  }

  /// Файлы с правками: свои единицы либо провайдеры, приезжающие в
  /// `config.local.yaml` (D26).
  List<_File> _activeFiles() => [
    for (final f in _files)
      if (f.units.isNotEmpty || f.incoming.any((m) => !m.resume)) f,
  ];

  // ---- подготовка -----------------------------------------------------------

  void _prepareEnvironment() {
    if (!Directory(_o.cwd).existsSync()) {
      _fail(64, ['secret migrate: no such directory: ${_o.cwd}']);
    }
    _cwd = Directory(_o.cwd).resolveSymbolicLinksSync();
    _env = {..._o.environment};
    // Общее правило подкоманд `secret`: недопустимый CODELAB_CONFIG —
    // предупреждение, код выхода не меняется (agent-secrets «Подкоманды
    // secret»).
    final extra = _env['CODELAB_CONFIG'];
    if (extra != null && extra.isNotEmpty) {
      try {
        checkConfigEnvPath(extra);
      } on ConfigUsageException catch (error) {
        _warnings.add('warning: CODELAB_CONFIG ignored: ${error.message}');
        _env.remove('CODELAB_CONFIG');
      }
    }
    final explicit = _env['CODELAB_HOME'];
    if ((explicit == null || explicit.isEmpty) && userHomeOf(_env) == null) {
      _fail(64, ['cannot find the home folder: set CODELAB_HOME or HOME']);
    }
    try {
      _home = codelabHomeOf(_env);
      _homeKnown = true;
    } on ConfigUsageException catch (error) {
      _fail(64, [error.message]);
    }
  }

  /// Полная загрузка обычным `ConfigLoader` (D7): любая проблема — код `1`.
  void _load() {
    final ({ConfigLoadResult result, List<ConfigTree> layers}) loaded;
    try {
      loaded = ConfigLoader().loadWithLayers(
        cwd: _cwd,
        environment: _env,
        platform: _m._platform,
      );
    } on ConfigUsageException catch (error) {
      _fail(64, ['secret migrate: ${error.message}']);
    }
    final issues = loaded.result.issues;
    if (issues.isNotEmpty) {
      // Конфликт источников ключа (R8-6) — состояние после частичного сбоя
      // `--all` либо исходная пара «ссылка в user, литерал в project»: его
      // снимают правки выбранных слоёв, поэтому повтор `migrate` обязан
      // загрузиться. Отложенными становятся все проблемы загрузки, а не
      // только R8-6: вместе с ней приходят её следствия (`default_model … is
      // not in the model catalog`), которые снимает та же правка. Итог всех
      // слоёв `_verifyRepaired` проверяет целиком до хранилища и записи, так
      // что любая посторонняя проблема всё равно даёт код 1 (R8-11). Без R8-6
      // — отказ сразу.
      if (!issues.any((i) => i.message == providerKeySourcesConflictMessage)) {
        _fail(1, [for (final issue in issues) '$issue']);
      }
      _deferred = issues;
    }
    _layers = loaded.layers;
    _secretsChoice =
        loaded.result.host?.secretsBackend ??
        _backendFromValues(loaded.result.values);
    _writer = ConfigWriter(
      codelabHome: _home,
      environment: _env,
      loader: ConfigLoader(),
      logger: const SilentLogger(),
      processRunner: _m._runner,
      clock: _m._clock,
      random: _m._random,
      cwd: _cwd,
      platform: _m._platform,
      // ignore: invalid_use_of_visible_for_testing_member
      seam: _m._seam,
    );
  }

  String? _secretsChoice;

  /// `secrets.backend` из слитых значений: при проблеме загрузки `host`
  /// пуст.
  String? _backendFromValues(Map<String, Object?> values) {
    final secrets = values['secrets'];
    final backend = secrets is Map<String, Object?> ? secrets['backend'] : null;
    return backend is String ? backend : null;
  }

  void _openStore() {
    try {
      final testPath = _o.testStorePath;
      _store = testPath != null && !_m._customOpener
          // Тестовая сборка: то же хранилище, что у агента (D8).
          ? openSecretStore(
              choice: _secretsChoice,
              environment: _env,
              home: _home,
              logger: const SilentLogger(),
              runner: _m._runner,
              platform: _m._platform,
              testStorePath: testPath,
            )
          : _m._openStore(
              choice: _secretsChoice,
              environment: _env,
              home: _home,
            );
    } on SecretStoreUnavailableException catch (error) {
      _fail(1, ['secrets.backend: ${error.reason}']);
    }
    _backendId = _store.backend.id;
    _admin = SecretAdmin(
      store: _store,
      environment: _env,
      platform: _m._platform,
    );
  }

  // ---- находки --------------------------------------------------------------

  Future<void> _collect() async {
    final targets = <(ConfigLayer, String)>[
      (ConfigLayer.user, 'user'),
      (ConfigLayer.project, 'project'),
      (ConfigLayer.projectLocal, 'local'),
    ];
    for (final (layer, label) in targets) {
      if (!_o.layers.contains(layer)) {
        continue;
      }
      final target = switch (layer) {
        ConfigLayer.user => const ConfigTarget.user(),
        ConfigLayer.project => ConfigTarget.project(_cwd),
        ConfigLayer.projectLocal => ConfigTarget.projectLocal(_cwd),
      };
      final ConfigSnapshot snapshot;
      try {
        snapshot = await _writer.read(target);
      } on ConfigException catch (error) {
        _fail(1, [for (final issue in error.issues) '$issue']);
      }
      final file = _File(
        label: label,
        path: snapshot.path,
        target: target,
        snapshot: snapshot,
      );
      _scan(file);
      _files.add(file);
    }
    // `CODELAB_CONFIG` не записывается (D7): о находках — одна строка.
    for (final layer in _layers) {
      if (layer.kind != ConfigLayerKind.extra) {
        continue;
      }
      if (findInlineSecrets(layer).isNotEmpty ||
          _argsNotes(layer.values).isNotEmpty) {
        _files.add(
          _File(label: 'CODELAB_CONFIG', path: layer.source)
            ..notes = ['${layer.source} is not a writable layer'],
        );
      }
    }
    for (final file in _files) {
      if (file.target != null && file.target!.layer != ConfigLayer.user) {
        await _checkTrust(file);
      }
    }
    await _planMoves();
  }

  /// Идентификатор провайдера, если находка [unit] лежит в поле группы D23
  /// (`api_key`, `api_key_env`, `api_key_secret`, `headers`), иначе `null`
  /// (D26). `apiKey` в шаблоне — не опечатка: `findInlineSecrets` сообщает
  /// camelCase-вариант как тот же литеральный ключ, и он переносится как
  /// `api_key`.
  String? _groupProviderOf(_Unit unit) {
    final match = RegExp(
      r'^providers\.([^.\[]+)\.(api_key|apiKey|api_key_env|api_key_secret|headers[.\[])',
    ).firstMatch(unit.key);
    return match?.group(1);
  }

  /// D26: провайдеры закоммиченного `config.yaml` доверенного проекта, у
  /// которых есть находка в поле группы, переезжают в `config.local.yaml`.
  /// Доверие проверено выше (недоверенный проект уже без единиц).
  Future<void> _planMoves() async {
    final project = _files
        .where((f) => f.label == 'project' && !f.untrusted)
        .firstOrNull;
    if (project == null || project.units.isEmpty) {
      return;
    }
    final ids = <String>{
      for (final unit in project.units) ?_groupProviderOf(unit),
    };
    if (ids.isEmpty) {
      return;
    }
    var local = _files.where((f) => f.label == 'local').firstOrNull;
    if (local == null) {
      final target = ConfigTarget.projectLocal(_cwd);
      final ConfigSnapshot snapshot;
      try {
        snapshot = await _writer.read(target);
      } on ConfigException catch (error) {
        _fail(1, [for (final issue in error.issues) '$issue']);
      }
      local = _File(
        label: 'local',
        path: snapshot.path,
        target: target,
        snapshot: snapshot,
      );
      _files.insert(_files.indexOf(project) + 1, local);
    }
    final binding = ProviderKeyBinding.fromLayers(_layers, _env);
    for (final id in ids) {
      // C5.6: в `config.local.yaml` ссылка разрешается без проверки origin
      // (условие (a) D23), а ссылку, которую написал репозиторий, переносить
      // нельзя: ключ пользователя ушёл бы на адрес из репозитория.
      final foreign = _unboundReference(project, id, binding);
      if (foreign != null) {
        project.units.removeWhere((u) => _groupProviderOf(u) == id);
        project.notes.add(
          'providers.$id in ${project.path}: $foreign is not bound to this '
          'address by the user config; move it by hand',
        );
        continue;
      }
      final move = _Move(id, project, local);
      move.units.addAll(project.units.where((u) => _groupProviderOf(u) == id));
      final entry = _providerEntry(project.snapshot!.values, id);
      final unitKeys = {for (final u in move.units) u.key};
      final prefix = 'providers.$id';
      for (final field in _groupFields) {
        final key = '$prefix.$field';
        if (entry[field] != null && !unitKeys.contains(key)) {
          move.copied[key] = entry[field]!;
        }
      }
      if (entry['headers'] case final Map<String, Object?> headers) {
        for (final MapEntry(:key, :value) in headers.entries) {
          final path = KeyPath('$prefix.headers').child(key).value;
          if (!unitKeys.contains(path)) {
            if (value != null) {
              move.copied[path] = value;
            }
          }
        }
      }
      if (_localConflicts(move, local)) {
        _refuse(move);
        continue;
      }
      for (final unit in move.units) {
        unit.move = move;
      }
      project.moves.add(move);
      local.incoming.add(move);
    }
  }

  /// Ссылка группы провайдера [id] в `config.yaml`, которую не создаёт сам
  /// мигратор из литерала и которую глобальные слои не связывают с итоговым
  /// адресом (условие (b) D23); `null` — все ссылки привязаны (D26, C5.6).
  /// В тексте — вид и имя ссылки без значения.
  String? _unboundReference(
    _File project,
    String id,
    ProviderKeyBinding binding,
  ) {
    final entry = _providerEntry(project.snapshot!.values, id);
    final unitKeys = {
      for (final u in project.units)
        if (_groupProviderOf(u) == id) u.key: u,
    };
    final prefix = 'providers.$id';
    // Итоговый адрес: свой `base_url`/`kind` проекта, иначе — из непроектных
    // слоёв (Q21 (a)).
    // Берётся верхний непроектный слой, задающий поле: так же группу соберёт
    // загрузка по Q21 (a) и правилу верхнего слоя `T`.
    Object? inherited(String field) {
      for (final layer in _layers.reversed) {
        if (layer.kind == ConfigLayerKind.project ||
            layer.kind == ConfigLayerKind.projectLocal) {
          continue;
        }
        final providers = layer.values['providers'];
        final body = providers is Map<String, Object?> ? providers[id] : null;
        if (body is Map<String, Object?> && body[field] != null) {
          return body[field];
        }
      }
      return null;
    }

    final kind = entry['kind'] ?? inherited('kind');
    final origin = providerOrigin(
      {'base_url': entry['base_url'] ?? inherited('base_url')},
      kind is String ? kind : null,
      _env,
    );
    for (final reference in providerReferences(entry)) {
      final key = reference.field.startsWith('headers.')
          ? KeyPath(
              '$prefix.headers',
            ).child(reference.field.substring('headers.'.length)).value
          : '$prefix.${reference.field}';
      final unit = unitKeys[key];
      // Находку-литерал мигратор заменяет ссылкой сам; чужими остаются
      // ссылки вне находок и ссылки в нетронутых частях строки находки.
      if (unit != null && !_isForeignInUnit(unit, reference)) {
        continue;
      }
      if (!binding.isBound(reference, origin)) {
        final shown = literalSecretTag(reference.name, asName: true) != null
            ? 'a reference'
            : switch (reference.kind) {
                ProviderReferenceKind.secret => 'secret ${reference.name}',
                ProviderReferenceKind.env => 'variable ${reference.name}',
              };
        return shown;
      }
    }
    return null;
  }

  /// Ссылка внутри строки находки (`headers.X: "Bearer <литерал> ${X}"`):
  /// чужая, если её имя лежит вне участков литералов, которые мигратор
  /// заменяет сам.
  bool _isForeignInUnit(_Unit unit, ProviderReference reference) {
    if (unit.kind != _UnitKind.templated) {
      return false;
    }
    var rest = unit.original!;
    for (final slot in unit.slots.reversed) {
      rest = rest.replaceRange(slot.start!, slot.end!, '');
    }
    return referencesIn(
      rest,
    ).any((r) => r.$1 == reference.kind && r.$2 == reference.name);
  }

  Map<String, Object?> _providerEntry(Map<String, Object?> values, String id) {
    final providers = values['providers'];
    final entry = providers is Map<String, Object?> ? providers[id] : null;
    return entry is Map<String, Object?> ? entry : const {};
  }

  /// `config.local.yaml` уже задаёт поля группы провайдера: совпадающие с тем,
  /// что записал бы перенос, — повтор после сбоя (`resume`); иначе группы не
  /// сливаются молча (D26). Значения-ссылки из секретов сверяются позже, когда
  /// известны имена ([_verifyResumes]).
  bool _localConflicts(_Move move, _File local) {
    final entry = _providerEntry(local.snapshot!.values, move.id);
    final prefix = 'providers.${move.id}';
    final present = <String, Object?>{
      for (final field in _groupFields)
        if (entry[field] != null) '$prefix.$field': entry[field],
      if (entry['headers'] case final Map<String, Object?> headers)
        for (final MapEntry(:key, :value) in headers.entries)
          KeyPath('$prefix.headers').child(key).value: value,
    };
    if (present.isEmpty) {
      return false;
    }
    final expected = {
      ...move.copied.keys,
      for (final unit in move.units) unit.localKey,
    };
    if (present.length != expected.length ||
        !present.keys.every(expected.contains)) {
      return true;
    }
    for (final MapEntry(:key, :value) in move.copied.entries) {
      if (present[key] != value) {
        return true;
      }
    }
    move.resume = true;
    return false;
  }

  /// Отказ по провайдеру: оба файла не меняются, значение в хранилище не
  /// попадает; остальные находки переносятся (D26).
  void _refuse(_Move move) {
    move.source.units.removeWhere(move.units.contains);
    move.source.moves.remove(move);
    move.target.incoming.remove(move);
    move.source.notes.add(
      'providers.${move.id} in ${move.source.path}: config.local.yaml '
      'already defines its address or key; move it by hand',
    );
  }

  /// После выдачи имён: ссылки повтора в `config.local.yaml` обязаны совпасть
  /// с теми, что записал бы перенос (то же имя, у которого то же значение).
  /// Несовпавший переезд отменяется; `true` — что-то отменено.
  bool _verifyResumes() {
    var changed = false;
    for (final file in [..._files]) {
      for (final move in [...file.moves]) {
        if (!move.resume) {
          continue;
        }
        final local = move.target.snapshot!;
        if (move.units.any((u) => local.get(u.localKey) != u.localValue)) {
          _refuse(move);
          changed = true;
        }
      }
    }
    return changed;
  }

  /// Находки слоя: единицы правки и строки `not migrated`.
  void _scan(_File file) {
    final values = file.snapshot!.values;
    final tree = ConfigTree(
      kind: configLayerKindOf(file.target!.layer),
      source: file.path,
      values: values,
    );
    final byKey = <String, List<InlineSecretFinding>>{};
    for (final finding in findInlineSecrets(tree)) {
      byKey.putIfAbsent(finding.keyPath, () => []).add(finding);
    }
    for (final MapEntry(:key, value: findings) in byKey.entries) {
      final value = file.snapshot!.get(key);
      final unit = _unitFor(key, findings, value, file);
      if (unit == null) {
        continue;
      }
      final problem = _slotProblem(unit);
      if (problem != null) {
        file.notes.add('$key cannot be stored ($problem)');
        continue;
      }
      file.units.add(unit);
    }
    file.notes.addAll(_argsNotes(values));
  }

  _Unit? _unitFor(
    String key,
    List<InlineSecretFinding> findings,
    Object? value,
    _File file,
  ) {
    final field = key.substring(key.lastIndexOf('.') + 1);
    final first = findings.first;
    if (value is! String) {
      file.notes.add('$key cannot be stored (the value is not a string)');
      return null;
    }
    switch (first.kind) {
      case InlineSecretKind.inlineKey:
        final provider =
            key.startsWith('providers.') &&
            !key.contains('[') &&
            (field == 'api_key' || field == 'apiKey');
        return _Unit(
          provider ? _UnitKind.providerKey : _UnitKind.otherInline,
          key,
          [_Slot(value: value, base: first.suggestedSecretName)],
        );
      case InlineSecretKind.nameLiteral:
        return _Unit(_UnitKind.nameLiteral, key, [
          _Slot(value: value, base: first.suggestedSecretName),
        ]);
      case InlineSecretKind.literalPart:
      case InlineSecretKind.referenceName:
        if (key.startsWith('providers.') &&
            (field == 'api_key' || field == 'apiKey')) {
          // Писатель не принимает значение в `api_key` даже со ссылкой:
          // правка вручную, переносить тут нечего.
          file.notes.add(
            '$key mixes a literal with a substitution; move it to '
            'api_key_secret manually',
          );
          return null;
        }
        if (inlineSecretKeys.contains(field)) {
          // Писатель отклоняет запись по ключу с таким именем независимо от
          // значения, поэтому ссылку вписать автоматически нельзя.
          file.notes.add(
            '$key has a name reserved for secret keys, so it cannot be '
            'rewritten automatically; rename it or move the value to '
            'a secret by hand',
          );
          return null;
        }
        final slots = <_Slot>[];
        for (final finding in findings) {
          for (final (start, end) in finding.spans) {
            final secretRef =
                finding.kind == InlineSecretKind.referenceName &&
                start >= 9 &&
                value.substring(start - 9, start) == '\${secret:';
            slots.add(
              _Slot(
                value: value.substring(start, end),
                base: finding.suggestedSecretName,
                start: start,
                end: end,
                secretReference: secretRef,
                variableReference:
                    finding.kind == InlineSecretKind.referenceName &&
                    !secretRef,
              ),
            );
          }
        }
        slots.sort((a, b) => a.start!.compareTo(b.start!));
        // Пересекающиеся участки разных шаблонов не режем дважды.
        final kept = <_Slot>[];
        for (final slot in slots) {
          if (kept.isEmpty || slot.start! >= kept.last.end!) {
            kept.add(slot);
          }
        }
        return kept.isEmpty
            ? null
            : _Unit(_UnitKind.templated, key, kept, original: value);
    }
  }

  /// `secretValueProblem` каждого значения единицы (D7): ключ не переносится
  /// частично.
  String? _slotProblem(_Unit unit) {
    for (final slot in unit.slots) {
      if (slot.value.isEmpty) {
        return 'empty secret value';
      }
      if (secretValueProblem(slot.value) case final problem?) {
        return problem;
      }
    }
    return null;
  }

  /// Элементы `mcp.servers[*].args` по шаблону §12.4 (OQ3): подсказка вместо
  /// переноса.
  List<String> _argsNotes(Map<String, Object?> values) {
    final out = <String>[];
    final mcp = values['mcp'];
    final servers = mcp is Map<String, Object?> ? mcp['servers'] : null;
    if (servers is! List<Object?>) {
      return out;
    }
    for (var i = 0; i < servers.length; i++) {
      final server = servers[i];
      if (server is! Map<String, Object?>) {
        continue;
      }
      final name = server['name'];
      final args = server['args'];
      if (args is! List<Object?>) {
        continue;
      }
      final at = KeyPath(
        'mcp.servers',
      ).at(name is String && name.isNotEmpty ? name : i);
      for (var j = 0; j < args.length; j++) {
        final arg = args[j];
        final tag = arg is String ? literalSecretTag(arg) : null;
        if (tag == null) {
          continue;
        }
        final key = at.child('args').at(j).value;
        out.add(
          '$key looks like a secret ($tag); pass it to the server via '
          "--env <NAME>='\${secret:${SecretNames.suggestFor(key)}}'",
        );
      }
    }
    return out;
  }

  /// Доверие писателя (H4): правка, которую он отклонил бы, превращает
  /// находку в `not migrated`, и значение до хранилища не доходит.
  Future<void> _checkTrust(_File file) async {
    if (file.units.isEmpty) {
      return;
    }
    final probe = <ConfigEdit>[];
    for (final unit in file.units) {
      for (final slot in unit.slots) {
        slot.name = slot.base;
      }
      probe.addAll(unit.edits());
    }
    try {
      await _writer.validate(file.snapshot!, probe);
    } on ConfigException catch (error) {
      if (error.issues.any(
        (i) => i.message.startsWith(untrustedProjectWritePrefix),
      )) {
        file
          ..untrusted = true
          ..units = []
          ..notes = ['${file.path} is an untrusted project config'];
      }
      // Прочие отказы кандидата сообщит шаг 1 с настоящими именами.
    }
  }

  // ---- имена ----------------------------------------------------------------

  void _allocateAll(List<_File> active) {
    for (final file in active) {
      _allocateFile(file);
    }
  }

  /// Окончательное распределение имён: сначала читаются владельцы, затем
  /// имена выдаются заново (предварительные забываются).
  Future<void> _assignNames(List<_File> active) async {
    _assigned.clear();
    await _loadOwned(active);
    _allocateAll(active);
  }

  Future<void> _refreshPreviews(List<_File> active) async {
    try {
      for (final file in active) {
        _previews[file] = await _writer.preview(file.snapshot!, _editsOf(file));
      }
    } on ConfigException catch (error) {
      _failIssues(error.issues);
    }
  }

  void _allocateFile(_File file) {
    for (final unit in file.units) {
      final owner = _ownerOf(unit.key);
      for (final slot in unit.slots) {
        slot.name = _allocate(slot.base, slot.value, owner);
      }
    }
  }

  /// Владелец ключа — провайдер либо сервер MCP (`providers.<id>`,
  /// `mcp.servers[<имя>]`); `null` у прочих ключей.
  String? _ownerOf(String key) => _ownerPattern.firstMatch(key)?.group(1);

  /// Имена, на которые уже ссылается тот же владелец в загруженном конфиге,
  /// и их значения в хранилище (`null` — нет секрета). Такое имя нельзя
  /// отдать другому значению того же владельца: ссылка молча указала бы на
  /// чужой ключ. Это же делает повтор после частичного сбоя идемпотентным
  /// (R8-6, L7).
  final _owned = <String, Map<String, String?>>{};

  Future<void> _loadOwned(List<_File> active) async {
    final owners = {
      for (final file in active)
        for (final unit in file.units) ?_ownerOf(unit.key),
    };
    for (final reference in _references()) {
      final owner = reference.owner;
      final name = reference.name;
      // Только владельцы переносимых ключей; значение, вписанное вместо
      // имени, и неверное имя в хранилище не читаются.
      if (owner == null ||
          !owners.contains(owner) ||
          SecretNames.problem(name) != null ||
          literalSecretTag(name) != null) {
        continue;
      }
      final names = _owned.putIfAbsent(owner, () => {});
      if (names.containsKey(name)) {
        continue;
      }
      try {
        names[name] = await _store.read(name);
      } on Object {
        // Значение неизвестно — имя считается занятым (null != значению).
        names[name] = null;
      }
    }
  }

  /// Имя для значения: то же значение — тот же секрет, другое — следующее
  /// свободное `<name>-2`, `<name>-3` (D7, шаг 2).
  String _allocate(String base, String value, String? owner) {
    final owned = owner == null ? null : _owned[owner];
    for (var n = 1; ; n++) {
      final candidate = n == 1 ? base : _suffixed(base, n);
      if (owned != null &&
          owned.containsKey(candidate) &&
          owned[candidate] != value) {
        continue;
      }
      final holder = _assigned[candidate];
      if (holder == value) {
        return candidate;
      }
      if (holder == null && !_clashesByVariable(candidate)) {
        _assigned[candidate] = value;
        return candidate;
      }
    }
  }

  String _suffixed(String base, int n) {
    final suffix = '-$n';
    final head = base.length + suffix.length > SecretNames.maxLength
        ? base.substring(0, SecretNames.maxLength - suffix.length)
        : base;
    return '$head$suffix';
  }

  /// Два разных имени с одной переменной `CODELAB_SECRET_*` действовали бы
  /// как один секрет (`SecretNames.envOverride`).
  bool _clashesByVariable(String candidate) {
    final variable = SecretNames.envOverride(candidate);
    return _assigned.keys.any(
      (other) =>
          other != candidate && SecretNames.envOverride(other) == variable,
    );
  }

  // ---- хранилище ------------------------------------------------------------

  /// Бэкенд только для чтения, коллизия переменных, имя — до любых записей.
  Future<void> _checkStore() async {
    for (final name in _assigned.keys) {
      final refusal = await _admin.checkStore(name);
      switch (refusal) {
        case null:
          continue;
        case final SecretReadOnly readOnly:
          final variables = [
            for (final n in _assigned.keys) SecretNames.envOverride(n),
          ];
          final head = 'secret store ${readOnly.backend} is read-only.';
          _fail(1, [
            readOnly.fileBackendOffered
                ? "$head Add 'secrets.backend: file' to $_home/config.yaml "
                      'to store secrets in $_home/secrets.yaml (plaintext, '
                      '0600), or set ${variables.join(', ')} in the '
                      'environment'
                : '$head Set ${variables.join(', ')} in the environment',
          ], readOnly: true);
        case SecretCollision(:final other, :final variable):
          _fail(1, [
            'secret name $name collides with $other (both map to $variable)',
          ]);
        case SecretFailed(:final reason):
          _fail(1, ['cannot store secret $name: $reason']);
        case SecretInvalidName(:final reason):
          _fail(1, ['cannot store secret $name: $reason']);
        case SecretInvalidValue(:final reason):
          _fail(1, ['cannot store secret $name: $reason']);
        case SecretStored() || SecretUpdated():
          continue;
      }
    }
  }

  /// Сравнивает имена с хранилищем: new, reuse, replace либо конфликт.
  Future<void> _resolveNames(Iterable<String> names) async {
    for (final name in [...names]) {
      if (_resolved.containsKey(name)) {
        continue;
      }
      final String? existing;
      try {
        existing = await _store.read(name);
      } on SecretStoreUnavailableException catch (error) {
        _fail(1, ['cannot read secret $name: ${error.reason}']);
      } on Object catch (error) {
        _fail(1, ['cannot read secret $name: ${error.runtimeType}']);
      }
      final value = _assigned[name]!;
      _resolved[name] = _Resolution(
        value,
        existing == null
            ? SecretMigrationAction.create
            : existing == value
            ? SecretMigrationAction.reuse
            : SecretMigrationAction.replace,
      );
    }
  }

  /// `; also referenced by: …` (тот же хвост, что у предупреждения
  /// `--force`) — чьи ключи затрёт `--force`; пусто, если никто не ссылается.
  String _referencedTail(String name) {
    final refs = _referencedBy(name);
    return refs.isEmpty ? '' : '; also referenced by: ${refs.join(', ')}';
  }

  /// Без `--force` другое значение в хранилище — код `1` до записи.
  void _failOnConflicts() {
    if (_o.force) {
      return;
    }
    final conflicts = [
      for (final MapEntry(:key, :value) in _resolved.entries)
        if (value.action == SecretMigrationAction.replace)
          'secret $key already exists with a different value; rerun with '
              '--force to replace it${_referencedTail(key)}',
    ];
    if (conflicts.isNotEmpty) {
      _fail(1, conflicts, conflict: true);
    }
  }

  /// Итог правок ВСЕХ выбранных файлов проверяется вместе (R8-10): кандидат
  /// каждого файла сливается с итоговыми текстами остальных
  /// (`ConfigLoader.validateCandidate(pending:)`), поэтому `--all` не
  /// спотыкается о промежуточный конфликт источников ключа (R8-6). Часть
  /// слоёв, оставляющая второй источник, — отказ до любой записи.
  Future<void> _checkCandidates(List<_File> active) async {
    try {
      for (final file in active) {
        _previews[file] = await _writer.preview(file.snapshot!, _editsOf(file));
      }
      for (final file in active) {
        await _writer.validate(
          file.snapshot!,
          _editsOf(file),
          pending: _pendingFor(file, active),
        );
      }
    } on ConfigException catch (error) {
      _failIssues(error.issues);
    }
    if (_deferred.isNotEmpty) {
      _verifyRepaired(active);
    }
  }

  /// Конфигурация уже была с конфликтом источников ключа (R8-6): писатель
  /// сравнивает кандидата с базой и такую проблему не увидит, поэтому итог
  /// выбранных слоёв грузится целиком и обязан быть чистым.
  void _verifyRepaired(List<_File> active) {
    final first = active.first;
    final result = ConfigLoader()
        .loadWithLayers(
          cwd: _cwd,
          environment: _env,
          platform: _m._platform,
          candidate: (
            kind: configLayerKindOf(first.target!.layer),
            text: _previews[first]!.text,
          ),
          pending: _pendingFor(first, active),
        )
        .result;
    if (result.issues.isNotEmpty) {
      _failIssues(result.issues);
    }
  }

  /// Отказ по проблемам кандидата. Остальные проблемы — следствия конфликта
  /// источников ключа (провайдер не построен, модель не в каталоге):
  /// достаточно причины.
  Never _failIssues(List<ConfigIssue> issues) {
    final sources = {for (final issue in issues) ?_twoKeySources(issue)};
    _fail(
      1,
      sources.isNotEmpty ? sources.toList() : [for (final i in issues) '$i'],
    );
  }

  List<PendingConfigText> _pendingFor(_File file, List<_File> others) => [
    for (final other in others)
      if (!identical(other, file) && _previews.containsKey(other))
        _previews[other]!,
  ];

  /// Текст про два источника ключа (R8-6, R8-10) или `null`.
  String? _twoKeySources(ConfigIssue issue) {
    if (issue.message != providerKeySourcesConflictMessage ||
        !issue.key.startsWith('providers.') ||
        !issue.key.endsWith('.api_key')) {
      return null;
    }
    final provider = issue.key.substring(
      0,
      issue.key.length - '.api_key'.length,
    );
    final rewritten = {
      for (final f in _active)
        if (f.units.any((u) => u.key.startsWith('$provider.')) ||
            f.incoming.any((m) => 'providers.${m.id}' == provider))
          f.label,
    };
    for (final layer in _layers) {
      final label = switch (layer.kind) {
        ConfigLayerKind.user => 'user',
        ConfigLayerKind.project => 'project',
        ConfigLayerKind.projectLocal => 'local',
        ConfigLayerKind.extra => 'CODELAB_CONFIG',
        _ => null,
      };
      if (label == null || rewritten.contains(label)) {
        continue;
      }
      final id = provider.substring('providers.'.length);
      final providers = layer.values['providers'];
      final body = providers is Map<String, Object?> ? providers[id] : null;
      if (body is Map<String, Object?> &&
          const [
            'api_key',
            'api_key_env',
            'api_key_secret',
          ].any((k) => body[k] != null && body[k] != '')) {
        // `--all` слой `CODELAB_CONFIG` не переносит: совет другой.
        return label == 'CODELAB_CONFIG'
            ? 'secret migrate: the result would leave two key sources for '
                  '$provider ($label keeps its own); remove the key from '
                  'CODELAB_CONFIG'
            : 'secret migrate: the result would leave two key sources for '
                  '$provider ($label keeps its own); run with --all';
      }
    }
    return null;
  }

  List<ConfigEdit> _editsOf(_File file) => [
    for (final unit in file.units)
      if (unit.move == null) ...unit.edits(),
    for (final move in file.moves) ...move.sourceEdits(),
    for (final move in file.incoming) ...move.localEdits(),
  ];

  // ---- запись ---------------------------------------------------------------

  /// Одна атомарная запись конфига файла (D7, шаг 3). Секреты к этому
  /// моменту уже в хранилище. `ConfigConflictException` — одно перечитывание
  /// и повтор шага 1 для файла; любой сбой повтора — штатный отказ.
  Future<void> _writeFile(_File file) async {
    for (var attempt = 0; ; attempt++) {
      try {
        if (!await _tryApply(file)) {
          return;
        }
        // Переезд провайдера (D26) связывает два файла: перепланировать один
        // из них нельзя, команду запускают заново.
        if (attempt >= 1 || file.moves.isNotEmpty || file.incoming.isNotEmpty) {
          _fail(1, [
            'config file changed during the edit; run the command again',
          ]);
        }
        await _replan(file);
      } on _Stop {
        rethrow;
      } on ConfigException catch (error) {
        _failIssues(error.issues);
      } on Object catch (error) {
        _fail(1, ['cannot write ${file.path}: ${error.runtimeType}']);
      }
    }
  }

  /// `true` — файл изменился с чтения (конфликт отпечатка).
  Future<bool> _tryApply(_File file) async {
    try {
      await _writer.apply(
        file.snapshot!,
        _editsOf(file),
        // Файлы, которые ещё не записаны, учитываются итоговым текстом.
        pending: _pendingFor(file, [
          for (final f in _active)
            if (!_done.contains(f)) f,
        ]),
      );
      return false;
    } on ConfigConflictException {
      return true;
    }
  }

  /// Шаг 1 заново для файла, изменившегося во время записи: находки, доверие,
  /// имена, кандидат с остальными файлами, хранилище.
  Future<void> _replan(_File file) async {
    file.snapshot = await _writer.read(file.target!);
    file
      ..units = []
      ..notes = [];
    _scan(file);
    await _checkTrust(file);
    if (file.units.isEmpty) {
      _previews.remove(file);
      return;
    }
    _allocateFile(file);
    await _checkStore();
    await _resolveNames(_assigned.keys);
    _failOnConflicts();
    _previews[file] = await _writer.preview(file.snapshot!, _editsOf(file));
    await _writer.validate(
      file.snapshot!,
      _editsOf(file),
      pending: _pendingFor(file, [
        for (final f in _active)
          if (!_done.contains(f)) f,
      ]),
    );
    final remaining = [
      for (final f in _active)
        if (!_done.contains(f) && _previews.containsKey(f)) f,
    ];
    if (_deferred.isNotEmpty && remaining.isNotEmpty) {
      _verifyRepaired(remaining);
    }
    await _storeSecrets(file);
  }

  /// Секреты файла в хранилище (D7, шаг 3); повтор того же имени пропускается.
  Future<void> _storeSecrets(_File file) async {
    for (final unit in file.units) {
      for (final slot in unit.slots) {
        final name = slot.name;
        final resolution = _resolved[name]!;
        if (_stored.contains(name) ||
            resolution.action == SecretMigrationAction.reuse) {
          continue;
        }
        // Окно гонки между `read` шага 2 и `store`: порт `SecretStore`
        // общей очереди не даёт (как у `SecretAdmin._inspect`); худший
        // исход — перезапись секрета, появившегося в этом окне.
        final outcome = await _admin.store(name, slot.value);
        switch (outcome) {
          case SecretStored() || SecretUpdated():
            _stored.add(name);
          case SecretFailed(:final reason) ||
              SecretInvalidValue(:final reason) ||
              SecretInvalidName(:final reason):
            _fail(1, ['cannot store secret $name: $reason']);
          case SecretCollision(:final other, :final variable):
            _fail(1, [
              'secret name $name collides with $other (both map to $variable)',
            ]);
          case SecretReadOnly():
            _fail(1, ['secret store ${_store.backend.id} is read-only.']);
        }
      }
    }
  }

  // ---- отчёт ----------------------------------------------------------------

  SecretMigrationReport _report({required bool planned}) {
    final items = _items(planned: planned, files: _files);
    return SecretMigrationReport(
      exitCode: 0,
      items: items,
      warnings: _warnings,
      dryRun: planned,
      home: _home,
      movedAny: !planned && _files.any((f) => f.units.isNotEmpty),
      // Только находки `CODELAB_CONFIG`: все файлы без единиц правки и без
      // собственных заметок, кроме незаписываемого слоя (D8).
      onlyExtraLayerFindings:
          items.isNotEmpty &&
          items.every((i) => i is SecretNotMigratedItem) &&
          _files.every((f) => f.label == 'CODELAB_CONFIG' || f.notes.isEmpty),
      backendId: _backendId,
    );
  }

  List<SecretMigrationItem> _items({
    required bool planned,
    required List<_File> files,
  }) {
    final out = <SecretMigrationItem>[];
    final announced = <String>{};
    for (final file in files) {
      for (final unit in file.units) {
        for (final slot in unit.slots) {
          final action = _resolved[slot.name]!.action;
          if (planned) {
            out.add(
              SecretPlanItem(
                path: file.path,
                key: unit.key,
                reference: unit.reference(slot),
                action: action,
              ),
            );
            continue;
          }
          if (action == SecretMigrationAction.replace &&
              announced.add(slot.name)) {
            out.add(
              SecretReplacedItem(
                name: slot.name,
                referencedBy: _referencedBy(slot.name),
              ),
            );
          }
          if (action == SecretMigrationAction.reuse) {
            out.add(
              SecretReusedItem(name: slot.name, key: unit.key, path: file.path),
            );
          }
          out.add(
            SecretMovedItem(name: slot.name, key: unit.key, path: file.path),
          );
        }
        if (unit.kind == _UnitKind.otherInline) {
          out.add(
            SecretActionRequiredItem(
              name: unit.slots.first.name,
              place: _placeFor(unit.key),
            ),
          );
        }
      }
      for (final move in file.moves) {
        out.add(
          SecretProviderMovedItem(
            provider: 'providers.${move.id}',
            from: file.path,
            to: move.target.path,
          ),
        );
      }
      for (final note in file.notes) {
        out.add(SecretNotMigratedItem(note));
      }
    }
    return out;
  }

  /// Куда вписать ссылку на секрет ключа, удалённого из схемы (`token`).
  String _placeFor(String key) {
    final server = RegExp(r'^(mcp\.servers\[[^\]]*\])\.').firstMatch(key);
    if (server != null) {
      return '${server.group(1)}.env or .headers';
    }
    final provider = RegExp(r'^(providers\.[^.]+)\.').firstMatch(key);
    return provider != null ? '${provider.group(1)}.headers' : key;
  }

  /// Ключи всех слоёв загруженного конфига, ссылающиеся на [name] (L7).
  List<String> _referencedBy(String name) => [
    for (final r in _references())
      if (r.name == name) '${r.key} (${r.label})',
  ];

  List<({String key, String? owner, String name, String label})>?
  _referenceCache;

  /// Все ссылки на секреты загруженных слоёв: `api_key_secret`, поле
  /// `secret` и `${secret:имя}`.
  List<({String key, String? owner, String name, String label})> _references() {
    final cached = _referenceCache;
    if (cached != null) {
      return cached;
    }
    final out = <({String key, String? owner, String name, String label})>[];
    for (final layer in _layers) {
      final label = switch (layer.kind) {
        ConfigLayerKind.user => 'user',
        ConfigLayerKind.project => 'project',
        ConfigLayerKind.projectLocal => 'local',
        ConfigLayerKind.extra => 'CODELAB_CONFIG',
        _ => null,
      };
      if (label != null) {
        _walk(layer.values, KeyPath.root, '', label, out);
      }
    }
    return _referenceCache = out;
  }

  static final _secretReference = RegExp(r'\$\{secret:([^}$]{1,200})\}');

  void _walk(
    Object? node,
    KeyPath at,
    String field,
    String label,
    List<({String key, String? owner, String name, String label})> out,
  ) {
    switch (node) {
      case final Map<String, Object?> map:
        for (final MapEntry(:key, :value) in map.entries) {
          _walk(value, at.child(key), key, label, out);
        }
      case final List<Object?> list:
        for (var i = 0; i < list.length; i++) {
          final item = list[i];
          final element =
              at.value == 'mcp.servers' &&
                  item is Map<String, Object?> &&
                  item['name'] is String &&
                  (item['name']! as String).isNotEmpty
              ? at.at(item['name']!)
              : at.at(i);
          _walk(item, element, field, label, out);
        }
      case final String text:
        final names = {
          if (field == 'api_key_secret' ||
              (field == 'secret' && _ownerOf(at.value) == null))
            text,
          for (final m in _secretReference.allMatches(text)) m.group(1)!,
        };
        for (final name in names) {
          out.add((
            key: at.value,
            owner: _ownerOf(at.value),
            name: name,
            label: label,
          ));
        }
    }
  }
}
