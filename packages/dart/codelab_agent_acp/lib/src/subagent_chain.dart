import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Согласие клиента на вызовы потомков: `clientCapabilities._meta.codelab.
/// subagentToolCalls` — объект с целым `version: 1` (design.md change
/// `add-subagents-and-tasks`, D9, D47 Т3).
///
/// Почему отдельная функция: согласие читают и мост (кому слать кадры
/// потомков), и `AcpPermissionGate` (что ждать перед запросом), причём из
/// `ClientLink.capabilities` в момент события или запроса: после
/// переподключения объявление может смениться. Любое другое значение
/// (`2`, `'1'`, `1.5`, не объект) — согласия нет, как у kit.
bool subagentToolCallsConsent(acp.ClientCapabilities capabilities) {
  final codelab = capabilities.meta?['codelab'];
  if (codelab is! Map) {
    return false;
  }
  final extension = codelab['subagentToolCalls'];
  if (extension is! Map) {
    return false;
  }
  final version = extension['version'];
  return version is int && version == 1;
}

/// Цепочки `toolCallId` вызовов потомков (D47 Т2).
///
/// Почему отдельный объект: вызов потомка на проводе получает id
/// `<префикс>/<id вызова>`, где префикс — цепочка вызова `agent`, который
/// запустил потомка. События ядра несут только адрес потомка
/// (`subagentId`, `path`, `depth`, `parentToolCallId` — сырой id вызова
/// `agent` в сессии родителя), поэтому префикс глубже первого уровня строится
/// из префикса предка: `префикс(path.last) + "/" + parentToolCallId`. Строки
/// цепочки НЕ разбираются: id провайдера может содержать `/` (D45 Т3).
///
/// Для чего: один алгоритм для живой проекции (`SessionBridge`) и для
/// реплея дерева (`replayUpdates`, задача 5.2 после 5.3), чтобы цепочки
/// живого хода и реплея совпадали (фикстуры `acp/prompt-subagent-tool-tree`
/// и `acp/session-load-subagent-tool-tree`).
///
/// Как использовать: на каждое [SubagentActivity] хода зовётся [prefixOf];
/// события ребёнка приходят раньше событий внука, поэтому префикс предка к
/// этому времени уже запомнен. `null` — предок неизвестен: вызывающий не
/// отправляет событие и пишет `acp.subagent.unknown_parent`. [clear] — на
/// конце хода.
final class SubagentChains {
  final _prefixes = <String, String>{};

  /// Префикс вызова `agent`, запустившего владельца события [activity];
  /// запоминает его за `subagentId`. `null` — префикс предка неизвестен.
  String? prefixOf(SubagentActivity activity) {
    final String prefix;
    if (activity.path.isEmpty) {
      // Глубина 1: `parentToolCallId` — id вызова `agent` корня как есть.
      prefix = activity.parentToolCallId;
    } else {
      final ancestor = _prefixes[activity.path.last];
      if (ancestor == null) {
        return null;
      }
      prefix = '$ancestor/${activity.parentToolCallId}';
    }
    _prefixes[activity.subagentId] = prefix;
    return prefix;
  }

  /// Цепочка вызова [toolCallId] потомка с префиксом [prefix].
  static String chainOf(String prefix, String toolCallId) =>
      '$prefix/$toolCallId';

  void clear() => _prefixes.clear();
}
