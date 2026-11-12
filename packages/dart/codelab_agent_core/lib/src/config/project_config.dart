import 'config_issue.dart';

/// Порт загрузки конфигурации папки сессии (design.md change
/// `require-project-folder`, D21; spec agent-runtime «Конфигурация сессии вне
/// корня запуска»).
///
/// Почему порт ядра: чтение `<cwd>/.codelab/config.yaml` и `config.local.yaml`
/// — `dart:io` (PKG-1), а ядру нужна только готовая [ConfigLoadResult].
/// Порт отдельный от `ConfigSource`: у хоста может быть одно без другого
/// (источник — перезагрузка корня, порт — конфигурация чужих папок).
///
/// Для чего: сессия в папке, отличной от корня запуска, получает полный
/// `CoreConfig` своей папки (включая провайдеров), а не снимок без проекта.
/// Так провайдер «This project only» проекта `B` работает в сессиях `B` без
/// перезапуска агента.
///
/// Как использовать: реализует хост (`FileConfigSource` в `codelab_agent_io`),
/// передаёт в `AgentCoreServices.projectConfig` вместе с `modelsFor`
/// (`HostWiringException` без него). Реализация обязана читать слои тем же
/// загрузчиком, окружением и флагами, что стартовая загрузка, с доверием,
/// закреплённым на старте (`initial.config.trustedProjects`), и не сдвигать
/// базу наблюдателя за файлами корня. Рантайм вызывает порт на каждый
/// `createSession` / `loadSession` сессии вне корня, без кэша, и сам
/// проверяет результат (`validateSnapshot`).
abstract interface class ProjectConfigLoader {
  /// Слои папки [canonicalCwd] (канонической, не корня запуска) в один
  /// результат. Ошибки конфигурации — в `ConfigLoadResult.issues`; исключение
  /// допустимо только для сбоя чтения и тоже закрывает сессию (fail closed).
  Future<ConfigLoadResult> loadForProject(String canonicalCwd);
}

/// Конфигурация папки сессии не загрузилась или не прошла проверку: сессия не
/// создаётся (design.md change `require-project-folder`, D21; §2 приоритет 1
/// корневого `AGENTS.md`).
///
/// Почему исключение, а не откат на снимок корня или `withoutProject`: сессия
/// без собственных запретов проекта (`permissions.deny`) была бы слабее, чем
/// ждёт пользователь. Ошибка видна клиенту (`-32603` с
/// `data.codelab.reason: "projectConfigInvalid"`), а не скрыта.
///
/// Как использовать: бросает `AgentRuntime.createSession` / `loadSession`;
/// журнал новой сессии при этом не создаётся, журнал загружаемой не
/// меняется. [issues] — проблемы в форме `config check` (источник, строка,
/// столбец, ключ, сообщение): значений секретов и подставленных переменных в
/// них нет (CFG-2). [message] — все проблемы одной строкой через `; ` для
/// `message` ошибки ACP (Q20 (a)).
final class ProjectConfigException implements Exception {
  const ProjectConfigException({required this.cwd, required this.issues});

  /// Канонический `cwd` папки, конфигурация которой не загрузилась.
  final String cwd;

  /// Проблемы загрузки, проверки снимка или `modelsFor` в форме `config check`
  /// (источник, строка, столбец, ключ, сообщение). Значений секретов и
  /// подставленных переменных в них нет (CFG-2): сообщение строится из пути,
  /// типа и допустимых значений.
  final List<ConfigIssue> issues;

  /// `<источник>:<строка>:<столбец>: <ключ>: <сообщение>` через `; `.
  String get message => issues.join('; ');

  @override
  String toString() => 'ProjectConfigException($cwd): $message';
}
