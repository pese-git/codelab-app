/// Проверка `/models` на `dart:io`-клиенте (design.md change
/// `add-provider-setup-ui`, D8, D20).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart' show Logger;
import 'package:http/io_client.dart';

import '../provider/http_provider_check.dart';
import '../provider/provider_check.dart';
import 'classify_provider_check_error.dart';

/// Проверка списка моделей с настоящим `IOClient`.
///
/// Почему здесь, а не в основном бареле: `package:http/io_client.dart`
/// тянет `dart:io`, а основной барель обязан компилироваться в JS и Wasm
/// (правило сторожа). `IOClient` создаётся только в этом файле.
///
/// Как использовать: composition root app и CLI зовёт `ioProviderCheck()` и
/// передаёт результат мастеру и Cubit-ам как [ProviderCheck]. Новый `IOClient`
/// на каждую проверку закрывается по её окончании: таймаут обрывает соединение.
/// [logger] получает события `provider_check.result` только с
/// `scheme://host:port`. Ошибка TLS отличается от недоступности по типу
/// исключения (`classifyProviderCheckError`), а не по тексту.
ProviderCheck ioProviderCheck({Logger? logger}) => HttpProviderCheck(
  IOClient.new,
  logger: logger,
  classifier: classifyProviderCheckError,
);
