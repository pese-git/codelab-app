import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Бэкенд `env`: секреты из переменных `CODELAB_SECRET_<…>`, только чтение
/// (design.md change `add-agent-secret-store`, D5, D6).
///
/// Почему отдельный бэкенд: на CI и в контейнерах секрет приходит
/// переменной окружения, а записывать его некуда и незачем. Резолвер ядра и
/// сам читает переменную переопределения до обращения к хранилищу (D3, шаг 3),
/// но `EnvSecretStore` нужен как `DescribedSecretStore` для `auto`/`env` и
/// для `--llm-script` (D11): у хоста всегда есть хранилище с честным `id`.
///
/// Для чего: `read` — значение переменной `SecretNames.envOverride(name)`;
/// `write` и `delete` — `SecretStoreUnavailableException("env backend is
/// read-only")`; `names()` пуст: отображение имя → переменная необратимо, и
/// список переменных показывает `SecretAdmin.list` (D6).
///
/// Как использовать: [environment] — окружение процесса хоста (в тестах — карта
/// теста); [unavailableReason] задаёт `openSecretStore` для `auto`.
final class EnvSecretStore implements DescribedSecretStore {
  EnvSecretStore({
    required Map<String, String> environment,
    String? unavailableReason,
  }) : _environment = environment,
       backend = SecretBackendInfo(
         id: 'env',
         writable: false,
         unavailableReason: unavailableReason,
       );

  final Map<String, String> _environment;

  @override
  final SecretBackendInfo backend;

  @override
  Future<String?> read(String name) async {
    if (SecretNames.problem(name) != null) {
      return null;
    }
    final value = _environment[SecretNames.envOverride(name)];
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String name, String value) async => throw _readOnly();

  @override
  Future<void> delete(String name) async => throw _readOnly();

  @override
  Future<List<String>> names() async => const [];

  // Текст без значения и без имени: его печатают как есть (CFG-10).
  SecretStoreUnavailableException _readOnly() =>
      const SecretStoreUnavailableException(
        backend: 'env',
        reason: 'env backend is read-only',
      );
}
