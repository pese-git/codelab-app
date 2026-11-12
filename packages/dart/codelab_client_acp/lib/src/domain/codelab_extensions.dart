import 'domain_models.dart';

/// Версия каждого расширения CodeLab, данные которого понимает клиент.
const _supportedExtensionVersion = 1;

/// Блок `clientCapabilities._meta`, которым CodeLab объявляет расширения.
///
/// Почему: клиент CodeLab понимает данные `_meta.codelab.task`,
/// `_meta.codelab.subagent` и вызовы потомков, а ACP разрешает объявлять
/// такое расширение только в `_meta` capability-объектов (`15-Extensibility.md`;
/// design.md change `add-subagents-and-tasks`, D9, D21).
///
/// Состав растёт вместе с поддержкой: сейчас клиент объявляет только `tasks`;
/// `subagents` добавит итерация 2, `subagentToolCalls` — итерация 5 (когда
/// клиент научится показывать вызовы потомков), иначе агент слал бы данные,
/// которых клиент не понимает.
///
/// Для чего: `initialize` кладёт его в `ClientCapabilities.meta`; агент
/// отвечает блоком объявлений, только если этот объект пришёл. Других
/// полей вне `_meta` для этого нет.
const Map<String, Object?> codelabClientExtensionsMeta = {
  'codelab': {
    'tasks': {'version': _supportedExtensionVersion},
  },
};

/// Расширения CodeLab, согласованные при `initialize`.
///
/// Почему: блок `agentCapabilities._meta.codelab` — необязательные данные
/// агента, поэтому разбор терпим: отсутствие блока, неизвестные ключи,
/// нецелая или чужая `version`, неверная форма значения не ломают
/// `initialize` и означают «расширение не согласовано».
///
/// Для чего: приложение узнаёт, какие расширения объявил агент. Данные
/// `_meta.codelab.task` и `_meta.codelab.subagent` приложение принимает и без
/// объявления — показ не зависит от того, кто и как загрузил сессию.
///
/// Как использовать: `ready.codelabExtensions`, где `ready` —
/// `ClientConnectionReady`.
final class CodelabExtensions {
  const CodelabExtensions({
    this.tasks = false,
    this.subagents = false,
    this.subagentToolCalls = false,
    this.subagentsMaxDepth,
  });

  /// Разбор [meta] из `agentCapabilities._meta`.
  factory CodelabExtensions.parse(Map<String, Object?>? meta) {
    final codelab = meta?['codelab'];
    if (codelab is! Map) {
      return const CodelabExtensions();
    }
    Map<Object?, Object?>? known(String key) {
      final value = codelab[key];
      // Версия строго `int` (`1.0` и строка не принимаются). Оговорка: пакет
      // web-безопасный, а в dart2js `1.0 is int` истинно (числа — JS number),
      // поэтому на web «версия не целое 1» (`1.0`) неотличима от `1`.
      return value is Map &&
              switch (value['version']) {
                final int v => v == _supportedExtensionVersion,
                _ => false,
              }
          ? value
          : null;
    }

    final subagents = known('subagents');
    final maxDepth = subagents?['maxDepth'];
    return CodelabExtensions(
      tasks: known('tasks') != null,
      subagents: subagents != null,
      subagentToolCalls: known('subagentToolCalls') != null,
      subagentsMaxDepth: maxDepth is int && maxDepth > 0 ? maxDepth : null,
    );
  }

  final bool tasks;
  final bool subagents;
  final bool subagentToolCalls;

  /// `subagents.maxDepth`; `null` — не объявлено или неверной формы.
  final int? subagentsMaxDepth;
}

/// Согласованные расширения соединения (`agentCapabilities._meta.codelab`).
extension ClientConnectionReadyCodelab on ClientConnectionReady {
  CodelabExtensions get codelabExtensions =>
      CodelabExtensions.parse(capabilities.meta);
}
