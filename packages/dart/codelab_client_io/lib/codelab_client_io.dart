/// `dart:io`-адаптеры клиентского слоя ACP: файлы, процессы, настоящие
/// транспорты и JSON-хранилища (change `extract-acp-client-kit`).
///
/// Почему: `codelab_client_core` и `codelab_client_acp` web-безопасны, а app и CLI
/// на десктопе нуждаются в одних и тех же реализациях их портов
/// (`dart-agent-and-clients` §9.10, задача 5.8).
///
/// Как использовать: импортируют только composition root и тесты; Flutter
/// здесь запрещён (реализации на Flutter-плагинах остаются в app).
library;

export 'src/platform/terminal_process_runner.dart';
export 'src/platform/text_file_io.dart';
export 'src/platform/working_directory_provider.dart';
export 'src/stores/json_file_profile_store.dart';
export 'src/stores/json_file_recent_projects_store.dart';
export 'src/transport/io_transport_resolver.dart';

const acpClientIoPackageName = 'codelab_client_io';
