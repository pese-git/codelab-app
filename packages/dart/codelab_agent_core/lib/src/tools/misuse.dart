import '../util/canonical_json.dart';

/// Пределы предохранителя неверных вызовов (`agent-core-architecture`
/// §6.3.7, конфиг `loop.misuse.*` §15.4).
///
/// Почему: модель, получившая ошибку валидации, иногда повторяет тот же
/// вызов шаг за шагом и тратит бюджет хода. Пределы задают, когда её
/// предупредить и когда перестать пропускать вызов.
///
/// Как использовать: цикл берёт значение из `AgentLoopConfig.misuse` и
/// создаёт по нему один [MisuseBreaker] на ход. Нарушение
/// `1 ≤ warnAfter ≤ blockAfter ≤ 50` — ошибка программиста (assert);
/// проверку конфига с `ConfigException` добавит загрузчик конфигурации
/// (этапы 4 и 8).
final class MisuseLimits {
  const MisuseLimits({
    this.enabled = true,
    this.warnAfter = 3,
    this.blockAfter = 6,
  }) : assert(1 <= warnAfter, 'warnAfter must be >= 1'),
       assert(warnAfter <= blockAfter, 'warnAfter must be <= blockAfter'),
       assert(blockAfter <= 50, 'blockAfter must be <= 50');

  /// `false` — предохранитель ничего не считает и не блокирует.
  final bool enabled;

  /// С какого неверного вызова с одним ключом дописывается предупреждение.
  final int warnAfter;

  /// На каком неверном вызове ключ блокируется до конца хода.
  final int blockAfter;
}

/// Счётчик неверных вызовов одного хода (C-08, TOOL-11, LOOP-16).
///
/// Почему: повтор одного и того же неверного вызова не даёт модели новой
/// информации; после предупреждений дешевле ответить ей сразу, без
/// валидации, разрешений и исполнения.
///
/// Для чего: шаги 1a и 9a единой точки исполнения (§6.3.1). «Неверный» —
/// только вызов, упавший на поиске инструмента, валидации или `preflight`;
/// отказ разрешения, отмена и ошибки исполнения сюда не попадают: повторить
/// упавший `exec dart test` после правки — нормальная работа.
///
/// Как использовать: цикл создаёт экземпляр в начале хода и передаёт его во
/// все `ToolContext` этого хода; точка исполнения вызывает [isBlocked] до
/// валидации и [recordInvalid] после ошибки шагов 2–3a. Следующий ход
/// начинает с нового экземпляра — счётчик пуст. Dart однопоточен, поэтому
/// синхронизация не нужна.
final class MisuseBreaker {
  MisuseBreaker(this.limits);

  final MisuseLimits limits;
  final _invalid = <String, int>{};

  /// Ключ вызова: имя и канонический JSON **сырых** аргументов модели.
  /// Одинаковый вызов — то, что модель прислала побайтово так же с
  /// точностью до порядка ключей.
  static String keyOf(String tool, Map<String, Object?> rawArgs) =>
      '$tool\u0000${canonicalJson(rawArgs)}';

  /// Сколько раз вызов с ключом [key] был неверным в этом ходе.
  int count(String key) => _invalid[key] ?? 0;

  bool isBlocked(String key) =>
      limits.enabled && count(key) >= limits.blockAfter;

  /// Засчитывает неверный вызов и возвращает текст предупреждения, который
  /// дописывается к ошибке, или `null`.
  String? recordInvalid(String key) {
    if (!limits.enabled) {
      return null;
    }
    final n = count(key) + 1;
    _invalid[key] = n;
    if (n >= limits.blockAfter) {
      return '[Warning: this exact call has failed $n times in this turn and '
          'is now blocked until the turn ends.]';
    }
    if (n >= limits.warnAfter) {
      return '[Warning: this exact call has failed $n times in this turn. Do '
          'not repeat it: change the arguments or use another approach.]';
    }
    return null;
  }

  /// Текст ответа на заблокированный вызов (шаг 1a).
  String blockedText(String tool, String key) =>
      'Blocked: this exact call to $tool has already failed ${count(key)} '
      'times in this turn and will not be run again until the turn ends. '
      'Change the arguments or use another approach.';
}
