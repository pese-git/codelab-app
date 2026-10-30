/// Основной барель моста `codelab_setup`: чистые типы конфигурации агента
/// (`dart-agent-and-clients` §12.4.2; design.md change
/// `add-agent-configuration`, D14, OQ2 (а)).
///
/// Почему: клиенты (`apps/*`) не импортируют `package:codelab_agent_*`
/// напрямую (`AGENTS.md` §5), а типы проверки конфигурации нужны им для
/// отображения проблем. Мост реэкспортирует их из ядра, как `codelab_embedded`
/// реэкспортирует `ProviderConfig`.
///
/// Для чего: барель остаётся web-безопасным — ни `dart:io`, ни
/// `package:codelab_agent_io/`, ни ссылок на `io.dart` (правило сторожа,
/// `melos run guard`). Всё, что требует `dart:io`, живёт в `io.dart`.
///
/// Как использовать: `import 'package:codelab_setup/codelab_setup.dart';`.
/// Мастер провайдера, `AgentConfigStore` и `SettingsAccess` (§12.4.2) придут
/// сюда со своими потребителями (этап 7, задачи 8.10 и 9.6 change).
library;

export 'package:codelab_agent_core/codelab_agent_core.dart'
    show ConfigIssue, ConfigIssueKind, ConfigLoadResult;
