import 'secret_store.dart';

/// Хранилище секретов в памяти (id `memory`) для тестов и хостов без
/// постоянного хранилища (design.md change `add-agent-secret-store`, D1, D12).
///
/// Почему в ядре, а не в тестах: чистое ядро не имеет файлов и процессов
/// (PKG-1), а резолверу, проекции и web-хосту нужна хоть какая-то
/// реализация [DescribedSecretStore]; держать её рядом с портом дешевле, чем
/// копировать фейк в каждый пакет. Значения живут до конца процесса и нигде
/// не сохраняются.
///
/// Для чего: тесты ядра, резолвера и проекции в протокол работают без файлов
/// и процессов; web-хост может держать ключи только в памяти сессии (D16).
///
/// Как использовать: `MemorySecretStore({'codelab/openai': 'sk-…'})`; запись
/// допустима, имена отдаются по алфавиту.
final class MemorySecretStore implements DescribedSecretStore {
  MemorySecretStore([Map<String, String> initial = const {}])
    : _values = {...initial};

  final Map<String, String> _values;

  @override
  SecretBackendInfo get backend =>
      const SecretBackendInfo(id: 'memory', writable: true);

  @override
  Future<String?> read(String name) async => _values[name];

  @override
  Future<void> write(String name, String value) async => _values[name] = value;

  @override
  Future<void> delete(String name) async => _values.remove(name);

  @override
  Future<List<String>> names() async => _values.keys.toList()..sort();
}
