import '../util/logger.dart';
import 'secret_lookup.dart';
import 'secret_names.dart';
import 'secret_store.dart';

/// Единственная дорога к значению секрета в ядре (`agent-core-architecture`
/// §17.5.4; design.md change `add-agent-secret-store`, D3, D10).
///
/// Почему резолвер, а не сам [SecretStore] в сервисах: функцию модели хост
/// строит раньше ядра (`createRoutedStreamFunction`), а переменная
/// переопределения `CODELAB_SECRET_*` требует окружения процесса, которого у
/// ядра нет. Один резолвер на процесс создаёт хост (D11, D15).
///
/// Для чего: порядок источников, кэш, single-flight, предупреждение о
/// недоступном хранилище и режим отладки (P-17) живут в одном месте. Ядро не
/// создаёт таймеров (PKG-6): предел ожидания соблюдают бэкенды
/// `codelab_agent_io`, а вызывающий код сам прекращает ожидание по отмене.
///
/// Как использовать: `await resolver.secret(name, purpose: <путь ключа>)` для
/// `api_key_secret` и `${secret:…}`, `resolver.env(VAR, purpose: …)` для
/// `api_key_env`. Порядок `secret`: кэш, переменная
/// `SecretNames.envOverride(name)`, хранилище. Кэшируются только найденные
/// значения, поэтому секрет, записанный после старта, подхватывается
/// следующим запросом; замена уже прочитанного видна после перезапуска до 8.10
/// (D3, D15). Значение секрета не попадает ни в лог, ни в `toString` ни одного
/// результата; в режиме [debug] пишется `secrets.lookup` с именем, назначением,
/// источником и признаком `found` (D10, CFG-10).
final class SecretResolver {
  SecretResolver({
    required DescribedSecretStore store,
    required Map<String, String> environment,
    required Logger logger,
    bool debug = false,
  }) : _store = store,
       _environment = environment,
       _logger = logger,
       _debug = debug;

  final DescribedSecretStore _store;
  final Map<String, String> _environment;
  final Logger _logger;
  final bool _debug;

  final _cache = <String, String>{};
  final _inflight = <String, Future<SecretLookup>>{};
  final _warned = <String>{};

  /// Разрешает секрет по имени; не бросает исключений.
  ///
  /// [purpose] — путь ключа конфига, ради которого читается секрет
  /// (`providers.openai.api_key_secret`); он попадает только в диагностику.
  Future<SecretLookup> secret(String name, {required String purpose}) async {
    final lookup = await _resolve(name);
    _record(name, purpose, lookup);
    return lookup;
  }

  /// Синхронно читает переменную окружения, переданного резолверу
  /// (`api_key_env`, D4). Пустое значение равно отсутствию.
  SecretLookup env(String variable, {required String purpose}) {
    final value = _environment[variable];
    final SecretLookup lookup = value == null || value.isEmpty
        ? const SecretMissing('env')
        : SecretFound(value, 'env');
    _record(variable, purpose, lookup);
    return lookup;
  }

  Future<SecretLookup> _resolve(String name) {
    // Имя проверила загрузка конфига; здесь защита в глубину (D3, шаг 1).
    if (SecretNames.problem(name) != null) {
      return Future.value(SecretMissing(_store.backend.id));
    }
    if (_cache[name] case final cached?) {
      return Future.value(SecretFound(cached, 'cache'));
    }
    final override = _environment[SecretNames.envOverride(name)];
    if (override != null && override.isNotEmpty) {
      _cache[name] = override;
      return Future.value(SecretFound(override, 'env'));
    }
    // Single-flight: одновременные запросы одного имени ждут одного `read`.
    return _inflight[name] ??= _read(name)
      ..whenComplete(() => _inflight.remove(name));
  }

  Future<SecretLookup> _read(String name) async {
    final backend = _store.backend.id;
    try {
      final value = await _store.read(name);
      if (value == null || value.isEmpty) {
        return SecretMissing(backend);
      }
      _cache[name] = value;
      return SecretFound(value, backend);
    } on SecretStoreUnavailableException catch (error) {
      _warnOnce(error.backend, error.reason);
      return SecretUnavailable(error.backend, error.reason);
    } on Object catch (error) {
      // Чужая реализация порта: в причину идёт только тип исключения, текст
      // мог бы содержать значение.
      final reason = 'secret store failed: ${error.runtimeType}';
      _warnOnce(backend, reason);
      return SecretUnavailable(backend, reason);
    }
  }

  /// Одно предупреждение на пару `(backend, reason)` за жизнь резолвера.
  void _warnOnce(String backend, String reason) {
    if (_warned.add('$backend\u0000$reason')) {
      _logger.log(
        LogLevel.warning,
        'secrets.backend.unavailable',
        fields: {'backend': backend, 'reason': reason},
      );
    }
  }

  /// Режим отладки (P-17): имя, назначение, источник, найдено ли. Значение,
  /// длина, префикс и хеш не пишутся никогда (CFG-10).
  void _record(String name, String purpose, SecretLookup lookup) {
    if (!_debug) {
      return;
    }
    final (source, found) = switch (lookup) {
      SecretFound(:final source) => (source, true),
      SecretMissing(:final backend) => (backend, false),
      SecretUnavailable(:final backend) => (backend, false),
    };
    _logger.log(
      LogLevel.info,
      'secrets.lookup',
      fields: {
        'name': name,
        'purpose': purpose,
        'source': source,
        'found': found,
      },
    );
  }
}
